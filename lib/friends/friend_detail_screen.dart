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
import '../screens/expenses/activity_log_screen.dart';
import '../screens/expenses/expense_detail_screen.dart';
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

class _FriendDetailScreenState extends State<FriendDetailScreen> {
  final FriendService _friendService = FriendService();
  final DatabaseService _databaseService = DatabaseService();

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
    _initialize();
  }

  @override
  void dispose() {
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
      _friend = await _friendService.getFriendFromBalance(
          _currentUserId!, widget.friendId);
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
      double balance = await _friendService.getFriendBalance(
          _currentUserId!, _friend!.id);
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
      List<ExpenseModel> allExpenses = await _friendService.getFriendExpenses(
          _currentUserId!, _friend!.id);

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
            color: Theme
                .of(context)
                .colorScheme
                .onSurface
                .withOpacity(0.6),
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            'Show settled expenses',
            style: TextStyle(
              color: Theme
                  .of(context)
                  .colorScheme
                  .onSurface
                  .withOpacity(0.8),
              fontSize: 14,
            ),
          ),
          const Spacer(),
          Switch(
            value: _currentFilter == ExpenseFilter.all,
            onChanged: (bool value) {
              setState(() {
                _currentFilter =
                value ? ExpenseFilter.all : ExpenseFilter.unsettled;
              });
              // Reload expenses with new filter
              _loadFriendExpenses();
            },
            activeColor: Theme
                .of(context)
                .primaryColor,
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

    if (kDebugMode) {
      print('🔧 === FIXED ADD EXPENSE FLOW ===');
    }

    try {
      // Step 1: Find ALL shared groups
      List<GroupModel> userGroups = await _databaseService.getAllUserGroups(
          _currentUserId!);
      List<GroupModel> sharedGroups = userGroups
          .where((group) => group.memberIds.contains(_friend!.id))
          .toList();

      if (kDebugMode) {
        print('🔧 Found ${sharedGroups.length} actual shared groups:');
      }
      for (var group in sharedGroups) {
        if (kDebugMode) {
          print('🔧   - ${group.name} (${group.id})');
        }
        if (kDebugMode) {
          print('🔧     Members: ${group.memberIds}');
        }
        if (kDebugMode) {
          print('🔧     Is Friend Group: ${group.metadata?['isFriendGroup'] ==
              true}');
        }
        if (kDebugMode) {
          print('🔧     Member count: ${group.memberIds.length}');
        }
      }

      if (sharedGroups.isEmpty) {
        if (kDebugMode) {
          print('🔧 No shared groups found - this should not happen!');
        }
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
          if (kDebugMode) {
            print('🔧 ✅ Found friend group: ${group.name} (${group.id})');
          }
          break;
        }
      }

      // Fallback: if no dedicated friend group found, use the first shared group
      if (targetGroup == null) {
        targetGroup = sharedGroups.first;
        if (kDebugMode) {
          print('🔧 ⚠️ Using fallback group: ${targetGroup.name} (${targetGroup
              .id})');
        }
      }

      // Step 3: Get current user and friend as members
      UserModel? currentUser = await _databaseService.getUser(_currentUserId!);
      currentUser ??= UserModel.empty();

      List<UserModel> members = [currentUser, _friend!];

      if (kDebugMode) {
        print(
            '🔧 Selected target group: ${targetGroup.name} (${targetGroup.id})');
      }
      if (kDebugMode) {
        print('🔧 Members: ${members.map((m) => m.name).toList()}');
      }

      // Step 4: Navigate to AddExpenseScreen with the CORRECT group
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              AddExpenseScreen(
                group: targetGroup!, // ✅ Use the prioritized friend group
                members: members,
              ),
        ),
      );

      if (kDebugMode) {
        print('🔧 AddExpenseScreen result: $result');
      }

      // ✅ Always refresh regardless of return value
      if (kDebugMode) {
        print('🔧 Refreshing friend data (regardless of return value)...');
      }

      // Wait a moment for Firestore to sync
      await Future.delayed(const Duration(seconds: 1));

      await _refresh();

      // Verify the expense was added to the correct group
      List<ExpenseModel> updatedExpenses = await _databaseService
          .getGroupExpenses(targetGroup.id);
      if (kDebugMode) {
        print('🔧 Target group now has ${updatedExpenses.length} expenses');
      }
      if (kDebugMode) {
        print('🔧 Friend expenses list has ${_expenses.length} expenses');
      }

      if (result != null) {
        if (kDebugMode) {
          print('🔧 AddExpenseScreen returned success');
        }
      } else {
        if (kDebugMode) {
          print(
              '🔧 AddExpenseScreen returned null, but expense was created anyway');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('🔧 Error in fixed add expense flow: $e');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error adding expense: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    if (kDebugMode) {
      print('🔧 === END FIXED ADD EXPENSE FLOW ===');
    }
  }

// ALSO: Add this method to directly create an expense without UI navigation

// Add this debug button to test direct creation

  void _settleDebt() async {
    if (_friend == null || _currentUserId == null ||
        _friendBalance.abs() <= 0.01) return;

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


// Add this method to check notification system vs group system

// Add this button to your friend detail screen UI temporarily

  Future<bool?> _showSettlementDialog() async {
    bool friendOwesUser = _friendBalance > 0.01;
    String balanceText = friendOwesUser
        ? 'owes you ${NumberFormatter.formatCurrency(_friendBalance)}'
        : 'you owe ${NumberFormatter.formatCurrency(-_friendBalance)}';

    return showDialog<bool>(
      context: context,
      builder: (context) =>
          AlertDialog(
            title: Text('Settle Debt with ${_friend!.name}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_friend!.name} $balanceText'),
                const SizedBox(height: 16),
                Text(
                  friendOwesUser
                      ? 'Mark that ${_friend!
                      .name} has paid you ${NumberFormatter.formatCurrency(
                      _friendBalance.abs())}?'
                      : 'Mark that you have paid ${_friend!
                      .name} ${NumberFormatter.formatCurrency(
                      _friendBalance.abs())}?',
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
        color: Theme
            .of(context)
            .primaryColor,
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
                  foregroundColor: Theme
                      .of(context)
                      .primaryColor,
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

              return FutureBuilder<GroupModel?>(
                future: _getExpenseGroupCached(expense),
                builder: (context, groupSnapshot) {
                  String groupDisplayName = 'Loading...';
                  if (groupSnapshot.hasData && groupSnapshot.data != null) {
                    groupDisplayName = _getGroupDisplayName(groupSnapshot.data!);
                  } else if (groupSnapshot.hasError ||
                      (groupSnapshot.connectionState == ConnectionState.done &&
                          groupSnapshot.data == null)) {
                    groupDisplayName = 'Unknown group';
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
                          // Group information - new addition
                          if (groupSnapshot.connectionState != ConnectionState.waiting)
                            Row(
                              children: [
                                Icon(
                                  groupDisplayName == 'Friend expense'
                                      ? Icons.person
                                      : Icons.group,
                                  size: 12,
                                  color: isSettledForUser
                                      ? Colors.grey.shade400
                                      : Colors.grey.shade500,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  groupDisplayName,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isSettledForUser
                                        ? Colors.grey.shade400
                                        : Colors.grey.shade500,
                                    fontWeight: FontWeight.w500,
                                    decoration: isSettledForUser ? TextDecoration.lineThrough : null,
                                  ),
                                ),
                              ],
                            ),
                          const SizedBox(height: 2),
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
                      onTap: () async {
                        // Get required data
                        GroupModel? group = await _getExpenseGroup(expense);
                        UserModel? currentUser = await _getCurrentUser();

                        if (group == null || currentUser == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Error loading expense details'),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }

                        final result = await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ExpenseDetailScreen(
                              expense: expense,
                              group: group,
                              members: [currentUser, _friend!],
                            ),
                          ),
                        );

                        // Refresh if expense was edited/deleted
                        if (result == true) {
                          _refresh();
                        }
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  // Add this method to cache group information for better performance
  Map<String, GroupModel> _groupCache = {};

  Future<GroupModel?> _getExpenseGroupCached(ExpenseModel expense) async {
    // Check cache first
    if (_groupCache.containsKey(expense.groupId)) {
      return _groupCache[expense.groupId];
    }

    // Fetch from database if not in cache
    try {
      GroupModel? group = await _databaseService.getGroup(expense.groupId);
      if (group != null) {
        _groupCache[expense.groupId] = group;
      }
      return group;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting expense group: $e');
      }
      return null;
    }
  }

// Helper method to determine group display name
  String _getGroupDisplayName(GroupModel group) {
    if (group.metadata?['isFriendGroup'] == true ||
        (group.memberIds.length == 2 && group.name.contains('&'))) {
      return 'Friend expense';
    }
    return group.name;
  }

  // Get the group where this expense belongs
  Future<GroupModel?> _getExpenseGroup(ExpenseModel expense) async {
    if (_currentUserId == null || _friend == null) return null;

    try {
      // Get the group by expense's groupId
      return await _databaseService.getGroup(expense.groupId);
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting expense group: $e');
      }
      return null;
    }
  }

// Get current user model
  Future<UserModel?> _getCurrentUser() async {
    if (_currentUserId == null) return null;
    try {
      return await _databaseService.getUser(_currentUserId!);
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting current user: $e');
      }
      return null;
    }
  }

  Future<String?> _getFriendGroupId() async {
    if (_currentUserId == null || _friend == null) return null;

    try {
      List<GroupModel> userGroups = await _databaseService.getAllUserGroups(
          _currentUserId!);
      List<GroupModel> sharedGroups = userGroups
          .where((group) => group.memberIds.contains(_friend!.id))
          .toList();

      // Find the friend group (contains & symbol)
      for (GroupModel group in sharedGroups) {
        if (group.name.contains('&')) {
          return group.id;
        }
      }

      // Fallback to first shared group if no & group found
      return sharedGroups.isNotEmpty ? sharedGroups.first.id : null;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting friend group ID: $e');
      }
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Loading...'),
          backgroundColor: Theme
              .of(context)
              .primaryColor,
          foregroundColor: Colors.white,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_friend == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Friend Not Found'),
          backgroundColor: Theme
              .of(context)
              .primaryColor,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: Text('Friend not found'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme
          .of(context)
          .scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(_friend!.name),
        backgroundColor: Theme
            .of(context)
            .primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // Activity Log Button
          FutureBuilder<String?>(
            future: _getFriendGroupId(), // Fixed: added underscore
            builder: (context, snapshot) {
              if (!snapshot.hasData)
                return const SizedBox.shrink(); // Fixed: added const

              return StreamBuilder<int>(
                stream: _databaseService
                    .streamUnreadActivityCount( // Fixed: added underscore
                    _currentUserId ?? '', // Fixed: added underscore
                    snapshot.data!
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
                      if (_currentUserId != null &&
                          snapshot.hasData) { // Fixed: added underscore
                        await _databaseService
                            .updateLastSeenActivity( // Fixed: added underscore
                            _currentUserId!,
                            snapshot.data! // Fixed: added underscore
                        );

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                ActivityLogScreen(groupId: snapshot.data!),
                          ),
                        );
                      }
                    },
                  );
                },
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          _buildBalanceHeader(), // Fixed: added underscore
          Expanded(
            child: _buildExpensesTab(), // Fixed: added underscore
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton( // Don't forget to add this back
        onPressed: _addExpense,
        backgroundColor: Theme
            .of(context)
            .primaryColor,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
