import 'package:flutter/foundation.dart';
import '../models/user_model.dart';
import '../models/group_model.dart';
import '../models/expense_model.dart';
import '../models/settlement_model.dart';
import '../models/friend_balance_model.dart';
import '../services/database_service.dart';

class FriendService {
  final DatabaseService _databaseService = DatabaseService();

  // Create a virtual "friend group" - this is just a data structure, not stored in Firestore
  FriendGroup createVirtualFriendGroup(UserModel currentUser, UserModel friend) {
    return FriendGroup(
      id: _generateFriendGroupId(currentUser.id, friend.id),
      currentUserId: currentUser.id,
      friendId: friend.id,
      currentUser: currentUser,
      friend: friend,
    );
  }

  // Generate consistent friend group ID
  String _generateFriendGroupId(String userId1, String userId2) {
    List<String> sortedIds = [userId1, userId2]..sort();
    return 'friend_${sortedIds[0]}_${sortedIds[1]}';
  }

  Future<void> debugFriendExpenseFlow(String currentUserId, String friendId) async {
    if (kDebugMode) {
      print('🔍 === COMPREHENSIVE FRIEND EXPENSE DEBUG ===');
      print('🔍 Current User ID: $currentUserId');
      print('🔍 Friend ID: $friendId');

      // Step 1: Check all user groups
      print('🔍 Step 1: Getting all user groups...');
      List<GroupModel> allGroups = await _databaseService.getAllUserGroups(currentUserId);
      print('🔍 User is member of ${allGroups.length} groups:');

      for (int i = 0; i < allGroups.length; i++) {
        GroupModel group = allGroups[i];
        print('🔍   ${i + 1}. "${group.name}" (${group.id})');
        print('🔍      Members: ${group.memberIds}');
        print('🔍      Friend in group: ${group.memberIds.contains(friendId)}');
        print('🔍      Metadata: ${group.metadata}');

        // Check expenses in each group
        List<ExpenseModel> groupExpenses = await _databaseService.getGroupExpenses(group.id);
        print('🔍      Expenses: ${groupExpenses.length}');

        for (int j = 0; j < groupExpenses.length; j++) {
          ExpenseModel expense = groupExpenses[j];
          print('🔍        ${j + 1}. "${expense.description}" - €${expense.amount}');
          print('🔍           Paid by: ${expense.paidBy}');
          print('🔍           Split: ${expense.splitBetween}');
          print('🔍           Group ID: ${expense.groupId}');
          print('🔍           Date: ${expense.date}');
        }
      }

      // Step 2: Check shared groups specifically
      print('🔍 Step 2: Filtering shared groups...');
      List<GroupModel> sharedGroups = allGroups.where((group) =>
          group.memberIds.contains(friendId)).toList();
      print('🔍 Found ${sharedGroups.length} shared groups with friend');

      // Step 3: Test expense filtering
      print('🔍 Step 3: Testing expense filtering...');
      List<ExpenseModel> allSharedExpenses = [];

      for (GroupModel group in sharedGroups) {
        List<ExpenseModel> groupExpenses = await _databaseService.getGroupExpenses(group.id);
        print('🔍 Group "${group.name}": ${groupExpenses.length} total expenses');

        for (ExpenseModel expense in groupExpenses) {
          bool currentUserInvolved = expense.paidBy == currentUserId ||
              expense.splitBetween.contains(currentUserId);
          bool friendInvolved = expense.paidBy == friendId ||
              expense.splitBetween.contains(friendId);
          bool bothInvolved = currentUserInvolved && friendInvolved;

          print('🔍   Expense: "${expense.description}"');
          print('🔍     Current user involved: $currentUserInvolved');
          print('🔍     Friend involved: $friendInvolved');
          print('🔍     Both involved: $bothInvolved');

          if (bothInvolved) {
            allSharedExpenses.add(expense);
          }
        }
      }

      print('🔍 Total shared expenses: ${allSharedExpenses.length}');

      // Step 4: Check friend details
      print('🔍 Step 4: Checking friend details...');
      UserModel? friend = await _databaseService.getUser(friendId);
      print('🔍 Friend found: ${friend?.name ?? 'NOT FOUND'}');

      // Step 5: Check database service methods
      print('🔍 Step 5: Testing database service methods...');
      try {
        double balance = await _databaseService.calculateDirectBalance(
            currentUserId, friendId, sharedGroups.first.id);
        print('🔍 Direct balance: €$balance');
      } catch (e) {
        print('🔍 Error calculating balance: $e');
      }

      print('🔍 === END DEBUG ===');
    }
  }

// Also add this method to test expense creation specifically
  Future<void> debugExpenseCreation(
      String currentUserId,
      String friendId,
      ExpenseModel testExpense
      ) async {
    if (kDebugMode) {
      print('🧪 === DEBUGGING EXPENSE CREATION ===');
      print('🧪 Test expense: ${testExpense.description}');
      print('🧪 Amount: €${testExpense.amount}');
      print('🧪 Paid by: ${testExpense.paidBy}');
      print('🧪 Split between: ${testExpense.splitBetween}');
      print('🧪 Original group ID: ${testExpense.groupId}');

      // Get shared groups
      List<GroupModel> userGroups = await _databaseService.getAllUserGroups(currentUserId);
      List<GroupModel> sharedGroups = userGroups
          .where((group) => group.memberIds.contains(friendId))
          .toList();

      print('🧪 Available shared groups: ${sharedGroups.length}');
      for (var group in sharedGroups) {
        print('🧪   - ${group.name} (${group.id})');
        print('🧪     Members: ${group.memberIds}');
      }

      // Find target group
      GroupModel? targetGroup;

      if (testExpense.groupId.isNotEmpty) {
        targetGroup = sharedGroups.where((g) => g.id == testExpense.groupId).firstOrNull;
        print('🧪 Target group from expense ID: ${targetGroup?.name ?? 'NOT FOUND'}');
      }

      if (targetGroup == null && sharedGroups.isNotEmpty) {
        targetGroup = sharedGroups.first;
        print('🧪 Using first available group: ${targetGroup.name}');
      }

      if (targetGroup == null) {
        print('🧪 ❌ NO TARGET GROUP FOUND!');
        return;
      }

      // Test expense creation
      try {
        ExpenseModel finalExpense = testExpense.copyWith(groupId: targetGroup.id);
        print('🧪 Final expense group ID: ${finalExpense.groupId}');
        print('🧪 Final expense details:');
        print('🧪   Description: ${finalExpense.description}');
        print('🧪   Amount: €${finalExpense.amount}');
        print('🧪   Paid by: ${finalExpense.paidBy}');
        print('🧪   Split between: ${finalExpense.splitBetween}');
        print('🧪   Group ID: ${finalExpense.groupId}');

        String expenseId = await _databaseService.createExpense(finalExpense, currentUserId: currentUserId);
        print('🧪 ✅ Expense created with ID: $expenseId');

        // Verify it was saved
        print('🧪 Verifying expense was saved...');
        await Future.delayed(const Duration(seconds: 1)); // Give it time to save

        List<ExpenseModel> groupExpenses = await _databaseService.getGroupExpenses(targetGroup.id);
        ExpenseModel? savedExpense = groupExpenses.where((e) => e.id == expenseId).firstOrNull;

        if (savedExpense != null) {
          print('🧪 ✅ Expense verified in database: ${savedExpense.description}');
        } else {
          print('🧪 ❌ Expense NOT found in database after creation!');
          print('🧪 Group now has ${groupExpenses.length} expenses:');
          for (var exp in groupExpenses) {
            print('🧪   - ${exp.description} (${exp.id})');
          }
        }

      } catch (e) {
        print('🧪 ❌ Error creating expense: $e');
      }

      print('🧪 === END EXPENSE CREATION DEBUG ===');
    }
  }

  // ✅ FIXED: Get all expenses between two friends (from ALL shared groups)
  Future<List<ExpenseModel>> getFriendExpenses(String currentUserId, String friendId) async {
    try {
      if (kDebugMode) {
        print('🤝 Getting expenses between $currentUserId and $friendId');
      }

      // Get ALL groups where both users are members
      List<GroupModel> currentUserGroups = await _databaseService.getAllUserGroups(currentUserId);
      List<GroupModel> sharedGroups = [];

      for (GroupModel group in currentUserGroups) {
        if (group.memberIds.contains(friendId)) {
          sharedGroups.add(group);
        }
      }

      if (kDebugMode) {
        print('🤝 Found ${sharedGroups.length} shared groups');
        for (var group in sharedGroups) {
          print('   - ${group.name} (${group.id})');
        }
      }

      List<ExpenseModel> allFriendExpenses = [];

      // Get expenses from all shared groups
      for (GroupModel group in sharedGroups) {
        List<ExpenseModel> groupExpenses = await _databaseService.getGroupExpenses(group.id);

        if (kDebugMode) {
          print('🤝 Group ${group.name} has ${groupExpenses.length} expenses');
          for (var expense in groupExpenses) {
            print('     📝 ${expense.description} (${expense.id})');
            print('        - Paid by: ${expense.paidBy}');
            print('        - Split: ${expense.splitBetween}');
          }
        }

        // ✅ FIX: Filter expenses where BOTH friends are involved (either as payer or split member)
        List<ExpenseModel> relevantExpenses = groupExpenses.where((expense) {
          bool currentUserInvolved = expense.paidBy == currentUserId || expense.splitBetween.contains(currentUserId);
          bool friendInvolved = expense.paidBy == friendId || expense.splitBetween.contains(friendId);

          // ✅ CRITICAL FIX: Use AND (&&) instead of OR (||)
          // We want expenses where BOTH users are involved
          bool bothInvolved = currentUserInvolved && friendInvolved;

          if (kDebugMode) {
            print('     🔍 ${expense.description}:');
            print('        Current user ($currentUserId) involved: $currentUserInvolved');
            print('        Friend ($friendId) involved: $friendInvolved');
            print('        Both involved: $bothInvolved');
          }

          return bothInvolved;
        }).toList();

        if (kDebugMode) {
          print('🤝 Group ${group.name}: ${relevantExpenses.length} relevant expenses');
        }

        allFriendExpenses.addAll(relevantExpenses);
      }

      // Sort by date (newest first)
      allFriendExpenses.sort((a, b) => b.date.compareTo(a.date));

      if (kDebugMode) {
        print('🤝 Found ${allFriendExpenses.length} total expenses involving both friends');
        for (var expense in allFriendExpenses) {
          print('   📋 ${expense.description}: €${expense.amount} (${expense.date})');
        }
      }

      return allFriendExpenses;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting friend expenses: $e');
      }
      return [];
    }
  }

  // Calculate direct balance between two friends across ALL groups
  Future<double> getFriendBalance(String currentUserId, String friendId) async {
    try {
      // Get ALL shared groups (including friend groups)
      List<GroupModel> currentUserGroups = await _databaseService.getAllUserGroups(currentUserId);
      double totalBalance = 0.0;

      for (GroupModel group in currentUserGroups) {
        if (group.memberIds.contains(friendId)) {
          // Calculate direct balance in this group
          double groupBalance = await _databaseService.calculateDirectBalance(
              currentUserId,
              friendId,
              group.id
          );
          totalBalance += groupBalance;
        }
      }

      return totalBalance;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error calculating friend balance: $e');
      }
      return 0.0;
    }
  }

  // Add expense to friend "group" (actually adds to a real shared group or creates one)
  Future<String> addFriendExpense(
      String currentUserId,
      String friendId,
      ExpenseModel expense,
      ) async {
    try {
      if (kDebugMode) {
        print('🤝 Adding friend expense: ${expense.description}');
        print('   - Amount: €${expense.amount}');
        print('   - Paid by: ${expense.paidBy}');
        print('   - Split between: ${expense.splitBetween}');
        print('   - Target group ID from expense: ${expense.groupId}');
      }

      // Find a shared group to add the expense to (including friend groups)
      List<GroupModel> currentUserGroups = await _databaseService.getAllUserGroups(currentUserId);
      List<GroupModel> sharedGroups = currentUserGroups
          .where((group) => group.memberIds.contains(friendId))
          .toList();

      if (kDebugMode) {
        print('🤝 Found ${sharedGroups.length} shared groups:');
        for (var group in sharedGroups) {
          print('   - ${group.name} (${group.id})');
          print('     Is Friend Group: ${group.metadata?['isFriendGroup'] == true}');
          print('     Member count: ${group.memberIds.length}');
        }
      }

      GroupModel? targetGroup;

      // ✅ PRIORITY 1: If expense already has a groupId, try to use that group first
      if (expense.groupId.isNotEmpty) {
        targetGroup = sharedGroups.where((g) => g.id == expense.groupId).firstOrNull;
        if (targetGroup != null) {
          if (kDebugMode) {
            print('🎯 Using specified group: ${targetGroup.name} (${targetGroup.id})');
          }
        }
      }

      // ✅ PRIORITY 2: Look for dedicated friend groups (created for 1-on-1 expenses)
      if (targetGroup == null) {
        for (GroupModel group in sharedGroups) {
          // Check if this is a friend group
          bool isFriendGroup = group.metadata?['isFriendGroup'] == true ||
              (group.memberIds.length == 2 && group.name.contains('&'));

          if (isFriendGroup) {
            targetGroup = group;
            if (kDebugMode) {
              print('🤝 Using friend group: ${group.name} (${group.id})');
            }
            break;
          }
        }
      }

      // ✅ PRIORITY 3: Use first shared group as fallback
      if (targetGroup == null && sharedGroups.isNotEmpty) {
        targetGroup = sharedGroups.first;
        if (kDebugMode) {
          print('🤝 Using first available shared group: ${targetGroup.name} (${targetGroup.id})');
        }
      }

      // ✅ PRIORITY 4: If no shared group exists, create a new friend group
      if (targetGroup == null) {
        UserModel? currentUser = await _databaseService.getUser(currentUserId);
        UserModel? friend = await _databaseService.getUser(friendId);

        if (currentUser == null || friend == null) {
          throw Exception('Could not find user details');
        }

        GroupModel newGroup = GroupModel(
          id: '',
          name: '${currentUser.name} & ${friend.name}',
          description: 'Personal expenses',
          memberIds: [currentUserId, friendId],
          createdBy: currentUserId,
          createdAt: DateTime.now(),
          currency: 'EUR',
          metadata: {
            'isFriendGroup': true,
            'friendIds': [currentUserId, friendId],
            'createdVia': 'addExpense',
          },
        );

        String groupId = await _databaseService.createGroup(newGroup);
        await _databaseService.addUserToGroup(groupId, friendId);

        targetGroup = await _databaseService.getGroup(groupId);

        if (kDebugMode) {
          print('🤝 Created new friend group: ${targetGroup?.name} (${targetGroup?.id})');
        }
      }

      if (targetGroup == null) {
        throw Exception('Could not create or find group');
      }

      // Create expense in the target group
      ExpenseModel groupExpense = expense.copyWith(groupId: targetGroup.id);
      String expenseId = await _databaseService.createExpense(groupExpense, currentUserId: currentUserId);

      if (kDebugMode) {
        print('🤝 Successfully created expense with ID: $expenseId in group: ${targetGroup.id}');
      }

      return expenseId;

    } catch (e) {
      if (kDebugMode) {
        print('❌ Error adding friend expense: $e');
      }
      rethrow;
    }
  }

// Settle debt between friends (across ALL groups)
  Future<void> settleFriendDebt(
      String currentUserId,
      String friendId,
      double totalAmount,
      SettlementMethod method,
      String? notes,
      ) async {
    try {
      if (kDebugMode) {
        print('💰 === SETTLING FRIEND DEBT ACROSS ALL GROUPS ===');
        print('💰 Between: $currentUserId and $friendId');
        print('💰 Total amount to settle: €${totalAmount.toStringAsFixed(2)}');
      }

      // Get ALL shared groups
      List<GroupModel> currentUserGroups = await _databaseService.getAllUserGroups(currentUserId);
      List<GroupModel> sharedGroups = currentUserGroups
          .where((group) => group.memberIds.contains(friendId))
          .toList();

      if (sharedGroups.isEmpty) {
        throw Exception('No shared groups found');
      }

      // Get friend and current user details for activity log
      UserModel? friend = await _databaseService.getUser(friendId);
      UserModel? currentUser = await _databaseService.getUser(currentUserId);

      if (friend == null || currentUser == null) {
        throw Exception('Could not find user details');
      }

      // ✅ NEW STRATEGY: Get current balances in each group and settle each one individually
      for (GroupModel group in sharedGroups) {
        double groupBalance = await _databaseService.calculateDirectBalance(
            currentUserId, friendId, group.id);

        if (kDebugMode) {
          print('💰 Group "${group.name}" (${group.id}): €${groupBalance.toStringAsFixed(2)}');
        }

        // Skip groups that are already settled
        if (groupBalance.abs() <= 0.01) {
          if (kDebugMode) {
            print('💰 ✅ Group "${group.name}" already settled, skipping');
          }
          continue;
        }

        // ✅ CRITICAL FIX: Create settlement to zero out THIS group's balance
        String fromUserId, toUserId;
        double settlementAmount = groupBalance.abs();

        if (groupBalance > 0) {
          // Positive balance means friend owes current user
          fromUserId = friendId;
          toUserId = currentUserId;
        } else {
          // Negative balance means current user owes friend
          fromUserId = currentUserId;
          toUserId = friendId;
        }

        // ✅ FIX: Create better settlement notes that reflect who performed the action
        String settlementNotes;
        if (groupBalance > 0) {
          // Friend owed current user, so current user is marking it as paid
          settlementNotes = notes ?? '${currentUser.name} marked payment received from ${friend.name} via friend view';
        } else {
          // Current user owed friend, so current user is marking their payment
          settlementNotes = notes ?? '${currentUser.name} marked payment made to ${friend.name} via friend view';
        }

        SettlementModel settlement = SettlementModel(
          id: _databaseService.generateSettlementId(),
          groupId: group.id,
          fromUserId: fromUserId,
          toUserId: toUserId,
          amount: settlementAmount,
          settledAt: DateTime.now(),
          method: method,
          notes: settlementNotes, // ✅ Fixed notes
        );

        if (kDebugMode) {
          print('💰 Creating settlement in group "${group.name}":');
          print('💰   From: $fromUserId');
          print('💰   To: $toUserId');
          print('💰   Amount: €${settlementAmount.toStringAsFixed(2)}');
          print('💰   Group ID: ${group.id}');
          print('💰   Notes: $settlementNotes');
        }

        // ✅ CRITICAL: Pass currentUserId as the user who performed the action
        await _databaseService.processSettlementWithSimplifiedDebts(
          settlement,
          performedByUserId: currentUserId,
        );

        if (kDebugMode) {
          print('💰 ✅ Settled €${settlementAmount.toStringAsFixed(2)} in group "${group.name}"');

          // Verify the settlement worked
          double newBalance = await _databaseService.calculateDirectBalance(
              currentUserId, friendId, group.id);
          print('💰 📊 New balance in "${group.name}": €${newBalance.toStringAsFixed(2)}');
        }
      }

      if (kDebugMode) {
        // Verify total balance is now zero
        double newTotalBalance = await getFriendBalance(currentUserId, friendId);
        print('💰 📊 Final total balance: €${newTotalBalance.toStringAsFixed(2)}');
        print('💰 === END SETTLEMENT ===');
      }

    } catch (e) {
      if (kDebugMode) {
        print('❌ Error settling friend debt: $e');
      }
      rethrow;
    }
  }

  // Get friend from existing friends list
  Future<UserModel?> getFriendFromBalance(String currentUserId, String friendId) async {
    try {
      List<FriendBalance> friends = await _databaseService.getUserFriendsWithBalances(currentUserId);
      FriendBalance? friendBalance = friends
          .where((fb) => fb.friend.id == friendId)
          .firstOrNull;

      return friendBalance?.friend;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting friend: $e');
      }
      return null;
    }
  }

  // Create friend relationship (by adding to a group together)
  Future<GroupModel> createFriendRelationship(String currentUserId, String friendEmail) async {
    try {
      // Find friend by email
      List<UserModel> users = await _databaseService.searchUsersByEmail(friendEmail);
      if (users.isEmpty) {
        throw Exception('No user found with email: $friendEmail');
      }

      UserModel friend = users.first;
      UserModel? currentUser = await _databaseService.getUser(currentUserId);

      if (currentUser == null) {
        throw Exception('Current user not found');
      }

      // Create a personal group for these two users
      GroupModel friendGroup = GroupModel(
        id: '',
        name: '${currentUser.name} & ${friend.name}',
        description: 'Personal expenses',
        memberIds: [currentUserId, friend.id],
        createdBy: currentUserId,
        createdAt: DateTime.now(),
        currency: 'EUR',
        metadata: {
          'isFriendGroup': true,
          'friendIds': [currentUserId, friend.id],
          'createdVia': 'addFriend',
        },
      );

      String groupId = await _databaseService.createGroup(friendGroup);
      await _databaseService.addUserToGroup(groupId, friend.id);

      GroupModel? createdGroup = await _databaseService.getGroup(groupId);
      if (createdGroup == null) {
        throw Exception('Failed to create friend group');
      }

      return createdGroup;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error creating friend relationship: $e');
      }
      rethrow;
    }
  }
}



// Simple data class for virtual friend group
class FriendGroup {
  final String id;
  final String currentUserId;
  final String friendId;
  final UserModel currentUser;
  final UserModel friend;

  FriendGroup({
    required this.id,
    required this.currentUserId,
    required this.friendId,
    required this.currentUser,
    required this.friend,
  });

  String get name => '${currentUser.name} & ${friend.name}';

  List<String> get memberIds => [currentUserId, friendId];

  // Convert to a GroupModel-like interface for UI compatibility
  GroupModel toGroupModel() {
    return GroupModel(
      id: id,
      name: name,
      description: 'Personal expenses',
      memberIds: memberIds,
      createdBy: currentUserId,
      createdAt: DateTime.now(),
      currency: 'EUR',
    );
  }
}