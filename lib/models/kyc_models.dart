class KycStatusModel {
  final String basicStatus;
  final String fullStatus;
  final String adminNote;

  const KycStatusModel({
    required this.basicStatus,
    required this.fullStatus,
    required this.adminNote,
  });

  static const KycStatusModel empty = KycStatusModel(
    basicStatus: 'none',
    fullStatus: 'none',
    adminNote: '',
  );

  bool get basicApproved => basicStatus.toLowerCase() == 'approved' || basicStatus.toLowerCase() == 'verified';
  bool get fullApproved => fullStatus.toLowerCase() == 'approved' || fullStatus.toLowerCase() == 'verified';

  factory KycStatusModel.fromJson(Map<String, dynamic> json) {
    return KycStatusModel(
      basicStatus: (json['basic_status'] ?? json['basic'] ?? 'none').toString(),
      fullStatus: (json['full_status'] ?? json['full'] ?? 'none').toString(),
      adminNote: (json['admin_note'] ?? json['note'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'basic_status': basicStatus,
        'full_status': fullStatus,
        'admin_note': adminNote,
      };
}

class KycTaskModel {
  final String taskId;
  final String level;
  final String instruction;

  const KycTaskModel({
    required this.taskId,
    required this.level,
    required this.instruction,
  });

  factory KycTaskModel.fromJson(Map<String, dynamic> json, {String? level}) {
    return KycTaskModel(
      taskId: (json['task_id'] ?? json['id'] ?? '').toString(),
      level: (json['level'] ?? level ?? '').toString(),
      instruction: (json['instruction'] ?? json['task'] ?? '').toString(),
    );
  }
}
