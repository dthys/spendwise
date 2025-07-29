class GroupModel {
  final String id;
  final String name;
  final String? description;
  final List<String> memberIds;
  final String createdBy;
  final DateTime createdAt;
  final String currency;
  final String? imageUrl;

  GroupModel({
    required this.id,
    required this.name,
    this.description,
    required this.memberIds,
    required this.createdBy,
    required this.createdAt,
    this.currency = 'EUR',
    this.imageUrl,
  });

  // Convert to Map for Firebase
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'memberIds': memberIds,
      'createdBy': createdBy,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'currency': currency,
      'imageUrl': imageUrl,
    };
  }

  // Create from Firebase Map
  factory GroupModel.fromMap(Map<String, dynamic> map) {
    return GroupModel(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      description: map['description'],
      memberIds: List<String>.from(map['memberIds'] ?? []),
      createdBy: map['createdBy'] ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] ?? 0),
      currency: map['currency'] ?? 'EUR',
      imageUrl: map['imageUrl'],
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
    String? imageUrl,
  }) {
    return GroupModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      memberIds: memberIds ?? this.memberIds,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      currency: currency ?? this.currency,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }

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
  bool isCreator(String userId) {
    return createdBy == userId;
  }

  @override
  String toString() {
    return 'GroupModel(id: $id, name: $name, members: ${memberIds.length})';
  }
}