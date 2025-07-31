import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../models/group_model.dart';
import '../../models/expense_model.dart';
import '../../models/user_model.dart';
import '../../utils/number_formatter.dart';

// Group Insights Models
class GroupInsight {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final GroupInsightType type;
  final Map<String, dynamic>? data;

  GroupInsight({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.type,
    this.data,
  });
}

enum GroupInsightType {
  activity,
  balance,
  social,
  trends,
  suggestion,
  celebration
}

class GroupMemberStats {
  final UserModel member;
  final double totalPaid;
  final double totalOwed;
  final int expenseCount;
  final double balance;
  final DateTime? lastExpense;

  GroupMemberStats({
    required this.member,
    required this.totalPaid,
    required this.totalOwed,
    required this.expenseCount,
    required this.balance,
    this.lastExpense,
  });
}

class GroupInsightsScreen extends StatefulWidget {
  final GroupModel group;
  final List<UserModel> members;

  const GroupInsightsScreen({super.key,
    required this.group,
    required this.members,
  });

  @override
  _GroupInsightsScreenState createState() => _GroupInsightsScreenState();
}

class _GroupInsightsScreenState extends State<GroupInsightsScreen>
    with TickerProviderStateMixin {

  final DatabaseService _databaseService = DatabaseService();

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _slideAnimation;

  final List<GroupInsight> _groupInsights = [];
  final List<GroupMemberStats> _memberStats = [];
  List<ExpenseModel> _allExpenses = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadGroupInsights();
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
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
      begin: 30.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadGroupInsights() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUserId = authService.currentUser?.uid;

      if (currentUserId == null) return;

      // Load expenses and settlements
      _allExpenses = await _databaseService.streamGroupExpenses(widget.group.id).first;

      await _calculateMemberStats();
      await _generateGroupInsights(currentUserId);

      // Start animations
      _animationController.forward();
    } catch (e) {
      if (kDebugMode) {
        print('Error loading group insights: $e');
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _calculateMemberStats() async {
    _memberStats.clear();

    for (UserModel member in widget.members) {
      // Calculate what they paid
      double totalPaid = _allExpenses
          .where((expense) => expense.paidBy == member.id)
          .fold(0.0, (sum, expense) => sum + expense.amount);

      // Calculate what they owe (their share of all group expenses)
      double totalOwed = 0.0;
      for (ExpenseModel expense in _allExpenses) {
        if (expense.splitBetween.contains(member.id)) {
          totalOwed += expense.amount / expense.splitBetween.length;
        }
      }

      // Calculate balance (positive = owed money, negative = owes money)
      double balance = totalPaid - totalOwed;

      // Count their expenses
      int expenseCount = _allExpenses
          .where((expense) => expense.paidBy == member.id)
          .length;

      // Find their last expense
      DateTime? lastExpense;
      try {
        lastExpense = _allExpenses
            .where((expense) => expense.paidBy == member.id)
            .map((expense) => expense.date)
            .reduce((a, b) => a.isAfter(b) ? a : b);
      } catch (e) {
        // No expenses found
      }

      _memberStats.add(GroupMemberStats(
        member: member,
        totalPaid: totalPaid,
        totalOwed: totalOwed,
        expenseCount: expenseCount,
        balance: balance,
        lastExpense: lastExpense,
      ));
    }

    // Sort by total paid descending
    _memberStats.sort((a, b) => b.totalPaid.compareTo(a.totalPaid));
  }

  Future<void> _generateGroupInsights(String currentUserId) async {
    _groupInsights.clear();

    // Activity insights
    _addActivityInsights();

    // Balance insights
    _addBalanceInsights(currentUserId);

    // Social insights
    _addSocialInsights();

    // Celebration insights
    _addCelebrationInsights();

    // Suggestion insights
    _addSuggestionInsights();
  }

  void _addActivityInsights() {
    if (_allExpenses.isEmpty) return;

    // Group activity streak
    List<ExpenseModel> sortedExpenses = List.from(_allExpenses)
      ..sort((a, b) => b.date.compareTo(a.date));

    DateTime now = DateTime.now();
    DateTime lastExpenseDate = sortedExpenses.first.date;

    // Check recent activity
    if (now.difference(lastExpenseDate).inDays <= 1) {
      Set<String> activeDays = {};
      DateTime checkDate = DateTime(now.year, now.month, now.day);

      for (int i = 0; i < 14; i++) {
        bool hadActivity = sortedExpenses.any((expense) {
          DateTime expenseDay = DateTime(expense.date.year, expense.date.month, expense.date.day);
          return expenseDay == checkDate;
        });

        if (hadActivity) {
          activeDays.add("${checkDate.year}-${checkDate.month}-${checkDate.day}");
        } else if (activeDays.isNotEmpty) {
          break;
        }

        checkDate = checkDate.subtract(const Duration(days: 1));
      }

      if (activeDays.length >= 3) {
        _groupInsights.add(GroupInsight(
          title: "🔥 Group on Fire!",
          description: "Your group has been active for ${activeDays.length} consecutive days! You're really making it a habit to spend time together.",
          icon: Icons.local_fire_department,
          color: Colors.orange,
          type: GroupInsightType.activity,
          data: {"streakDays": activeDays.length},
        ));
      }
    }

    // Most active day analysis
    Map<int, int> dayCount = {};
    for (ExpenseModel expense in _allExpenses) {
      dayCount[expense.date.weekday] = (dayCount[expense.date.weekday] ?? 0) + 1;
    }

    if (dayCount.isNotEmpty) {
      int mostActiveWeekday = dayCount.entries.reduce((a, b) => a.value > b.value ? a : b).key;
      List<String> days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      String mostActiveDay = days[mostActiveWeekday - 1];
      int activityCount = dayCount[mostActiveWeekday]!;

      if (activityCount >= 3) {
        String dayEmoji = mostActiveWeekday >= 6 ? "🎉" : "📅";
        _groupInsights.add(GroupInsight(
          title: "$dayEmoji $mostActiveDay Squad",
          description: "${mostActiveDay}s are your group's favorite! You've had $activityCount expenses on ${mostActiveDay}s. It's your go-to day for group activities!",
          icon: mostActiveWeekday >= 6 ? Icons.weekend : Icons.today,
          color: mostActiveWeekday >= 6 ? Colors.purple : Colors.blue,
          type: GroupInsightType.social,
          data: {"mostActiveDay": mostActiveDay, "count": activityCount},
        ));
      }
    }
  }

  void _addBalanceInsights(String currentUserId) {
    if (_memberStats.isEmpty) return;

    // Find the group's top spender
    GroupMemberStats topSpender = _memberStats.first;

    if (topSpender.member.id == currentUserId && topSpender.totalPaid > 50) {
      _groupInsights.add(GroupInsight(
        title: "👑 Group Champion",
        description: "You're the group's biggest spender with ${_formatCurrency(topSpender.totalPaid)}! Your friends really appreciate you picking up the tab.",
        icon: Icons.emoji_events,
        color: Colors.amber,
        type: GroupInsightType.celebration,
        data: {"totalPaid": topSpender.totalPaid},
      ));
    } else if (topSpender.totalPaid > 50) {
      _groupInsights.add(GroupInsight(
        title: "🙏 Thank ${topSpender.member.name}",
        description: "${topSpender.member.name} is carrying the group with ${_formatCurrency(topSpender.totalPaid)} in expenses! Maybe it's time to treat them back?",
        icon: Icons.volunteer_activism,
        color: Colors.green,
        type: GroupInsightType.suggestion,
        data: {"championName": topSpender.member.name, "amount": topSpender.totalPaid},
      ));
    }

    // Check for balanced group
    if (_memberStats.length >= 3) {
      double totalSpent = _memberStats.fold(0.0, (sum, stat) => sum + stat.totalPaid);
      double averageSpent = totalSpent / _memberStats.length;

      int balancedMembers = _memberStats.where((stat) {
        double ratio = stat.totalPaid / averageSpent;
        return ratio >= 0.7 && ratio <= 1.3; // Within 30% of average
      }).length;

      if (balancedMembers >= (_memberStats.length * 0.7)) {
        _groupInsights.add(GroupInsight(
          title: "⚖️ Perfectly Balanced",
          description: "This group has great balance! Most members contribute fairly equally. You've mastered the art of fair sharing!",
          icon: Icons.balance,
          color: Colors.teal,
          type: GroupInsightType.celebration,
          data: {"balancedMembers": balancedMembers, "totalMembers": _memberStats.length},
        ));
      }
    }

    // Find who should treat next
    if (_memberStats.length >= 2) {
      List<GroupMemberStats> sortedByLastExpense = List.from(_memberStats);
      sortedByLastExpense.sort((a, b) {
        if (a.lastExpense == null && b.lastExpense == null) return 0;
        if (a.lastExpense == null) return -1;
        if (b.lastExpense == null) return 1;
        return a.lastExpense!.compareTo(b.lastExpense!);
      });

      GroupMemberStats nextTreater = sortedByLastExpense.first;
      if (nextTreater.member.id != currentUserId && nextTreater.lastExpense != null) {
        int daysSinceLastExpense = DateTime.now().difference(nextTreater.lastExpense!).inDays;

        if (daysSinceLastExpense >= 7) {
          _groupInsights.add(GroupInsight(
            title: "🎯 ${nextTreater.member.name}'s Turn",
            description: "${nextTreater.member.name} hasn't paid for a group expense in $daysSinceLastExpense days. Time for them to treat the group!",
            icon: Icons.person_pin,
            color: Colors.indigo,
            type: GroupInsightType.suggestion,
            data: {"nextTreater": nextTreater.member.name, "daysSince": daysSinceLastExpense},
          ));
        }
      }
    }
  }

  void _addSocialInsights() {
    if (_allExpenses.isEmpty) return;

    // Analyze spending categories
    Map<ExpenseCategory, int> categoryCount = {};
    for (ExpenseModel expense in _allExpenses) {
      categoryCount[expense.category] = (categoryCount[expense.category] ?? 0) + 1;
    }

    if (categoryCount.isNotEmpty) {
      ExpenseCategory topCategory = categoryCount.entries.reduce((a, b) => a.value > b.value ? a : b).key;
      int count = categoryCount[topCategory]!;

      if (count >= 5) {
        String categoryInsight = _getCategoryInsight(topCategory, count);
        _groupInsights.add(GroupInsight(
          title: "${topCategory.emoji} ${_getCategoryTitle(topCategory)}",
          description: categoryInsight,
          icon: _getCategoryIcon(topCategory),
          color: _getCategoryColor(topCategory),
          type: GroupInsightType.social,
          data: {"category": topCategory.toString(), "count": count},
        ));
      }
    }

    // Monthly activity analysis
    DateTime now = DateTime.now();
    DateTime thisMonth = DateTime(now.year, now.month, 1);
    DateTime lastMonth = DateTime(now.year, now.month - 1, 1);

    int thisMonthExpenses = _allExpenses.where((e) => e.date.isAfter(thisMonth)).length;
    int lastMonthExpenses = _allExpenses.where((e) =>
    e.date.isAfter(lastMonth) && e.date.isBefore(thisMonth)).length;

    if (thisMonthExpenses > lastMonthExpenses && lastMonthExpenses > 0) {
      double increase = ((thisMonthExpenses - lastMonthExpenses) / lastMonthExpenses) * 100;
      if (increase >= 50) {
        _groupInsights.add(GroupInsight(
          title: "📈 Social Butterflies",
          description: "Your group activity is up ${increase.toInt()}% this month! You've had $thisMonthExpenses expenses vs $lastMonthExpenses last month. You're really bonding!",
          icon: Icons.trending_up,
          color: Colors.green,
          type: GroupInsightType.trends,
          data: {"increase": increase, "thisMonth": thisMonthExpenses, "lastMonth": lastMonthExpenses},
        ));
      }
    }
  }

  void _addCelebrationInsights() {
    // Milestone celebrations
    if (_allExpenses.length >= 50) {
      _groupInsights.add(GroupInsight(
        title: "🎊 Milestone Achieved!",
        description: "Wow! Your group has shared ${_allExpenses.length} expenses together. You're building incredible memories and friendships!",
        icon: Icons.celebration,
        color: Colors.pink,
        type: GroupInsightType.celebration,
        data: {"totalExpenses": _allExpenses.length},
      ));
    } else if (_allExpenses.length >= 25) {
      _groupInsights.add(GroupInsight(
        title: "🎉 Quarter Century Club",
        description: "Your group has hit 25+ shared expenses! You're well on your way to becoming expense-sharing pros.",
        icon: Icons.stars,
        color: Colors.purple,
        type: GroupInsightType.celebration,
        data: {"totalExpenses": _allExpenses.length},
      ));
    } else if (_allExpenses.length >= 10) {
      _groupInsights.add(GroupInsight(
        title: "🚀 Getting Started",
        description: "Your group is gaining momentum with ${_allExpenses.length} shared expenses! Keep the good times rolling.",
        icon: Icons.rocket_launch,
        color: Colors.blue,
        type: GroupInsightType.celebration,
        data: {"totalExpenses": _allExpenses.length},
      ));
    }

    // Long-term group celebration
    if (_allExpenses.isNotEmpty) {
      DateTime oldestExpense = _allExpenses.map((e) => e.date).reduce((a, b) => a.isBefore(b) ? a : b);
      int groupAgeDays = DateTime.now().difference(oldestExpense).inDays;

      if (groupAgeDays >= 180) {
        _groupInsights.add(GroupInsight(
          title: "💎 Long-term Friends",
          description: "Your group has been sharing expenses for ${(groupAgeDays / 30).round()} months! That's some serious friendship commitment.",
          icon: Icons.diamond,
          color: Colors.cyan,
          type: GroupInsightType.celebration,
          data: {"groupAgeMonths": (groupAgeDays / 30).round()},
        ));
      }
    }
  }

  void _addSuggestionInsights() {
    if (_allExpenses.length < 5) return;

    // Suggest group activities based on patterns
    Map<ExpenseCategory, double> categorySpending = {};
    for (ExpenseModel expense in _allExpenses) {
      categorySpending[expense.category] = (categorySpending[expense.category] ?? 0) + expense.amount;
    }

    if (categorySpending[ExpenseCategory.food] != null &&
        categorySpending[ExpenseCategory.food]! > 200) {
      _groupInsights.add(GroupInsight(
        title: "👨‍🍳 Cooking Party Time",
        description: "Your group loves dining out! Why not try hosting a cooking party? Everyone brings ingredients and you cook together - more fun, less cost!",
        icon: Icons.kitchen,
        color: Colors.orange,
        type: GroupInsightType.suggestion,
        data: {"suggestion": "cooking_party", "foodSpending": categorySpending[ExpenseCategory.food]},
      ));
    }

    // Weekend vs weekday analysis
    int weekendExpenses = _allExpenses.where((e) => e.date.weekday >= 6).length;
    int weekdayExpenses = _allExpenses.length - weekendExpenses;

    if (weekendExpenses > weekdayExpenses * 2) {
      _groupInsights.add(GroupInsight(
        title: "🎯 Weekday Opportunity",
        description: "You're weekend warriors! $weekendExpenses weekend expenses vs $weekdayExpenses weekday ones. Try some weekday hangouts for variety!",
        icon: Icons.calendar_today,
        color: Colors.teal,
        type: GroupInsightType.suggestion,
        data: {"weekendExpenses": weekendExpenses, "weekdayExpenses": weekdayExpenses},
      ));
    }
  }

  String _getCategoryInsight(ExpenseCategory category, int count) {
    switch (category) {
      case ExpenseCategory.food:
        return "Your group is a foodie squad! You've shared $count meals together. Nothing brings friends closer than good food!";
      case ExpenseCategory.entertainment:
        return "Entertainment lovers! $count shared fun activities. Your group knows how to have a good time together.";
      case ExpenseCategory.transport:
        return "Always on the move! $count transport expenses show you're adventure seekers who explore together.";
      case ExpenseCategory.accommodation:
        return "Travel buddies! $count accommodation expenses means you're creating memories on trips together.";
      case ExpenseCategory.shopping:
        return "Shopping squad! $count shared shopping expenses. You know how to treat yourselves together.";
      default:
        return "Your group has shared $count ${category.displayName} expenses together!";
    }
  }

  String _getCategoryTitle(ExpenseCategory category) {
    switch (category) {
      case ExpenseCategory.food:
        return "Foodie Squad";
      case ExpenseCategory.entertainment:
        return "Fun Seekers";
      case ExpenseCategory.transport:
        return "Adventure Crew";
      case ExpenseCategory.accommodation:
        return "Travel Buddies";
      case ExpenseCategory.shopping:
        return "Shopping Squad";
      default:
        return "${category.displayName} Group";
    }
  }

  IconData _getCategoryIcon(ExpenseCategory category) {
    switch (category) {
      case ExpenseCategory.food:
        return Icons.restaurant;
      case ExpenseCategory.entertainment:
        return Icons.movie;
      case ExpenseCategory.transport:
        return Icons.directions_car;
      case ExpenseCategory.accommodation:
        return Icons.hotel;
      case ExpenseCategory.shopping:
        return Icons.shopping_bag;
      default:
        return Icons.category;
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

  String _formatCurrency(double amount) {
    return NumberFormatter.formatCurrency(amount, currencySymbol: widget.group.currency);
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
                      title: "Total Expenses",
                      value: "${_allExpenses.length}",
                      icon: Icons.receipt,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSummaryCard(
                      title: "Group Spending",
                      value: _formatCurrency(_allExpenses.fold(0.0, (sum, e) => sum + e.amount)),
                      icon: Icons.euro,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSummaryCard(
                      title: "Members",
                      value: "${widget.members.length}",
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
            textAlign: TextAlign.center,
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
          itemCount: _groupInsights.length,
          itemBuilder: (context, index) {
            return TweenAnimationBuilder<double>(
              duration: Duration(milliseconds: 600 + (index * 100)),
              tween: Tween(begin: 0.0, end: 1.0),
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(50 * (1 - value), 0),
                  child: Opacity(
                    opacity: value,
                    child: _buildInsightCard(_groupInsights[index]),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildInsightCard(GroupInsight insight) {
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
                if (insight.data != null) ...[
                  const SizedBox(height: 16),
                  _buildInsightMetric(insight),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInsightMetric(GroupInsight insight) {
    String? metricText;
    IconData? metricIcon;

    if (insight.data != null) {
      if (insight.data!.containsKey('streakDays')) {
        metricText = "${insight.data!['streakDays']} days";
        metricIcon = Icons.local_fire_department;
      } else if (insight.data!.containsKey('totalPaid')) {
        metricText = _formatCurrency(insight.data!['totalPaid']);
        metricIcon = Icons.euro;
      } else if (insight.data!.containsKey('count')) {
        metricText = "${insight.data!['count']} times";
        metricIcon = Icons.repeat;
      } else if (insight.data!.containsKey('totalExpenses')) {
        metricText = "${insight.data!['totalExpenses']} expenses";
        metricIcon = Icons.receipt;
      } else if (insight.data!.containsKey('groupAgeMonths')) {
        metricText = "${insight.data!['groupAgeMonths']} months";
        metricIcon = Icons.timeline;
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

  String _getInsightTypeLabel(GroupInsightType type) {
    switch (type) {
      case GroupInsightType.activity:
        return 'ACTIVITY';
      case GroupInsightType.balance:
        return 'BALANCE';
      case GroupInsightType.social:
        return 'SOCIAL';
      case GroupInsightType.trends:
        return 'TRENDS';
      case GroupInsightType.suggestion:
        return 'SUGGESTION';
      case GroupInsightType.celebration:
        return 'ACHIEVEMENT';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('${widget.group.name} Insights'),
        backgroundColor: theme.appBarTheme.backgroundColor,
        foregroundColor: theme.appBarTheme.foregroundColor,
        elevation: 0,
      ),
      body: _isLoading
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(
              'Analyzing your group dynamics...',
              style: TextStyle(
                color: colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ),
      )
          : RefreshIndicator(
        onRefresh: _loadGroupInsights,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              // Header with group info
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
                      '🔍 Group Analysis',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Discover patterns and insights about your group\'s spending habits and social dynamics!',
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

              // Insights
              if (_groupInsights.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: Row(
                    children: [
                      Icon(Icons.auto_awesome, color: theme.primaryColor),
                      const SizedBox(width: 8),
                      Text(
                        'Group Insights',
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
              ] else ...[
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.3,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.insights,
                          size: 64,
                          color: colorScheme.onSurface.withOpacity(0.4),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Not enough data yet',
                          style: TextStyle(
                            fontSize: 18,
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Add more expenses to unlock group insights!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              // Bottom padding
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }
}