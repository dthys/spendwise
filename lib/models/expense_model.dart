enum SplitType {
  equal,      // Split equally among all participants
  exact,      // Exact amounts per person
  percentage, // Percentage based split
}

enum ExpenseCategory {
  food('Food & Drinks', '🍕'),
  transport('Transport', '🚗'),
  accommodation('Accommodation', '🏠'),
  entertainment('Entertainment', '🎬'),
  shopping('Shopping', '🛍️'),
  bills('Bills & Utilities', '💡'),
  healthcare('Healthcare', '🏥'),
  other('Other', '📝');


  const ExpenseCategory(this.displayName, this.emoji);
  final String displayName;
  final String emoji;
}

class ExpenseModel {
  final String id;
  final String groupId;
  final String description;
  final double amount;
  final String paidBy;
  final List<String> splitBetween;
  final Map<String, double> customSplits; // For exact amounts or percentages
  final SplitType splitType;
  final ExpenseCategory category;
  final DateTime date;
  final DateTime createdAt;
  final String? receiptUrl;
  final String? notes;

  // NEW: Track which users have settled this expense
  final Map<String, bool> settledByUser;

  ExpenseModel({
    required this.id,
    required this.groupId,
    required this.description,
    required this.amount,
    required this.paidBy,
    required this.splitBetween,
    this.customSplits = const {},
    this.splitType = SplitType.equal,
    this.category = ExpenseCategory.other,
    required this.date,
    required this.createdAt,
    this.receiptUrl,
    this.notes,
    this.settledByUser = const {}, // NEW: Default to empty map
  });


  // Convert to Map for Firebase
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'groupId': groupId,
      'description': description,
      'amount': amount,
      'paidBy': paidBy,
      'splitBetween': splitBetween,
      'customSplits': customSplits,
      'splitType': splitType.name,
      'category': category.name,
      'date': date.millisecondsSinceEpoch,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'receiptUrl': receiptUrl,
      'notes': notes,
      'settledByUser': settledByUser, // NEW: Add to Firebase
    };
  }

  // Create from Firebase Map
  factory ExpenseModel.fromMap(Map<String, dynamic> map) {
    return ExpenseModel(
      id: map['id'] ?? '',
      groupId: map['groupId'] ?? '',
      description: map['description'] ?? '',
      amount: (map['amount'] ?? 0).toDouble(),
      paidBy: map['paidBy'] ?? '',
      splitBetween: List<String>.from(map['splitBetween'] ?? []),
      customSplits: Map<String, double>.from(map['customSplits'] ?? {}),
      splitType: SplitType.values.firstWhere(
            (e) => e.name == map['splitType'],
        orElse: () => SplitType.equal,
      ),
      category: ExpenseCategory.values.firstWhere(
            (e) => e.name == map['category'],
        orElse: () => ExpenseCategory.other,
      ),
      date: DateTime.fromMillisecondsSinceEpoch(map['date'] ?? 0),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] ?? 0),
      receiptUrl: map['receiptUrl'],
      notes: map['notes'],
      settledByUser: Map<String, bool>.from(map['settledByUser'] ?? {}), // NEW: Read from Firebase
    );
  }

  // Copy with modifications
  ExpenseModel copyWith({
    String? id,
    String? groupId,
    String? description,
    double? amount,
    String? paidBy,
    List<String>? splitBetween,
    Map<String, double>? customSplits,
    SplitType? splitType,
    ExpenseCategory? category,
    DateTime? date,
    DateTime? createdAt,
    String? receiptUrl,
    String? notes,
    Map<String, bool>? settledByUser, // NEW: Add to copyWith
  }) {
    return ExpenseModel(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      description: description ?? this.description,
      amount: amount ?? this.amount,
      paidBy: paidBy ?? this.paidBy,
      splitBetween: splitBetween ?? this.splitBetween,
      customSplits: customSplits ?? this.customSplits,
      splitType: splitType ?? this.splitType,
      category: category ?? this.category,
      date: date ?? this.date,
      createdAt: createdAt ?? this.createdAt,
      receiptUrl: receiptUrl ?? this.receiptUrl,
      notes: notes ?? this.notes,
      settledByUser: settledByUser ?? this.settledByUser, // NEW: Include in copyWith
    );
  }

  // Calculate individual share for equal split
  double getEqualShare() {
    if (splitBetween.isEmpty) return 0;
    return amount / splitBetween.length;
  }

  // Get amount owed by specific user
  double getAmountOwedBy(String userId) {
    if (!splitBetween.contains(userId)) return 0;

    switch (splitType) {
      case SplitType.equal:
        return getEqualShare();
      case SplitType.exact:
        return customSplits[userId] ?? 0;
      case SplitType.percentage:
        final percentage = customSplits[userId] ?? 0;
        return amount * (percentage / 100);
    }
  }

  // UPDATED: Check if expense is settled for a user (using settlement tracking)
  bool isSettledFor(String userId) {
    return settledByUser[userId] ?? false;
  }

  // NEW: Check if expense is settled for a specific user (alias for consistency)
  bool isSettledForUser(String userId) {
    return isSettledFor(userId);
  }

  // NEW: Check if expense is fully settled for all participants
  bool isFullySettled() {
    for (String participant in splitBetween) {
      if (participant != paidBy && !isSettledForUser(participant)) {
        return false;
      }
    }
    return true;
  }

  // NEW: Get unsettled participants (those who still owe money)
  List<String> getUnsettledParticipants() {
    return splitBetween
        .where((participant) => participant != paidBy && !isSettledForUser(participant))
        .toList();
  }

  // NEW: Create a copy with updated settlement status for a specific user
  ExpenseModel copyWithSettlement(String userId, bool isSettled) {
    Map<String, bool> newSettledByUser = Map.from(settledByUser);
    newSettledByUser[userId] = isSettled;

    return copyWith(
      settledByUser: newSettledByUser,
    );
  }

  @override
  String toString() {
    return 'ExpenseModel(id: $id, description: $description, amount: €$amount, paidBy: $paidBy, settled: $settledByUser)';
  }
}