import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../models/user_model.dart';
import '../../models/expense_model.dart';
import '../../models/settlement_model.dart';
import '../../utils/number_formatter.dart';
import '../models/group_model.dart';
import '../screens/groups/add_expense_screen.dart';
import 'friend_service.dart';

enum ExpenseFilter {
  unsettled,
  all;
}


class FriendDetailScreen extends StatefulWidget {
  final String friendId;

  const FriendDetailScreen({
    super.key,
    required this.friendId,
  });

  // Add this helper method to get category colors

  @override
  _FriendDetailScreenState createState() => _FriendDetailScreenState();
}

class _FriendDetailScreenState extends State<FriendDetailScreen>
    with SingleTickerProviderStateMixin {
  final FriendService _friendService = FriendService();
  final DatabaseService _databaseService = DatabaseService();

  late TabController _tabController;
  UserModel? _friend;
  String? _currentUserId;
  double _friendBalance = 0.0;
  bool _isLoading = true;

  List<ExpenseModel> _expenses = [];
  Timer? _refreshTimer;

  ExpenseFilter _currentFilter = ExpenseFilter.unsettled;


  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initialize();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      _currentUserId = authService.currentUser?.uid;

      if (_currentUserId == null) return;

      setState(() => _isLoading = true);

      // Get friend details
      _friend = await _friendService.getFriendFromBalance(_currentUserId!, widget.friendId);
      _friend ??= await _databaseService.getUser(widget.friendId);

      if (_friend != null) {
        // Load friend balance and expenses
        await Future.wait([
          _loadFriendBalance(),
          _loadFriendExpenses(),
        ]);
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error initializing friend screen: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadFriendBalance() async {
    if (_currentUserId == null || _friend == null) return;

    try {
      double balance = await _friendService.getFriendBalance(_currentUserId!, _friend!.id);
      if (mounted) {
        setState(() => _friendBalance = balance);
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error loading friend balance: $e');
      }
    }
  }

  Future<void> _loadFriendExpenses() async {
    if (_currentUserId == null || _friend == null) return;

    try {
      List<ExpenseModel> allExpenses = await _friendService.getFriendExpenses(_currentUserId!, _friend!.id);

      List<ExpenseModel> filteredExpenses = [];

      if (_currentFilter == ExpenseFilter.all) {
        filteredExpenses = allExpenses;
      } else {
        // Filter out settled expenses (same logic as group screen)
        for (ExpenseModel expense in allExpenses) {
          // Rule 1: Hide expenses that are completely settled for everyone
          if (expense.isFullySettled()) {
            continue;
          }

          // Rule 2: For expenses involving this user, hide if settled for them
          if (expense.splitBetween.contains(_currentUserId) &&
              expense.paidBy != _currentUserId &&
              expense.isSettledForUser(_currentUserId!)) {
            continue;
          }

          filteredExpenses.add(expense);
        }
      }

      if (mounted) {
        setState(() => _expenses = filteredExpenses);
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error loading friend expenses: $e');
      }
    }
  }

// Add this method to create the filter toggle widget
  Widget _buildFilterToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.filter_list,
            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            'Show settled expenses',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
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
              // Reload expenses with new filter
              _loadFriendExpenses();
            },
            activeColor: Theme.of(context).primaryColor,
          ),
        ],
      ),
    );
  }

  Future<void> _refresh() async {
    await Future.wait([
      _loadFriendBalance(),
      _loadFriendExpenses(),
    ]);
  }

  void _addExpense() async {
    if (_friend == null || _currentUserId == null) return;

    print('🔧 === FIXED ADD EXPENSE FLOW ===');

    try {
      // Step 1: Find ALL shared groups
      List<GroupModel> userGroups = await _databaseService.getAllUserGroups(_currentUserId!);
      List<GroupModel> sharedGroups = userGroups
          .where((group) => group.memberIds.contains(_friend!.id))
          .toList();

      print('🔧 Found ${sharedGroups.length} actual shared groups:');
      for (var group in sharedGroups) {
        print('🔧   - ${group.name} (${group.id})');
        print('🔧     Members: ${group.memberIds}');
        print('🔧     Is Friend Group: ${group.metadata?['isFriendGroup'] == true}');
        print('🔧     Member count: ${group.memberIds.length}');
      }

      if (sharedGroups.isEmpty) {
        print('🔧 No shared groups found - this should not happen!');
        return;
      }

      // Step 2: ✅ PRIORITIZE FRIEND GROUP - look for a group that is specifically a friend group
      GroupModel? targetGroup;

      // First, try to find the dedicated friend group (2 members only OR has friend metadata)
      for (GroupModel group in sharedGroups) {
        bool isFriendGroup = group.metadata?['isFriendGroup'] == true ||
            (group.memberIds.length == 2 && group.name.contains('&'));

        if (isFriendGroup) {
          targetGroup = group;
          print('🔧 ✅ Found friend group: ${group.name} (${group.id})');
          break;
        }
      }

      // Fallback: if no dedicated friend group found, use the first shared group
      if (targetGroup == null) {
        targetGroup = sharedGroups.first;
        print('🔧 ⚠️ Using fallback group: ${targetGroup.name} (${targetGroup.id})');
      }

      // Step 3: Get current user and friend as members
      UserModel? currentUser = await _databaseService.getUser(_currentUserId!);
      currentUser ??= UserModel.empty();

      List<UserModel> members = [currentUser, _friend!];

      print('🔧 Selected target group: ${targetGroup.name} (${targetGroup.id})');
      print('🔧 Members: ${members.map((m) => m.name).toList()}');

      // Step 4: Navigate to AddExpenseScreen with the CORRECT group
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AddExpenseScreen(
            group: targetGroup!, // ✅ Use the prioritized friend group
            members: members,
          ),
        ),
      );

      print('🔧 AddExpenseScreen result: $result');

      // ✅ Always refresh regardless of return value
      print('🔧 Refreshing friend data (regardless of return value)...');

      // Wait a moment for Firestore to sync
      await Future.delayed(Duration(seconds: 1));

      await _refresh();

      // Verify the expense was added to the correct group
      List<ExpenseModel> updatedExpenses = await _databaseService.getGroupExpenses(targetGroup.id);
      print('🔧 Target group now has ${updatedExpenses.length} expenses');
      print('🔧 Friend expenses list has ${_expenses.length} expenses');

      if (result != null) {
        print('🔧 AddExpenseScreen returned success');
      } else {
        print('🔧 AddExpenseScreen returned null, but expense was created anyway');
      }

    } catch (e) {
      print('🔧 Error in fixed add expense flow: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding expense: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    print('🔧 === END FIXED ADD EXPENSE FLOW ===');
  }

// ALSO: Add this method to directly create an expense without UI navigation
  Future<void> _createExpenseDirectly() async {
    if (_friend == null || _currentUserId == null) return;

    print('🚀 === DIRECT EXPENSE CREATION TEST ===');

    try {
      // Create test expense
      ExpenseModel testExpense = ExpenseModel(
        id: '', // Will be generated
        groupId: '', // Will be set by service
        description: 'DIRECT TEST EXPENSE',
        amount: 15.0,
        paidBy: _currentUserId!,
        splitBetween: [_currentUserId!, _friend!.id],
        date: DateTime.now(),
        category: ExpenseCategory.other,
        createdAt: DateTime.now(),
      );

      print('🚀 Creating expense directly...');
      String expenseId = await _friendService.addFriendExpense(
          _currentUserId!,
          _friend!.id,
          testExpense
      );

      print('🚀 Direct expense created with ID: $expenseId');

      // Wait a moment for database to sync
      await Future.delayed(Duration(seconds: 2));

      // Refresh and verify
      await _refresh();
      print('🚀 After refresh: ${_expenses.length} expenses');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Direct expense created: $expenseId'),
            backgroundColor: Colors.green,
          ),
        );
      }

    } catch (e) {
      print('🚀 Error in direct expense creation: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    print('🚀 === END DIRECT EXPENSE CREATION ===');
  }

// Add this debug button to test direct creation
  Widget _buildDirectExpenseButton() {
    return ElevatedButton.icon(
      onPressed: _createExpenseDirectly,
      icon: Icon(Icons.bolt),
      label: Text('Create Expense Directly'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.orange,
      ),
    );
  }

  void _settleDebt() async {
    if (_friend == null || _currentUserId == null || _friendBalance.abs() <= 0.01) return;

    // Show a simple settlement dialog
    bool? result = await _showSettlementDialog();

    if (result == true) {
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('💰 Debt settled successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _findMissingExpense() async {
    if (_currentUserId == null || _friend == null) return;

    print('🔍 === HUNTING FOR MISSING EXPENSE ===');

    try {
      // 1. Check what getAllUserGroups returns
      print('🔍 Step 1: Checking getAllUserGroups...');
      List<GroupModel> allGroups = await _databaseService.getAllUserGroups(_currentUserId!);
      print('🔍 getAllUserGroups returned ${allGroups.length} groups:');

      for (GroupModel group in allGroups) {
        print('🔍   - "${group.name}" (${group.id})');
        print('🔍     Members: ${group.memberIds}');
        print('🔍     Created by: ${group.createdBy}');
        print('🔍     Contains friend: ${group.memberIds.contains(_friend!.id)}');

        // Check expenses in each group
        List<ExpenseModel> expenses = await _databaseService.getGroupExpenses(group.id);
        print('🔍     Expenses: ${expenses.length}');
        for (ExpenseModel exp in expenses) {
          print('🔍       - "${exp.description}" (${exp.id}) - €${exp.amount}');
        }
      }

      // 2. Let's also try to find ALL groups in the database that contain either user
      print('🔍 Step 2: Searching for groups containing current user...');
      // This would require a database query - you might need to add this method to DatabaseService

      // 3. Check if there are any groups we're missing
      print('🔍 Step 3: Direct check for the specific expense ID...');
      String lastExpenseId = 'OCXkeVVNdrhHhk3xP6t2'; // From your logs

      // Try to find this expense by searching through ALL possible groups
      // This is a brute force approach but will help us understand where it went

      // 4. Check Firestore directly (if possible)
      print('🔍 Step 4: Manual group detection...');

      // Let's manually check the group we saw in logs
      String suspectedGroupId = 'mDv1zQikMXG1MafudFrF'; // From your earlier logs
      try {
        GroupModel? suspectedGroup = await _databaseService.getGroup(suspectedGroupId);
        if (suspectedGroup != null) {
          print('🔍 Suspected group found: ${suspectedGroup.name}');
          print('🔍   Members: ${suspectedGroup.memberIds}');
          print('🔍   Current user is member: ${suspectedGroup.memberIds.contains(_currentUserId)}');

          List<ExpenseModel> suspectedExpenses = await _databaseService.getGroupExpenses(suspectedGroupId);
          print('🔍   Expenses in suspected group: ${suspectedExpenses.length}');
          for (ExpenseModel exp in suspectedExpenses) {
            print('🔍     - "${exp.description}" (${exp.id}) - €${exp.amount}');
          }
        } else {
          print('🔍 Suspected group NOT found in database');
        }
      } catch (e) {
        print('🔍 Error checking suspected group: $e');
      }

      // 5. Let's also check the user's document directly
      print('🔍 Step 5: Checking user document...');
      UserModel? currentUser = await _databaseService.getUser(_currentUserId!);
      if (currentUser != null) {
        print('🔍 Current user: ${currentUser.name} (${currentUser.id})');
        print('🔍 Current user email: ${currentUser.email}');
      }

    } catch (e) {
      print('🔍 Error in missing expense hunt: $e');
    }

    print('🔍 === END HUNT ===');
  }

// Add this method to check notification system vs group system
  Future<void> _debugNotificationGroupMismatch() async {
    if (_currentUserId == null) return;

    print('🔍 === DEBUGGING NOTIFICATION vs GROUP MISMATCH ===');

    // Check what the notification system sees
    print('🔍 What notification system sees:');
    // You'll need to expose or replicate the notification calculation logic here

    // Check what the group system sees
    print('🔍 What group system sees:');
    List<GroupModel> groups = await _databaseService.getAllUserGroups(_currentUserId!);
    print('🔍 Group system found ${groups.length} groups');

    // Check what the friend system sees
    print('🔍 What friend system sees:');
    List<GroupModel> friendGroups = groups.where((g) => g.memberIds.contains(_friend!.id)).toList();
    print('🔍 Friend system found ${friendGroups.length} shared groups');

    // The issue might be that different parts of your app are using different methods
    // to get groups, or there's a caching/timing issue

    print('🔍 === END MISMATCH DEBUG ===');
  }

// Add this button to your friend detail screen UI temporarily
  Widget _buildDebugButtons() {
    return Column(
      children: [
        ElevatedButton(
          onPressed: _findMissingExpense,
          child: Text('🔍 Find Missing Expense'),
        ),
        ElevatedButton(
          onPressed: _debugNotificationGroupMismatch,
          child: Text('🔍 Debug Notification Mismatch'),
        ),
        ElevatedButton(
          onPressed: () async {
            print('🔍 === SIMPLE REFRESH TEST ===');
            await _refresh();
            print('🔍 After refresh: ${_expenses.length} expenses');
            print('🔍 === END REFRESH TEST ===');
          },
          child: Text('🔍 Test Refresh'),
        ),
      ],
    );
  }

  Future<bool?> _showSettlementDialog() async {
    bool friendOwesUser = _friendBalance > 0.01;
    String balanceText = friendOwesUser
        ? 'owes you ${NumberFormatter.formatCurrency(_friendBalance)}'
        : 'you owe ${NumberFormatter.formatCurrency(-_friendBalance)}';

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Settle Debt with ${_friend!.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_friend!.name} $balanceText'),
            const SizedBox(height: 16),
            Text(
              friendOwesUser
                  ? 'Mark that ${_friend!.name} has paid you ${NumberFormatter.formatCurrency(_friendBalance.abs())}?'
                  : 'Mark that you have paid ${_friend!.name} ${NumberFormatter.formatCurrency(_friendBalance.abs())}?',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                // Use friend service to settle across all groups
                await _friendService.settleFriendDebt(
                  _currentUserId!,
                  _friend!.id,
                  _friendBalance,
                  SettlementMethod.cash,
                  'Settled via friend view',
                );
                Navigator.pop(context, true);
              } catch (e) {
                Navigator.pop(context, false);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error settling debt: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Settle'),
          ),
        ],
      ),
    );
  }

  // Add this helper method to get category colors
  Color _getExpenseCategoryColor(ExpenseCategory category) {
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
        return Colors.green;
      case ExpenseCategory.bills:
        return Colors.red;
      case ExpenseCategory.healthcare:
        return Colors.teal;
      case ExpenseCategory.other:
        return Colors.grey;
      }
  }

  Widget _buildBalanceHeader() {
    if (_friend == null) return const SizedBox.shrink();

    bool friendOwesUser = _friendBalance > 0.01;
    bool isSettled = _friendBalance.abs() <= 0.01;


    String balanceText = isSettled
        ? 'Settled up'
        : friendOwesUser
        ? 'owes you ${NumberFormatter.formatCurrency(_friendBalance)}'
        : 'you owe ${NumberFormatter.formatCurrency(-_friendBalance)}';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundImage: _friend!.photoUrl != null
                    ? NetworkImage(_friend!.photoUrl!)
                    : null,
                backgroundColor: Colors.white.withOpacity(0.2),
                child: _friend!.photoUrl == null
                    ? Text(
                  _friend!.name.substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                )
                    : null,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _friend!.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      balanceText,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!isSettled) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _settleDebt,
                icon: const Icon(Icons.payment),
                label: Text(
                  friendOwesUser ? 'Record Payment' : 'Settle Debt',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Theme.of(context).primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExpensesTab() {
    return Column(
      children: [
        // Add the filter toggle at the top
        _buildFilterToggle(),

        // Expenses list
        Expanded(
          child: _expenses.isEmpty
              ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.receipt_long,
                  size: 64,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  _currentFilter == ExpenseFilter.all
                      ? 'No shared expenses yet'
                      : 'No unsettled expenses',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _currentFilter == ExpenseFilter.all
                      ? 'Add your first expense together!'
                      : 'All expenses are settled!',
                  style: TextStyle(
                    color: Colors.grey.shade500,
                  ),
                ),
                if (_expenses.isEmpty && _currentFilter == ExpenseFilter.unsettled) ...[
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _currentFilter = ExpenseFilter.all;
                      });
                      _loadFriendExpenses();
                    },
                    child: const Text('View all expenses'),
                  ),
                ],
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _addExpense,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Expense'),
                ),
              ],
            ),
          )
              : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _expenses.length,
            itemBuilder: (context, index) {
              ExpenseModel expense = _expenses[index];
              bool isPaidByCurrentUser = expense.paidBy == _currentUserId;
              bool isCurrentUserInvolved = expense.splitBetween.contains(_currentUserId);

              // Check if expense is settled for visual styling
              bool isSettledForUser = false;
              if (_currentUserId != null) {
                if (expense.isFullySettled()) {
                  isSettledForUser = true;
                } else if (expense.splitBetween.contains(_currentUserId) &&
                    expense.paidBy != _currentUserId &&
                    expense.isSettledForUser(_currentUserId!)) {
                  isSettledForUser = true;
                }
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isSettledForUser
                        ? _getExpenseCategoryColor(expense.category).withOpacity(0.3)
                        : _getExpenseCategoryColor(expense.category).withOpacity(0.2),
                    child: Text(
                      expense.category.emoji,
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                  title: Text(
                    expense.description,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      decoration: isSettledForUser ? TextDecoration.lineThrough : null,
                      color: isSettledForUser
                          ? Colors.grey.shade600
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${expense.date.day}/${expense.date.month}/${expense.date.year}',
                        style: TextStyle(
                          color: isSettledForUser
                              ? Colors.grey.shade500
                              : Colors.grey.shade600,
                          decoration: isSettledForUser ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      if (isPaidByCurrentUser)
                        Text(
                          'You paid • ${NumberFormatter.formatCurrency(expense.amount)}',
                          style: TextStyle(
                            color: isSettledForUser ? Colors.grey.shade500 : Colors.blue,
                            fontWeight: FontWeight.w500,
                            decoration: isSettledForUser ? TextDecoration.lineThrough : null,
                          ),
                        )
                      else
                        Text(
                          '${_friend!.name} paid • ${NumberFormatter.formatCurrency(expense.amount)}',
                          style: TextStyle(
                            color: isSettledForUser
                                ? Colors.grey.shade500
                                : Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                            decoration: isSettledForUser ? TextDecoration.lineThrough : null,
                          ),
                        ),
                    ],
                  ),
                  trailing: isCurrentUserInvolved
                      ? Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        isPaidByCurrentUser ? 'you lent' : 'you owe',
                        style: TextStyle(
                          fontSize: 12,
                          color: isSettledForUser
                              ? Colors.grey.shade500
                              : Colors.grey.shade600,
                          decoration: isSettledForUser ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      Text(
                        NumberFormatter.formatCurrency(
                          isPaidByCurrentUser
                              ? expense.getAmountOwedBy(_friend!.id)
                              : expense.getAmountOwedBy(_currentUserId!),
                        ),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isSettledForUser
                              ? Colors.grey.shade500
                              : (isPaidByCurrentUser ? Colors.green : Colors.orange),
                          decoration: isSettledForUser ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ],
                  )
                      : null,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSettlementsTab() {
    // For now, show a simple message. You can implement this later if needed
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.handshake,
            size: 64,
            color: Colors.grey,
          ),
          SizedBox(height: 16),
          Text(
            'Settlements History',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Settlement history will appear here',
            style: TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Loading...'),
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_friend == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Friend Not Found'),
          backgroundColor: Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Text('Friend not found'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(_friend!.name),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withOpacity(0.7),
          tabs: const [
            Tab(text: 'Expenses'),
            Tab(text: 'History'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildBalanceHeader(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildExpensesTab(),
                _buildSettlementsTab(),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addExpense,
        backgroundColor: Theme.of(context).primaryColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}