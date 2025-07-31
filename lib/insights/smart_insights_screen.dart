import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../models/group_model.dart';
import '../../models/expense_model.dart';
import '../../models/user_model.dart';
import '../utils/number_formatter.dart';

// Enhanced Insights Data Models for Splitwise-style app
class SpendingInsight {
  final String title;
  final String description;
  final String actionText;
  final IconData icon;
  final Color color;
  final InsightType type;
  final Map<String, dynamic>? data;

  SpendingInsight({
    required this.title,
    required this.description,
    required this.actionText,
    required this.icon,
    required this.color,
    required this.type,
    this.data,
  });
}

enum InsightType {
  friendship,
  groupDynamics,
  social,
  fairness,
  celebration,
  opportunity
}

class CategorySpending {
  final ExpenseCategory category;
  final double amount;
  final int count;
  final double percentage;
  final List<ExpenseModel> recentExpenses;

  CategorySpending({
    required this.category,
    required this.amount,
    required this.count,
    required this.percentage,
    required this.recentExpenses,
  });
}

class MonthlyTrend {
  final DateTime month;
  final double amount;
  final int expenseCount;

  MonthlyTrend({
    required this.month,
    required this.amount,
    required this.expenseCount,
  });
}

class FriendSpendingComparison {
  final UserModel friend;
  final double totalShared;
  final int sharedExpenseCount;
  final double averageExpenseSize;

  FriendSpendingComparison({
    required this.friend,
    required this.totalShared,
    required this.sharedExpenseCount,
    required this.averageExpenseSize,
  });
}

class SmartInsightsScreen extends StatefulWidget {
  const SmartInsightsScreen({super.key});

  @override
  _SmartInsightsScreenState createState() => _SmartInsightsScreenState();
}

class _SmartInsightsScreenState extends State<SmartInsightsScreen>
    with TickerProviderStateMixin {
  final DatabaseService _databaseService = DatabaseService();

  late AnimationController _animationController;
  late AnimationController _chartAnimationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _slideAnimation;
  late Animation<double> _chartAnimation;

  List<ExpenseModel> _allExpenses = [];
  List<GroupModel> _userGroups = [];
  List<UserModel> _allMembers = [];
  bool _isLoading = true;

  // Insights data
  final List<SpendingInsight> _insights = [];
  List<CategorySpending> _categorySpending = [];
  List<MonthlyTrend> _monthlyTrends = [];
  List<FriendSpendingComparison> _friendComparisons = [];

  // Summary stats
  double _totalSpent = 0;
  int _totalExpenses = 0;
  String? _spendingStreak;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadInsightsData();
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _chartAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1800),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _slideAnimation = Tween<double>(
      begin: 50.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    _chartAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _chartAnimationController,
      curve: Curves.elasticOut,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    _chartAnimationController.dispose();
    super.dispose();
  }

  Future<void> _loadInsightsData() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUserId = authService.currentUser?.uid;

      if (currentUserId == null) return;

      // Load user's groups and expenses
      _userGroups = await _databaseService.streamUserGroups(currentUserId).first;

      // Collect all expenses from all groups
      List<ExpenseModel> allExpenses = [];
      Set<String> allMemberIds = {};

      for (GroupModel group in _userGroups) {
        List<ExpenseModel> groupExpenses = await _databaseService
            .streamGroupExpenses(group.id).first;
        allExpenses.addAll(groupExpenses);
        allMemberIds.addAll(group.memberIds);
      }

      // Load all members
      List<UserModel> allMembers = [];
      for (String memberId in allMemberIds) {
        UserModel? member = await _databaseService.getUser(memberId);
        if (member != null) allMembers.add(member);
      }

      setState(() {
        _allExpenses = allExpenses;
        _allMembers = allMembers;
      });

      // Calculate insights
      await _calculateInsights(currentUserId);

      // Start animations
      _animationController.forward();
      await Future.delayed(const Duration(milliseconds: 300));
      _chartAnimationController.forward();

    } catch (e) {
      if (kDebugMode) {
        print('❌ Error loading insights: $e');
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _calculateInsights(String currentUserId) async {
    _calculateSummaryStats(currentUserId);
    _calculateCategorySpending(currentUserId);
    _calculateMonthlyTrends(currentUserId);
    _calculateFriendComparisons(currentUserId);
    _generateSplitWiseInsights(currentUserId);
  }

  void _calculateSummaryStats(String currentUserId) {
    List<ExpenseModel> userExpenses = _allExpenses
        .where((expense) =>
    expense.paidBy == currentUserId ||
        expense.splitBetween.contains(currentUserId))
        .toList();

    _totalExpenses = userExpenses.length;
    _totalSpent = userExpenses
        .where((expense) => expense.paidBy == currentUserId)
        .fold(0.0, (sum, expense) => sum + expense.amount);


    // Find top spending category
    Map<ExpenseCategory, double> categoryTotals = {};
    for (ExpenseModel expense in userExpenses.where((e) => e.paidBy == currentUserId)) {
      categoryTotals[expense.category] =
          (categoryTotals[expense.category] ?? 0) + expense.amount;
    }

    if (categoryTotals.isNotEmpty) {
    }

    // Calculate spending streak
    _calculateSpendingStreak(userExpenses);
  }

  void _calculateSpendingStreak(List<ExpenseModel> expenses) {
    if (expenses.isEmpty) {
      _spendingStreak = "Ready for your first group expense!";
      return;
    }

    expenses.sort((a, b) => b.date.compareTo(a.date));

    int consecutiveDays = 0;
    DateTime? lastExpenseDate;

    for (ExpenseModel expense in expenses) {
      if (lastExpenseDate == null) {
        lastExpenseDate = expense.date;
        consecutiveDays = 1;
      } else {
        Duration difference = lastExpenseDate.difference(expense.date);
        if (difference.inDays == 1) {
          consecutiveDays++;
          lastExpenseDate = expense.date;
        } else {
          break;
        }
      }
    }

    if (consecutiveDays >= 7) {
      _spendingStreak = "$consecutiveDays day friendship streak! 🔥";
    } else if (consecutiveDays >= 3) {
      _spendingStreak = "$consecutiveDays day social streak";
    } else {
      _spendingStreak = "Last group expense: ${_formatDateAgo(expenses.first.date)}";
    }
  }

  void _calculateCategorySpending(String currentUserId) {
    Map<ExpenseCategory, List<ExpenseModel>> categoryExpenses = {};

    List<ExpenseModel> userPaidExpenses = _allExpenses
        .where((expense) => expense.paidBy == currentUserId)
        .toList();

    for (ExpenseModel expense in userPaidExpenses) {
      categoryExpenses[expense.category] ??= [];
      categoryExpenses[expense.category]!.add(expense);
    }

    _categorySpending = categoryExpenses.entries.map((entry) {
      double totalAmount = entry.value.fold(0.0, (sum, expense) => sum + expense.amount);
      double percentage = _totalSpent > 0 ? (totalAmount / _totalSpent) * 100 : 0;

      return CategorySpending(
        category: entry.key,
        amount: totalAmount,
        count: entry.value.length,
        percentage: percentage,
        recentExpenses: entry.value
          ..sort((a, b) => b.date.compareTo(a.date))
          ..take(3).toList(),
      );
    }).toList();

    _categorySpending.sort((a, b) => b.amount.compareTo(a.amount));
  }

  void _calculateMonthlyTrends(String currentUserId) {
    Map<String, List<ExpenseModel>> monthlyExpenses = {};

    List<ExpenseModel> userPaidExpenses = _allExpenses
        .where((expense) => expense.paidBy == currentUserId)
        .where((expense) => expense.date.isAfter(DateTime.now().subtract(const Duration(days: 180))))
        .toList();

    for (ExpenseModel expense in userPaidExpenses) {
      String monthKey = "${expense.date.year}-${expense.date.month.toString().padLeft(2, '0')}";
      monthlyExpenses[monthKey] ??= [];
      monthlyExpenses[monthKey]!.add(expense);
    }

    _monthlyTrends = monthlyExpenses.entries.map((entry) {
      List<String> parts = entry.key.split('-');
      DateTime month = DateTime(int.parse(parts[0]), int.parse(parts[1]));
      double totalAmount = entry.value.fold(0.0, (sum, expense) => sum + expense.amount);

      return MonthlyTrend(
        month: month,
        amount: totalAmount,
        expenseCount: entry.value.length,
      );
    }).toList();

    _monthlyTrends.sort((a, b) => a.month.compareTo(b.month));
  }

  void _calculateFriendComparisons(String currentUserId) {
    Map<String, List<ExpenseModel>> friendExpenses = {};

    for (ExpenseModel expense in _allExpenses) {
      if (expense.splitBetween.contains(currentUserId)) {
        for (String memberId in expense.splitBetween) {
          if (memberId != currentUserId) {
            friendExpenses[memberId] ??= [];
            friendExpenses[memberId]!.add(expense);
          }
        }
      }
    }

    _friendComparisons = friendExpenses.entries.map((entry) {
      UserModel? friend = _allMembers.firstWhere(
            (member) => member.id == entry.key,
        orElse: () => UserModel(
          id: entry.key,
          name: 'Unknown User',
          email: '',
          groupIds: [],
          createdAt: DateTime.now(),
        ),
      );

      double totalShared = entry.value.fold(0.0, (sum, expense) => sum + expense.amount);
      double averageExpense = entry.value.isNotEmpty ? totalShared / entry.value.length : 0;

      return FriendSpendingComparison(
        friend: friend,
        totalShared: totalShared,
        sharedExpenseCount: entry.value.length,
        averageExpenseSize: averageExpense,
      );
    }).toList();

    _friendComparisons.sort((a, b) => b.totalShared.compareTo(a.totalShared));
    _friendComparisons = _friendComparisons.take(5).toList();
  }

  void _generateSplitWiseInsights(String currentUserId) {
    _insights.clear();

    // Group dynamics insights
    _addGroupDynamicsInsights(currentUserId);

    // Friendship insights
    _addFriendshipInsights(currentUserId);

    // Social patterns
    _addSocialPatternInsights(currentUserId);

    // Fairness insights
    _addFairnessInsights(currentUserId);

    // Celebration insights
    _addCelebrationInsights(currentUserId);

    // Group opportunity insights
    _addGroupOpportunityInsights(currentUserId);
  }

  void _addGroupDynamicsInsights(String currentUserId) {
    // Most active group
    if (_userGroups.isNotEmpty) {
      GroupModel mostActiveGroup = _userGroups.first;
      int maxExpenses = 0;

      for (GroupModel group in _userGroups) {
        int groupExpenseCount = _allExpenses
            .where((e) => group.memberIds.contains(e.paidBy))
            .length;
        if (groupExpenseCount > maxExpenses) {
          maxExpenses = groupExpenseCount;
          mostActiveGroup = group;
        }
      }

      if (maxExpenses > 5) {
        _insights.add(SpendingInsight(
          title: "🏆 Most Active Group",
          description: "${mostActiveGroup.name} is your busiest group with $maxExpenses shared expenses! You're really making memories together.",
          actionText: "View Group",
          icon: Icons.groups,
          color: Colors.blue,
          type: InsightType.groupDynamics,
          data: {"groupId": mostActiveGroup.id, "expenseCount": maxExpenses},
        ));
      }
    }

    // Group spending champion
    Map<String, double> memberContributions = {};
    for (ExpenseModel expense in _allExpenses) {
      memberContributions[expense.paidBy] =
          (memberContributions[expense.paidBy] ?? 0) + expense.amount;
    }

    if (memberContributions.isNotEmpty) {
      String topSpender = memberContributions.entries
          .reduce((a, b) => a.value > b.value ? a : b).key;

      if (topSpender == currentUserId) {
        _insights.add(SpendingInsight(
          title: "🎯 Group Hero",
          description: "You're the top spender across all groups! Your friends appreciate you picking up the tab. You've spent ${NumberFormatter.formatCurrency(memberContributions[topSpender]!)} total.",
          actionText: "See Who Owes You",
          icon: Icons.volunteer_activism,
          color: Colors.orange,
          type: InsightType.celebration,
          data: {"totalSpent": memberContributions[topSpender]},
        ));
      } else {
        UserModel? topSpenderUser = _allMembers.firstWhere(
                (m) => m.id == topSpender,
            orElse: () => UserModel(id: topSpender, name: 'Someone', email: '', groupIds: [], createdAt: DateTime.now())
        );

        _insights.add(SpendingInsight(
          title: "🙏 Thank Your Friend",
          description: "${topSpenderUser.name} is the group's biggest spender with ${NumberFormatter.formatCurrency(memberContributions[topSpender]!)}! Maybe it's time to treat them?",
          actionText: "Plan Something Special",
          icon: Icons.card_giftcard,
          color: Colors.green,
          type: InsightType.friendship,
          data: {"friendId": topSpender, "amount": memberContributions[topSpender]},
        ));
      }
    }
  }

  void _addFriendshipInsights(String currentUserId) {
    if (_friendComparisons.isEmpty) return;

    // Best friend insight
    FriendSpendingComparison bestFriend = _friendComparisons.first;
    _insights.add(SpendingInsight(
      title: "👯‍♀️ Spending Bestie",
      description: "${bestFriend.friend.name} is your #1 spending partner! You've shared ${bestFriend.sharedExpenseCount} expenses together totaling ${NumberFormatter.formatCurrency(bestFriend.totalShared)}.",
      actionText: "Message ${bestFriend.friend.name}",
      icon: Icons.favorite,
      color: Colors.pink,
      type: InsightType.friendship,
      data: {
        "friendId": bestFriend.friend.id,
        "friendName": bestFriend.friend.name,
        "sharedAmount": bestFriend.totalShared
      },
    ));

    // Social butterfly insight
    if (_friendComparisons.length >= 5) {
      int totalFriends = _friendComparisons.length;
      double totalSharedAmount = _friendComparisons
          .fold(0.0, (sum, friend) => sum + friend.totalShared);

      _insights.add(SpendingInsight(
        title: "🦋 Social Butterfly",
        description: "You've shared expenses with $totalFriends different friends! You're definitely the social coordinator of the group.",
        actionText: "Plan Group Event",
        icon: Icons.diversity_3,
        color: Colors.purple,
        type: InsightType.social,
        data: {"friendCount": totalFriends, "totalShared": totalSharedAmount},
      ));
    }

    // Balanced friendship insight
    for (FriendSpendingComparison friend in _friendComparisons.take(3)) {
      List<ExpenseModel> yourExpensesWithFriend = _allExpenses
          .where((e) => e.paidBy == currentUserId && e.splitBetween.contains(friend.friend.id))
          .toList();

      List<ExpenseModel> friendExpensesWithYou = _allExpenses
          .where((e) => e.paidBy == friend.friend.id && e.splitBetween.contains(currentUserId))
          .toList();

      double yourTotal = yourExpensesWithFriend.fold(0.0, (sum, e) => sum + e.amount);
      double friendTotal = friendExpensesWithYou.fold(0.0, (sum, e) => sum + e.amount);

      double ratio = friendTotal > 0 ? yourTotal / friendTotal : double.infinity;

      if (ratio >= 0.8 && ratio <= 1.2) { // Within 20% of each other
        _insights.add(SpendingInsight(
          title: "⚖️ Perfectly Balanced",
          description: "You and ${friend.friend.name} have a great balance! You've both contributed fairly equally to shared expenses.",
          actionText: "Keep It Balanced",
          icon: Icons.balance,
          color: Colors.teal,
          type: InsightType.fairness,
          data: {"friendName": friend.friend.name, "ratio": ratio},
        ));
        break; // Only show one balanced friendship
      }
    }
  }

  void _addSocialPatternInsights(String currentUserId) {
    // Weekend warriors
    List<ExpenseModel> weekendExpenses = _allExpenses
        .where((e) => e.splitBetween.contains(currentUserId))
        .where((e) => e.date.weekday >= 6)
        .toList();

    if (weekendExpenses.length > 10) {
      Set<String> weekendFriends = {};
      for (ExpenseModel expense in weekendExpenses) {
        weekendFriends.addAll(expense.splitBetween.where((id) => id != currentUserId));
      }

      _insights.add(SpendingInsight(
        title: "🎉 Weekend Warriors",
        description: "You and your crew know how to have fun! ${weekendExpenses.length} of your expenses happen on weekends with ${weekendFriends.length} different friends.",
        actionText: "Plan Weekend Fun",
        icon: Icons.weekend,
        color: Colors.deepOrange,
        type: InsightType.social,
        data: {"weekendExpenses": weekendExpenses.length},
      ));
    }

    // Food lovers group
    List<ExpenseModel> foodExpenses = _allExpenses
        .where((e) => e.category == ExpenseCategory.food && e.splitBetween.contains(currentUserId))
        .toList();

    if (foodExpenses.length > 15) {
      Map<String, int> foodiePartners = {};
      for (ExpenseModel expense in foodExpenses) {
        for (String friendId in expense.splitBetween) {
          if (friendId != currentUserId) {
            foodiePartners[friendId] = (foodiePartners[friendId] ?? 0) + 1;
          }
        }
      }

      if (foodiePartners.isNotEmpty) {
        String topFoodieFriendId = foodiePartners.entries
            .reduce((a, b) => a.value > b.value ? a : b).key;

        UserModel? topFoodieFriend = _allMembers.firstWhere(
                (m) => m.id == topFoodieFriendId,
            orElse: () => UserModel(id: topFoodieFriendId, name: 'Your foodie friend', email: '', groupIds: [], createdAt: DateTime.now())
        );

        _insights.add(SpendingInsight(
          title: "🍕 Foodie Squad",
          description: "You and ${topFoodieFriend.name} are food adventure partners! You've shared ${foodiePartners[topFoodieFriendId]} meals together.",
          actionText: "Find New Restaurant",
          icon: Icons.restaurant,
          color: Colors.red,
          type: InsightType.social,
          data: {"foodiePartner": topFoodieFriend.name, "mealCount": foodiePartners[topFoodieFriendId]},
        ));
      }
    }

    // Travel buddies
    List<ExpenseModel> travelExpenses = _allExpenses
        .where((e) => (e.category == ExpenseCategory.accommodation ||
        e.category == ExpenseCategory.transport) &&
        e.splitBetween.contains(currentUserId))
        .toList();

    if (travelExpenses.length > 5) {
      Set<String> travelPartners = {};
      for (ExpenseModel expense in travelExpenses) {
        travelPartners.addAll(expense.splitBetween.where((id) => id != currentUserId));
      }

      _insights.add(SpendingInsight(
        title: "✈️ Travel Squad",
        description: "Adventure awaits! You've shared ${travelExpenses.length} travel expenses with ${travelPartners.length} travel buddies.",
        actionText: "Plan Next Trip",
        icon: Icons.flight,
        color: Colors.lightBlue,
        type: InsightType.social,
        data: {"travelExpenses": travelExpenses.length, "travelBuddies": travelPartners.length},
      ));
    }
  }

  void _addFairnessInsights(String currentUserId) {
    // Check for imbalanced relationships
    for (FriendSpendingComparison friend in _friendComparisons.take(5)) {
      double yourContribution = _allExpenses
          .where((e) => e.paidBy == currentUserId && e.splitBetween.contains(friend.friend.id))
          .fold(0.0, (sum, e) => sum + e.amount);

      double friendContribution = _allExpenses
          .where((e) => e.paidBy == friend.friend.id && e.splitBetween.contains(currentUserId))
          .fold(0.0, (sum, e) => sum + e.amount);

      if (yourContribution > friendContribution * 2 && yourContribution > 50) {
        _insights.add(SpendingInsight(
          title: "💸 Generous Friend Alert",
          description: "You've been covering a lot for ${friend.friend.name}! You've paid ${NumberFormatter.formatCurrency(yourContribution)} vs their ${NumberFormatter.formatCurrency(friendContribution)}.",
          actionText: "Suggest They Treat Next",
          icon: Icons.trending_up,
          color: Colors.amber,
          type: InsightType.fairness,
          data: {
            "friendName": friend.friend.name,
            "yourAmount": yourContribution,
            "friendAmount": friendContribution
          },
        ));
        break; // Only show one imbalance insight
      }
    }

    // Group debt insights
    Map<String, double> groupDebts = {};
    for (ExpenseModel expense in _allExpenses) {
      if (expense.splitBetween.contains(currentUserId) && expense.paidBy != currentUserId) {
        double splitAmount = expense.amount / expense.splitBetween.length;
        groupDebts[expense.paidBy] = (groupDebts[expense.paidBy] ?? 0) + splitAmount;
      }
    }

    double totalOwed = groupDebts.values.fold(0.0, (sum, debt) => sum + debt);
    if (totalOwed > 20) {
      _insights.add(SpendingInsight(
        title: "💳 Settlement Time",
        description: "You owe ${NumberFormatter.formatCurrency(totalOwed)} total across ${groupDebts.length} friends. Time to settle up and keep friendships happy!",
        actionText: "Settle Debts",
        icon: Icons.payment,
        color: Colors.indigo,
        type: InsightType.fairness,
        data: {"totalOwed": totalOwed, "friendCount": groupDebts.length},
      ));
    }
  }

  void _addCelebrationInsights(String currentUserId) {
    // Group milestones
    if (_totalExpenses >= 100) {
      _insights.add(SpendingInsight(
        title: "🎊 Century Club",
        description: "Wow! You've shared 100+ expenses with friends. You're building amazing memories and friendships through shared experiences!",
        actionText: "Share Achievement",
        icon: Icons.celebration,
        color: Colors.amber,
        type: InsightType.celebration,
        data: {"expenseCount": _totalExpenses},
      ));
    }

    // Long-term friendship celebration
    DateTime sixMonthsAgo = DateTime.now().subtract(const Duration(days: 180));
    Map<String, List<ExpenseModel>> longTermFriends = {};

    for (ExpenseModel expense in _allExpenses) {
      if (expense.splitBetween.contains(currentUserId) && expense.date.isAfter(sixMonthsAgo)) {
        for (String friendId in expense.splitBetween) {
          if (friendId != currentUserId) {
            longTermFriends[friendId] ??= [];
            longTermFriends[friendId]!.add(expense);
          }
        }
      }
    }

    var consistentFriends = longTermFriends.entries
        .where((entry) => entry.value.length >= 10)
        .toList();

    if (consistentFriends.isNotEmpty) {
      String friendId = consistentFriends.first.key;
      UserModel? friend = _allMembers.firstWhere(
              (m) => m.id == friendId,
          orElse: () => UserModel(id: friendId, name: 'Your consistent friend', email: '', groupIds: [], createdAt: DateTime.now())
      );

      _insights.add(SpendingInsight(
        title: "💎 Friendship Goal",
        description: "You and ${friend.name} have been consistently sharing expenses for 6+ months. That's real friendship right there!",
        actionText: "Celebrate Friendship",
        icon: Icons.diamond,
        color: Colors.pink.shade300,
        type: InsightType.celebration,
        data: {"friendName": friend.name, "duration": "6+ months"},
      ));
    }
  }

  void _addGroupOpportunityInsights(String currentUserId) {
    // Suggest group activities based on patterns
    Map<ExpenseCategory, int> categoryFrequency = {};
    for (ExpenseModel expense in _allExpenses.where((e) => e.splitBetween.contains(currentUserId))) {
      categoryFrequency[expense.category] = (categoryFrequency[expense.category] ?? 0) + 1;
    }

    if (categoryFrequency[ExpenseCategory.food] != null && categoryFrequency[ExpenseCategory.food]! > 20) {
      _insights.add(SpendingInsight(
        title: "👨‍🍳 Cooking Party Idea",
        description: "Your group loves food! Why not host a cooking party where everyone brings ingredients? More fun, less cost!",
        actionText: "Organize Cooking Night",
        icon: Icons.kitchen,
        color: Colors.orange.shade400,
        type: InsightType.opportunity,
        data: {"activity": "cooking_party"},
      ));
    }

    // Subscription splitting opportunity
    List<ExpenseModel> entertainmentExpenses = _allExpenses
        .where((e) => e.category == ExpenseCategory.entertainment && e.splitBetween.contains(currentUserId))
        .toList();

    if (entertainmentExpenses.length > 8) {
      _insights.add(SpendingInsight(
        title: "📺 Subscription Squad",
        description: "Your group spends a lot on entertainment! Consider sharing streaming subscriptions to save money while enjoying together.",
        actionText: "Set Up Shared Subscriptions",
        icon: Icons.subscriptions,
        color: Colors.deepPurple,
        type: InsightType.opportunity,
        data: {"activity": "shared_subscriptions"},
      ));
    }

    // Group savings challenge
    if (_friendComparisons.length >= 3) {
      double avgGroupExpense = _allExpenses
          .where((e) => e.splitBetween.contains(currentUserId))
          .fold(0.0, (sum, e) => sum + e.amount) / max(_allExpenses.where((e) => e.splitBetween.contains(currentUserId)).length, 1);

      _insights.add(SpendingInsight(
        title: "🎯 Group Challenge",
        description: "Challenge your friend group to find cheaper alternatives for your usual activities. Your average group expense is ${NumberFormatter.formatCurrency(avgGroupExpense)}!",
        actionText: "Start Challenge",
        icon: Icons.emoji_events,
        color: Colors.green.shade600,
        type: InsightType.opportunity,
        data: {"averageExpense": avgGroupExpense},
      ));
    }
  }

  Color _getCategoryColor(ExpenseCategory category) {
    switch (category) {
      case ExpenseCategory.food:
        return Colors.orange;
      case ExpenseCategory.transport:
        return Colors.blue;
      case ExpenseCategory.entertainment:
        return Colors.purple;
      case ExpenseCategory.shopping:
        return Colors.pink;
      case ExpenseCategory.accommodation:
        return Colors.brown;
      case ExpenseCategory.bills:
        return Colors.red;
      case ExpenseCategory.healthcare:
        return Colors.green;
      case ExpenseCategory.other:
        return Colors.grey;
    }
  }

  String _formatDateAgo(DateTime date) {
    Duration difference = DateTime.now().difference(date);
    if (difference.inDays == 0) {
      return "Today";
    } else if (difference.inDays == 1) {
      return "Yesterday";
    } else if (difference.inDays < 7) {
      return "${difference.inDays} days ago";
    } else if (difference.inDays < 30) {
      return "${(difference.inDays / 7).floor()} weeks ago";
    } else {
      return "${(difference.inDays / 30).floor()} months ago";
    }
  }


  Widget _buildSummaryCards() {
    return AnimatedBuilder(
      animation: _fadeAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _slideAnimation.value),
          child: Opacity(
            opacity: _fadeAnimation.value,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: _buildSummaryCard(
                      title: "You Spent",
                      value: NumberFormatter.formatCurrency(_totalSpent),
                      icon: Icons.euro,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSummaryCard(
                      title: "Group Expenses",
                      value: "$_totalExpenses",
                      icon: Icons.receipt,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSummaryCard(
                      title: "Friends",
                      value: "${_friendComparisons.length}",
                      icon: Icons.people,
                      color: Colors.pink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightsList() {
    return AnimatedBuilder(
      animation: _fadeAnimation,
      builder: (context, child) {
        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _insights.length,
          itemBuilder: (context, index) {
            return TweenAnimationBuilder<double>(
              duration: Duration(milliseconds: 600 + (index * 100)),
              tween: Tween(begin: 0.0, end: 1.0),
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(50 * (1 - value), 0),
                  child: Opacity(
                    opacity: value,
                    child: _buildInsightCard(_insights[index]),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildInsightCard(SpendingInsight insight) {
    // Check if this insight should have an action button
    bool showActionButton = insight.type == InsightType.fairness &&
        insight.data?.containsKey('totalOwed') == true;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [
                insight.color.withOpacity(0.1),
                insight.color.withOpacity(0.05),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: insight.color,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        insight.icon,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            insight.title,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: insight.color,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: insight.color.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _getInsightTypeLabel(insight.type),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: insight.color,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  insight.description,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (insight.data != null) ...[
                      _buildInsightMetric(insight),
                    ],
                    if (showActionButton) ...[
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () => _handleInsightAction(insight),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: insight.color,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                        ),
                        child: Text(insight.actionText),
                      ),
                    ] else if (insight.data == null) ...[
                      // If no metric to show, just show some spacing
                      const SizedBox(),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleInsightAction(SpendingInsight insight) {
    // Only handle fairness insights with settlement functionality
    if (insight.type == InsightType.fairness &&
        insight.data?.containsKey('totalOwed') == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Settlement features coming soon! 💰'),
          backgroundColor: insight.color,
        ),
      );
    }
  }

  Widget _buildInsightMetric(SpendingInsight insight) {
    String? metricText;
    IconData? metricIcon;

    if (insight.data != null) {
      if (insight.data!.containsKey('expenseCount')) {
        metricText = "${insight.data!['expenseCount']} expenses";
        metricIcon = Icons.receipt;
      } else if (insight.data!.containsKey('sharedAmount')) {
        metricText = NumberFormatter.formatCurrency(insight.data!['sharedAmount']);
        metricIcon = Icons.euro;
      } else if (insight.data!.containsKey('friendCount')) {
        metricText = "${insight.data!['friendCount']} friends";
        metricIcon = Icons.people;
      } else if (insight.data!.containsKey('totalOwed')) {
        metricText = NumberFormatter.formatCurrency(insight.data!['totalOwed']);
        metricIcon = Icons.payment;
      } else if (insight.data!.containsKey('weekendExpenses')) {
        metricText = "${insight.data!['weekendExpenses']} weekends";
        metricIcon = Icons.weekend;
      }
    }

    if (metricText == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: insight.color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (metricIcon != null) ...[
            Icon(metricIcon, size: 16, color: insight.color),
            const SizedBox(width: 4),
          ],
          Text(
            metricText,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: insight.color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChart() {
    if (_categorySpending.isEmpty) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _chartAnimation,
      builder: (context, child) {
        return Container(
          margin: const EdgeInsets.all(16),
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.pie_chart, color: Colors.blue, size: 24),
                      const SizedBox(width: 12),
                      Text(
                        'What You Treat Friends To',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 200,
                    child: CustomPaint(
                      size: const Size(double.infinity, 200),
                      painter: CategoryPieChartPainter(
                        categories: _categorySpending,
                        animationValue: _chartAnimation.value,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...(_categorySpending.take(5).map((category) => _buildCategoryLegendItem(category))),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCategoryLegendItem(CategorySpending category) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: _getCategoryColor(category.category),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${category.category.emoji} ${category.category.displayName}',
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                NumberFormatter.formatCurrency(category.amount),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                '${category.count} times',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyTrendChart() {
    if (_monthlyTrends.length < 2) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _chartAnimation,
      builder: (context, child) {
        return Container(
          margin: const EdgeInsets.all(16),
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.show_chart, color: Colors.green, size: 24),
                      const SizedBox(width: 12),
                      Text(
                        'Your Group Generosity Trend',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 150,
                    child: CustomPaint(
                      size: const Size(double.infinity, 150),
                      painter: MonthlyTrendChartPainter(
                        trends: _monthlyTrends,
                        animationValue: _chartAnimation.value,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTopFriends() {
    if (_friendComparisons.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.all(16),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.people, color: Colors.pink, size: 24),
                  const SizedBox(width: 12),
                  Text(
                    'Your Spending Squad',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...(_friendComparisons.take(3).toList().asMap().entries.map((entry) {
                int index = entry.key;
                FriendSpendingComparison friend = entry.value;
                return TweenAnimationBuilder<double>(
                  duration: Duration(milliseconds: 800 + (index * 200)),
                  tween: Tween(begin: 0.0, end: 1.0),
                  builder: (context, value, child) {
                    return Transform.translate(
                      offset: Offset(30 * (1 - value), 0),
                      child: Opacity(
                        opacity: value,
                        child: _buildFriendComparisonItem(friend, index),
                      ),
                    );
                  },
                );
              })),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFriendComparisonItem(FriendSpendingComparison friend, int index) {
    List<String> medals = ['🥇', '🥈', '🥉'];
    String medal = index < 3 ? medals[index] : '${index + 1}';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.pink.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.pink.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Text(
            medal,
            style: const TextStyle(fontSize: 20),
          ),
          const SizedBox(width: 12),
          CircleAvatar(
            backgroundImage: friend.friend.photoUrl != null
                ? NetworkImage(friend.friend.photoUrl!)
                : null,
            backgroundColor: Colors.pink.withOpacity(0.2),
            child: friend.friend.photoUrl == null
                ? Text(
              friend.friend.name.substring(0, 1).toUpperCase(),
              style: const TextStyle(
                color: Colors.pink,
                fontWeight: FontWeight.bold,
              ),
            )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  friend.friend.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                Text(
                  '${friend.sharedExpenseCount} shared expenses',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                NumberFormatter.formatCurrency(friend.totalShared),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.pink,
                ),
              ),
              Text(
                'Together',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _getInsightTypeLabel(InsightType type) {
    switch (type) {
      case InsightType.friendship:
        return 'FRIENDSHIP';
      case InsightType.groupDynamics:
        return 'GROUP DYNAMICS';
      case InsightType.social:
        return 'SOCIAL INSIGHT';
      case InsightType.fairness:
        return 'FAIRNESS';
      case InsightType.celebration:
        return 'ACHIEVEMENT';
      case InsightType.opportunity:
        return 'OPPORTUNITY';
    }
  }




  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Friend Insights'),
        backgroundColor: theme.appBarTheme.backgroundColor,
        foregroundColor: theme.appBarTheme.foregroundColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _isLoading = true;
              });
              _loadInsightsData();
            },
            tooltip: 'Refresh Insights',
          ),
        ],
      ),
      body: _isLoading
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Analyzing your friendships and group dynamics...',
              style: TextStyle(
                color: colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ),
      )
          : RefreshIndicator(
        onRefresh: _loadInsightsData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              // Header with user streak
              if (_spendingStreak != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        theme.primaryColor,
                        theme.primaryColor.withOpacity(0.8),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '👫 Your Social Journey',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _spendingStreak!,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),

              // Summary Cards
              _buildSummaryCards(),

              // Smart Insights
              if (_insights.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: Row(
                    children: [
                      Icon(Icons.auto_awesome, color: theme.primaryColor),
                      const SizedBox(width: 8),
                      Text(
                        'Friend Insights',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildInsightsList(),
              ],

              // Category Chart
              _buildCategoryChart(),

              // Monthly Trend Chart
              _buildMonthlyTrendChart(),

              // Top Friends
              _buildTopFriends(),

              // Bottom padding
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }
}

// Custom Painters for Charts
class CategoryPieChartPainter extends CustomPainter {
  final List<CategorySpending> categories;
  final double animationValue;

  CategoryPieChartPainter({
    required this.categories,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (categories.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 * 0.8;

    double startAngle = -pi / 2;

    for (int i = 0; i < categories.length && i < 6; i++) {
      final category = categories[i];
      final sweepAngle = (category.percentage / 100) * 2 * pi * animationValue;

      final paint = Paint()
        ..color = _getCategoryColor(category.category)
        ..style = PaintingStyle.fill;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        true,
        paint,
      );

      startAngle += sweepAngle;
    }

    // Draw center circle for donut effect
    final centerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius * 0.5, centerPaint);
  }

  Color _getCategoryColor(ExpenseCategory category) {
    switch (category) {
      case ExpenseCategory.food:
        return Colors.orange;
      case ExpenseCategory.transport:
        return Colors.blue;
      case ExpenseCategory.entertainment:
        return Colors.purple;
      case ExpenseCategory.shopping:
        return Colors.pink;
      case ExpenseCategory.accommodation:
        return Colors.brown;
      case ExpenseCategory.bills:
        return Colors.red;
      case ExpenseCategory.healthcare:
        return Colors.green;
      case ExpenseCategory.other:
        return Colors.grey;
    }
  }

  @override
  bool shouldRepaint(CategoryPieChartPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.categories != categories;
  }
}

class MonthlyTrendChartPainter extends CustomPainter {
  final List<MonthlyTrend> trends;
  final double animationValue;

  MonthlyTrendChartPainter({
    required this.trends,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (trends.isEmpty) return;

    final paint = Paint()
      ..color = Colors.green
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = Colors.green.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    final maxAmount = trends.map((t) => t.amount).reduce(max);
    final minAmount = trends.map((t) => t.amount).reduce(min);
    final range = maxAmount - minAmount;

    final path = Path();
    final fillPath = Path();

    for (int i = 0; i < trends.length; i++) {
      final x = (i / (trends.length - 1)) * size.width * animationValue;
      final normalizedAmount = range > 0 ? (trends[i].amount - minAmount) / range : 0.5;
      final y = size.height - (normalizedAmount * size.height * 0.8) - (size.height * 0.1);

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }

      // Draw points
      final pointPaint = Paint()
        ..color = Colors.green
        ..style = PaintingStyle.fill;

      canvas.drawCircle(Offset(x, y), 4, pointPaint);
    }

    // Complete fill path
    if (trends.isNotEmpty) {
      final lastX = ((trends.length - 1) / (trends.length - 1)) * size.width * animationValue;
      fillPath.lineTo(lastX, size.height);
      fillPath.close();
    }

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(MonthlyTrendChartPainter oldDelegate) {
    return oldDelegate.animationValue != animationValue ||
        oldDelegate.trends != trends;
  }
}