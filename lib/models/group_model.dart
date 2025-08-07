import 'dart:math';

class GroupModel {
  final String id;
  final String name;
  final String? description;
  final List<String> memberIds;
  final String createdBy;
  final DateTime createdAt;
  final String currency;
  final String? imageUrl;
  final String? inviteCode;
  final bool inviteCodeEnabled;
  final DateTime? inviteCodeExpiresAt;
  final int? maxMembers;
  final Map<String, dynamic>? metadata;

  GroupModel({
    required this.id,
    required this.name,
    this.description,
    required this.memberIds,
    required this.createdBy,
    required this.createdAt,
    this.currency = 'EUR',
    this.imageUrl,
    this.inviteCode,
    this.inviteCodeEnabled = false,
    this.inviteCodeExpiresAt,
    this.maxMembers,
    this.metadata,
  });

  // Generate a random 6-character invite code
  static String generateInviteCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    Random random = Random();
    return String.fromCharCodes(Iterable.generate(
        6, (_) => chars.codeUnitAt(random.nextInt(chars.length))));
  }

  // Update your existing toMap method
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'memberIds': memberIds,
      'createdBy': createdBy,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'currency': currency,
      'inviteCode': inviteCode,
      'inviteCodeEnabled': inviteCodeEnabled,
      'inviteCodeExpiresAt': inviteCodeExpiresAt?.millisecondsSinceEpoch,
      'maxMembers': maxMembers,
      'metadata': metadata,
    };
  }

  // Update your existing fromMap method
  factory GroupModel.fromMap(Map<String, dynamic> map) {
    return GroupModel(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      description: map['description'],
      memberIds: List<String>.from(map['memberIds'] ?? []),
      createdBy: map['createdBy'] ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] ?? 0),
      currency: map['currency'] ?? 'EUR',
      inviteCode: map['inviteCode'],
      inviteCodeEnabled: map['inviteCodeEnabled'] ?? false,
      inviteCodeExpiresAt: map['inviteCodeExpiresAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['inviteCodeExpiresAt'])
          : null,
      maxMembers: map['maxMembers'],
      metadata: map['metadata'] != null ? Map<String, dynamic>.from(map['metadata']) : null,
    );
  }

  // Copy with modifications
  GroupModel copyWith({
    String? id,
    String? name,
    String? description,
    List<String>? memberIds,
    String? createdBy,
    DateTime? createdAt,
    String? currency,
    String? inviteCode,
    bool? inviteCodeEnabled,
    DateTime? inviteCodeExpiresAt,
    int? maxMembers,
    Map<String, dynamic>? metadata,
  }) {
    return GroupModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      memberIds: memberIds ?? this.memberIds,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      currency: currency ?? this.currency,
      inviteCode: inviteCode ?? this.inviteCode,
      inviteCodeEnabled: inviteCodeEnabled ?? this.inviteCodeEnabled,
      inviteCodeExpiresAt: inviteCodeExpiresAt ?? this.inviteCodeExpiresAt,
      maxMembers: maxMembers ?? this.maxMembers,
      metadata: metadata ?? this.metadata,
    );
  }

  // Helper methods
  bool get hasActiveInviteCode => inviteCodeEnabled &&
      inviteCode != null &&
      (inviteCodeExpiresAt == null || inviteCodeExpiresAt!.isAfter(DateTime.now()));

  bool get canAcceptNewMembers => maxMembers == null || memberIds.length < maxMembers!;

  // Add member to group
  GroupModel addMember(String userId) {
    if (!memberIds.contains(userId)) {
      return copyWith(memberIds: [...memberIds, userId]);
    }
    return this;
  }

  // Remove member from group
  GroupModel removeMember(String userId) {
    return copyWith(memberIds: memberIds.where((id) => id != userId).toList());
  }

  // Check if user is member
  bool isMember(String userId) {
    return memberIds.contains(userId);
  }

  // Check if user is creator
  bool isCreator(String userId) => createdBy == userId;


  @override
  String toString() {
    return 'GroupModel(id: $id, name: $name, members: ${memberIds.length})';
  }
}