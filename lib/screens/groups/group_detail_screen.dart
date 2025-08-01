import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../models/group_model.dart';
import '../../models/expense_model.dart';
import '../../models/user_model.dart';
import '../../models/settlement_model.dart';
import '../../utils/number_formatter.dart';
import 'add_expense_screen.dart';
import '../expenses/expense_detail_screen.dart';
import '../expenses/activity_log_screen.dart';
import '../balances/balances_screen.dart';
import 'group_settings_screen.dart';
import 'group_insights_screen.dart';
import '../../widgets/shimmer_box.dart';
import 'package:rxdart/rxdart.dart';

enum ExpenseFilter {
  unsettled,
  all;
}


class GroupDetailScreen extends StatefulWidget {
  final String groupId;

  const GroupDetailScreen({super.key, required this.groupId});

  @override
  _GroupDetailScreenState createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> with AutomaticKeepAliveClientMixin {
  final DatabaseService _databaseService = DatabaseService();
  GroupModel? _group;
  List<UserModel> _members = [];
  bool _isLoading = true;

  // Cache for group data to prevent unnecessary reloads
  DateTime? _lastDataUpdate;
  Map<String, double>? _cachedBalances;

  ExpenseFilter _currentFilter = ExpenseFilter.unsettled;

  // Add stream subscriptions for proper disposal
  StreamSubscription? _balanceSubscription;
  StreamSubscription? _expenseSubscription;
  StreamSubscription? _settlementSubscription;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadGroupData();
  }

  Stream<List<ExpenseModel>> _getFilteredExpenseStream() {
    final currentUserId = Provider.of<AuthService>(context, listen: false).currentUser?.uid;

    return _databaseService.streamGroupExpenses(widget.groupId).asyncMap((expenses) async {
      if (currentUserId == null || _currentFilter == ExpenseFilter.all) {
        return expenses; // Show all expenses
      }

      // Show only unsettled expenses
      DateTime? lastCheckpoint = await _databaseService.getUserLastSettlementCheckpoint(currentUserId, widget.groupId);

      return expenses.where((expense) {
        // Rule 1: Hide expenses older than user's last full settlement
        if (lastCheckpoint != null && expense.date.isBefore(lastCheckpoint)) {
          return false;
        }

        // Rule 2: Hide expenses that are completely settled for everyone
        if (expense.isFullySettled()) {
          return false;
        }

        // Rule 3: For expenses involving this user, hide if settled for them
        if (expense.splitBetween.contains(currentUserId) &&
            expense.paidBy != currentUserId &&
            expense.isSettledForUser(currentUserId)) {
          return false;
        }

        return true;
      }).toList();
    });
  }

  @override
  void dispose() {
    // Cancel all stream subscriptions to prevent memory leaks
    _balanceSubscription?.cancel();
    _expenseSubscription?.cancel();
    _settlementSubscription?.cancel();
    super.dispose();
  }

  Map<String, double> _calculateSimplifiedBalances(
      List<ExpenseModel> expenses,
      List<SettlementModel> settlements,
      String? viewingUserId,
      ) {
    return _databaseService.calculateUserSpecificBalances(expenses, settlements, viewingUserId);
  }

// AND UPDATE the _getBalanceStream method to pass currentUserId:
  Stream<Map<String, double>> _getBalanceStream() {
    final currentUserId = Provider.of<AuthService>(context, listen: false).currentUser?.uid;

    return Rx.combineLatest2(
      _databaseService.streamGroupExpenses(widget.groupId),
      _databaseService.streamGroupSettlements(widget.groupId),
          (List<ExpenseModel> expenses, List<SettlementModel> settlements) {
        return _calculateSimplifiedBalances(expenses, settlements, currentUserId);
      },
    ).distinct();
  }

  // Add error handling to data loading
  Future<void> _loadGroupData({bool forceRefresh = false}) async {
    if (!mounted) return; // Check if widget is still mounted

    // Use cache if recent and not forcing refresh
    if (!forceRefresh &&
        _group != null &&
        _lastDataUpdate != null &&
        DateTime.now().difference(_lastDataUpdate!).inSeconds < 15) {
      return;
    }

    try {
      _group = await _databaseService.getGroup(widget.groupId);
      if (_group != null && mounted) {
        // Load member details
        _members = [];
        for (String memberId in _group!.memberIds) {
          if (!mounted) break; // Check mounted state in loop

          UserModel? member = await _databaseService.getUser(memberId);
          if (member != null) {
            _members.add(member);
          }
        }
        _lastDataUpdate = DateTime.now();
      }
      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading group: $e');
      }
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatCurrency(double amount) {
    return NumberFormatter.formatCurrency(amount, currencySymbol: _group?.currency ?? 'EUR');
  }

  // Add refresh functionality with smart caching
  Future<void> _refreshData() async {
    await _loadGroupData(forceRefresh: true);
    await Future.delayed(const Duration(milliseconds: 300)); // Reduced delay for better responsiveness
  }

  // Create smooth page transitions
  Future<void> _navigateWithTransition(Widget page) async {
    final result = await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionDuration: const Duration(milliseconds: 250),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: animation.drive(
              Tween(begin: const Offset(1.0, 0.0), end: Offset.zero).chain(
                CurveTween(curve: Curves.easeInOut),
              ),
            ),
            child: child,
          );
        },
      ),
    );

    // Smart refresh logic
    if (result == 'refresh' || result == true) {
      await _refreshData();
    } else {
      // Light refresh for balance updates
      await _loadGroupData();
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('Loading...'),
          backgroundColor: theme.appBarTheme.backgroundColor,
          foregroundColor: theme.appBarTheme.foregroundColor,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_group == null) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('Group Not Found'),
          backgroundColor: theme.appBarTheme.backgroundColor,
          foregroundColor: theme.appBarTheme.foregroundColor,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: colorScheme.onSurface.withOpacity(0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'Group not found',
                style: TextStyle(
                  fontSize: 18,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, 'refresh'),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(_group!.name),
        backgroundColor: theme.appBarTheme.backgroundColor,
        foregroundColor: theme.appBarTheme.foregroundColor,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.group),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => _buildMembersDialog(),
              );
            },
          ),
          // Activity Log Button with smart badge
          StreamBuilder<int>(
            stream: _databaseService.streamUnreadActivityCount(
                Provider.of<AuthService>(context, listen: false).currentUser?.uid ?? '',
                widget.groupId
            ),
            builder: (context, unreadSnapshot) {
              int unreadCount = unreadSnapshot.data ?? 0;

              return IconButton(
                icon: Stack(
                  children: [
                    const Icon(Icons.history),
                    if (unreadCount > 0)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 12,
                            minHeight: 12,
                          ),
                          child: Text(
                            unreadCount > 9 ? '9+' : unreadCount.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
                onPressed: () async {
                  final authService = Provider.of<AuthService>(context, listen: false);
                  if (authService.currentUser != null) {
                    await _databaseService.updateLastSeenActivity(
                        authService.currentUser!.uid, widget.groupId
                    );

                    if (mounted) {
                      setState(() {});
                    }
                  }

                  await _navigateWithTransition(ActivityLogScreen(groupId: widget.groupId));
                },
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {
              _showGroupOptions(context);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: Column(
          children: [
            // Group Header
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: theme.primaryColor,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  if (_group!.description != null) ...[
                    Text(
                      _group!.description!,
                      style: TextStyle(
                        color: colorScheme.onPrimary.withOpacity(0.8),
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Group Balance - StreamBuilder with cached initial data
                  StreamBuilder<Map<String, double>>(
                    stream: _getBalanceStream(),
                    initialData: _cachedBalances,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          snapshot.data == null) {
                        return _buildBalanceSkeleton();
                      }

                      final authService = Provider.of<AuthService>(context, listen: false);
                      final currentUserId = authService.currentUser?.uid;
                      final userBalance = snapshot.hasData && currentUserId != null
                          ? snapshot.data![currentUserId] ?? 0.0
                          : 0.0;

                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colorScheme.onPrimary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              userBalance >= 0
                                  ? Icons.trending_up
                                  : Icons.trending_down,
                              color: colorScheme.onPrimary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Your Balance',
                                    style: TextStyle(
                                      color: colorScheme.onPrimary.withOpacity(0.8),
                                      fontSize: 14,
                                    ),
                                  ),
                                  AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 300),
                                    style: TextStyle(
                                      color: colorScheme.onPrimary,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    child: Text(_formatCurrency(userBalance)),
                                  ),
                                  Text(
                                    userBalance >= 0
                                        ? 'You are owed'
                                        : 'You owe',
                                    style: TextStyle(
                                      color: colorScheme.onPrimary.withOpacity(0.8),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Group Insights Button (keep this as is)
                            StreamBuilder<List<ExpenseModel>>(
                              stream: _databaseService.streamGroupExpenses(widget.groupId),
                              builder: (context, expenseSnapshot) {
                                List<ExpenseModel> expenses = expenseSnapshot.data ?? [];

                                if (expenses.isEmpty) {
                                  return const SizedBox.shrink();
                                }

                                return Container(
                                  margin: const EdgeInsets.only(left: 8),
                                  child: IconButton(
                                    onPressed: () {
                                      _navigateWithTransition(GroupInsightsScreen(
                                        group: _group!,
                                        members: _members,
                                      ));
                                    },
                                    icon: Icon(
                                      Icons.auto_awesome,
                                      color: colorScheme.onPrimary,
                                    ),
                                    style: IconButton.styleFrom(
                                      backgroundColor: colorScheme.onPrimary.withOpacity(0.2),
                                      padding: const EdgeInsets.all(8),
                                    ),
                                    tooltip: 'Group Insights',
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // Quick access to balances
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await _navigateWithTransition(BalancesScreen(
                          groupId: widget.groupId,
                          members: _members,
                        ));
                        // Always refresh after balances screen since settlements might have happened
                        await _loadGroupData(forceRefresh: true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.onPrimary.withOpacity(0.2),
                        foregroundColor: colorScheme.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.account_balance),
                      label: const Text('View All Balances'),
                    ),
                  ),
                ],
              ),
            ),


            // Members Count, Add Expense + Filter Dropdown
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.group, color: colorScheme.onSurface.withOpacity(0.6)),
                      const SizedBox(width: 8),
                      Text(
                        '${_members.length} members',
                        style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.6),
                          fontSize: 14,
                        ),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () {
                          _navigateWithTransition(AddExpenseScreen(
                            group: _group!,
                            members: _members,
                          ));
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Add Expense'),
                      ),
                    ],
                  ),

// Filter Toggle
                  Row(
                    children: [
                      Icon(
                        Icons.filter_list,
                        color: colorScheme.onSurface.withOpacity(0.6),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Show settled expenses',
                        style: TextStyle(
                          color: colorScheme.onSurface.withOpacity(0.8),
                          fontSize: 14,
                        ),
                      ),
                      const Spacer(),
                      Switch(
                        value: _currentFilter == ExpenseFilter.all,
                        onChanged: (bool value) {
                          setState(() {
                            _currentFilter = value ? ExpenseFilter.all : ExpenseFilter.unsettled;
                          });
                        },
                        activeColor: theme.primaryColor,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // UPDATED: Expenses List with new stream
            Expanded(
              child: StreamBuilder<List<ExpenseModel>>(
                stream: _getFilteredExpenseStream(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                    return _buildExpenseListSkeleton();
                  }

                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return _buildEmptyExpensesState();
                  }

                  List<ExpenseModel> expenses = snapshot.data!;

                  return Column(
                    children: [

                      // Expenses list
                      Expanded(
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: expenses.length,
                          itemBuilder: (context, index) {
                            return _buildExpenseItem(expenses[index]);
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          _navigateWithTransition(AddExpenseScreen(
            group: _group!,
            members: _members,
          ));
        },
        backgroundColor: theme.primaryColor,
        child: Icon(
          Icons.add,
          color: colorScheme.onPrimary,
        ),
      ),
    );
  }

  Widget _buildExpenseItem(ExpenseModel expense) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentUserId = Provider.of<AuthService>(context, listen: false).currentUser?.uid;

    UserModel? paidByUser = _members.firstWhere(
          (member) => member.id == expense.paidBy,
      orElse: () => UserModel(
        id: '',
        name: 'Unknown',
        email: '',
        groupIds: [],
        createdAt: DateTime.now(),
      ),
    );

    // Check if expense is settled for current user or fully settled
    bool isSettledForUser = false;
    if (currentUserId != null) {
      // Check if expense is fully settled for everyone
      if (expense.isFullySettled()) {
        isSettledForUser = true;
      }
      // Check if it's settled specifically for this user
      else if (expense.splitBetween.contains(currentUserId) &&
          expense.paidBy != currentUserId &&
          expense.isSettledForUser(currentUserId)) {
        isSettledForUser = true;
      }
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      child: Hero(
        tag: 'expense_${expense.id}',
        child: Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: theme.cardColor,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isSettledForUser
                  ? colorScheme.onSurface.withOpacity(0.3)
                  : theme.primaryColor,
              child: Text(
                expense.category.emoji,
                style: const TextStyle(
                  fontSize: 18,
                  color: Colors.white,
                ),
              ),
            ),
            title: Text(
              expense.description,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isSettledForUser
                    ? colorScheme.onSurface.withOpacity(0.6)
                    : colorScheme.onSurface,
                decoration: isSettledForUser
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Paid by ${paidByUser.name}',
                  style: TextStyle(
                    color: isSettledForUser
                        ? colorScheme.onSurface.withOpacity(0.5)
                        : colorScheme.onSurface.withOpacity(0.8),
                    decoration: isSettledForUser
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${expense.date.day}/${expense.date.month}/${expense.date.year}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isSettledForUser
                        ? colorScheme.onSurface.withOpacity(0.4)
                        : colorScheme.onSurface.withOpacity(0.6),
                    decoration: isSettledForUser
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                  ),
                ),
              ],
            ),
            trailing: Text(
              _formatCurrency(expense.amount),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: isSettledForUser
                    ? colorScheme.onSurface.withOpacity(0.6)
                    : colorScheme.onSurface,
                decoration: isSettledForUser
                    ? TextDecoration.lineThrough
                    : TextDecoration.none,
              ),
            ),
            onTap: () {
              _navigateWithTransition(ExpenseDetailScreen(
                expense: expense,
                group: _group!,
                members: _members,
              ));
            },
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyExpensesState() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.4,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.receipt_long,
                size: 64,
                color: colorScheme.onSurface.withOpacity(0.4),
              ),
              const SizedBox(height: 16),
              Text(
                'No expenses yet',
                style: TextStyle(
                  fontSize: 18,
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Add your first expense to start splitting!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  _navigateWithTransition(AddExpenseScreen(
                    group: _group!,
                    members: _members,
                  ));
                },
                icon: const Icon(Icons.add),
                label: const Text('Add Expense'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  foregroundColor: colorScheme.onPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Loading skeleton for balance card
  Widget _buildBalanceSkeleton() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          ShimmerBox(width: 24, height: 24, borderRadius: 4),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerBox(width: 100, height: 14, borderRadius: 4),
                SizedBox(height: 4),
                ShimmerBox(width: 120, height: 20, borderRadius: 4),
                SizedBox(height: 4),
                ShimmerBox(width: 80, height: 12, borderRadius: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Loading skeleton for expense list
  Widget _buildExpenseListSkeleton() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: 6,
      itemBuilder: (context, index) => const Card(
        margin: EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: ShimmerBox(width: 40, height: 40, borderRadius: 20),
          title: ShimmerBox(width: double.infinity, height: 16, borderRadius: 4),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: 4),
              ShimmerBox(width: 120, height: 14, borderRadius: 4),
              SizedBox(height: 2),
              ShimmerBox(width: 80, height: 12, borderRadius: 4),
            ],
          ),
          trailing: ShimmerBox(width: 60, height: 20, borderRadius: 4),
        ),
      ),
    );
  }

  Widget _buildMembersDialog() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return AlertDialog(
      backgroundColor: theme.dialogBackgroundColor,
      title: Text(
        'Group Members',
        style: TextStyle(color: colorScheme.onSurface),
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: _members.length,
          itemBuilder: (context, index) {
            UserModel member = _members[index];
            return AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: theme.primaryColor,
                  child: Text(
                    member.name.substring(0, 1).toUpperCase(),
                    style: TextStyle(color: colorScheme.onPrimary),
                  ),
                ),
                title: Text(
                  member.name,
                  style: TextStyle(color: colorScheme.onSurface),
                ),
                subtitle: Text(
                  member.email,
                  style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  // ADD this method to show the explanation dialog:

  void _showGroupOptions(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.bottomSheetTheme.backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.history, color: theme.primaryColor),
              title: Text(
                'Activity Log',
                style: TextStyle(color: colorScheme.onSurface),
              ),
              subtitle: Text(
                'View all group activities',
                style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
              ),
              onTap: () {
                Navigator.pop(context);
                _navigateWithTransition(ActivityLogScreen(groupId: widget.groupId));
              },
            ),
            ListTile(
              leading: Icon(Icons.account_balance, color: Colors.green.shade600),
              title: Text(
                'Balances',
                style: TextStyle(color: colorScheme.onSurface),
              ),
              subtitle: Text(
                'View detailed balances',
                style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
              ),
              onTap: () {
                Navigator.pop(context);
                _navigateWithTransition(BalancesScreen(
                  groupId: widget.groupId,
                  members: _members,
                )).then((_) {
                  // Always refresh after balances screen
                  _loadGroupData(forceRefresh: true);
                });
              },
            ),
            ListTile(
              leading: Icon(Icons.settings, color: theme.primaryColor),
              title: Text(
                'Group Settings',
                style: TextStyle(color: colorScheme.onSurface),
              ),
              subtitle: Text(
                'Manage members and group settings',
                style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
              ),
              onTap: () {
                Navigator.pop(context);
                _navigateWithTransition(GroupSettingsScreen(group: _group!));
              },
            ),
          ],
        ),
      ),
    );
  }
}