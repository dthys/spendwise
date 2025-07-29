import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/activity_log_model.dart';
import '../models/user_model.dart';
import '../models/group_model.dart';
import '../models/expense_model.dart';
import '../models/settlement_model.dart';
import '../services/notification_service.dart';
import '../models/friend_balance_model.dart';


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

      print('✅ Activity log added: ${activityLog.description}');

      // Send notification if currentUserId is provided
      if (currentUserId != null) {
        try {
          final notificationService = NotificationService();
          await notificationService.sendActivityNotification(activityLog, currentUserId);
          print('📱 Notification sent for activity: ${activityLog.type}');
        } catch (e) {
          print('❌ Failed to send notification: $e');
          // Don't fail the activity log if notification fails
        }
      }
    } catch (e) {
      print('❌ Error adding activity log: $e');
      throw e;
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
      print('Searching for user with email: $email'); // Debug

      QuerySnapshot query = await _users
          .where('email', isEqualTo: email)
          .limit(1)
          .get();

      print('Query returned ${query.docs.length} documents'); // Debug

      List<UserModel> users = query.docs
          .map((doc) {
        print('Found user document: ${doc.data()}'); // Debug
        return UserModel.fromMap(doc.data() as Map<String, dynamic>);
      })
          .toList();

      print('Returning ${users.length} users'); // Debug
      return users;
    } catch (e) {
      print('Error searching users: $e'); // Debug
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

      print('✅ User $userId successfully left group $groupId');
      return true;
    } catch (e) {
      print('❌ Error leaving group: $e');
      throw e;
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

      print('✅ Successfully added ${userToAdd.name} to group $groupId');
    } catch (e) {
      print('❌ Error adding member to group: $e');
      throw e;
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
      await Future.delayed(Duration(milliseconds: 500));

      // Now delete the entire group using existing method
      await deleteGroup(groupId);

      print('✅ Group $groupId successfully deleted by user $userId');
      return true;
    } catch (e) {
      print('❌ Error deleting group: $e');
      throw e;
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
      print('Error checking bank accounts: $e');
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
      print('Error getting group members: $e');
      return [];
    }
  }

  // Last Seen Methods
  Future<void> updateLastSeenActivity(String userId, String groupId) async {
    try {
      String docId = '${userId}_$groupId';
      DateTime now = DateTime.now();

      print('📝 Updating last seen activity: $docId at ${now.toIso8601String()}');

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

      print('✅ Successfully updated last seen activity for $docId');

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
      await Future.delayed(Duration(milliseconds: 100));
      await _firestore
          .collection('activity_logs')
          .doc('_trigger_${now.millisecondsSinceEpoch}')
          .delete();

    } catch (e) {
      print('❌ Error updating last seen activity: $e');
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
      print('Error getting last seen activity: $e');
      return null;
    }
  }

  // Get unread activity count for a group
  Future<int> getUnreadActivityCount(String userId, String groupId) async {
    try {
      DateTime? lastSeen = await getLastSeenActivity(userId, groupId);

      print('🔍 Checking unread activities for $userId in group $groupId');
      print('📅 Last seen: ${lastSeen?.toIso8601String() ?? 'Never'}');

      Query query = _firestore
          .collection('activity_logs')
          .where('groupId', isEqualTo: groupId);

      if (lastSeen != null) {
        query = query.where('timestamp', isGreaterThan: lastSeen.millisecondsSinceEpoch);
      }

      QuerySnapshot snapshot = await query.get();
      int count = snapshot.docs.length;

      print('📊 Found $count unread activities for group $groupId');

      return count;
    } catch (e) {
      print('❌ Error getting unread activity count: $e');
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

        print('🔔 === CALCULATING TOTAL UNREAD NOTIFICATIONS ===');
        print('🔔 User has ${groups.length} groups');

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

            print('🔔 Group "${group.name}": $groupUnreadCount unread activities');
          } catch (e) {
            print('❌ Error calculating unread for group ${group.id}: $e');
          }
        }

        print('🔔 Total unread across all groups: $totalUnread');
        return totalUnread;
      } catch (e) {
        print('❌ Error in streamTotalUnreadActivities: $e');
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
      print('🤝 === CALCULATING FRIENDS BALANCES ===');

      // Get all user's groups
      List<GroupModel> groups = await getUserGroups(userId);
      print('📊 User has ${groups.length} groups');

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

        print('💰 Group "${group.name}": User balance = €${userBalanceInGroup.toStringAsFixed(2)}');

        // Process each other member in the group
        for (String memberId in group.memberIds) {
          if (memberId == userId) continue; // Skip self

          double memberBalanceInGroup = groupBalances[memberId] ?? 0.0;

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

          print('👥 Friend ${friendDetails[memberId]?.name ?? memberId}: €${friendToUserBalance.toStringAsFixed(2)} in group "${group.name}"');
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

      print('🤝 Final friends list: ${friendsList.length} friends with balances');
      for (var friend in friendsList) {
        print('👤 ${friend.friend.name}: €${friend.balance.toStringAsFixed(2)} (${friend.sharedGroupsCount} groups)');
      }

      return friendsList;
    } catch (e) {
      print('❌ Error calculating friends balances: $e');
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

      print('🔍 Search results for "$query": ${filteredGroups.length} groups found');
      return filteredGroups;
    } catch (e) {
      print('❌ Error searching groups: $e');
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

      print('🔍 Search results for "$query": ${filteredFriends.length} friends found');
      return filteredFriends;
    } catch (e) {
      print('❌ Error searching friends: $e');
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
      print('❌ Error in combined search: $e');
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

      String lowercaseQuery = query.toLowerCase();
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

      print('🔍 Global user search for "$query": ${foundUsers.length} users found');
      return foundUsers;
    } catch (e) {
      print('❌ Error in global user search: $e');
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
      print('❌ Error getting search suggestions: $e');
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

        // Check if this expense portion is settled between these two users
        bool isSettled = settlements.any((settlement) =>
        settlement.settledExpenseIds.contains(expense.id) &&
            ((settlement.fromUserId == userId && settlement.toUserId == friendId) ||
                (settlement.fromUserId == friendId && settlement.toUserId == userId))
        );

        if (isSettled) continue; // Skip settled expenses

        // Calculate the direct relationship for this expense
        if (expense.paidBy == userId && expense.splitBetween.contains(friendId)) {
          // User paid, friend owes their share
          directBalance += expense.getAmountOwedBy(friendId);
        } else if (expense.paidBy == friendId && expense.splitBetween.contains(userId)) {
          // Friend paid, user owes their share
          directBalance -= expense.getAmountOwedBy(userId);
        }
      }

      return directBalance;
    } catch (e) {
      print('❌ Error calculating direct balance: $e');
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

      // Get user details for activity log
      UserModel? user = await getUser(expense.paidBy);
      String userName = user?.name ?? 'Unknown User';

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

      // Add activity log with notification
      await addActivityLog(
        ActivityLogModel(
          id: _firestore.collection('activity_logs').doc().id,
          groupId: expense.groupId,
          userId: expense.paidBy,
          userName: userName,
          type: ActivityType.expenseEdited,
          description: '$userName edited expense: ${expense.description}',
          metadata: {
            'expenseId': expense.id,
            'changes': changes,
            'newAmount': expense.amount,
            'newDescription': expense.description,
            'originalExpense': oldExpense?.toMap(),
            'updatedExpense': expense.toMap(),
          },
          timestamp: DateTime.now(),
        ),
        currentUserId: currentUserId,
      );

      print('✅ Expense updated and notification sent');
    } catch (e) {
      print('❌ Error updating expense: $e');
      throw e;
    }
  }

// Updated createExpense method (already correct, but for completeness)
  Future<String> createExpense(ExpenseModel expense, {String? currentUserId}) async {
    try {
      DocumentReference docRef = await _firestore.collection('expenses').add(expense.toMap());

      // Update the expense with the generated ID
      await docRef.update({'id': docRef.id});

      // Get user details for activity log
      UserModel? user = await getUser(expense.paidBy);
      String userName = user?.name ?? 'Unknown User';

      // Add activity log with notification
      await addActivityLog(
        ActivityLogModel(
          id: _firestore.collection('activity_logs').doc().id,
          groupId: expense.groupId,
          userId: expense.paidBy,
          userName: userName,
          type: ActivityType.expenseAdded,
          description: '$userName added expense: ${expense.description}',
          metadata: {
            'expenseId': docRef.id,
            'amount': expense.amount,
            'description': expense.description,
            'category': expense.category.displayName,
            'expense': expense.toMap(),
          },
          timestamp: DateTime.now(),
        ),
        currentUserId: currentUserId,
      );

      print('✅ Expense created with ID: ${docRef.id} and notification sent');
      return docRef.id; // Return the generated ID
    } catch (e) {
      print('❌ Error creating expense: $e');
      throw e;
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

      // Get user details for activity log
      UserModel? user = await getUser(expense.paidBy);
      String userName = user?.name ?? 'Unknown User';

      // Add activity log with notification
      await addActivityLog(
        ActivityLogModel(
          id: _firestore.collection('activity_logs').doc().id,
          groupId: expense.groupId,
          userId: expense.paidBy,
          userName: userName,
          type: ActivityType.expenseDeleted,
          description: '$userName deleted expense: ${expense.description}',
          metadata: {
            'expenseId': expenseId,
            'deletedAmount': expense.amount,
            'deletedDescription': expense.description,
            'deletedCategory': expense.category.displayName,
            'originalExpense': expense.toMap(),
          },
          timestamp: DateTime.now(),
        ),
        currentUserId: currentUserId,
      );

      print('✅ Expense deleted and notification sent');
    } catch (e) {
      print('❌ Error deleting expense: $e');
      throw e;
    }
  }

  // SETTLEMENT OPERATIONS

  // Create a new settlement
  Future<void> createSettlement(SettlementModel settlement) async {
    try {
      await _settlements.doc(settlement.id).set(settlement.toMap());
      print('Settlement created: ${settlement.id}');
    } catch (e) {
      print('Error creating settlement: $e');
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
      print('Error getting group settlements: $e');
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
      print('Settlement deleted: $settlementId');
    } catch (e) {
      print('Error deleting settlement: $e');
      throw Exception('Failed to delete settlement: $e');
    }
  }

  // Generate unique settlement ID
  String generateSettlementId() {
    return _settlements.doc().id;
  }

  // BALANCE CALCULATIONS

  // Calculate balances for a group (WITHOUT settlements - original method)
  Future<Map<String, double>> calculateGroupBalances(String groupId) async {
    try {
      List<ExpenseModel> expenses = await getGroupExpenses(groupId);
      Map<String, double> balances = {};

      for (ExpenseModel expense in expenses) {
        // Add amount paid by payer
        balances[expense.paidBy] = (balances[expense.paidBy] ?? 0) + expense.amount;

        // Subtract individual shares from each participant
        for (String participant in expense.splitBetween) {
          double amountOwed = expense.getAmountOwedBy(participant);
          balances[participant] = (balances[participant] ?? 0) - amountOwed;
        }
      }

      return balances;
    } catch (e) {
      throw Exception('Failed to calculate group balances: $e');
    }
  }

  // Calculate balances considering settlements (NEW method)
  Future<Map<String, double>> calculateGroupBalancesWithSettlements(String groupId) async {
    print('🧮 === CALCULATING GROUP BALANCES WITH SETTLEMENTS ===');

    try {
      // Get expenses and settlements
      List<ExpenseModel> expenses = await getGroupExpenses(groupId);
      List<SettlementModel> settlements = await getGroupSettlements(groupId);

      print('📝 Total expenses: ${expenses.length}');
      print('💰 Total settlements: ${settlements.length}');

      Map<String, double> balances = {};

      for (ExpenseModel expense in expenses) {
        // Check if this expense has any settlements
        List<SettlementModel> expenseSettlements = settlements
            .where((s) => s.settledExpenseIds.contains(expense.id))
            .toList();

        if (expenseSettlements.isEmpty) {
          // No settlements for this expense - calculate normally
          _addExpenseToBalances(balances, expense);
        } else {
          // This expense has settlements - calculate only unsettled portions
          _addUnsettledExpenseToBalances(balances, expense, expenseSettlements);
        }
      }

      print('📊 Final group balances: $balances');
      return balances;
    } catch (e) {
      print('❌ Error calculating group balances: $e');
      return {};
    }
  }

  // Helper method for normal expense calculation
  void _addExpenseToBalances(Map<String, double> balances, ExpenseModel expense) {
    // Payer gets credit
    balances[expense.paidBy] = (balances[expense.paidBy] ?? 0) + expense.amount;

    // Split participants owe their share
    for (String participant in expense.splitBetween) {
      double amountOwed = expense.getAmountOwedBy(participant);
      balances[participant] = (balances[participant] ?? 0) - amountOwed;
    }
  }

// Helper method for settled expense calculation
  void _addUnsettledExpenseToBalances(
      Map<String, double> balances,
      ExpenseModel expense,
      List<SettlementModel> expenseSettlements,
      ) {
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

    // For each participant in the expense
    for (String participant in expense.splitBetween) {
      double participantOwes = expense.getAmountOwedBy(participant);

      if (participant == payer) {
        // Payer doesn't owe themselves
        continue;
      }

      // Check if this debt has been settled
      bool isSettled = settledUserPairs.contains('$participant-$payer');

      if (!isSettled) {
        // This portion is NOT settled - include in balances
        balances[payer] = (balances[payer] ?? 0) + participantOwes;
        balances[participant] = (balances[participant] ?? 0) - participantOwes;
      } else {
        print('✅ Settled portion: $participant owes $payer €${participantOwes.toStringAsFixed(2)} for expense ${expense.id}');
      }
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