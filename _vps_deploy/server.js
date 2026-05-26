'use strict';

const http = require('http');
const { Server } = require('socket.io');
const mysql = require('mysql2/promise');

// ── DB pool — credentials loaded from environment variables ──────────────────
// On the VPS set these in /etc/systemd/system/goreto-socket.service [Service]:
//   Environment=DB_HOST=127.0.0.1
//   Environment=DB_USER=ekloadmin_user
//   Environment=DB_PASS=your_actual_password
//   Environment=DB_NAME=ekloadmin_db
//   Environment=ALLOWED_ORIGIN=https://goreto.org
const db = mysql.createPool({
  host: process.env.DB_HOST || '127.0.0.1',
  user: process.env.DB_USER || 'ekloadmin_user',
  password: process.env.DB_PASS || '', // No hardcoded fallback — must be in env
  database: process.env.DB_NAME || 'ekloadmin_db',
  waitForConnections: true,
  connectionLimit: 20,
  queueLimit: 0,
});

// ── HTTP server (no Express needed) ──────────────────────────────────────────
const httpServer = http.createServer((req, res) => {
  res.writeHead(200);
  res.end('Goreto Socket Server');
});

// ── Socket.IO ─────────────────────────────────────────────────────────────────
const _allowedOrigin = process.env.ALLOWED_ORIGIN || 'https://goreto.org';
const io = new Server(httpServer, {
  path: '/socket.io/',
  cors: {
    origin: _allowedOrigin,
    methods: ['GET', 'POST'],
    credentials: true,
  },
  pingTimeout: 20000,
  pingInterval: 25000,
});

// userId → Set<socketId>
const onlineUsers = new Map();

function addOnline(userId, socketId) {
  if (!onlineUsers.has(userId)) onlineUsers.set(userId, new Set());
  onlineUsers.get(userId).add(socketId);
}

function removeOnline(userId, socketId) {
  const sockets = onlineUsers.get(userId);
  if (!sockets) return;
  sockets.delete(socketId);
  if (sockets.size === 0) onlineUsers.delete(userId);
}

function isOnline(userId) {
  return onlineUsers.has(userId) && onlineUsers.get(userId).size > 0;
}

// Emit to all sockets of a user
function emitToUser(userId, event, data) {
  const sockets = onlineUsers.get(userId);
  if (!sockets) return;
  for (const sid of sockets) {
    io.to(sid).emit(event, data);
  }
}

// ── Auth middleware ───────────────────────────────────────────────────────────
io.use(async (socket, next) => {
  try {
    const token = socket.handshake.auth?.token || socket.handshake.query?.token;
    if (!token) return next(new Error('Missing token'));

    // Reject malformed tokens without hitting the DB
    if (!/^[a-f0-9]{64}$/i.test(token)) return next(new Error('Invalid token format'));

    // Try multi-session table first (new logins)
    const [rows] = await db.query(
      'SELECT user_id FROM user_auth_tokens WHERE token = ? AND revoked_at IS NULL LIMIT 1',
      [token]
    );
    if (rows.length) {
      socket.userId = String(rows[0].user_id);
      return next();
    }

    // Legacy fallback: users.api_token (old logins still in circulation)
    const [legacy] = await db.query(
      'SELECT id FROM users WHERE api_token = ? LIMIT 1',
      [token]
    );
    if (!legacy.length) return next(new Error('Invalid token'));

    socket.userId = String(legacy[0].id);
    next();
  } catch (err) {
    next(new Error('Auth error'));
  }
});

// ── Connection handler ────────────────────────────────────────────────────────
io.on('connection', (socket) => {
  const userId = socket.userId;
  addOnline(userId, socket.id);

  // Update last_seen + online flag in DB
  db.query('UPDATE users SET is_online = 1, last_seen = NOW() WHERE id = ?', [userId]).catch(() => {});

  // Notify anyone subscribed to this user's status
  _broadcastStatus(userId, true);

  // ── send_message ────────────────────────────────────────────────────────────
  socket.on('send_message', async (data, ack) => {
    try {
      const { receiver_id, content, type = 'text', temp_id } = data || {};
      if (!receiver_id || !content) {
        return ack && ack({ success: false, error: 'Missing fields' });
      }

      // Insert message
      const [result] = await db.query(
        `INSERT INTO messages (sender_id, receiver_id, content, type, status, created_at)
         VALUES (?, ?, ?, ?, 'sent', NOW())`,
        [userId, receiver_id, content, type]
      );
      const msgId = result.insertId;

      // Fetch the inserted row
      const [rows] = await db.query(
        'SELECT * FROM messages WHERE id = ? LIMIT 1',
        [msgId]
      );
      const msg = rows[0];
      const msgObj = _formatMessage(msg);

      // Ack sender
      ack && ack({ success: true, message: { ...msgObj, temp_id } });

      // Deliver to receiver if online
      if (isOnline(String(receiver_id))) {
        emitToUser(String(receiver_id), 'new_message', msgObj);

        // Mark as delivered
        await db.query(
          "UPDATE messages SET status = 'delivered' WHERE id = ?",
          [msgId]
        );
        emitToUser(userId, 'message_delivered', { message_id: String(msgId), receiver_id: String(receiver_id) });
      }
    } catch (err) {
      console.error('[send_message]', err.message);
      ack && ack({ success: false, error: 'Server error' });
    }
  });

  // ── mark_read ───────────────────────────────────────────────────────────────
  socket.on('mark_read', async (data) => {
    try {
      const { sender_id } = data || {};
      if (!sender_id) return;

      await db.query(
        "UPDATE messages SET status = 'read', read_at = NOW() WHERE sender_id = ? AND receiver_id = ? AND status != 'read'",
        [sender_id, userId]
      );

      // Notify sender their messages were read
      emitToUser(String(sender_id), 'messages_read', {
        reader_id: userId,
        sender_id: String(sender_id),
        read_at: new Date().toISOString(),
      });
    } catch (err) {
      console.error('[mark_read]', err.message);
    }
  });

  // ── typing ──────────────────────────────────────────────────────────────────
  socket.on('typing', (data) => {
    const { receiver_id, is_typing } = data || {};
    if (!receiver_id) return;
    emitToUser(String(receiver_id), 'user_typing', {
      sender_id: userId,
      is_typing: !!is_typing,
    });
  });

  // ── subscribe_status ─────────────────────────────────────────────────────────
  socket.on('subscribe_status', async (data) => {
    const { user_id } = data || {};
    if (!user_id) return;
    socket.join(`status:${user_id}`);
    const visible = await _canShowOnline(String(user_id));
    const online = visible ? isOnline(String(user_id)) : false;
    socket.emit('online_status', {
      user_id: String(user_id),
      is_online: online,
      last_seen: (!online && visible) ? await _getLastSeen(String(user_id)) : null,
    });
  });

  socket.on('unsubscribe_status', (data) => {
    const { user_id } = data || {};
    if (user_id) socket.leave(`status:${user_id}`);
  });

  // ── get_online_status (bulk) ──────────────────────────────────────────────
  socket.on('get_online_status', async (data, ack) => {
    const { user_ids } = data || {};
    if (!ack || !Array.isArray(user_ids)) return;
    const result = {};
    for (const uid of user_ids) {
      const visible = await _canShowOnline(String(uid));
      result[String(uid)] = visible ? isOnline(String(uid)) : false;
    }
    ack(result);
  });

  // ── disconnect ───────────────────────────────────────────────────────────────
  socket.on('disconnect', () => {
    removeOnline(userId, socket.id);
    const stillOnline = isOnline(userId);

    if (!stillOnline) {
      db.query(
        'UPDATE users SET is_online = 0, last_seen = NOW() WHERE id = ?',
        [userId]
      ).catch(() => {});
      _broadcastStatus(userId, false);
    }
  });
});

// ── Helpers ───────────────────────────────────────────────────────────────────

// Returns true if others are allowed to see this user's online status.
// Defaults to true if the column doesn't exist or query fails.
async function _canShowOnline(userId) {
  try {
    const [rows] = await db.query(
      'SELECT COALESCE(privacy_show_online, 1) AS v FROM users WHERE id = ? LIMIT 1',
      [userId]
    );
    return rows.length > 0 ? rows[0].v !== 0 : true;
  } catch (_) {
    return true;
  }
}

async function _getLastSeen(userId) {
  try {
    const [rows] = await db.query(
      'SELECT COALESCE(privacy_show_last_seen, 1) AS show_ls, last_seen FROM users WHERE id = ? LIMIT 1',
      [userId]
    );
    if (!rows.length || rows[0].show_ls === 0) return null;
    return rows[0].last_seen ? String(rows[0].last_seen) : null;
  } catch (_) {
    return null;
  }
}

async function _broadcastStatus(userId, online) {
  const visible = await _canShowOnline(userId);
  io.to(`status:${userId}`).emit('online_status', {
    user_id: userId,
    is_online: visible ? online : false,
    last_seen: (!online && visible) ? await _getLastSeen(userId) : null,
  });
}

function _formatMessage(row) {
  return {
    id: String(row.id),
    sender_id: String(row.sender_id),
    receiver_id: String(row.receiver_id),
    type: row.type || 'text',
    content: row.content || null,
    media_url: row.media_url || null,
    status: row.status || 'sent',
    created_at: row.created_at instanceof Date
      ? row.created_at.toISOString()
      : String(row.created_at),
    read_at: row.read_at
      ? (row.read_at instanceof Date ? row.read_at.toISOString() : String(row.read_at))
      : null,
  };
}

// ── Start ─────────────────────────────────────────────────────────────────────
const PORT = 3001;
httpServer.listen(PORT, '127.0.0.1', () => {
  console.log(`[Goreto Socket] Listening on 127.0.0.1:${PORT}`);
});
