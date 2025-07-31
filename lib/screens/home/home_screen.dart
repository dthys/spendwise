import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../insights/smart_insights_screen.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../services/theme_service.dart';
import '../../models/group_model.dart';
import '../../models/user_model.dart';
import '../../models/friend_balance_model.dart';
import '../groups/group_detail_screen.dart';
import '../groups/groups_screen.dart';
import '../home/settings_screen.dart';
import '../search/search_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
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

  // Toggle between Groups and Friends view
  bool _showingFriends = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _balanceController = StreamController<double>.broadcast();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authService = Provider.of<AuthService>(context, listen: false);
    if (authService.currentUser != null) {
      _currentUserId = authService.currentUser!.uid;
      _refreshBalance();
      _loadUserName();

      // Check for updates on first home screen load

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

        if (user != null && user.name.isNotEmpty) {
          setState(() {
            _userName = user.name;
          });
          if (kDebugMode) {
            print('✅ Username loaded from database: ${user.name}');
          }
        } else if (authService.currentUser!.displayName != null && authService.currentUser!.displayName!.isNotEmpty) {
          setState(() {
            _userName = authService.currentUser!.displayName;
          });
          if (kDebugMode) {
            print('✅ Username loaded from Firebase Auth: ${authService.currentUser!.displayName}');
          }
        } else {
          String emailPrefix = authService.currentUser!.email?.split('@')[0] ?? 'User';
          setState(() {
            _userName = emailPrefix;
          });
          if (kDebugMode) {
            print('✅ Username set to email prefix: $emailPrefix');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error loading username: $e');
      }
      setState(() {
        _userName = 'User';
      });
    }
  }

  Future<void> _refreshBalance({bool forceRefresh = false}) async {
    // Use cache if recent and not forcing refresh (reduce cache time to 10 seconds)
    if (!forceRefresh &&
        _cachedBalance != null &&
        _lastBalanceUpdate != null &&
        DateTime.now().difference(_lastBalanceUpdate!).inSeconds < 10) {
      _balanceController.add(_cachedBalance!);
      return;
    }

    try {
      List<GroupModel> groups = await _databaseService.streamUserGroups(_currentUserId).first;
      double totalBalance = 0.0;

      if (kDebugMode) {
        print('🏠 === CALCULATING HOME SCREEN BALANCE ===');
      }
      if (kDebugMode) {
        print('🏠 User has ${groups.length} groups');
      }

      for (GroupModel group in groups) {
        try {
          Map<String, double> groupBalances = await _databaseService.calculateGroupBalancesWithSettlements(group.id);
          double userBalance = groupBalances[_currentUserId] ?? 0.0;

          if (kDebugMode) {
            print('🏠 Group "${group.name}": User balance = €${userBalance.toStringAsFixed(2)}');
          }
          totalBalance += userBalance;
        } catch (e) {
          if (kDebugMode) {
            print('❌ Error calculating balance for group ${group.id}: $e');
          }
        }
      }

      if (kDebugMode) {
        print('🏠 Total balance across all groups: €${totalBalance.toStringAsFixed(2)}');
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
      // Option 1: Smooth transition to SearchScreen
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => SearchScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // Slide up transition
            const begin = Offset(0.0, 1.0);
            const end = Offset.zero;
            const curve = Curves.easeInOutCubic;

            var tween = Tween(begin: begin, end: end).chain(
              CurveTween(curve: curve),
            );
            var offsetAnimation = animation.drive(tween);

            // Fade transition combined with slide
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

      // Option 2: Custom SearchDelegate with smooth animation
      // _showCustomSearch(user.uid);
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
    // Force refresh only if screen explicitly requests it
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

              List<GroupModel> groups = groupSnapshot.data!;

              if (groups.isEmpty) {
                return const Center(
                  child: Text('No groups yet'),
                );
              }

              return ListView.builder(
                itemCount: groups.length,
                itemBuilder: (context, index) {
                  GroupModel group = groups[index];

                  return StreamBuilder<int>(
                    stream: _databaseService.streamUnreadActivityCount(user.uid, group.id),
                    builder: (context, unreadSnapshot) {
                      int unreadCount = unreadSnapshot.data ?? 0;

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: unreadCount > 0 ? Colors.red.shade500 : Colors.grey.shade400,
                          child: Text(
                            group.name.substring(0, 1).toUpperCase(),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(group.name),
                        subtitle: Text(
                            unreadCount > 0
                                ? '$unreadCount new activit${unreadCount == 1 ? 'y' : 'ies'}'
                                : 'No new activity'
                        ),
                        trailing: unreadCount > 0
                            ? const Icon(Icons.fiber_manual_record, color: Colors.red, size: 12)
                            : null,
                        onTap: () async {
                          Navigator.pop(context);
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
                setState(() {
                  _showingFriends = false;
                });
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
                setState(() {
                  _showingFriends = true;
                });
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

  // Build Friends View
  Widget _buildFriendsView(String userId) {
    return StreamBuilder<List<FriendBalance>>(
      stream: _databaseService.streamUserFriendsWithBalances(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
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
                  'No friends with balances yet',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Add friends to groups to see\nyour balances with them',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
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
                  onTap: () => _showFriendDetailsDialog(context, friendBalance),
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
        );
      },
    );
  }

// Build Groups View
  Widget _buildGroupsView(String userId) {
    return Column(
      children: [
        // Header with "New Group" button
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Row(
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
        ),

        // Groups List
        Expanded(
          child: StreamBuilder<List<GroupModel>>(
            stream: _databaseService.streamUserGroups(userId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (!snapshot.hasData || snapshot.data!.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.group_add,
                        size: 64,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No groups yet',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Create your first group to start\nsplitting expenses with friends!',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () {
                          _navigateWithTransition(const GroupsScreen());
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('Create Group'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade500,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
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
                        title: Text(
                          group.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
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

// Helper method for bigger Smart Insights button (stays on the right)
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
          user != null ? StreamBuilder<int>(
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
          ) : const SizedBox.shrink(),

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
      body: user == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          // Balance Header - BUTTON STAYS ON THE RIGHT BUT BIGGER
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
                          // Balance info - takes less space to give button more room
                          Expanded(
                            flex: 1, // Reduced from 3 to 2
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
                                        ? '€${balanceSnapshot.data!.toStringAsFixed(2)}'
                                        : '€0.00',
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
                          // Smart Insights button - more space allocated
                          Expanded(
                            flex: 1, // More generous space allocation
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