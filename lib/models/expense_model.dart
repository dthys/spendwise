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

  // Check if expense is settled for a user
  bool isSettledFor(String userId) {
    return paidBy == userId; // Simplified - in real app you'd track settlements
  }

  @override
  String toString() {
    return 'ExpenseModel(id: $id, description: $description, amount: €$amount, paidBy: $paidBy)';
  }
}