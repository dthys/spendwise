class ActivityLogModel {
  final String id;
  final String groupId;
  final String userId; // Who performed the action
  final String userName; // Cache the user's name
  final ActivityType type;
  final String description;
  final Map<String, dynamic> metadata; // Store expense details, old values, etc.
  final DateTime timestamp;

  ActivityLogModel({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.userName,
    required this.type,
    required this.description,
    required this.metadata,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'groupId': groupId,
      'userId': userId,
      'userName': userName,
      'type': type.name,
      'description': description,
      'metadata': metadata,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  factory ActivityLogModel.fromMap(Map<String, dynamic> map) {
    return ActivityLogModel(
      id: map['id'] ?? '',
      groupId: map['groupId'] ?? '',
      userId: map['userId'] ?? '',
      userName: map['userName'] ?? '',
      type: ActivityType.values.firstWhere(
            (e) => e.name == map['type'],
        orElse: () => ActivityType.other,
      ),
      description: map['description'] ?? '',
      metadata: Map<String, dynamic>.from(map['metadata'] ?? {}),
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] ?? 0),
    );
  }
}

enum ActivityType {
  expenseAdded,
  expenseEdited,
  expenseDeleted,
  memberAdded,
  memberRemoved,
  groupCreated,
  other,
}

extension ActivityTypeExtension on ActivityType {
  String get displayName {
    switch (this) {
      case ActivityType.expenseAdded:
        return 'Expense Added';
      case ActivityType.expenseEdited:
        return 'Expense Edited';
      case ActivityType.expenseDeleted:
        return 'Expense Deleted';
      case ActivityType.memberAdded:
        return 'Member Added';
      case ActivityType.memberRemoved:
        return 'Member Removed';
      case ActivityType.groupCreated:
        return 'Group Created';
      case ActivityType.other:
        return 'Activity';
    }
  }

  String get emoji {
    switch (this) {
      case ActivityType.expenseAdded:
        return '➕';
      case ActivityType.expenseEdited:
        return '✏️';
      case ActivityType.expenseDeleted:
        return '🗑️';
      case ActivityType.memberAdded:
        return '👥';
      case ActivityType.memberRemoved:
        return '👤';
      case ActivityType.groupCreated:
        return '🎉';
      case ActivityType.other:
        return 'ℹ️';
    }
  }
}