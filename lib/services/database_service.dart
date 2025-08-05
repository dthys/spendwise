import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/activity_log_model.dart';
import '../models/user_model.dart';
import '../models/group_model.dart';
import '../models/expense_model.dart';
import '../models/settlement_model.dart';
import '../screens/balances/balances_screen.dart';
import '../services/notification_service.dart';
import '../models/friend_balance_model.dart';
import 'dart:math' as math;



class DatabaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Collections
  CollectionReference get _users => _firestore.collection('users');
  CollectionReference get _groups => _firestore.collection('groups');
  CollectionReference get _expenses => _firestore.collection('expenses');
  CollectionReference get _settlements => _firestore.collection('settlements');

  // USER OPERATIONS

  // Create or update user in Firestore
  Future<void> createUser(UserModel user) async {
    try {
      await _users.doc(user.id).set(user.toMap());
    } catch (e) {
      throw Exception('Failed to create user: $e');
    }
  }

  // Updated addActivityLog method with notification support
  Future<void> addActivityLog(ActivityLogModel activityLog, {String? currentUserId}) async {
    try {
      // Add to Firestore
      await _firestore
          .collection('activity_logs')
          .doc(activityLog.id)
          .set(activityLog.toMap());

      if (kDebugMode) {
        print('✅ Activity log added: ${activityLog.description}');
      }

      // Send notification if currentUserId is provided
      if (currentUserId != null) {
        try {
          final notificationService = NotificationService();
          await notificationService.sendActivityNotification(activityLog, currentUserId);
          if (kDebugMode) {
            print('📱 Notification sent for activity: ${activityLog.type}');
          }
        } catch (e) {
          if (kDebugMode) {
            print('❌ Failed to send notification: $e');
          }
          // Don't fail the activity log if notification fails
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error adding activity log: $e');
      }
      rethrow;
    }
  }

  // Get user by ID
  Future<UserModel?> getUser(String userId) async {
    try {
      DocumentSnapshot doc = await _users.doc(userId).get();
      if (doc.exists) {
        return UserModel.fromMap(doc.data() as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to get user: $e');
    }
  }

  // Get current user
  Future<UserModel?> getCurrentUser() async {
    final user = _auth.currentUser;
    if (user != null) {
      return await getUser(user.uid);
    }
    return null;
  }

  // Update user
  Future<void> updateUser(UserModel user) async {
    try {
      await _users.doc(user.id).update(user.toMap());
    } catch (e) {
      throw Exception('Failed to update user: $e');
    }
  }

  // Search users by email
  Future<List<UserModel>> searchUsersByEmail(String email) async {
    try {
      if (kDebugMode) {
        print('Searching for user with email: $email');
      } // Debug

      QuerySnapshot query = await _users
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      if (kDebugMode) {
        print('Query returned ${query.docs.length} documents');
      } // Debug

      List<UserModel> users = query.docs
          .map((doc) {
        if (kDebugMode) {
          print('Found user document: ${doc.data()}');
        } // Debug
        return UserModel.fromMap(doc.data() as Map<String, dynamic>);
      })
          .toList();

      if (kDebugMode) {
        print('Returning ${users.length} users');
      } // Debug
      return users;
    } catch (e) {
      if (kDebugMode) {
        print('Error searching users: $e');
      } // Debug
      throw Exception('Failed to search users: $e');
    }
  }

  // GROUP OPERATIONS

  // Create group
  Future<String> createGroup(GroupModel group) async {
    try {
      DocumentReference docRef = await _groups.add(group.toMap());

      // Update group with its ID
      await docRef.update({'id': docRef.id});

      // Add group to creator's groupIds
      await addUserToGroup(docRef.id, group.createdBy);

      return docRef.id;
    } catch (e) {
      throw Exception('Failed to create group: $e');
    }
  }

  // Get group by ID
  Future<GroupModel?> getGroup(String groupId) async {
    try {
      DocumentSnapshot doc = await _groups.doc(groupId).get();
      if (doc.exists) {
        return GroupModel.fromMap(doc.data() as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to get group: $e');
    }
  }

  // Get user's groups
  Future<List<GroupModel>> getUserGroups(String userId) async {
    try {
      QuerySnapshot query = await _groups
          .where('memberIds', arrayContains: userId)
          .orderBy('createdAt', descending: true)
          .get();

      return query.docs
          .map((doc) => GroupModel.fromMap(doc.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw Exception('Failed to get user groups: $e');
    }
  }

  // Add user to group
  Future<void> addUserToGroup(String groupId, String userId) async {
    try {
      // Add user to group's memberIds
      await _groups.doc(groupId).update({
        'memberIds': FieldValue.arrayUnion([userId])
      });

      // Add group to user's groupIds
      await _users.doc(userId).update({
        'groupIds': FieldValue.arrayUnion([groupId])
      });
    } catch (e) {
      throw Exception('Failed to add user to group: $e');
    }
  }

  // Remove user from group
  Future<void> removeUserFromGroup(String groupId, String userId) async {
    try {
      // Remove user from group's memberIds
      await _groups.doc(groupId).update({
        'memberIds': FieldValue.arrayRemove([userId])
      });

      // Remove group from user's groupIds
      await _users.doc(userId).update({
        'groupIds': FieldValue.arrayRemove([groupId])
      });
    } catch (e) {
      throw Exception('Failed to remove user from group: $e');
    }
  }

  // Update group
  Future<void> updateGroup(GroupModel group) async {
    try {
      await _groups.doc(group.id).update(group.toMap());
    } catch (e) {
      throw Exception('Failed to update group: $e');
    }
  }

  // Delete group
  Future<void> deleteGroup(String groupId) async {
    try {
      // Get group to find members
      GroupModel? group = await getGroup(groupId);
      if (group != null) {
        // Remove group from all members' groupIds
        for (String memberId in group.memberIds) {
          await _users.doc(memberId).update({
            'groupIds': FieldValue.arrayRemove([groupId])
          });
        }
      }

      // Delete all expenses in the group
      QuerySnapshot expenses = await _expenses
          .where('groupId', isEqualTo: groupId)
          .get();

      for (DocumentSnapshot expense in expenses.docs) {
        await expense.reference.delete();
      }

      // Delete all settlements in the group
      QuerySnapshot settlements = await _settlements
          .where('groupId', isEqualTo: groupId)
          .get();

      for (DocumentSnapshot settlement in settlements.docs) {
        await settlement.reference.delete();
      }

      // Delete the group
      await _groups.doc(groupId).delete();
    } catch (e) {
      throw Exception('Failed to delete group: $e');
    }
  }

  // Leave a group (with safety checks) - FIXED VERSION
  Future<bool> leaveGroup(String groupId, String userId) async {
    try {
      GroupModel? group = await getGroup(groupId);
      if (group == null) {
        throw Exception('Group not found');
      }

      // Check if user is in the group
      if (!group.memberIds.contains(userId)) {
        throw Exception('User is not a member of this group');
      }

      // Safety check: Don't allow leaving if it would make group empty
      if (group.memberIds.length <= 1) {
        throw Exception('Cannot leave group - you are the last member. Delete the group instead.');
      }

      // Check if user has outstanding balances
      Map<String, double> balances = await calculateGroupBalancesWithSettlements(groupId);
      double userBalance = balances[userId] ?? 0.0;

      if (userBalance.abs() > 0.01) { // Allow for small rounding differences
        throw Exception('Cannot leave group - you have outstanding balances (€${userBalance.toStringAsFixed(2)}). Settle all debts first.');
      }

      // Get user details for activity log
      UserModel? user = await getUser(userId);
      String userName = user?.name ?? 'Unknown User';

      // Remove user from group
      await removeUserFromGroup(groupId, userId);

      // Add activity log with notification - UPDATED
      await addActivityLog(
          ActivityLogModel(
            id: _firestore.collection('activity_logs').doc().id,
            groupId: groupId,
            userId: userId,
            userName: userName,
            type: ActivityType.memberRemoved,
            description: '$userName left the group',
            metadata: {
              'action': 'left_group',
              'leftAt': DateTime.now().millisecondsSinceEpoch,
            },
            timestamp: DateTime.now(),
          ),
          currentUserId: userId, // Pass current user ID
      );

      if (kDebugMode) {
        print('✅ User $userId successfully left group $groupId');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error leaving group: $e');
      }
      rethrow;
    }
  }

  // Add member to existing group - FIXED VERSION
  Future<void> addMemberToExistingGroup(String groupId, String userEmail, {String? currentUserId}) async {
    try {
      // Find user by email
      List<UserModel> users = await searchUsersByEmail(userEmail);
      if (users.isEmpty) {
        throw Exception('No user found with email: $userEmail');
      }

      UserModel userToAdd = users.first;

      // Check if group exists
      GroupModel? group = await getGroup(groupId);
      if (group == null) {
        throw Exception('Group not found');
      }

      // Check if user is already a member
      if (group.memberIds.contains(userToAdd.id)) {
        throw Exception('User is already a member of this group');
      }

      // Add user to group
      await addUserToGroup(groupId, userToAdd.id);

      // Add activity log with notification - UPDATED
      await addActivityLog(
        ActivityLogModel(
          id: _firestore.collection('activity_logs').doc().id,
          groupId: groupId,
          userId: userToAdd.id,
          userName: userToAdd.name,
          type: ActivityType.memberAdded,
          description: '${userToAdd.name} was added to the group',
          metadata: {
            'action': 'joined_group',
            'email': userToAdd.email,
            'addedAt': DateTime.now().millisecondsSinceEpoch,
          },
          timestamp: DateTime.now(),
        ),
        currentUserId: currentUserId, // Pass current user ID
      );

      if (kDebugMode) {
        print('✅ Successfully added ${userToAdd.name} to group $groupId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error adding member to group: $e');
      }
      rethrow;
    }
  }

  // NEW: Enhanced balance calculation that respects user-specific settlements
  Map<String, double> calculateUserSpecificBalances(
      List<ExpenseModel> expenses,
      List<SettlementModel> settlements,
      String? viewingUserId,
      ) {
    if (kDebugMode) {
      print('🧮 === CALCULATING USER-SPECIFIC BALANCES ===');
      print('👤 Viewing user: $viewingUserId');
      print('📝 Total expenses: ${expenses.length}');
      print('💰 Total settlements: ${settlements.length}');
    }

    Map<String, double> balances = {};

    // Step 1: Calculate balances from expenses, considering settlement status
    for (ExpenseModel expense in expenses) {
      if (kDebugMode) {
        print('📊 Processing expense: ${expense.description}');
        print('💰 Amount: €${expense.amount}, Paid by: ${expense.paidBy}');
        print('👥 Split between: ${expense.splitBetween}');
        print('✅ Settled status: ${expense.settledByUser}');
      }

      // Payer gets credit for what they paid
      balances[expense.paidBy] = (balances[expense.paidBy] ?? 0) + expense.amount;

      // Each participant owes their share ONLY if they haven't settled it
      for (String participant in expense.splitBetween) {
        double amountOwed = expense.getAmountOwedBy(participant);

        // Check if this expense is settled for this participant
        bool isSettled = expense.isSettledForUser(participant);

        if (viewingUserId != null) {
          // For user-specific view, check if either:
          // 1. The viewing user has settled this (if they're the participant)
          // 2. The viewing user has received settlement for this (if they're the payer)
          if (participant == viewingUserId) {
            isSettled = expense.isSettledForUser(viewingUserId);
          } else if (expense.paidBy == viewingUserId) {
            isSettled = expense.isSettledForUser(participant);
          }
        }

        if (!isSettled) {
          // Normal case: participant still owes money
          balances[participant] = (balances[participant] ?? 0) - amountOwed;
          if (kDebugMode) {
            print('💸 $participant owes €${amountOwed.toStringAsFixed(2)} (not settled)');
          }
        } else {
          // FIXED: When debt is settled, reduce the payer's credit too
          balances[expense.paidBy] = (balances[expense.paidBy] ?? 0) - amountOwed;
          if (kDebugMode) {
            print('✅ $participant\'s debt of €${amountOwed.toStringAsFixed(2)} is settled - reducing ${expense.paidBy}\'s credit');
          }
        }
      }
    }

    if (kDebugMode) {
      print('📊 Final balances: $balances');
    }

    return balances;
  }

  Future<void> updateUserSettlementCheckpoint(String userId, String groupId) async {
    try {
      String docId = '${userId}_${groupId}_checkpoint';
      DateTime now = DateTime.now();

      await _firestore
          .collection('settlement_checkpoints')
          .doc(docId)
          .set({
        'userId': userId,
        'groupId': groupId,
        'fullySettledAt': now.millisecondsSinceEpoch,
        'updatedAt': now.millisecondsSinceEpoch,
      }, SetOptions(merge: true));

      if (kDebugMode) {
        print('✅ Updated settlement checkpoint for $userId in group $groupId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error updating settlement checkpoint: $e');
      }
    }
  }

  Future<DateTime?> getUserLastSettlementCheckpoint(String userId, String groupId) async {
    try {
      String docId = '${userId}_${groupId}_checkpoint';

      DocumentSnapshot doc = await _firestore
          .collection('settlement_checkpoints')
          .doc(docId)
          .get();

      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        return DateTime.fromMillisecondsSinceEpoch(data['fullySettledAt'] ?? 0);
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting settlement checkpoint: $e');
      }
      return null;
    }
  }

// 2. Add expense filtering method
  Future<List<ExpenseModel>> getFilteredExpensesForUser(
      String groupId,
      String? userId
      ) async {
    try {
      // Get all expenses
      List<ExpenseModel> allExpenses = await getGroupExpenses(groupId);

      if (userId == null) {
        return allExpenses; // Return all if no user specified
      }

      // Get user's last settlement checkpoint
      DateTime? lastCheckpoint = await getUserLastSettlementCheckpoint(userId, groupId);

      List<ExpenseModel> filteredExpenses = [];

      for (ExpenseModel expense in allExpenses) {
        bool shouldShow = true;

        // Rule 1: Hide expenses older than user's last full settlement
        if (lastCheckpoint != null && expense.date.isBefore(lastCheckpoint)) {
          shouldShow = false;
          if (kDebugMode) {
            print('🙈 Hiding expense "${expense.description}" - older than settlement checkpoint');
          }
        }

        // Rule 2: Hide expenses that are completely settled for everyone
        else if (expense.isFullySettled()) {
          shouldShow = false;
          if (kDebugMode) {
            print('🙈 Hiding expense "${expense.description}" - fully settled by everyone');
          }
        }

        // Rule 3: For expenses involving this user, hide if settled for them
        else if (expense.splitBetween.contains(userId) &&
            expense.paidBy != userId &&
            expense.isSettledForUser(userId)) {
          shouldShow = false;
          if (kDebugMode) {
            print('🙈 Hiding expense "${expense.description}" - settled for this user');
          }
        }

        if (shouldShow) {
          filteredExpenses.add(expense);
        }
      }

      if (kDebugMode) {
        print('📊 Filtered expenses: ${filteredExpenses.length}/${allExpenses.length} shown for user $userId');
      }

      return filteredExpenses;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error filtering expenses: $e');
      }
      return await getGroupExpenses(groupId); // Return all on error
    }
  }

// 3. Create a stream version for real-time updates
  Stream<List<ExpenseModel>> streamFilteredExpensesForUser(String groupId, String? userId) {
    return streamGroupExpenses(groupId).asyncMap((expenses) async {
      if (userId == null) return expenses;

      DateTime? lastCheckpoint = await getUserLastSettlementCheckpoint(userId, groupId);

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
        if (expense.splitBetween.contains(userId) &&
            expense.paidBy != userId &&
            expense.isSettledForUser(userId)) {
          return false;
        }

        return true;
      }).toList();
    });
  }

  // NEW: Process settlement and mark affected expenses as settled
  Future<void> processSettlementWithSimplifiedDebts(SettlementModel settlement) async {
    try {
      if (kDebugMode) {
        print('🔄 === PROCESSING SIMPLIFIED SETTLEMENT ===');
        print('💰 Settlement: ${settlement.fromUserId} → ${settlement.toUserId}, €${settlement.amount}');
      }

      // 1. Create the settlement record
      await createSettlement(settlement);

      // 2. Get all expenses in the group
      List<ExpenseModel> expenses = await getGroupExpenses(settlement.groupId);

      // 3. Find ALL expenses involving both users and mark them as settled
      List<ExpenseModel> expensesToUpdate = [];

      for (ExpenseModel expense in expenses) {
        bool shouldMarkAsSettled = false;
        String userToMarkAsSettled = '';

        // Case 1: Settlement payer was a debtor in this expense
        if (expense.paidBy == settlement.toUserId &&
            expense.splitBetween.contains(settlement.fromUserId) &&
            !expense.isSettledForUser(settlement.fromUserId)) {
          shouldMarkAsSettled = true;
          userToMarkAsSettled = settlement.fromUserId;
        }

        // Case 2: Settlement receiver was a debtor in this expense
        // (This handles the net settlement - when A owes B $50 but B owes A $30,
        //  settling $20 should mark both expenses as settled)
        else if (expense.paidBy == settlement.fromUserId &&
            expense.splitBetween.contains(settlement.toUserId) &&
            !expense.isSettledForUser(settlement.toUserId)) {
          shouldMarkAsSettled = true;
          userToMarkAsSettled = settlement.toUserId;
        }

        if (shouldMarkAsSettled) {
          ExpenseModel updatedExpense = expense.copyWithSettlement(userToMarkAsSettled, true);
          expensesToUpdate.add(updatedExpense);

          if (kDebugMode) {
            print('✅ Marking expense "${expense.description}" as settled for $userToMarkAsSettled');
            print('💰 Amount: €${expense.getAmountOwedBy(userToMarkAsSettled).toStringAsFixed(2)}');
          }
        }
      }

      // 4. Update all affected expenses
      for (ExpenseModel expense in expensesToUpdate) {
        await _firestore.collection('expenses').doc(expense.id).update(expense.toMap());
      }

      // 5. Add activity log
      UserModel? fromUser = await getUser(settlement.fromUserId);
      UserModel? toUser = await getUser(settlement.toUserId);

      await addActivityLog(
        ActivityLogModel(
          id: _firestore.collection('activity_logs').doc().id,
          groupId: settlement.groupId,
          userId: settlement.fromUserId,
          userName: fromUser?.name ?? 'Unknown User',
          type: ActivityType.settlement,
          description: '${fromUser?.name ?? "Unknown"} settled €${settlement.amount.toStringAsFixed(2)} with ${toUser?.name ?? "Unknown"}',
          metadata: {
            'settlementId': settlement.id,
            'fromUserId': settlement.fromUserId,
            'toUserId': settlement.toUserId,
            'amount': settlement.amount,
            'method': settlement.method.name,
            'expensesSettled': expensesToUpdate.length,
            'settlementType': 'simplified_net_settlement',
          },
          timestamp: DateTime.now(),
        ),
        currentUserId: settlement.fromUserId,
      );

      if (kDebugMode) {
        print('✅ Simplified settlement processed successfully');
        print('📊 Updated ${expensesToUpdate.length} expenses');
      }

    } catch (e) {
      if (kDebugMode) {
        print('❌ Error processing simplified settlement: $e');
      }
      rethrow;
    }
  }

  // NEW: Calculate individual debts with settlement awareness
  Map<String, List<IndividualDebt>> calculateIndividualDebtsWithSettlements(
      List<ExpenseModel> expenses,
      String? viewingUserId,
      ) {
    Map<String, Map<String, double>> memberToMemberDebts = {};

    // Get all unique member IDs from expenses
    Set<String> allMemberIds = {};
    for (ExpenseModel expense in expenses) {
      allMemberIds.add(expense.paidBy);
      allMemberIds.addAll(expense.splitBetween);
    }

    // Initialize debt matrix
    for (String memberId in allMemberIds) {
      memberToMemberDebts[memberId] = {};
      for (String otherMemberId in allMemberIds) {
        if (memberId != otherMemberId) {
          memberToMemberDebts[memberId]![otherMemberId] = 0.0;
        }
      }
    }

    // Calculate debts from expenses, considering settlement status
    for (ExpenseModel expense in expenses) {
      if (expense.splitBetween.length <= 1) continue;

      for (String participant in expense.splitBetween) {
        if (participant != expense.paidBy) {
          // Check if settled for this participant
          bool isSettled = expense.isSettledForUser(participant);

          // Apply user-specific settlement view if specified
          if (viewingUserId != null) {
            if (participant == viewingUserId) {
              isSettled = expense.isSettledForUser(viewingUserId);
            } else if (expense.paidBy == viewingUserId) {
              isSettled = expense.isSettledForUser(participant);
            }
          }

          if (!isSettled) {
            double amountOwed = expense.getAmountOwedBy(participant);
            memberToMemberDebts[participant]![expense.paidBy] =
                (memberToMemberDebts[participant]![expense.paidBy] ?? 0) + amountOwed;
          }
        }
      }
    }

    // Convert to IndividualDebt objects and filter out zero amounts
    Map<String, List<IndividualDebt>> result = {};
    for (String memberId in memberToMemberDebts.keys) {
      result[memberId] = [];
      memberToMemberDebts[memberId]!.forEach((creditorId, amount) {
        if (amount > 0.01) {
          result[memberId]!.add(IndividualDebt(
            debtorId: memberId,
            creditorId: creditorId,
            amount: amount,
          ));
        }
      });
    }

    return result;
  }

  // NEW: Calculate debts owed TO a specific member (considering settlements)
  List<IndividualDebt> calculateDebtsOwedToMember(
      String memberId,
      List<ExpenseModel> expenses,
      String? viewingUserId,
      ) {
    Map<String, double> debtsToMember = {};

    // Calculate debts from expenses where this member paid (and not settled)
    for (ExpenseModel expense in expenses) {
      if (expense.paidBy == memberId && expense.splitBetween.length > 1) {
        for (String participant in expense.splitBetween) {
          if (participant != memberId) {
            // Check if this expense is settled for this participant
            bool isSettled = expense.isSettledForUser(participant);

            // Apply user-specific view
            if (viewingUserId != null) {
              if (participant == viewingUserId) {
                isSettled = expense.isSettledForUser(viewingUserId);
              } else if (expense.paidBy == viewingUserId) {
                isSettled = expense.isSettledForUser(participant);
              }
            }

            if (!isSettled) {
              double amountOwed = expense.getAmountOwedBy(participant);
              debtsToMember[participant] = (debtsToMember[participant] ?? 0) + amountOwed;
            }
          }
        }
      }
    }

    // Convert to IndividualDebt objects
    List<IndividualDebt> result = [];
    debtsToMember.forEach((debtorId, amount) {
      if (amount > 0.01) {
        result.add(IndividualDebt(
          debtorId: debtorId,
          creditorId: memberId,
          amount: amount,
        ));
      }
    });

    return result;
  }

  // NEW: Updated method to replace the old _confirmSettlement
  Future<void> confirmSettlementWithExpenseTracking(
      SimplifiedDebt debt,
      UserModel fromUser,
      UserModel toUser,
      SettlementMethod method,
      String? notes,
      ) async {
    try {
      if (kDebugMode) {
        print('💰 === CONFIRMING SETTLEMENT ===');
        print('👤 From: ${fromUser.name} (${debt.fromUserId})');
        print('👤 To: ${toUser.name} (${debt.toUserId})');
        print('💰 Amount: €${debt.amount}');
      }

      // Create settlement record
      SettlementModel settlementModel = SettlementModel(
        id: generateSettlementId(),
        groupId: debt.groupId,
        fromUserId: debt.fromUserId,
        toUserId: debt.toUserId,
        amount: debt.amount,
        settledAt: DateTime.now(),
        method: method,
        notes: notes,
      );

      // Process the settlement with expense tracking
      await processSettlementWithSimplifiedDebts(settlementModel);

      // NEW: Check if the user is now fully settled
      Map<String, double> balances = await calculateGroupBalancesWithSettlements(debt.groupId);
      double userBalance = balances[debt.fromUserId] ?? 0.0;

      if (userBalance.abs() <= 0.01) {
        // User is fully settled - create checkpoint
        await updateUserSettlementCheckpoint(debt.fromUserId, debt.groupId);
        if (kDebugMode) {
          print('🎯 User ${debt.fromUserId} is now fully settled - checkpoint created');
        }
      }

      if (kDebugMode) {
        print('✅ Settlement confirmed and expenses updated');
      }

    } catch (e) {
      if (kDebugMode) {
        print('❌ Error confirming settlement: $e');
      }
      rethrow;
    }
  }

  Future<bool> validateSettlementResult(String groupId, String userId1, String userId2) async {
    try {
      double directBalance = await _calculateDirectBalance(userId1, userId2, groupId);

      if (kDebugMode) {
        print('🔍 Validation: Direct balance between $userId1 and $userId2: €${directBalance.toStringAsFixed(2)}');
      }

      // After a settlement, the direct balance should be very close to zero
      return directBalance.abs() <= 0.01;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error validating settlement: $e');
      }
      return false;
    }
  }

  // UPDATED: Replace your existing calculateGroupBalancesWithSettlements method
  Future<Map<String, double>> calculateGroupBalancesWithSettlements(String groupId) async {
    try {
      List<ExpenseModel> expenses = await getGroupExpenses(groupId);
      List<SettlementModel> settlements = await getGroupSettlements(groupId);

      // Use the new calculation method (without viewingUserId for global view)
      return calculateUserSpecificBalances(expenses, settlements, null);
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error calculating group balances: $e');
      }
      return {};
    }
  }

  // Delete entire group (for last member or admin)
  Future<bool> deleteGroupCompletely(String groupId, String userId) async {
    try {
      GroupModel? group = await getGroup(groupId);
      if (group == null) {
        throw Exception('Group not found');
      }

      // Check if user is in the group
      if (!group.memberIds.contains(userId)) {
        throw Exception('User is not a member of this group');
      }

      // Get user details for activity log
      UserModel? user = await getUser(userId);
      String userName = user?.name ?? 'Unknown User';

      // Add final activity log before deletion with notification
      await addActivityLog(
        ActivityLogModel(
          id: _firestore.collection('activity_logs').doc().id,
          groupId: groupId,
          userId: userId,
          userName: userName,
          type: ActivityType.other,
          description: '$userName deleted the group',
          metadata: {
            'action': 'group_deleted',
            'deletedAt': DateTime.now().millisecondsSinceEpoch,
            'finalMemberCount': group.memberIds.length,
          },
          timestamp: DateTime.now(),
        ),
        currentUserId: userId, // Pass current user ID
      );

      // Wait a moment for the activity log to be written
      await Future.delayed(const Duration(milliseconds: 500));

      // Now delete the entire group using existing method
      await deleteGroup(groupId);

      if (kDebugMode) {
        print('✅ Group $groupId successfully deleted by user $userId');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error deleting group: $e');
      }
      rethrow;
    }
  }

  // Get user details for settlements
  Future<UserModel?> getUserForSettlement(String userId) async {
    return await getUser(userId);
  }

// Check if all users in group have bank accounts
  Future<Map<String, bool>> checkGroupBankAccounts(String groupId) async {
    try {
      GroupModel? group = await getGroup(groupId);
      if (group == null) return {};

      Map<String, bool> bankAccountStatus = {};

      for (String memberId in group.memberIds) {
        UserModel? user = await getUser(memberId);
        bankAccountStatus[memberId] = user?.bankAccount != null && user!.bankAccount!.isNotEmpty;
      }

      return bankAccountStatus;
    } catch (e) {
      if (kDebugMode) {
        print('Error checking bank accounts: $e');
      }
      return {};
    }
  }

  // Check if user can leave group (for UI validation)
  Future<Map<String, dynamic>> canUserLeaveGroup(String groupId, String userId) async {
    try {
      GroupModel? group = await getGroup(groupId);
      if (group == null) {
        return {'canLeave': false, 'reason': 'Group not found'};
      }

      if (!group.memberIds.contains(userId)) {
        return {'canLeave': false, 'reason': 'You are not a member of this group'};
      }

      // Check if this is the last member
      if (group.memberIds.length <= 1) {
        return {
          'canLeave': false,
          'reason': 'You are the last member.',
          'isLastMember': true,
          'canDelete': true,
        };
      }

      Map<String, double> balances = await calculateGroupBalancesWithSettlements(groupId);
      double userBalance = balances[userId] ?? 0.0;

      if (userBalance.abs() > 0.01) {
        return {
          'canLeave': false,
          'reason': 'You have outstanding balances (€${userBalance.toStringAsFixed(2)}). Settle all debts first.',
          'balance': userBalance,
          'isLastMember': false,
        };
      }

      return {
        'canLeave': true,
        'reason': 'You can leave this group',
        'isLastMember': false,
      };
    } catch (e) {
      return {'canLeave': false, 'reason': 'Error checking group status: $e'};
    }
  }

  // Get group members with details (useful for member management)
  Future<List<UserModel>> getGroupMembers(String groupId) async {
    try {
      GroupModel? group = await getGroup(groupId);
      if (group == null) {
        return [];
      }

      List<UserModel> members = [];
      for (String memberId in group.memberIds) {
        UserModel? member = await getUser(memberId);
        if (member != null) {
          members.add(member);
        }
      }

      return members;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting group members: $e');
      }
      return [];
    }
  }

  // Last Seen Methods
  Future<void> updateLastSeenActivity(String userId, String groupId) async {
    try {
      String docId = '${userId}_$groupId';
      DateTime now = DateTime.now();

      if (kDebugMode) {
        print('📝 Updating last seen activity: $docId at ${now.toIso8601String()}');
      }

      await _firestore
          .collection('last_seen_activities')
          .doc(docId)
          .set({
        'id': docId,
        'userId': userId,
        'groupId': groupId,
        'lastSeenActivityTime': now.millisecondsSinceEpoch,
        'updatedAt': now.millisecondsSinceEpoch,
        // Add a trigger field that changes to force stream updates
        'triggerUpdate': now.millisecondsSinceEpoch,
      }, SetOptions(merge: true));

      if (kDebugMode) {
        print('✅ Successfully updated last seen activity for $docId');
      }

      // IMPORTANT: Add a small artificial activity log entry to trigger the stream
      // This won't be visible to users but will trigger the notification stream
      await _firestore
          .collection('activity_logs')
          .doc('_trigger_${now.millisecondsSinceEpoch}')
          .set({
        'id': '_trigger_${now.millisecondsSinceEpoch}',
        'groupId': 'SYSTEM_TRIGGER',
        'userId': 'SYSTEM',
        'userName': 'System',
        'type': 'system_trigger',
        'description': 'Notification refresh trigger',
        'timestamp': now.millisecondsSinceEpoch,
        'isSystemTrigger': true,
      });

      // Delete the trigger document immediately
      await Future.delayed(const Duration(milliseconds: 100));
      await _firestore
          .collection('activity_logs')
          .doc('_trigger_${now.millisecondsSinceEpoch}')
          .delete();

    } catch (e) {
      if (kDebugMode) {
        print('❌ Error updating last seen activity: $e');
      }
    }
  }

  Future<DateTime?> getLastSeenActivity(String userId, String groupId) async {
    try {
      String docId = '${userId}_$groupId';

      DocumentSnapshot doc = await _firestore
          .collection('last_seen_activities')
          .doc(docId)
          .get();

      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        return DateTime.fromMillisecondsSinceEpoch(data['lastSeenActivityTime'] ?? 0);
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting last seen activity: $e');
      }
      return null;
    }
  }

  // Get unread activity count for a group
  Future<int> getUnreadActivityCount(String userId, String groupId) async {
    try {
      DateTime? lastSeen = await getLastSeenActivity(userId, groupId);

      if (kDebugMode) {
        print('🔍 Checking unread activities for $userId in group $groupId');
      }
      if (kDebugMode) {
        print('📅 Last seen: ${lastSeen?.toIso8601String() ?? 'Never'}');
      }

      Query query = _firestore
          .collection('activity_logs')
          .where('groupId', isEqualTo: groupId);

      if (lastSeen != null) {
        query = query.where('timestamp', isGreaterThan: lastSeen.millisecondsSinceEpoch);
      }

      QuerySnapshot snapshot = await query.get();
      int count = snapshot.docs.length;

      if (kDebugMode) {
        print('📊 Found $count unread activities for group $groupId');
      }

      return count;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting unread activity count: $e');
      }
      return 0;
    }
  }

  // Get total unread activities across all user groups
  Stream<int> streamTotalUnreadActivities(String userId) {
    return _firestore
        .collection('activity_logs')
        .snapshots()
        .asyncMap((snapshot) async {
      try {
        // Get user's groups
        List<GroupModel> groups = await getUserGroups(userId);
        int totalUnread = 0;

        if (kDebugMode) {
          print('🔔 === CALCULATING TOTAL UNREAD NOTIFICATIONS ===');
        }
        if (kDebugMode) {
          print('🔔 User has ${groups.length} groups');
        }

        for (GroupModel group in groups) {
          try {
            // Get last seen time for this group
            DateTime? lastSeen = await getLastSeenActivity(userId, group.id);

            // Count activities in this group after last seen time
            Query query = _firestore
                .collection('activity_logs')
                .where('groupId', isEqualTo: group.id);

            if (lastSeen != null) {
              query = query.where('timestamp', isGreaterThan: lastSeen.millisecondsSinceEpoch);
            }

            QuerySnapshot groupActivities = await query.get();
            int groupUnreadCount = groupActivities.docs.length;

            totalUnread += groupUnreadCount;

            if (kDebugMode) {
              print('🔔 Group "${group.name}": $groupUnreadCount unread activities');
            }
          } catch (e) {
            if (kDebugMode) {
              print('❌ Error calculating unread for group ${group.id}: $e');
            }
          }
        }

        if (kDebugMode) {
          print('🔔 Total unread across all groups: $totalUnread');
        }
        return totalUnread;
      } catch (e) {
        if (kDebugMode) {
          print('❌ Error in streamTotalUnreadActivities: $e');
        }
        return 0;
      }
    });
  }

  // Get unread count for specific group (real-time)
  Stream<int> streamUnreadActivityCount(String userId, String groupId) {
    return streamGroupActivityLogs(groupId).asyncMap((_) async {
      return await getUnreadActivityCount(userId, groupId);
    });
  }

  // EXPENSE OPERATIONS

  // Get expense by ID
  Future<ExpenseModel?> getExpense(String expenseId) async {
    try {
      DocumentSnapshot doc = await _expenses.doc(expenseId).get();
      if (doc.exists) {
        return ExpenseModel.fromMap(doc.data() as Map<String, dynamic>);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to get expense: $e');
    }
  }

  // Get group expenses
  Future<List<ExpenseModel>> getGroupExpenses(String groupId) async {
    try {
      QuerySnapshot query = await _expenses
          .where('groupId', isEqualTo: groupId)
          .orderBy('date', descending: true)
          .get();

      return query.docs
          .map((doc) => ExpenseModel.fromMap(doc.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw Exception('Failed to get group expenses: $e');
    }
  }

  Stream<List<ActivityLogModel>> streamGroupActivityLogs(String groupId) {
    return _firestore
        .collection('activity_logs')
        .where('groupId', isEqualTo: groupId)
        .orderBy('timestamp', descending: true)
        .limit(50) // Limit to last 50 activities
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return ActivityLogModel.fromMap(doc.data());
      }).toList();
    });
  }

  // Get all friends with consolidated balances across all groups
  Future<List<FriendBalance>> getUserFriendsWithBalances(String userId) async {
    try {
      if (kDebugMode) {
        print('🤝 === CALCULATING FRIENDS BALANCES ===');
      }

      // Get all user's groups
      List<GroupModel> groups = await getUserGroups(userId);
      if (kDebugMode) {
        print('📊 User has ${groups.length} groups');
      }

      // Map to store friend ID -> consolidated balance
      Map<String, double> friendBalances = {};
      // Map to store friend ID -> UserModel
      Map<String, UserModel> friendDetails = {};
      // Map to store friend ID -> list of groups shared
      Map<String, List<String>> sharedGroups = {};

      for (GroupModel group in groups) {
        // Get balances for this group
        Map<String, double> groupBalances = await calculateGroupBalancesWithSettlements(group.id);
        double userBalanceInGroup = groupBalances[userId] ?? 0.0;

        if (kDebugMode) {
          print('💰 Group "${group.name}": User balance = €${userBalanceInGroup.toStringAsFixed(2)}');
        }

        // Process each other member in the group
        for (String memberId in group.memberIds) {
          if (memberId == userId) continue; // Skip self


          // Calculate what this friend owes/is owed relative to current user
          // If user has +50 and friend has -30, friend owes user some amount
          // We need to calculate the direct relationship between these two users
          double friendToUserBalance = await _calculateDirectBalance(userId, memberId, group.id);

          // Add to consolidated balance
          friendBalances[memberId] = (friendBalances[memberId] ?? 0.0) + friendToUserBalance;

          // Store friend details if not already stored
          if (!friendDetails.containsKey(memberId)) {
            UserModel? friend = await getUser(memberId);
            if (friend != null) {
              friendDetails[memberId] = friend;
            }
          }

          // Track shared groups
          if (!sharedGroups.containsKey(memberId)) {
            sharedGroups[memberId] = [];
          }
          sharedGroups[memberId]!.add(group.id);

          if (kDebugMode) {
            print('👥 Friend ${friendDetails[memberId]?.name ?? memberId}: €${friendToUserBalance.toStringAsFixed(2)} in group "${group.name}"');
          }
        }
      }

      // Convert to FriendBalance objects
      List<FriendBalance> friendsList = [];

      for (String friendId in friendBalances.keys) {
        UserModel? friend = friendDetails[friendId];
        if (friend != null) {
          double balance = friendBalances[friendId] ?? 0.0;

          // Only include friends with non-zero balances or if you want to show all
          // Comment out the if condition below to show all friends regardless of balance
          if (balance.abs() > 0.01) {
            friendsList.add(FriendBalance(
              friend: friend,
              balance: balance,
              sharedGroupIds: sharedGroups[friendId] ?? [],
              sharedGroupsCount: sharedGroups[friendId]?.length ?? 0,
            ));
          }
        }
      }

      // Sort by balance (highest owed to you first, then what you owe)
      friendsList.sort((a, b) => b.balance.compareTo(a.balance));

      if (kDebugMode) {
        print('🤝 Final friends list: ${friendsList.length} friends with balances');
      }
      for (var friend in friendsList) {
        if (kDebugMode) {
          print('👤 ${friend.friend.name}: €${friend.balance.toStringAsFixed(2)} (${friend.sharedGroupsCount} groups)');
        }
      }

      return friendsList;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error calculating friends balances: $e');
      }
      return [];
    }
  }

  // SEARCH METHODS

  // Search groups by name or description
  Future<List<GroupModel>> searchGroups(String query, String userId) async {
    try {
      if (query.trim().isEmpty) {
        return await getUserGroups(userId);
      }

      // Get user's groups first
      List<GroupModel> userGroups = await getUserGroups(userId);

      // Filter by query
      List<GroupModel> filteredGroups = userGroups.where((group) {
        String lowercaseQuery = query.toLowerCase();
        return group.name.toLowerCase().contains(lowercaseQuery) ||
            (group.description?.toLowerCase().contains(lowercaseQuery) ?? false);
      }).toList();

      // Sort by relevance (name matches first, then description matches)
      filteredGroups.sort((a, b) {
        String lowercaseQuery = query.toLowerCase();
        bool aNameMatch = a.name.toLowerCase().contains(lowercaseQuery);
        bool bNameMatch = b.name.toLowerCase().contains(lowercaseQuery);

        if (aNameMatch && !bNameMatch) return -1;
        if (!aNameMatch && bNameMatch) return 1;

        // Both have name matches or both don't - sort alphabetically
        return a.name.compareTo(b.name);
      });

      if (kDebugMode) {
        print('🔍 Search results for "$query": ${filteredGroups.length} groups found');
      }
      return filteredGroups;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error searching groups: $e');
      }
      return [];
    }
  }

  // Search friends by name or email
  Future<List<FriendBalance>> searchFriends(String query, String userId) async {
    try {
      if (query.trim().isEmpty) {
        return await getUserFriendsWithBalances(userId);
      }

      // Get user's friends first
      List<FriendBalance> userFriends = await getUserFriendsWithBalances(userId);

      // Filter by query
      List<FriendBalance> filteredFriends = userFriends.where((friendBalance) {
        String lowercaseQuery = query.toLowerCase();
        return friendBalance.friend.name.toLowerCase().contains(lowercaseQuery) ||
            friendBalance.friend.email.toLowerCase().contains(lowercaseQuery);
      }).toList();

      // Sort by relevance (name matches first, then email matches)
      filteredFriends.sort((a, b) {
        String lowercaseQuery = query.toLowerCase();
        bool aNameMatch = a.friend.name.toLowerCase().contains(lowercaseQuery);
        bool bNameMatch = b.friend.name.toLowerCase().contains(lowercaseQuery);

        if (aNameMatch && !bNameMatch) return -1;
        if (!aNameMatch && bNameMatch) return 1;

        // Both have name matches or both don't - sort alphabetically
        return a.friend.name.compareTo(b.friend.name);
      });

      if (kDebugMode) {
        print('🔍 Search results for "$query": ${filteredFriends.length} friends found');
      }
      return filteredFriends;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error searching friends: $e');
      }
      return [];
    }
  }

  // Combined search for both groups and friends
  Future<Map<String, dynamic>> searchAll(String query, String userId) async {
    try {
      final results = await Future.wait([
        searchGroups(query, userId),
        searchFriends(query, userId),
      ]);

      return {
        'groups': results[0] as List<GroupModel>,
        'friends': results[1] as List<FriendBalance>,
        'totalResults': (results[0] as List).length + (results[1] as List).length,
      };
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error in combined search: $e');
      }
      return {
        'groups': <GroupModel>[],
        'friends': <FriendBalance>[],
        'totalResults': 0,
      };
    }
  }

  // Search for users by email or name (for adding new friends)
  Future<List<UserModel>> searchUsersGlobally(String query, String currentUserId) async {
    try {
      if (query.trim().isEmpty) return [];

      query.toLowerCase();
      List<UserModel> foundUsers = [];

      // Search by email first (exact match)
      if (query.contains('@')) {
        List<UserModel> emailResults = await searchUsersByEmail(query);
        foundUsers.addAll(emailResults);
      }

      // Search by name (partial match) - this would require a different Firestore structure
      // For now, we'll limit to email search to avoid expensive queries
      // In a production app, you might want to use Algolia or similar for text search

      // Remove current user from results
      foundUsers.removeWhere((user) => user.id == currentUserId);

      if (kDebugMode) {
        print('🔍 Global user search for "$query": ${foundUsers.length} users found');
      }
      return foundUsers;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error in global user search: $e');
      }
      return [];
    }
  }

  // Get search suggestions based on user's data
  Future<List<String>> getSearchSuggestions(String userId) async {
    try {
      List<String> suggestions = [];

      // Get user's groups
      List<GroupModel> groups = await getUserGroups(userId);
      suggestions.addAll(groups.map((group) => group.name));

      // Get user's friends
      List<FriendBalance> friends = await getUserFriendsWithBalances(userId);
      suggestions.addAll(friends.map((friend) => friend.friend.name));

      // Remove duplicates and sort
      suggestions = suggestions.toSet().toList();
      suggestions.sort();

      return suggestions.take(10).toList(); // Limit to 10 suggestions
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting search suggestions: $e');
      }
      return [];
    }
  }

  // Stream-based search for real-time results
  Stream<List<GroupModel>> streamSearchGroups(String query, String userId) {
    if (query.trim().isEmpty) {
      return streamUserGroups(userId);
    }

    return streamUserGroups(userId).map((groups) {
      String lowercaseQuery = query.toLowerCase();
      return groups.where((group) {
        return group.name.toLowerCase().contains(lowercaseQuery) ||
            (group.description?.toLowerCase().contains(lowercaseQuery) ?? false);
      }).toList();
    });
  }

  Stream<List<FriendBalance>> streamSearchFriends(String query, String userId) {
    if (query.trim().isEmpty) {
      return streamUserFriendsWithBalances(userId);
    }

    return streamUserFriendsWithBalances(userId).map((friends) {
      String lowercaseQuery = query.toLowerCase();
      return friends.where((friendBalance) {
        return friendBalance.friend.name.toLowerCase().contains(lowercaseQuery) ||
            friendBalance.friend.email.toLowerCase().contains(lowercaseQuery);
      }).toList();
    });
  }

// Helper method to calculate direct balance between two users in a specific group
  Future<double> _calculateDirectBalance(String userId, String friendId, String groupId) async {
    try {
      // Get all expenses in the group
      List<ExpenseModel> expenses = await getGroupExpenses(groupId);
      List<SettlementModel> settlements = await getGroupSettlements(groupId);

      double directBalance = 0.0;

      for (ExpenseModel expense in expenses) {
        // Check if both users are involved in this expense
        bool userInvolved = expense.paidBy == userId || expense.splitBetween.contains(userId);
        bool friendInvolved = expense.paidBy == friendId || expense.splitBetween.contains(friendId);

        if (!userInvolved || !friendInvolved) continue;

        // REMOVED: Check for settled expenses - we now use simplified approach
        // Just calculate the direct relationship for this expense
        if (expense.paidBy == userId && expense.splitBetween.contains(friendId)) {
          // User paid, friend owes their share
          directBalance += expense.getAmountOwedBy(friendId);
        } else if (expense.paidBy == friendId && expense.splitBetween.contains(userId)) {
          // Friend paid, user owes their share
          directBalance -= expense.getAmountOwedBy(userId);
        }
      }

      // Apply settlements between these two users
      for (SettlementModel settlement in settlements) {
        if ((settlement.fromUserId == userId && settlement.toUserId == friendId)) {
          directBalance += settlement.amount;
        } else if ((settlement.fromUserId == friendId && settlement.toUserId == userId)) {
          directBalance -= settlement.amount;
        }
      }

      return directBalance;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error calculating direct balance: $e');
      }
      return 0.0;
    }
  }

// Stream version for real-time updates
  Stream<List<FriendBalance>> streamUserFriendsWithBalances(String userId) {
    return streamUserGroups(userId).asyncMap((groups) async {
      return await getUserFriendsWithBalances(userId);
    });
  }

  Future<void> updateExpense(ExpenseModel expense, ExpenseModel? oldExpense, {String? currentUserId}) async {
    try {
      await _firestore
          .collection('expenses')
          .doc(expense.id)
          .update(expense.toMap());

      // ✅ FIXED: Get the CURRENT USER's details (who is updating the expense)
      UserModel? currentUser = currentUserId != null ? await getUser(currentUserId) : null;
      String currentUserName = currentUser?.name ?? 'Unknown User';

      // Get paidBy user's name for reference
      UserModel? paidByUser = await getUser(expense.paidBy);
      String paidByUserName = paidByUser?.name ?? 'Unknown User';

      // Create change list for metadata
      List<String> changes = [];
      if (oldExpense != null) {
        if (oldExpense.description != expense.description) {
          changes.add('Description: "${oldExpense.description}" → "${expense.description}"');
        }
        if (oldExpense.amount != expense.amount) {
          changes.add('Amount: €${oldExpense.amount.toStringAsFixed(2)} → €${expense.amount.toStringAsFixed(2)}');
        }
        if (oldExpense.category != expense.category) {
          changes.add('Category: ${oldExpense.category.displayName} → ${expense.category.displayName}');
        }
        if (oldExpense.paidBy != expense.paidBy) {
          UserModel? oldPayer = await getUser(oldExpense.paidBy);
          UserModel? newPayer = await getUser(expense.paidBy);
          changes.add('Paid by: ${oldPayer?.name ?? 'Unknown'} → ${newPayer?.name ?? 'Unknown'}');
        }
        if (oldExpense.splitType != expense.splitType) {
          changes.add('Split type: ${oldExpense.splitType.name} → ${expense.splitType.name}');
        }
        if (oldExpense.date != expense.date) {
          changes.add('Date: ${oldExpense.date.day}/${oldExpense.date.month}/${oldExpense.date.year} → ${expense.date.day}/${expense.date.month}/${expense.date.year}');
        }
      }

      // Create appropriate description
      String description;
      if (currentUserId == expense.paidBy) {
        description = '$currentUserName edited expense: ${expense.description}';
      } else {
        description = '$currentUserName edited expense: ${expense.description} (paid by $paidByUserName)';
      }

      // Add activity log with notification
      await addActivityLog(
        ActivityLogModel(
          id: _firestore.collection('activity_logs').doc().id,
          groupId: expense.groupId,
          userId: currentUserId ?? expense.paidBy,  // ✅ Use currentUserId, fallback to paidBy
          userName: currentUserName,                // ✅ Use current user's name
          type: ActivityType.expenseEdited,
          description: description,                 // ✅ Clear description showing who did what
          metadata: {
            'expenseId': expense.id,
            'changes': changes,
            'newAmount': expense.amount,
            'newDescription': expense.description,
            'paidBy': expense.paidBy,              // ✅ Store who actually paid
            'paidByName': paidByUserName,          // ✅ Store payer's name
            'editedBy': currentUserId,             // ✅ Store who edited the expense
            'originalExpense': oldExpense?.toMap(),
            'updatedExpense': expense.toMap(),
          },
          timestamp: DateTime.now(),
        ),
        currentUserId: currentUserId,
      );

      if (kDebugMode) {
        print('✅ Expense updated and notification sent');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error updating expense: $e');
      }
      rethrow;
    }
  }

// Updated createExpense method (already correct, but for completeness)
  Future<String> createExpense(ExpenseModel expense, {String? currentUserId}) async {
    try {
      DocumentReference docRef = await _firestore.collection('expenses').add(expense.toMap());

      // Update the expense with the generated ID
      await docRef.update({'id': docRef.id});

      // ✅ FIXED: Get the CURRENT USER's details (who is adding the expense)
      UserModel? currentUser = currentUserId != null ? await getUser(currentUserId) : null;
      String currentUserName = currentUser?.name ?? 'Unknown User';

      // ✅ FIXED: Get paidBy user's name for the description
      UserModel? paidByUser = await getUser(expense.paidBy);
      String paidByUserName = paidByUser?.name ?? 'Unknown User';

      // Create appropriate description
      String description;
      if (currentUserId == expense.paidBy) {
        // Current user paid for themselves
        description = '$currentUserName added expense: ${expense.description}';
      } else {
        // Current user added expense for someone else
        description = '$currentUserName added expense: ${expense.description} (paid by $paidByUserName)';
      }

      // Add activity log with notification
      await addActivityLog(
        ActivityLogModel(
          id: _firestore.collection('activity_logs').doc().id,
          groupId: expense.groupId,
          userId: currentUserId ?? expense.paidBy,  // ✅ Use currentUserId, fallback to paidBy
          userName: currentUserName,                // ✅ Use current user's name
          type: ActivityType.expenseAdded,
          description: description,                 // ✅ Clear description showing who did what
          metadata: {
            'expenseId': docRef.id,
            'amount': expense.amount,
            'description': expense.description,
            'category': expense.category.displayName,
            'paidBy': expense.paidBy,              // ✅ Store who actually paid in metadata
            'paidByName': paidByUserName,          // ✅ Store payer's name for reference
            'addedBy': currentUserId,              // ✅ Store who added the expense
            'expense': expense.toMap(),
          },
          timestamp: DateTime.now(),
        ),
        currentUserId: currentUserId,
      );

      if (kDebugMode) {
        print('✅ Expense created with ID: ${docRef.id} and notification sent');
      }
      return docRef.id;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error creating expense: $e');
      }
      rethrow;
    }
  }

// Updated deleteExpense method (already correct, but for completeness)
  Future<void> deleteExpense(String expenseId, {String? currentUserId}) async {
    try {
      // Get expense details before deletion
      ExpenseModel? expense = await getExpense(expenseId);
      if (expense == null) {
        throw Exception('Expense not found');
      }

      // Delete the expense
      await _firestore
          .collection('expenses')
          .doc(expenseId)
          .delete();

      // ✅ FIXED: Get the CURRENT USER's details (who is deleting the expense)
      UserModel? currentUser = currentUserId != null ? await getUser(currentUserId) : null;
      String currentUserName = currentUser?.name ?? 'Unknown User';

      // Get paidBy user's name for reference
      UserModel? paidByUser = await getUser(expense.paidBy);
      String paidByUserName = paidByUser?.name ?? 'Unknown User';

      // Create appropriate description
      String description;
      if (currentUserId == expense.paidBy) {
        description = '$currentUserName deleted expense: ${expense.description}';
      } else {
        description = '$currentUserName deleted expense: ${expense.description} (was paid by $paidByUserName)';
      }

      // Add activity log with notification
      await addActivityLog(
        ActivityLogModel(
          id: _firestore.collection('activity_logs').doc().id,
          groupId: expense.groupId,
          userId: currentUserId ?? expense.paidBy,  // ✅ Use currentUserId, fallback to paidBy
          userName: currentUserName,                // ✅ Use current user's name
          type: ActivityType.expenseDeleted,
          description: description,                 // ✅ Clear description showing who did what
          metadata: {
            'expenseId': expenseId,
            'deletedAmount': expense.amount,
            'deletedDescription': expense.description,
            'deletedCategory': expense.category.displayName,
            'paidBy': expense.paidBy,              // ✅ Store who actually paid
            'paidByName': paidByUserName,          // ✅ Store payer's name
            'deletedBy': currentUserId,            // ✅ Store who deleted the expense
            'originalExpense': expense.toMap(),
          },
          timestamp: DateTime.now(),
        ),
        currentUserId: currentUserId,
      );

      if (kDebugMode) {
        print('✅ Expense deleted and notification sent');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error deleting expense: $e');
      }
      rethrow;
    }
  }
  // SETTLEMENT OPERATIONS

  // Create a new settlement
  Future<void> createSettlement(SettlementModel settlement) async {
    try {
      await _settlements.doc(settlement.id).set(settlement.toMap());
      if (kDebugMode) {
        print('Settlement created: ${settlement.id}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error creating settlement: $e');
      }
      throw Exception('Failed to create settlement: $e');
    }
  }

  // Get settlements for a group
  Future<List<SettlementModel>> getGroupSettlements(String groupId) async {
    try {
      QuerySnapshot querySnapshot = await _settlements
          .where('groupId', isEqualTo: groupId)
          .orderBy('settledAt', descending: true)
          .get();

      return querySnapshot.docs
          .map((doc) => SettlementModel.fromMap(doc.data() as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (kDebugMode) {
        print('Error getting group settlements: $e');
      }
      return [];
    }
  }

  // Stream settlements for real-time updates
  Stream<List<SettlementModel>> streamGroupSettlements(String groupId) {
    return _settlements
        .where('groupId', isEqualTo: groupId)
        .orderBy('settledAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => SettlementModel.fromMap(doc.data() as Map<String, dynamic>))
        .toList());
  }

  // Delete a settlement (if needed)
  Future<void> deleteSettlement(String settlementId) async {
    try {
      await _settlements.doc(settlementId).delete();
      if (kDebugMode) {
        print('Settlement deleted: $settlementId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting settlement: $e');
      }
      throw Exception('Failed to delete settlement: $e');
    }
  }

  // Generate unique settlement ID
  String generateSettlementId() {
    return _settlements.doc().id;
  }

  // BALANCE CALCULATIONS


  List<SimplifiedDebt> calculateSimplifiedDebts(Map<String, double> balances) {
    if (kDebugMode) {
      print('🎯 === CALCULATING SIMPLIFIED DEBTS ===');
    }

    List<SimplifiedDebt> debts = [];

    // Separate creditors (positive balance) and debtors (negative balance)
    List<MapEntry<String, double>> creditors = [];
    List<MapEntry<String, double>> debtors = [];

    balances.forEach((userId, balance) {
      if (balance > 0.01) {
        creditors.add(MapEntry(userId, balance));
      } else if (balance < -0.01) {
        debtors.add(MapEntry(userId, -balance)); // Make positive for easier calculation
      }
    });

    if (creditors.isEmpty || debtors.isEmpty) {
      if (kDebugMode) {
        print('✅ No debts remaining');
      }
      return debts;
    }

    // Sort by amount (largest first) for optimal debt simplification
    creditors.sort((a, b) => b.value.compareTo(a.value));
    debtors.sort((a, b) => b.value.compareTo(a.value));

    if (kDebugMode) {
      print('💰 Creditors: $creditors');
      print('💸 Debtors: $debtors');
    }

    // Calculate minimal settlements using greedy algorithm
    int i = 0, j = 0;
    while (i < debtors.length && j < creditors.length) {
      String debtor = debtors[i].key;
      String creditor = creditors[j].key;
      double debtAmount = debtors[i].value;
      double creditAmount = creditors[j].value;

      double settlementAmount = math.min(debtAmount, creditAmount);

      if (settlementAmount > 0.01) {
        debts.add(SimplifiedDebt(
          fromUserId: debtor,
          toUserId: creditor,
          amount: settlementAmount, groupId: '',
        ));

        if (kDebugMode) {
          print('💡 Debt: $debtor owes $creditor €${settlementAmount.toStringAsFixed(2)}');
        }
      }

      // Update remaining amounts
      debtors[i] = MapEntry(debtor, debtAmount - settlementAmount);
      creditors[j] = MapEntry(creditor, creditAmount - settlementAmount);

      // Move to next if current is settled
      if (debtors[i].value < 0.01) i++;
      if (creditors[j].value < 0.01) j++;
    }

    if (kDebugMode) {
      print('🎯 Simplified debts: ${debts.length} settlements needed');
    }

    return debts;
  }

  Future<List<UserModel>> searchPreviousMembers(String userId, String query) async {
    try {
      if (query.trim().isEmpty) return [];

      // Get all groups where user is a member
      List<GroupModel> userGroups = await getUserGroups(userId);

      // Collect all unique member IDs from all groups
      Set<String> allMemberIds = {};
      for (GroupModel group in userGroups) {
        allMemberIds.addAll(group.memberIds);
      }

      // Remove current user from the set
      allMemberIds.remove(userId);

      // Fetch user details for all previous members
      List<UserModel> previousMembers = [];
      for (String memberId in allMemberIds) {
        UserModel? member = await getUser(memberId);
        if (member != null) {
          previousMembers.add(member);
        }
      }

      // Filter by query (name or email)
      String lowercaseQuery = query.toLowerCase();
      List<UserModel> filteredMembers = previousMembers.where((member) {
        return member.name.toLowerCase().contains(lowercaseQuery) ||
            member.email.toLowerCase().contains(lowercaseQuery);
      }).toList();

      // Sort by relevance
      filteredMembers.sort((a, b) => a.name.compareTo(b.name));

      return filteredMembers.take(5).toList(); // Return max 5 results
    } catch (e) {
      if (kDebugMode) {
        print('Error searching previous members: $e');
      }
      return [];
    }
  }

  // Get user's total balance across all groups
  Future<double> getUserTotalBalance(String userId) async {
    try {
      List<GroupModel> groups = await getUserGroups(userId);
      double totalBalance = 0;

      for (GroupModel group in groups) {
        Map<String, double> groupBalances = await calculateGroupBalancesWithSettlements(group.id);
        totalBalance += groupBalances[userId] ?? 0;
      }

      return totalBalance;
    } catch (e) {
      throw Exception('Failed to get user total balance: $e');
    }
  }

  // Generate and enable invite code for a group
  Future<String> generateInviteCode(String groupId, {
    Duration? expiresIn,
    int? maxMembers,
  }) async {
    try {
      String inviteCode = GroupModel.generateInviteCode();

      // Ensure the code is unique
      while (await _isInviteCodeExists(inviteCode)) {
        inviteCode = GroupModel.generateInviteCode();
      }

      DateTime? expiresAt;
      if (expiresIn != null) {
        expiresAt = DateTime.now().add(expiresIn);
      }

      await _groups.doc(groupId).update({
        'inviteCode': inviteCode,
        'inviteCodeEnabled': true,
        'inviteCodeExpiresAt': expiresAt?.millisecondsSinceEpoch,
        'maxMembers': maxMembers,
      });

      if (kDebugMode) {
        print('✅ Generated invite code: $inviteCode for group: $groupId');
      }

      return inviteCode;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error generating invite code: $e');
      }
      throw Exception('Failed to generate invite code: $e');
    }
  }

  // Check if invite code already exists
  Future<bool> _isInviteCodeExists(String inviteCode) async {
    try {
      QuerySnapshot query = await _groups
          .where('inviteCode', isEqualTo: inviteCode)
          .where('inviteCodeEnabled', isEqualTo: true)
          .limit(1)
          .get();

      return query.docs.isNotEmpty;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error checking invite code: $e');
      }
      return false;
    }
  }

  // Disable invite code for a group
  Future<void> disableInviteCode(String groupId) async {
    try {
      await _groups.doc(groupId).update({
        'inviteCodeEnabled': false,
      });

      if (kDebugMode) {
        print('✅ Disabled invite code for group: $groupId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error disabling invite code: $e');
      }
      throw Exception('Failed to disable invite code: $e');
    }
  }

  // Join group using invite code
  Future<GroupModel?> joinGroupWithInviteCode(String inviteCode, String userId) async {
    try {
      if (kDebugMode) {
        print('🔍 Attempting to join group with code: $inviteCode');
      }

      // Find group with this invite code
      QuerySnapshot query = await _groups
          .where('inviteCode', isEqualTo: inviteCode.toUpperCase())
          .where('inviteCodeEnabled', isEqualTo: true)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        throw Exception('Invalid or expired invite code');
      }

      DocumentSnapshot groupDoc = query.docs.first;
      GroupModel group = GroupModel.fromMap(groupDoc.data() as Map<String, dynamic>);

      // Check if code is expired
      if (group.inviteCodeExpiresAt != null &&
          group.inviteCodeExpiresAt!.isBefore(DateTime.now())) {
        throw Exception('Invite code has expired');
      }

      // Check if user is already a member
      if (group.memberIds.contains(userId)) {
        throw Exception('You are already a member of this group');
      }

      // Check if group has reached max members
      if (!group.canAcceptNewMembers) {
        throw Exception('Group has reached maximum number of members');
      }

      // Add user to group
      await addUserToGroup(group.id, userId);

      // Get user details for activity log
      UserModel? user = await getUser(userId);
      String userName = user?.name ?? 'Unknown User';

      // Add activity log
      await addActivityLog(
        ActivityLogModel(
          id: _firestore.collection('activity_logs').doc().id,
          groupId: group.id,
          userId: userId,
          userName: userName,
          type: ActivityType.memberAdded,
          description: '$userName joined using invite code',
          metadata: {
            'action': 'joined_via_invite_code',
            'inviteCode': inviteCode,
            'joinedAt': DateTime.now().millisecondsSinceEpoch,
          },
          timestamp: DateTime.now(),
        ),
        currentUserId: userId,
      );

      if (kDebugMode) {
        print('✅ User $userId successfully joined group ${group.id} via invite code');
      }

      // Return updated group
      return await getGroup(group.id);
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error joining group with invite code: $e');
      }
      rethrow;
    }
  }

  // Get group by invite code (for preview)
  Future<GroupModel?> getGroupByInviteCode(String inviteCode) async {
    try {
      QuerySnapshot query = await _groups
          .where('inviteCode', isEqualTo: inviteCode.toUpperCase())
          .where('inviteCodeEnabled', isEqualTo: true)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        return null;
      }

      GroupModel group = GroupModel.fromMap(query.docs.first.data() as Map<String, dynamic>);

      // Check if code is expired
      if (group.inviteCodeExpiresAt != null &&
          group.inviteCodeExpiresAt!.isBefore(DateTime.now())) {
        return null;
      }

      return group;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting group by invite code: $e');
      }
      return null;
    }
  }

  // Regenerate invite code
  Future<String> regenerateInviteCode(String groupId, {
    Duration? expiresIn,
    int? maxMembers,
  }) async {
    try {
      // Disable current code first
      await disableInviteCode(groupId);

      // Wait a moment to ensure Firestore consistency
      await Future.delayed(const Duration(milliseconds: 100));

      // Generate new code
      return await generateInviteCode(groupId, expiresIn: expiresIn, maxMembers: maxMembers);
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error regenerating invite code: $e');
      }
      throw Exception('Failed to regenerate invite code: $e');
    }
  }

  // Get invite code usage stats
  Future<Map<String, dynamic>> getInviteCodeStats(String groupId) async {
    try {
      // Get activity logs for invite code joins
      QuerySnapshot inviteJoins = await _firestore
          .collection('activity_logs')
          .where('groupId', isEqualTo: groupId)
          .where('type', isEqualTo: 'memberAdded')
          .where('metadata.action', isEqualTo: 'joined_via_invite_code')
          .get();

      GroupModel? group = await getGroup(groupId);

      return {
        'totalInviteJoins': inviteJoins.docs.length,
        'currentMembers': group?.memberIds.length ?? 0,
        'maxMembers': group?.maxMembers,
        'canAcceptMore': group?.canAcceptNewMembers ?? false,
        'codeActive': group?.hasActiveInviteCode ?? false,
        'expiresAt': group?.inviteCodeExpiresAt,
      };
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting invite code stats: $e');
      }
      return {
        'totalInviteJoins': 0,
        'currentMembers': 0,
        'maxMembers': null,
        'canAcceptMore': false,
        'codeActive': false,
        'expiresAt': null,
      };
    }
  }

  // REAL-TIME STREAMS

  // Stream user's groups
  Stream<List<GroupModel>> streamUserGroups(String userId) {
    return _groups
        .where('memberIds', arrayContains: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => GroupModel.fromMap(doc.data() as Map<String, dynamic>))
        .toList());
  }

  // Stream group expenses
  Stream<List<ExpenseModel>> streamGroupExpenses(String groupId) {
    return _expenses
        .where('groupId', isEqualTo: groupId)
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
        .map((doc) => ExpenseModel.fromMap(doc.data() as Map<String, dynamic>))
        .toList());
  }

  // Stream group details
  Stream<GroupModel?> streamGroup(String groupId) {
    return _groups.doc(groupId).snapshots().map((doc) {
      if (doc.exists) {
        return GroupModel.fromMap(doc.data() as Map<String, dynamic>);
      }
      return null;
    });
  }
}

class SimplifiedDebt {
  final String fromUserId;
  final String toUserId;
  final double amount;
  final String groupId; // This should already be there

  SimplifiedDebt({
    required this.fromUserId,
    required this.toUserId,
    required this.amount,
    required this.groupId, // This should already be there
  });

  @override
  String toString() {
    return 'SimplifiedDebt(from: $fromUserId, to: $toUserId, amount: €${amount.toStringAsFixed(2)}, group: $groupId)';
  }
}