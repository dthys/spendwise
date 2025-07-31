import 'package:flutter/material.dart';
import 'user_model.dart';
import '../utils/number_formatter.dart'; // Add this import

class FriendBalance {
  final UserModel friend;
  final double balance; // Positive = friend owes you, Negative = you owe friend
  final List<String> sharedGroupIds;
  final int sharedGroupsCount;

  FriendBalance({
    required this.friend,
    required this.balance,
    required this.sharedGroupIds,
    required this.sharedGroupsCount,
  });

  // Helper getters for UI
  bool get friendOwesYou => balance > 0.01;
  bool get youOweFriend => balance < -0.01;
  bool get isSettled => balance.abs() <= 0.01;

  String get balanceText {
    if (isSettled) return 'Settled up';
    if (friendOwesYou) return 'owes you ${NumberFormatter.formatCurrency(balance)}';
    return 'you owe ${NumberFormatter.formatCurrency(-balance)}';
  }

  Color get balanceColor {
    if (isSettled) return Colors.green;
    if (friendOwesYou) return Colors.blue;
    return Colors.orange;
  }

  IconData get balanceIcon {
    if (isSettled) return Icons.check_circle;
    if (friendOwesYou) return Icons.arrow_downward;
    return Icons.arrow_upward;
  }

  @override
  String toString() {
    return 'FriendBalance(${friend.name}: ${NumberFormatter.formatCurrency(balance)}, ${sharedGroupsCount} groups)';
  }
}