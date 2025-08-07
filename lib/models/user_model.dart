class UserModel {
  final String id;
  final String name;
  final String email;
  final String? photoUrl;
  final List<String> groupIds;
  final DateTime createdAt;
  final String? bankAccount; // IBAN nummer

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    this.photoUrl,
    required this.groupIds,
    required this.createdAt,
    this.bankAccount,
  });

  // Convert to Map for Firebase
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'photoUrl': photoUrl,
      'groupIds': groupIds,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'bankAccount': bankAccount,
    };
  }

  // Create from Firebase Map
  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      photoUrl: map['photoUrl'],
      groupIds: List<String>.from(map['groupIds'] ?? []),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] ?? 0),
      bankAccount: map['bankAccount'],
    );
  }

  static UserModel empty() {
    return UserModel(
      id: '',
      name: 'Unknown User',
      email: '',
      createdAt: DateTime.now(),
      groupIds: [],
    );
  }

  // Create from Firebase Auth User
  factory UserModel.fromFirebaseUser(String id, String name, String email, String? photoUrl) {
    return UserModel(
      id: id,
      name: name,
      email: email,
      photoUrl: photoUrl,
      groupIds: [],
      createdAt: DateTime.now(),
      bankAccount: null,
    );
  }

  // Copy with modifications
  UserModel copyWith({
    String? id,
    String? name,
    String? email,
    String? photoUrl,
    List<String>? groupIds,
    DateTime? createdAt,
    String? bankAccount,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      groupIds: groupIds ?? this.groupIds,
      createdAt: createdAt ?? this.createdAt,
      bankAccount: bankAccount ?? this.bankAccount,
    );
  }

  @override
  String toString() {
    return 'UserModel(id: $id, name: $name, email: $email, groupIds: $groupIds, bankAccount: $bankAccount)';
  }
}