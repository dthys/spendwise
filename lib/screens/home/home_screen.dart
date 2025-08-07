import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../dialogs/add_friend_dialog.dart';
import '../../dialogs/join_group_dialog.dart';
import '../../friends/friend_detail_screen.dart';
import '../../insights/smart_insights_screen.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../services/theme_service.dart';
import '../../models/group_model.dart';
import '../../models/user_model.dart';
import '../../models/friend_balance_model.dart';
import '../../utils/number_formatter.dart';
import '../groups/group_detail_screen.dart';
import '../groups/groups_screen.dart';
import '../home/settings_screen.dart';
import '../search/search_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

// Helper class to store group with its unread count
class GroupWithUnreadCount {
  final GroupModel group;
  final int unreadCount;

  GroupWithUnreadCount({required this.group, required this.unreadCount});
}

class _HomeScreenState extends State<HomeScreen> with AutomaticKeepAliveClientMixin {
  final DatabaseService _databaseService = DatabaseService();
  Timer? _refreshTimer;
  late StreamController<double> _balanceController;
  late String _currentUserId;
  String? _userName;

  // Cache to prevent unnecessary rebuilds
  double? _cachedBalance;
  DateTime? _lastBalanceUpdate;
  Map<String, int> _unreadCountsCache = {};
  DateTime? _lastUnreadCountsUpdate;

  // Toggle between Groups and Friends view
  bool _showingFriends = false;

  // Loading state to prevent flash
  bool _isInitializing = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _balanceController = StreamController<double>.broadcast();
    _initializeHomeScreen();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only refresh if not already initializing
    if (!_isInitializing) {
      final authService = Provider.of<AuthService>(context, listen: false);
      if (authService.currentUser != null && _currentUserId != authService.currentUser!.uid) {
        _currentUserId = authService.currentUser!.uid;
        _refreshBalance();
        _loadUserName();
      }
    }
  }

  // Consolidated initialization method
  Future<void> _initializeHomeScreen() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      if (authService.currentUser != null) {
        _currentUserId = authService.currentUser!.uid;

        // Load everything in parallel
        await Future.wait([
          _loadUserName(),
          _refreshBalance(forceRefresh: true),
        ]);
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error initializing home screen: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _balanceController.close();
    super.dispose();
  }

  Future<void> _loadUserName() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      if (authService.currentUser != null) {
        UserModel? user = await _databaseService.getUser(authService.currentUser!.uid);

        String newUserName;
        if (user != null && user.name.isNotEmpty) {
          newUserName = user.name;
          if (kDebugMode) {
            print('✅ Username loaded from database: ${user.name}');
          }
        } else if (authService.currentUser!.displayName != null && authService.currentUser!.displayName!.isNotEmpty) {
          newUserName = authService.currentUser!.displayName!;
          if (kDebugMode) {
            print('✅ Username loaded from Firebase Auth: ${authService.currentUser!.displayName}');
          }
        } else {
          String emailPrefix = authService.currentUser!.email?.split('@')[0] ?? 'User';
          newUserName = emailPrefix;
          if (kDebugMode) {
            print('✅ Username set to email prefix: $emailPrefix');
          }
        }

        // Only update state if the name actually changed
        if (_userName != newUserName && mounted) {
          setState(() {
            _userName = newUserName;
          });
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error loading username: $e');
      }
      if (mounted && _userName == null) {
        setState(() {
          _userName = 'User';
        });
      }
    }
  }

  Future<void> _refreshBalance({bool forceRefresh = false}) async {
    // Use cache if recent and not forcing refresh
    if (!forceRefresh &&
        _cachedBalance != null &&
        _lastBalanceUpdate != null &&
        DateTime.now().difference(_lastBalanceUpdate!).inSeconds < 10) {
      _balanceController.add(_cachedBalance!);
      return;
    }

    try {
      // ✅ FIX: Use getAllUserGroups instead of streamUserGroups to include friend groups in balance calculation
      List<GroupModel> groups = await _databaseService.getAllUserGroups(_currentUserId);
      double totalBalance = 0.0;

      if (kDebugMode) {
        print('🏠 === CALCULATING HOME SCREEN BALANCE ===');
        print('🏠 User has ${groups.length} total groups (including friend groups)');
      }

      for (GroupModel group in groups) {
        try {
          Map<String, double> groupBalances = await _databaseService.calculateGroupBalancesWithSettlements(group.id);
          double userBalance = groupBalances[_currentUserId] ?? 0.0;

          if (kDebugMode) {
            print('🏠 Group "${group.name}": User balance = ${NumberFormatter.formatCurrency(userBalance)}');
          }
          totalBalance += userBalance;
        } catch (e) {
          if (kDebugMode) {
            print('❌ Error calculating balance for group ${group.id}: $e');
          }
        }
      }

      if (kDebugMode) {
        print('🏠 Total balance across all groups: ${NumberFormatter.formatCurrency(totalBalance)}');
      }

      // Update cache
      _cachedBalance = totalBalance;
      _lastBalanceUpdate = DateTime.now();

      if (!_balanceController.isClosed) {
        _balanceController.add(totalBalance);
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error refreshing balance: $e');
      }
      if (!_balanceController.isClosed) {
        _balanceController.add(0.0);
      }
    }
  }

  // Open search functionality
  void _openSearch() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;

    if (user != null) {
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => SearchScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            const begin = Offset(0.0, 1.0);
            const end = Offset.zero;
            const curve = Curves.easeInOutCubic;

            var tween = Tween(begin: begin, end: end).chain(
              CurveTween(curve: curve),
            );
            var offsetAnimation = animation.drive(tween);

            var fadeAnimation = animation.drive(
              Tween(begin: 0.0, end: 1.0).chain(
                CurveTween(curve: curve),
              ),
            );

            return FadeTransition(
              opacity: fadeAnimation,
              child: SlideTransition(
                position: offsetAnimation,
                child: child,
              ),
            );
          },
          transitionDuration: const Duration(milliseconds: 350),
          reverseTransitionDuration: const Duration(milliseconds: 300),
        ),
      );
    }
  }

  // Quick search bar widget
  Widget _buildQuickSearchBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: GestureDetector(
        onTap: _openSearch,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              Icon(Icons.search, color: Colors.grey.shade600),
              const SizedBox(width: 12),
              Text(
                'Search groups and friends...',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Smooth navigation with smart refresh
  Future<void> _navigateWithTransition(Widget screen) async {
    final result = await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => screen,
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
        transitionDuration: const Duration(milliseconds: 250),
      ),
    );

    // Always refresh balance when returning (but use cache if recent)
    bool forceRefresh = (result == 'refresh' || result == true);
    _refreshBalance(forceRefresh: forceRefresh);

    if (forceRefresh) {
      _loadUserName();
    }
  }

  void _showNotificationsDialog(BuildContext context, dynamic user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.notifications, color: Colors.blue.shade500),
            const SizedBox(width: 8),
            const Text('Recent Activity'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: StreamBuilder<List<GroupModel>>(
            stream: _databaseService.streamUserGroups(user.uid),
            builder: (context, groupSnapshot) {
              if (!groupSnapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              List<GroupModel> allGroups = groupSnapshot.data!;

              if (allGroups.isEmpty) {
                return const Center(
                  child: Text('No groups yet'),
                );
              }

              // Use optimized method
              return FutureBuilder<List<GroupModel>>(
                future: _getGroupsWithUnreadNotificationsOptimized(user.uid, allGroups),
                builder: (context, filteredGroupsSnapshot) {
                  if (!filteredGroupsSnapshot.hasData) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Loading notifications...'),
                        ],
                      ),
                    );
                  }

                  List<GroupModel> groupsWithUnread = filteredGroupsSnapshot.data!;

                  if (groupsWithUnread.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.notifications_none,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'All caught up!',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'No new activity in your groups',
                            style: TextStyle(
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    itemCount: groupsWithUnread.length,
                    itemBuilder: (context, index) {
                      GroupModel group = groupsWithUnread[index];
                      // Use cached unread count instead of streaming
                      int unreadCount = _unreadCountsCache[group.id] ?? 0;

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.red.shade500,
                          child: Text(
                            group.name.substring(0, 1).toUpperCase(),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(
                          group.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '$unreadCount new activit${unreadCount == 1 ? 'y' : 'ies'}',
                          style: TextStyle(
                            color: Colors.red.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.red.shade500,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                unreadCount.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                            ),
                          ],
                        ),
                        onTap: () async {
                          Navigator.pop(context);
                          // Clear cache when navigating to force refresh next time
                          _unreadCountsCache.clear();
                          _lastUnreadCountsUpdate = null;
                          _navigateWithTransition(GroupDetailScreen(groupId: group.id));
                        },
                      );
                    },
                  );
                },
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
      ),
    );
  }

  void _clearUnreadCountsCache() {
    _unreadCountsCache.clear();
    _lastUnreadCountsUpdate = null;
  }

// Fixed helper method - replace your existing _getGroupsWithUnreadNotifications method
  Future<List<GroupModel>> _getGroupsWithUnreadNotificationsOptimized(String userId, List<GroupModel> allGroups) async {
    try {
      // Use cache if recent (less than 30 seconds old)
      if (_lastUnreadCountsUpdate != null &&
          DateTime.now().difference(_lastUnreadCountsUpdate!).inSeconds < 30 &&
          _unreadCountsCache.isNotEmpty) {

        List<GroupModel> groupsWithUnread = allGroups
            .where((group) => (_unreadCountsCache[group.id] ?? 0) > 0)
            .toList();

        // Sort by cached unread count
        groupsWithUnread.sort((a, b) {
          int aCount = _unreadCountsCache[a.id] ?? 0;
          int bCount = _unreadCountsCache[b.id] ?? 0;
          return bCount.compareTo(aCount);
        });

        if (kDebugMode) {
          print('🚀 Using cached unread counts (${groupsWithUnread.length} groups with unread)');
        }
        return groupsWithUnread;
      }

      // Batch fetch unread counts for all groups in parallel
      if (kDebugMode) {
        print('🔄 Fetching fresh unread counts for ${allGroups.length} groups...');
      }

      List<Future<MapEntry<String, int>>> futures = allGroups.map((group) async {
        try {
          int count = await _databaseService.getUnreadActivityCount(userId, group.id);
          return MapEntry(group.id, count);
        } catch (e) {
          if (kDebugMode) {
            print('❌ Error getting unread count for ${group.id}: $e');
          }
          return MapEntry(group.id, 0);
        }
      }).toList();

      // Wait for all queries to complete in parallel
      List<MapEntry<String, int>> results = await Future.wait(futures);

      // Update cache
      _unreadCountsCache.clear();
      for (var result in results) {
        _unreadCountsCache[result.key] = result.value;
      }
      _lastUnreadCountsUpdate = DateTime.now();

      // Filter and sort groups with unread notifications
      List<GroupWithUnreadCount> groupsWithCounts = [];
      for (GroupModel group in allGroups) {
        int unreadCount = _unreadCountsCache[group.id] ?? 0;
        if (unreadCount > 0) {
          groupsWithCounts.add(GroupWithUnreadCount(group: group, unreadCount: unreadCount));
        }
      }

      // Sort by unread count (highest first)
      groupsWithCounts.sort((a, b) => b.unreadCount.compareTo(a.unreadCount));

      if (kDebugMode) {
        print('✅ Fresh unread counts fetched: ${groupsWithCounts.length} groups with unread');
      }

      return groupsWithCounts.map((item) => item.group).toList();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error in optimized unread notifications: $e');
      }
      return [];
    }
  }

  Future<void> _showJoinGroupDialog() async {
    final result = await JoinGroupDialog.showJoinGroupDialog(context);

    // Check if result is not null (user didn't cancel and successfully joined)
    if (result != null) {
      // Refresh data (remove await if these methods return void)
      _refreshBalance(forceRefresh: true);
      _loadUserName();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully joined "${result.name}"!'),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: 'View',
              textColor: Colors.white,
              onPressed: () {
                _navigateWithTransition(GroupDetailScreen(groupId: result.id));
              },
            ),
          ),
        );
      }
    }
  }
  void _showFriendDetailsDialog(BuildContext context, FriendBalance friendBalance) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            CircleAvatar(
              backgroundImage: friendBalance.friend.photoUrl != null
                  ? NetworkImage(friendBalance.friend.photoUrl!)
                  : null,
              backgroundColor: friendBalance.balanceColor.withOpacity(0.2),
              child: friendBalance.friend.photoUrl == null
                  ? Text(
                friendBalance.friend.name.substring(0, 1).toUpperCase(),
                style: TextStyle(
                  color: friendBalance.balanceColor,
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
                    friendBalance.friend.name,
                    style: const TextStyle(fontSize: 18),
                  ),
                  Text(
                    friendBalance.balanceText,
                    style: TextStyle(
                      color: friendBalance.balanceColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Shared Groups (${friendBalance.sharedGroupsCount}):',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: friendBalance.sharedGroupIds.length,
                itemBuilder: (context, index) {
                  String groupId = friendBalance.sharedGroupIds[index];
                  return FutureBuilder<GroupModel?>(
                    future: _databaseService.getGroup(groupId),
                    builder: (context, snapshot) {
                      if (snapshot.hasData && snapshot.data != null) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              const Icon(Icons.group, size: 16, color: Colors.grey),
                              const SizedBox(width: 8),
                              Expanded(child: Text(snapshot.data!.name)),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _navigateWithTransition(GroupDetailScreen(groupId: groupId));
                                },
                                child: const Text('View'),
                              ),
                            ],
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  );
                },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // Build the toggle buttons
  Widget _buildToggleButtons() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(25),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (_showingFriends) {
                  setState(() {
                    _showingFriends = false;
                  });
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: !_showingFriends ? Theme.of(context).primaryColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.group,
                      color: !_showingFriends ? Colors.white : Colors.grey.shade600,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Groups',
                      style: TextStyle(
                        color: !_showingFriends ? Colors.white : Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (!_showingFriends) {
                  setState(() {
                    _showingFriends = true;
                  });
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _showingFriends ? Theme.of(context).primaryColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.people,
                      color: _showingFriends ? Colors.white : Colors.grey.shade600,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Friends',
                      style: TextStyle(
                        color: _showingFriends ? Colors.white : Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Build Friends View with loading handling
  Widget _buildFriendsView(String userId) {
    return StreamBuilder<List<FriendBalance>>(
      stream: _databaseService.streamUserFriendsWithBalances(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                const Text('Error loading friends'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => setState(() {}),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        List<FriendBalance> friends = snapshot.data ?? [];

        if (friends.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.people_outline,
                  size: 64,
                  color: Colors.grey.shade400,
                ),
                const SizedBox(height: 16),
                Text(
                  'No friends yet',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Add friends to start sharing expenses!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _addFriend,
                  icon: const Icon(Icons.person_add),
                  label: const Text('Add Friend'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            // Add Friend Button at the top
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _addFriend,
                  icon: const Icon(Icons.person_add),
                  label: const Text('Add New Friend'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: BorderSide(color: Theme.of(context).primaryColor),
                    foregroundColor: Theme.of(context).primaryColor,
                  ),
                ),
              ),
            ),

            // Friends List
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: friends.length,
                itemBuilder: (context, index) {
                  FriendBalance friendBalance = friends[index];

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      elevation: 2,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _navigateToFriendDetail(friendBalance.friend.id), // UPDATED
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundImage: friendBalance.friend.photoUrl != null
                                    ? NetworkImage(friendBalance.friend.photoUrl!)
                                    : null,
                                backgroundColor: friendBalance.balanceColor.withOpacity(0.2),
                                child: friendBalance.friend.photoUrl == null
                                    ? Text(
                                  friendBalance.friend.name.substring(0, 1).toUpperCase(),
                                  style: TextStyle(
                                    color: friendBalance.balanceColor,
                                    fontSize: 16,
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
                                      friendBalance.friend.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      friendBalance.balanceText,
                                      style: TextStyle(
                                        color: friendBalance.balanceColor,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${friendBalance.sharedGroupsCount} shared group${friendBalance.sharedGroupsCount != 1 ? 's' : ''}',
                                      style: TextStyle(
                                        color: Colors.grey.shade600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                children: [
                                  Icon(
                                    friendBalance.balanceIcon,
                                    color: friendBalance.balanceColor,
                                    size: 20,
                                  ),
                                  const SizedBox(height: 4),
                                  Icon(
                                    Icons.arrow_forward_ios,
                                    size: 14,
                                    color: Colors.grey.shade400,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

// Add these methods to your _HomeScreenState class:

  Future<void> _addFriend() async {
    final result = await AddFriendDialog.showAddFriendDialog(context);

    if (result != null) {
      // Refresh data
      _refreshBalance(forceRefresh: true);
      _loadUserName();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Friend added successfully!'),
            backgroundColor: Colors.green,
            action: SnackBarAction(
              label: 'View',
              textColor: Colors.white,
              onPressed: () {
                // Navigate to the friend detail (you'll need to extract friend ID from result)
                // This is a simplified version - you might need to adjust based on your needs
              },
            ),
          ),
        );
      }
    }
  }

  Future<void> _navigateToFriendDetail(String friendId) async {
    final result = await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => FriendDetailScreen(friendId: friendId),
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
        transitionDuration: const Duration(milliseconds: 250),
      ),
    );

    // Refresh balance when returning
    bool forceRefresh = (result == 'refresh' || result == true);
    _refreshBalance(forceRefresh: forceRefresh);

    if (forceRefresh) {
      _loadUserName();
    }
  }

  // Build Groups View with loading handling
  Widget _buildGroupsView(String userId) {
    return Column(
      children: [
        // Header with "New Group" and "Join Group" buttons
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Your Groups',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      _navigateWithTransition(const GroupsScreen());
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('New Group'),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Join Group Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _showJoinGroupDialog,
                  icon: const Icon(Icons.group_add),
                  label: const Text('Join Group with Invite Code'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    side: BorderSide(color: Theme.of(context).primaryColor),
                    foregroundColor: Theme.of(context).primaryColor,
                  ),
                ),
              ),
            ],
          ),
        ),

// Groups List
        Expanded(
          child: StreamBuilder<List<GroupModel>>(
            stream: _databaseService.streamUserGroups(userId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(),
                );
              }

              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return ClipRect(  // This will simply clip any overflow without showing the debug stripes
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.group_add,
                          size: 24,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'No groups yet',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Create or join a group!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              height: 24,
                              child: ElevatedButton(
                                onPressed: () {
                                  _navigateWithTransition(const GroupsScreen());
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue.shade500,
                                  foregroundColor: Colors.white,
                                  textStyle: const TextStyle(fontSize: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                ),
                                child: const Text('Create'),
                              ),
                            ),
                            const SizedBox(width: 3),
                            SizedBox(
                              height: 24,
                              child: OutlinedButton(
                                onPressed: _showJoinGroupDialog,
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: Theme.of(context).primaryColor),
                                  foregroundColor: Theme.of(context).primaryColor,
                                  textStyle: const TextStyle(fontSize: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                ),
                                child: const Text('Join'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }

              List<GroupModel> groups = snapshot.data!;
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: groups.length,
                itemBuilder: (context, index) {
                  GroupModel group = groups[index];
                  return Hero(
                    tag: 'group_${group.id}',
                    child: Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Theme.of(context).primaryColor,
                          child: Text(
                            group.name.substring(0, 1).toUpperCase(),
                            style: TextStyle(
                              color: Theme.of(context).primaryColor.computeLuminance() > 0.5
                                  ? Colors.black
                                  : Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                group.name,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                            // Show invite code indicator if active
                            if (group.inviteCode != null &&
                                group.inviteCodeEnabled == true &&
                                (group.inviteCodeExpiresAt == null ||
                                    group.inviteCodeExpiresAt!.isAfter(DateTime.now())))
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.link,
                                      size: 12,
                                      color: Colors.green.shade700,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      'Code',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.green.shade700,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          '${group.memberIds.length} members • ${group.currency}',
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () {
                          _navigateWithTransition(GroupDetailScreen(groupId: group.id));
                        },
                      ),
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

  // Helper method for bigger Smart Insights button
  Widget _buildBiggerRightSideButton() {
    return TextButton(
      onPressed: () {
        _navigateWithTransition(const SmartInsightsScreen());
      },
      style: TextButton.styleFrom(
        backgroundColor: Colors.white.withOpacity(0.15),
        padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        minimumSize: const Size(80, 36),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, color: Colors.white, size: 16),
          SizedBox(width: 4),
          Text(
            'Insights',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    final authService = Provider.of<AuthService>(context);
    final user = authService.currentUser;

    // Show loading screen while initializing
    if (_isInitializing || user == null) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('Spendwise'),
          backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
          foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
          elevation: 0,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Spendwise'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        elevation: 0,
        actions: [
          // Search icon
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _openSearch,
            tooltip: 'Search',
          ),

          // Notifications
          StreamBuilder<int>(
            stream: _databaseService.streamTotalUnreadActivities(user.uid),
            builder: (context, unreadSnapshot) {
              int totalUnread = unreadSnapshot.data ?? 0;

              return IconButton(
                icon: Stack(
                  children: [
                    const Icon(Icons.notifications_outlined),
                    if (totalUnread > 0)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          child: Text(
                            totalUnread > 99 ? '99+' : totalUnread.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
                onPressed: () {
                  _showNotificationsDialog(context, user);
                },
              );
            },
          ),

          // Theme toggle
          Consumer<ThemeService>(
            builder: (context, themeService, child) {
              return IconButton(
                icon: Icon(themeService.currentThemeIcon),
                onPressed: () => themeService.toggleTheme(),
                tooltip: 'Toggle theme',
              );
            },
          ),

          // Settings
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              _navigateWithTransition(SettingsScreen());
            },
            tooltip: 'Settings',
          ),
        ],
      ),
      body: Column(
        children: [
          // Balance Header
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome back,',
                  style: TextStyle(
                    color: Theme.of(context).primaryColor.computeLuminance() > 0.5
                        ? Colors.black54
                        : Colors.white70,
                    fontSize: 16,
                  ),
                ),
                Text(
                  _userName ?? user.displayName ?? user.email?.split('@')[0] ?? 'User',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),

                StreamBuilder<double>(
                  stream: _balanceController.stream,
                  initialData: _cachedBalance ?? 0.0,
                  builder: (context, balanceSnapshot) {
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const Icon(Icons.account_balance_wallet, color: Colors.white),
                          const SizedBox(width: 12),
                          // Balance info
                          Expanded(
                            flex: 1,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Your Balance',
                                  style: TextStyle(
                                    color: Colors.blue.shade100,
                                    fontSize: 14,
                                  ),
                                ),
                                FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    balanceSnapshot.hasData
                                        ? NumberFormatter.formatCurrency(balanceSnapshot.data!)
                                        : NumberFormatter.formatCurrency(0),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Text(
                                  balanceSnapshot.hasData && balanceSnapshot.data!.abs() < 0.01
                                      ? 'All settled up!'
                                      : balanceSnapshot.hasData && balanceSnapshot.data! > 0
                                      ? 'You are owed'
                                      : 'You owe',
                                  style: TextStyle(
                                    color: Colors.blue.shade100,
                                    fontSize: 12,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Smart Insights button
                          Expanded(
                            flex: 1,
                            child: _buildBiggerRightSideButton(),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // Quick Search Bar
          _buildQuickSearchBar(),

          // Toggle Buttons
          _buildToggleButtons(),

          // Content Area
          Expanded(
            child: _showingFriends
                ? _buildFriendsView(user.uid)
                : _buildGroupsView(user.uid),
          ),
        ],
      ),
    );
  }
}