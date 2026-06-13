<?php
/**
 * api_recommendations.php — People you may know + nearby friends
 *
 * GET ?action=users    → people you may know (mutual connections, same area)
 * GET ?action=creators → top active creators
 * GET ?action=nearby   → users near the viewer's last known location
 */
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Content-Type, Authorization');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') { http_response_code(200); exit; }

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/auth_middleware.php';

function out(array $d, int $code = 200): void {
    http_response_code($code);
    echo json_encode($d);
    exit;
}

function resolveAvatar(string $pic, string $base = 'https://goreto.org/ekloadmin/'): string {
    if ($pic === '') return '';
    if (preg_match('~^https?://~i', $pic)) return $pic;
    return $base . ltrim($pic, '/');
}

try {
    $viewer = requireUser($pdo);
    $me     = (int)$viewer['id'];

    $action = strtolower(trim($_GET['action'] ?? $_POST['action'] ?? 'users'));
    $limit  = min(30, max(1, (int)($_GET['limit'] ?? 20)));

    // ── People you may know ──────────────────────────────────────────────────
    if ($action === 'users') {
        $meInt   = (int)$me;
        $limInt  = (int)$limit;
        // 2nd-degree: people followed by who I follow, that I don't already follow
        $st = $pdo->query("
            SELECT u.id, u.name, u.username, COALESCE(u.profile_pic,'') AS profile_pic,
                   COUNT(DISTINCT f2.follower_id) AS mutual_count
            FROM follows f1
            JOIN follows f2 ON f2.following_id = f1.following_id
            JOIN users u ON u.id = f2.follower_id
            WHERE f1.follower_id = $meInt
              AND f2.follower_id != $meInt
              AND u.id != $meInt
              AND u.is_banned = 0
              AND NOT EXISTS (SELECT 1 FROM follows fx WHERE fx.follower_id=$meInt AND fx.following_id=u.id)
              AND NOT EXISTS (SELECT 1 FROM user_blocks b WHERE (b.blocker_id=$meInt AND b.blocked_id=u.id) OR (b.blocker_id=u.id AND b.blocked_id=$meInt))
            GROUP BY u.id
            ORDER BY mutual_count DESC
            LIMIT $limInt");
        $rows = $st->fetchAll(PDO::FETCH_ASSOC);

        // Fallback: popular unfollowed users if not enough results
        if (count($rows) < 5) {
            $excludeIds = array_map('intval', array_column($rows, 'id'));
            $excludeIds[] = $meInt;
            $excList = implode(',', $excludeIds);
            $fallLim = $limInt - count($rows);
            $fb = $pdo->query("
                SELECT u.id, u.name, u.username, COALESCE(u.profile_pic,'') AS profile_pic,
                       0 AS mutual_count
                FROM users u
                LEFT JOIN match_profiles mp ON mp.user_id = u.id
                WHERE u.id NOT IN ($excList)
                  AND u.is_banned = 0
                  AND (mp.is_visible IS NULL OR mp.is_visible = 1)
                  AND NOT EXISTS (SELECT 1 FROM follows fx WHERE fx.follower_id=$meInt AND fx.following_id=u.id)
                ORDER BY COALESCE(mp.rating,0) DESC
                LIMIT $fallLim");
            $rows = array_merge($rows, $fb->fetchAll(PDO::FETCH_ASSOC));
        }

        // Enrich with place / age / rating / distance. Distance is only shown
        // when the TARGET user shares it (privacy_share_distance) and the
        // viewer has a known location.
        $myLat = null; $myLng = null;
        $locSt = $pdo->prepare("SELECT lat, lng FROM match_profiles WHERE user_id = ? AND lat IS NOT NULL LIMIT 1");
        $locSt->execute([$meInt]);
        if ($locRow = $locSt->fetch(PDO::FETCH_ASSOC)) {
            $myLat = (float)$locRow['lat'];
            $myLng = (float)$locRow['lng'];
        }
        $enrich = [];
        $ids = array_filter(array_map('intval', array_column($rows, 'id')));
        if ($ids) {
            $inList = implode(',', $ids);
            $est = $pdo->query("SELECT u.id, u.location AS u_location, mp.location AS mp_location, mp.age, mp.rating, mp.lat, mp.lng, COALESCE(u.privacy_share_distance, 1) AS share_dist FROM users u LEFT JOIN match_profiles mp ON mp.user_id = u.id WHERE u.id IN ($inList)");
            foreach ($est->fetchAll(PDO::FETCH_ASSOC) as $e) { $enrich[(int)$e['id']] = $e; }
        }

        $users = array_map(function ($r) use ($enrich, $myLat, $myLng) {
            $e = $enrich[(int)$r['id']] ?? [];
            $place = trim((string)($e['mp_location'] ?? ''));
            if ($place === '') $place = trim((string)($e['u_location'] ?? ''));
            $share = (int)($e['share_dist'] ?? 1) === 1;
            $dist = -1.0;
            if ($share && $myLat !== null && isset($e['lat']) && $e['lat'] !== null && isset($e['lng']) && $e['lng'] !== null) {
                $la = deg2rad($myLat); $lb = deg2rad((float)$e['lat']);
                $dLat = deg2rad((float)$e['lat'] - $myLat);
                $dLng = deg2rad((float)$e['lng'] - $myLng);
                $h = sin($dLat / 2) ** 2 + cos($la) * cos($lb) * sin($dLng / 2) ** 2;
                $dist = round(6371 * 2 * atan2(sqrt($h), sqrt(1 - $h)), 1);
            }
            return [
                'id'           => (string)$r['id'],
                'name'         => $r['name'] ?? '',
                'username'     => $r['username'] ?? '',
                'avatar'       => resolveAvatar($r['profile_pic'] ?? ''),
                'mutual_count' => (int)$r['mutual_count'],
                'distance_km'  => $dist,
                'place'        => $place,
                'age'          => isset($e['age']) ? (int)$e['age'] : 0,
                'rating'       => isset($e['rating']) ? round((float)$e['rating'], 1) : 0,
            ];
        }, $rows);
        out(['status' => 'success', 'users' => $users]);
    }

        // ── Nearby friends ────────────────────────────────────────────────────────
    if ($action === 'nearby') {
        // Use the viewer's last known location from match_profiles
        $locSt = $pdo->prepare("SELECT lat, lng FROM match_profiles WHERE user_id = ? AND lat IS NOT NULL LIMIT 1");
        $locSt->execute([$me]);
        $loc = $locSt->fetch(PDO::FETCH_ASSOC);

        if (!$loc) {
            out(['status' => 'success', 'users' => []]);
        }

        $lat = (float)$loc['lat'];
        $lng = (float)$loc['lng'];

        $st = $pdo->prepare("
            SELECT u.id, u.name, u.username, COALESCE(u.profile_pic,'') AS profile_pic,
                   (6371 * acos(
                       cos(radians(:lat)) * cos(radians(mp.lat)) *
                       cos(radians(mp.lng) - radians(:lng)) +
                       sin(radians(:lat2)) * sin(radians(mp.lat))
                   )) AS distance_km
            FROM match_profiles mp
            JOIN users u ON u.id = mp.user_id
            WHERE mp.user_id != :me
              AND mp.is_visible = 1
              AND u.is_banned = 0
              AND mp.lat IS NOT NULL
              AND mp.last_location_update >= DATE_SUB(UTC_TIMESTAMP(), INTERVAL 60 MINUTE)
              AND COALESCE(u.privacy_nearby_visible, 1) = 1
              AND NOT EXISTS (
                  SELECT 1 FROM follows fx WHERE fx.follower_id = :me2 AND fx.following_id = u.id
              )
              AND NOT EXISTS (
                  SELECT 1 FROM user_blocks b
                  WHERE (b.blocker_id = :me3 AND b.blocked_id = u.id)
                     OR (b.blocker_id = u.id AND b.blocked_id = :me4)
              )
            HAVING distance_km <= 10
            ORDER BY distance_km ASC
            LIMIT $limit");

        $st->bindValue(':lat',  $lat, PDO::PARAM_STR);
        $st->bindValue(':lng',  $lng, PDO::PARAM_STR);
        $st->bindValue(':lat2', $lat, PDO::PARAM_STR);
        $st->bindValue(':me',   $me,  PDO::PARAM_INT);
        $st->bindValue(':me2',  $me,  PDO::PARAM_INT);
        $st->bindValue(':me3',  $me,  PDO::PARAM_INT);
        $st->bindValue(':me4',  $me,  PDO::PARAM_INT);
        $st->execute();
        $rows = $st->fetchAll(PDO::FETCH_ASSOC);

        $users = array_map(fn($r) => [
            'id'          => (string)$r['id'],
            'name'        => $r['name'] ?? '',
            'username'    => $r['username'] ?? '',
            'avatar'      => resolveAvatar($r['profile_pic'] ?? ''),
            'distance_km' => round((float)$r['distance_km'], 1),
        ], $rows);

        out(['status' => 'success', 'users' => $users]);
    }

    // ── Creators ──────────────────────────────────────────────────────────────
    if ($action === 'creators') {
        $st = $pdo->prepare("
            SELECT u.id, u.name, u.username, COALESCE(u.profile_pic,'') AS profile_pic,
                   COALESCE(mp.rating, 0) AS rating,
                   (SELECT COUNT(*) FROM follows WHERE following_id = u.id) AS followers_count
            FROM users u
            LEFT JOIN match_profiles mp ON mp.user_id = u.id
            WHERE u.id != :me
              AND u.is_banned = 0
              AND mp.is_visible = 1
              AND NOT EXISTS (SELECT 1 FROM follows fx WHERE fx.follower_id=:me2 AND fx.following_id=u.id)
            ORDER BY mp.rating DESC, followers_count DESC
            LIMIT $limit");
        $st->bindValue(':me',  $me,  PDO::PARAM_INT);
        $st->bindValue(':me2', $me,  PDO::PARAM_INT);
                $st->execute();
        $rows = $st->fetchAll(PDO::FETCH_ASSOC);

        $users = array_map(fn($r) => [
            'id'              => (string)$r['id'],
            'name'            => $r['name'] ?? '',
            'username'        => $r['username'] ?? '',
            'avatar'          => resolveAvatar($r['profile_pic'] ?? ''),
            'followers_count' => (int)$r['followers_count'],
        ], $rows);

        out(['status' => 'success', 'users' => $users]);
    }

    out(['status' => 'error', 'message' => 'Unknown action'], 400);
} catch (Throwable $e) {
    http_response_code(500);
    echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
}
