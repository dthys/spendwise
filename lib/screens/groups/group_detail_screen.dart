import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../models/group_model.dart';
import '../../models/expense_model.dart';
import '../../models/user_model.dart';
import '../../models/settlement_model.dart';
import 'add_expense_screen.dart';
import '../expenses/expense_detail_screen.dart';
import '../expenses/activity_log_screen.dart';
import '../balances/balances_screen.dart';
import 'group_settings_screen.dart';
import '../../widgets/shimmer_box.dart';

class GroupDetailScreen extends StatefulWidget {
  final String groupId;

  const GroupDetailScreen({Key? key, required this.groupId}) : super(key: key);

  @override
  _GroupDetailScreenState createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen> {
  final DatabaseService _databaseService = DatabaseService();
  GroupModel? _group;
  List<UserModel> _members = [];
  bool _isLoading = true;
  bool _showSettledExpenses = false; // NEW: Toggle for settled expenses

  @override
  void initState() {
    super.initState();
    _loadGroupData();
  }



  Future<void> _loadGroupData() async {
    try {
      _group = await _databaseService.getGroup(widget.groupId);
      if (_group != null) {
        // Load member details
        _members = [];
        for (String memberId in _group!.memberIds) {
          UserModel? member = await _databaseService.getUser(memberId);
          if (member != null) {
            _members.add(member);
          }
        }
      }
      setState(() => _isLoading = false);
    } catch (e) {
      print('Error loading group: $e');
      setState(() => _isLoading = false);
    }
  }

  String _formatCurrency(double amount) {
    return '${_group?.currency ?? 'EUR'} ${amount.toStringAsFixed(2)}';
  }

  // Create a stream for balance updates that reacts to expense changes
  Stream<Map<String, double>> _getBalanceStream() {
    return _databaseService.streamGroupExpenses(widget.groupId).asyncMap((
        _) async {
      // Use the updated method that considers settlements
      return await _databaseService.calculateGroupBalancesWithSettlements(
          widget.groupId);
    });
  }

  // NEW: Check if an expense is fully settled
  bool _isExpenseFullySettled(ExpenseModel expense,
      List<SettlementModel> settlements) {
    // Get settlements that include this expense
    List<SettlementModel> expenseSettlements = settlements
        .where((s) => s.settledExpenseIds.contains(expense.id))
        .toList();

    if (expenseSettlements.isEmpty) {
      return false; // No settlements for this expense
    }

    // Get all user pairs that have settled this expense
    Set<String> settledUserPairs = expenseSettlements
        .map((s) => '${s.fromUserId}-${s.toUserId}')
        .toSet();

    // Add reverse pairs (settlements work both ways)
    List<String> reversePairs = expenseSettlements
        .map((s) => '${s.toUserId}-${s.fromUserId}')
        .toList();
    settledUserPairs.addAll(reversePairs);

    String payer = expense.paidBy;

    // Check if all debts for this expense are settled
    for (String participant in expense.splitBetween) {
      if (participant == payer) {
        continue; // Payer doesn't owe themselves
      }

      // If any participant hasn't settled with the payer, expense is not fully settled
      if (!settledUserPairs.contains('$participant-$payer')) {
        return false;
      }
    }

    return true; // All participants have settled with the payer
  }

  // NEW: Filter expenses based on settled status
  List<ExpenseModel> _filterExpenses(List<ExpenseModel> expenses,
      List<SettlementModel> settlements) {
    if (_showSettledExpenses) {
      return expenses; // Show all expenses
    } else {
      // Show only unsettled expenses
      return expenses.where((expense) =>
      !_isExpenseFullySettled(expense, settlements)).toList();
    }
  }

  // Add refresh functionality
  Future<void> _refreshData() async {
    await _loadGroupData();
    await Future.delayed(
        Duration(milliseconds: 500)); // Small delay for better UX
  }

  // Create smooth page transitions
  Route _createRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionDuration: Duration(milliseconds: 300),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(1.0, 0.0);
        const end = Offset.zero;
        const curve = Curves.easeInOut;

        var tween = Tween(begin: begin, end: end).chain(
          CurveTween(curve: curve),
        );

        return SlideTransition(
          position: animation.drive(tween),
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text('Loading...'),
          backgroundColor: theme.appBarTheme.backgroundColor,
          foregroundColor: theme.appBarTheme.foregroundColor,
        ),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_group == null) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text('Group Not Found'),
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
              SizedBox(height: 16),
              Text(
                'Group not found',
                style: TextStyle(
                  fontSize: 18,
                  color: colorScheme.onSurface,
                ),
              ),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Go Back'),
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
            icon: Icon(Icons.group),
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
                    Icon(Icons.history),
                    if (unreadCount > 0)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          padding: EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          constraints: BoxConstraints(
                            minWidth: 12,
                            minHeight: 12,
                          ),
                          child: Text(
                            unreadCount > 9 ? '9+' : unreadCount.toString(),
                            style: TextStyle(
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

                  final result = await Navigator.push(
                    context,
                    _createRoute(ActivityLogScreen(groupId: widget.groupId)),
                  );

                  if (result == true && mounted) {
                    setState(() {});
                  }
                },
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.more_vert),
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
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              padding: EdgeInsets.fromLTRB(24, 0, 24, 24),
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
                    SizedBox(height: 16),
                  ],

                  // Group Balance - Changed to StreamBuilder for real-time updates
                  StreamBuilder<Map<String, double>>(
                    stream: _getBalanceStream(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          snapshot.data == null) {
                        return _buildBalanceSkeleton();
                      }

                      final authService = Provider.of<AuthService>(
                          context, listen: false);
                      final currentUserId = authService.currentUser?.uid;
                      final userBalance = snapshot.hasData &&
                          currentUserId != null
                          ? snapshot.data![currentUserId] ?? 0.0
                          : 0.0;

                      return AnimatedContainer(
                        duration: Duration(milliseconds: 300),
                        padding: EdgeInsets.all(16),
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
                            SizedBox(width: 12),
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
                                    duration: Duration(milliseconds: 300),
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
                          ],
                        ),
                      );
                    },
                  ),

                  SizedBox(height: 16),

                  // Quick access to balances
                  Container(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          _createRoute(BalancesScreen(
                            groupId: widget.groupId,
                            members: _members,
                          )),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.onPrimary.withOpacity(0.2),
                        foregroundColor: colorScheme.onPrimary,
                        padding: EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: Icon(Icons.account_balance),
                      label: Text('View All Balances'),
                    ),
                  ),
                ],
              ),
            ),

            // Members Count and Add Expense
            Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.group, color: colorScheme.onSurface.withOpacity(0.6)),
                  SizedBox(width: 8),
                  Text(
                    '${_members.length} members',
                    style: TextStyle(
                      color: colorScheme.onSurface.withOpacity(0.6),
                      fontSize: 14,
                    ),
                  ),
                  Spacer(),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        _createRoute(AddExpenseScreen(
                          group: _group!,
                          members: _members,
                        )),
                      );
                    },
                    icon: Icon(Icons.add),
                    label: Text('Add Expense'),
                  ),
                ],
              ),
            ),

            // NEW: Show/Hide Settled Expenses Toggle
            StreamBuilder<List<SettlementModel>>(
              stream: _databaseService.streamGroupSettlements(widget.groupId),
              builder: (context, settlementSnapshot) {
                List<SettlementModel> settlements = settlementSnapshot.data ??
                    [];

                // Count settled expenses
                int settledExpensesCount = 0;
                if (settlementSnapshot.hasData) {
                  Set<String> settledExpenseIds = settlements
                      .expand((s) => s.settledExpenseIds)
                      .toSet();
                  settledExpensesCount = settledExpenseIds.length;
                }

                // Only show toggle if there are settled expenses
                if (settledExpensesCount == 0) {
                  return SizedBox.shrink();
                }

                return Container(
                  margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        _showSettledExpenses ? Icons.visibility_off : Icons.visibility,
                        color: colorScheme.onSurface.withOpacity(0.6),
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _showSettledExpenses
                              ? 'Hiding settled expenses'
                              : '$settledExpensesCount settled expenses hidden',
                          style: TextStyle(
                            color: colorScheme.onSurface.withOpacity(0.6),
                            fontSize: 14,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _showSettledExpenses = !_showSettledExpenses;
                          });
                        },
                        icon: Icon(
                          _showSettledExpenses ? Icons.expand_less : Icons.expand_more,
                          size: 18,
                        ),
                        label: Text(
                          _showSettledExpenses ? 'Hide settled' : 'Show settled',
                          style: TextStyle(fontSize: 14),
                        ),
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size(0, 0),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            // Expenses List
            Expanded(
              child: StreamBuilder<List<ExpenseModel>>(
                stream: _databaseService.streamGroupExpenses(widget.groupId),
                builder: (context, expenseSnapshot) {
                  return StreamBuilder<List<SettlementModel>>(
                    stream: _databaseService.streamGroupSettlements(widget.groupId),
                    builder: (context, settlementSnapshot) {
                      if (expenseSnapshot.connectionState == ConnectionState.waiting &&
                          expenseSnapshot.data == null) {
                        return _buildExpenseListSkeleton();
                      }

                      if (!expenseSnapshot.hasData || expenseSnapshot.data!.isEmpty) {
                        return SingleChildScrollView(
                          physics: AlwaysScrollableScrollPhysics(),
                          child: Container(
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
                                  SizedBox(height: 16),
                                  Text(
                                    'No expenses yet',
                                    style: TextStyle(
                                      fontSize: 18,
                                      color: colorScheme.onSurface,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Add your first expense to start splitting!',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: colorScheme.onSurface.withOpacity(0.7),
                                    ),
                                  ),
                                  SizedBox(height: 24),
                                  ElevatedButton.icon(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        _createRoute(AddExpenseScreen(
                                          group: _group!,
                                          members: _members,
                                        )),
                                      );
                                    },
                                    icon: Icon(Icons.add),
                                    label: Text('Add Expense'),
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

                      List<ExpenseModel> allExpenses = expenseSnapshot.data!;
                      List<SettlementModel> settlements = settlementSnapshot.data ?? [];

                      List<ExpenseModel> filteredExpenses = _filterExpenses(allExpenses, settlements);

                      if (filteredExpenses.isEmpty && !_showSettledExpenses) {
                        return SingleChildScrollView(
                          physics: AlwaysScrollableScrollPhysics(),
                          child: Container(
                            height: MediaQuery.of(context).size.height * 0.4,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    size: 64,
                                    color: Colors.green.shade500,
                                  ),
                                  SizedBox(height: 16),
                                  Text(
                                    'All expenses settled!',
                                    style: TextStyle(
                                      fontSize: 18,
                                      color: Colors.green.shade600,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'All current expenses have been settled.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: colorScheme.onSurface.withOpacity(0.7),
                                    ),
                                  ),
                                  SizedBox(height: 16),
                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        _showSettledExpenses = true;
                                      });
                                    },
                                    child: Text('Show settled expenses'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }

                      return ListView.builder(
                        physics: AlwaysScrollableScrollPhysics(),
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        itemCount: filteredExpenses.length,
                        itemBuilder: (context, index) {
                          ExpenseModel expense = filteredExpenses[index];
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

                          bool isSettled = _isExpenseFullySettled(expense, settlements);

                          return AnimatedContainer(
                            duration: Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            child: Card(
                              margin: EdgeInsets.only(bottom: 8),
                              color: theme.cardColor,
                              child: ListTile(
                                leading: Hero(
                                  tag: 'expense_${expense.id}',
                                  child: Stack(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: isSettled
                                            ? Colors.grey.shade400
                                            : theme.primaryColor,
                                        child: Text(
                                          expense.category.emoji,
                                          style: TextStyle(
                                            fontSize: 18,
                                            color: isSettled
                                                ? Colors.white.withOpacity(0.7)
                                                : Colors.white,
                                          ),
                                        ),
                                      ),
                                      if (isSettled)
                                        Positioned(
                                          right: -2,
                                          bottom: -2,
                                          child: Container(
                                            padding: EdgeInsets.all(2),
                                            decoration: BoxDecoration(
                                              color: Colors.green.shade500,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Icon(
                                              Icons.check,
                                              color: Colors.white,
                                              size: 12,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                title: Text(
                                  expense.description,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: isSettled
                                        ? colorScheme.onSurface.withOpacity(0.6)
                                        : colorScheme.onSurface,
                                    decoration: isSettled
                                        ? TextDecoration.lineThrough
                                        : TextDecoration.none,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          'Paid by ${paidByUser.name}',
                                          style: TextStyle(
                                            color: isSettled
                                                ? colorScheme.onSurface.withOpacity(0.4)
                                                : colorScheme.onSurface.withOpacity(0.8),
                                          ),
                                        ),
                                        if (isSettled) ...[
                                          SizedBox(width: 8),
                                          Container(
                                            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.green.shade100,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              'SETTLED',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.green.shade700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    Text(
                                      '${expense.date.day}/${expense.date.month}/${expense.date.year}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isSettled
                                            ? colorScheme.onSurface.withOpacity(0.4)
                                            : colorScheme.onSurface.withOpacity(0.6),
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: Text(
                                  _formatCurrency(expense.amount),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: isSettled
                                        ? colorScheme.onSurface.withOpacity(0.5)
                                        : colorScheme.onSurface,
                                    decoration: isSettled
                                        ? TextDecoration.lineThrough
                                        : TextDecoration.none,
                                  ),
                                ),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    _createRoute(ExpenseDetailScreen(
                                      expense: expense,
                                      group: _group!,
                                      members: _members,
                                    )),
                                  );
                                },
                              ),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            _createRoute(AddExpenseScreen(
              group: _group!,
              members: _members,
            )),
          );
        },
        backgroundColor: theme.primaryColor,
        child: Icon(
          Icons.add,
          color: colorScheme.onPrimary,
        ),
      ),
    );
  }

  // Loading skeleton for balance card
  Widget _buildBalanceSkeleton() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme
            .of(context)
            .colorScheme
            .onPrimary
            .withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
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
      padding: EdgeInsets.symmetric(horizontal: 16),
      itemCount: 6,
      itemBuilder: (context, index) =>
          Card(
            margin: EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: ShimmerBox(width: 40, height: 40, borderRadius: 20),
              title: ShimmerBox(
                  width: double.infinity, height: 16, borderRadius: 4),
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
      content: Container(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: _members.length,
          itemBuilder: (context, index) {
            UserModel member = _members[index];
            return AnimatedContainer(
              duration: Duration(milliseconds: 200),
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
                  style: TextStyle(
                      color: colorScheme.onSurface.withOpacity(0.7)),
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Close'),
        ),
      ],
    );
  }

  void _showGroupOptions(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.bottomSheetTheme.backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) =>
          AnimatedContainer(
            duration: Duration(milliseconds: 300),
            padding: EdgeInsets.symmetric(vertical: 20),
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
                    style: TextStyle(
                        color: colorScheme.onSurface.withOpacity(0.7)),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      _createRoute(ActivityLogScreen(groupId: widget.groupId)),
                    );
                  },
                ),
                ListTile(
                  leading: Icon(
                      Icons.account_balance, color: Colors.green.shade600),
                  title: Text(
                    'Balances',
                    style: TextStyle(color: colorScheme.onSurface),
                  ),
                  subtitle: Text(
                    'View detailed balances',
                    style: TextStyle(
                        color: colorScheme.onSurface.withOpacity(0.7)),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      _createRoute(BalancesScreen(
                        groupId: widget.groupId,
                        members: _members,
                      )),
                    );
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
                    style: TextStyle(
                        color: colorScheme.onSurface.withOpacity(0.7)),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      _createRoute(GroupSettingsScreen(group: _group!)),
                    );
                  },
                ),
              ],
            ),
          ),
    );
  }
}
