// Create this as models/friend_balance_model.dart

import 'dart:ui';

import 'package:flutter/material.dart';

import 'user_model.dart';

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
    if (friendOwesYou) return 'owes you €${balance.toStringAsFixed(2)}';
    return 'you owe €${(-balance).toStringAsFixed(2)}';
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
    return 'FriendBalance(${friend.name}: €${balance.toStringAsFixed(2)}, ${sharedGroupsCount} groups)';
  }
}