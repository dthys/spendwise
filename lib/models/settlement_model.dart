// models/settlement_model.dart
class SettlementModel {
  final String id;
  final String groupId;
  final String fromUserId;  // Who paid
  final String toUserId;    // Who received
  final double amount;
  final DateTime settledAt;
  final String? notes;
  final String? transactionId; // Optional: bank transfer reference
  final SettlementMethod method;
  final List<String> settledExpenseIds; // NEW: Track which expenses are settled

  SettlementModel({
    required this.id,
    required this.groupId,
    required this.fromUserId,
    required this.toUserId,
    required this.amount,
    required this.settledAt,
    this.notes,
    this.transactionId,
    this.method = SettlementMethod.cash,
    this.settledExpenseIds = const [], // NEW: Default to empty list
  });

  // Convert to Map for Firebase
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'groupId': groupId,
      'fromUserId': fromUserId,
      'toUserId': toUserId,
      'amount': amount,
      'settledAt': settledAt.millisecondsSinceEpoch,
      'notes': notes,
      'transactionId': transactionId,
      'method': method.name,
      'settledExpenseIds': settledExpenseIds, // NEW: Include in serialization
    };
  }

  // Create from Firebase Map
  factory SettlementModel.fromMap(Map<String, dynamic> map) {
    return SettlementModel(
      id: map['id'] ?? '',
      groupId: map['groupId'] ?? '',
      fromUserId: map['fromUserId'] ?? '',
      toUserId: map['toUserId'] ?? '',
      amount: (map['amount'] ?? 0).toDouble(),
      settledAt: DateTime.fromMillisecondsSinceEpoch(map['settledAt'] ?? 0),
      notes: map['notes'],
      transactionId: map['transactionId'],
      method: SettlementMethod.values.firstWhere(
            (e) => e.name == map['method'],
        orElse: () => SettlementMethod.cash,
      ),
      settledExpenseIds: List<String>.from(map['settledExpenseIds'] ?? []), // NEW: Parse expense IDs
    );
  }

  // Copy with modifications
  SettlementModel copyWith({
    String? id,
    String? groupId,
    String? fromUserId,
    String? toUserId,
    double? amount,
    DateTime? settledAt,
    String? notes,
    String? transactionId,
    SettlementMethod? method,
    List<String>? settledExpenseIds, // NEW: Allow copying with different expense IDs
  }) {
    return SettlementModel(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      fromUserId: fromUserId ?? this.fromUserId,
      toUserId: toUserId ?? this.toUserId,
      amount: amount ?? this.amount,
      settledAt: settledAt ?? this.settledAt,
      notes: notes ?? this.notes,
      transactionId: transactionId ?? this.transactionId,
      method: method ?? this.method,
      settledExpenseIds: settledExpenseIds ?? this.settledExpenseIds,
    );
  }

  @override
  String toString() {
    return 'SettlementModel(id: $id, from: $fromUserId, to: $toUserId, amount: €$amount, expenses: ${settledExpenseIds.length})';
  }
}

enum SettlementMethod {
  cash('Cash', '💵'),
  bankTransfer('Bank Transfer', '🏦'),
  paypal('PayPal', '💰'),
  venmo('Venmo', '📱'),
  other('Other', '💳');

  const SettlementMethod(this.displayName, this.emoji);
  final String displayName;
  final String emoji;
}