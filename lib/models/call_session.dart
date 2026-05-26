import 'package:uuid/uuid.dart';

enum CallType { audio, video }

enum CallState {
  idle,
  outgoing,
  incoming,
  connecting,
  connected,
  ended,
  declined,
  missed,
  failed,
}

class CallSession {
  final String id;
  final String callerId;
  final String callerName;
  final String? callerAvatar;
  final String receiverId;
  final String receiverName;
  final String? receiverAvatar;
  final CallType type;
  final CallState state;
  final DateTime startedAt;
  final DateTime? connectedAt;
  final DateTime? endedAt;
  final Duration? duration;
  final String? endReason;
  final bool isRandomCall;

  CallSession({
    String? id,
    required this.callerId,
    required this.callerName,
    this.callerAvatar,
    required this.receiverId,
    required this.receiverName,
    this.receiverAvatar,
    required this.type,
    this.state = CallState.idle,
    DateTime? startedAt,
    this.connectedAt,
    this.endedAt,
    this.duration,
    this.endReason,
    this.isRandomCall = false,
  }) : id = id ?? const Uuid().v4(),
       startedAt = startedAt ?? DateTime.now();

  bool get isOutgoing => state == CallState.outgoing;
  bool get isIncoming => state == CallState.incoming;

  Duration? get callDuration {
    if (connectedAt != null && endedAt != null) {
      return endedAt!.difference(connectedAt!);
    }
    if (connectedAt != null && state == CallState.connected) {
      return DateTime.now().difference(connectedAt!);
    }
    return null;
  }

  CallSession copyWith({
    String? id,
    String? callerId,
    String? callerName,
    String? callerAvatar,
    String? receiverId,
    String? receiverName,
    String? receiverAvatar,
    CallType? type,
    CallState? state,
    DateTime? startedAt,
    DateTime? connectedAt,
    DateTime? endedAt,
    Duration? duration,
    String? endReason,
    bool? isRandomCall,
  }) {
    return CallSession(
      id: id ?? this.id,
      callerId: callerId ?? this.callerId,
      callerName: callerName ?? this.callerName,
      callerAvatar: callerAvatar ?? this.callerAvatar,
      receiverId: receiverId ?? this.receiverId,
      receiverName: receiverName ?? this.receiverName,
      receiverAvatar: receiverAvatar ?? this.receiverAvatar,
      type: type ?? this.type,
      state: state ?? this.state,
      startedAt: startedAt ?? this.startedAt,
      connectedAt: connectedAt ?? this.connectedAt,
      endedAt: endedAt ?? this.endedAt,
      duration: duration ?? this.duration,
      endReason: endReason ?? this.endReason,
      isRandomCall: isRandomCall ?? this.isRandomCall,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'caller_id': callerId,
      'caller_name': callerName,
      'caller_avatar': callerAvatar,
      'receiver_id': receiverId,
      'receiver_name': receiverName,
      'receiver_avatar': receiverAvatar,
      'type': type.name,
      'state': state.name,
      'started_at': startedAt.toIso8601String(),
      'connected_at': connectedAt?.toIso8601String(),
      'ended_at': endedAt?.toIso8601String(),
      'duration': duration?.inSeconds,
      'end_reason': endReason,
      'is_random_call': isRandomCall,
    };
  }

  factory CallSession.fromJson(Map<String, dynamic> json) {
    return CallSession(
      id: json['id'],
      callerId: json['caller_id'],
      callerName: json['caller_name'] ?? 'Unknown',
      callerAvatar: json['caller_avatar'],
      receiverId: json['receiver_id'],
      receiverName: json['receiver_name'] ?? 'Unknown',
      receiverAvatar: json['receiver_avatar'],
      type: CallType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => CallType.audio,
      ),
      state: CallState.values.firstWhere(
        (e) => e.name == json['state'],
        orElse: () => CallState.idle,
      ),
      startedAt: DateTime.tryParse(json['started_at'] ?? '') ?? DateTime.now(),
      connectedAt: json['connected_at'] != null
          ? DateTime.tryParse(json['connected_at'])
          : null,
      endedAt: json['ended_at'] != null
          ? DateTime.tryParse(json['ended_at'])
          : null,
      duration: json['duration'] != null
          ? Duration(seconds: json['duration'])
          : null,
      endReason: json['end_reason'],
      isRandomCall: json['is_random_call'] == true,
    );
  }
}

/// WebRTC session description wrapper
class SessionDescription {
  final String type; // 'offer' or 'answer'
  final String sdp;

  SessionDescription({required this.type, required this.sdp});

  Map<String, dynamic> toJson() => {'type': type, 'sdp': sdp};

  factory SessionDescription.fromJson(Map<String, dynamic> json) {
    return SessionDescription(type: json['type'], sdp: json['sdp']);
  }
}

/// ICE candidate wrapper
class IceCandidate {
  final String candidate;
  final String sdpMid;
  final int sdpMLineIndex;

  IceCandidate({
    required this.candidate,
    required this.sdpMid,
    required this.sdpMLineIndex,
  });

  Map<String, dynamic> toJson() => {
    'candidate': candidate,
    'sdpMid': sdpMid,
    'sdpMLineIndex': sdpMLineIndex,
  };

  factory IceCandidate.fromJson(Map<String, dynamic> json) {
    return IceCandidate(
      candidate: json['candidate'],
      sdpMid: json['sdpMid'],
      sdpMLineIndex: json['sdpMLineIndex'],
    );
  }
}
