class LastSeenModel {
  final String id;
  final String userId;
  final String groupId;
  final DateTime lastSeenActivityTime;
  final DateTime updatedAt;

  LastSeenModel({
    required this.id,
    required this.userId,
    required this.groupId,
    required this.lastSeenActivityTime,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'groupId': groupId,
      'lastSeenActivityTime': lastSeenActivityTime.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory LastSeenModel.fromMap(Map<String, dynamic> map) {
    return LastSeenModel(
      id: map['id'] ?? '',
      userId: map['userId'] ?? '',
      groupId: map['groupId'] ?? '',
      lastSeenActivityTime: DateTime.fromMillisecondsSinceEpoch(map['lastSeenActivityTime'] ?? 0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updatedAt'] ?? 0),
    );
  }

  LastSeenModel copyWith({
    String? id,
    String? userId,
    String? groupId,
    DateTime? lastSeenActivityTime,
    DateTime? updatedAt,
  }) {
    return LastSeenModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      groupId: groupId ?? this.groupId,
      lastSeenActivityTime: lastSeenActivityTime ?? this.lastSeenActivityTime,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}