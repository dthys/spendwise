// models/settlement_model.dart
class SettlementModel {
  final String id;
  final String groupId;
  final String fromUserId;  // Who paid the debt
  final String toUserId;    // Who received the payment
  final double amount;
  final DateTime settledAt;
  final String? notes;
  final String? transactionId;
  final SettlementMethod method;

  // REMOVED: settledExpenseIds - we don't track individual expenses anymore

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
  });

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
      // REMOVED: 'settledExpenseIds' field
    };
  }

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
      // REMOVED: settledExpenseIds parsing
    );
  }

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
    );
  }

  @override
  String toString() {
    return 'SettlementModel(id: $id, from: $fromUserId, to: $toUserId, amount: €$amount)';
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