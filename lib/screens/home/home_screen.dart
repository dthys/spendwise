import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../services/theme_service.dart';
import '../../models/group_model.dart';
import '../../models/user_model.dart';
import '../groups/group_detail_screen.dart';
import '../groups/groups_screen.dart';
import '../home/settings_screen.dart';

class HomeScreen extends StatefulWidget {
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
          print('✅ Username loaded from database: ${user.name}');
        } else if (authService.currentUser!.displayName != null && authService.currentUser!.displayName!.isNotEmpty) {
          setState(() {
            _userName = authService.currentUser!.displayName;
          });
          print('✅ Username loaded from Firebase Auth: ${authService.currentUser!.displayName}');
        } else {
          String emailPrefix = authService.currentUser!.email?.split('@')[0] ?? 'User';
          setState(() {
            _userName = emailPrefix;
          });
          print('✅ Username set to email prefix: $emailPrefix');
        }
      }
    } catch (e) {
      print('❌ Error loading username: $e');
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

      print('🏠 === CALCULATING HOME SCREEN BALANCE ===');
      print('🏠 User has ${groups.length} groups');

      for (GroupModel group in groups) {
        try {
          Map<String, double> groupBalances = await _databaseService.calculateGroupBalancesWithSettlements(group.id);
          double userBalance = groupBalances[_currentUserId] ?? 0.0;

          print('🏠 Group "${group.name}": User balance = €${userBalance.toStringAsFixed(2)}');
          totalBalance += userBalance;
        } catch (e) {
          print('❌ Error calculating balance for group ${group.id}: $e');
        }
      }

      print('🏠 Total balance across all groups: €${totalBalance.toStringAsFixed(2)}');

      // Update cache
      _cachedBalance = totalBalance;
      _lastBalanceUpdate = DateTime.now();

      if (!_balanceController.isClosed) {
        _balanceController.add(totalBalance);
      }
    } catch (e) {
      print('❌ Error refreshing balance: $e');
      if (!_balanceController.isClosed) {
        _balanceController.add(0.0);
      }
    }
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
              Tween(begin: Offset(1.0, 0.0), end: Offset.zero).chain(
                CurveTween(curve: Curves.easeInOut),
              ),
            ),
            child: child,
          );
        },
        transitionDuration: Duration(milliseconds: 250),
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

  void _refreshNotifications() {
    if (mounted) {
      setState(() {});
    }
  }

  void _showNotificationsDialog(BuildContext context, dynamic user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.notifications, color: Colors.blue.shade500),
            SizedBox(width: 8),
            Text('Recent Activity'),
          ],
        ),
        content: Container(
          width: double.maxFinite,
          height: 300,
          child: StreamBuilder<List<GroupModel>>(
            stream: _databaseService.streamUserGroups(user.uid),
            builder: (context, groupSnapshot) {
              if (!groupSnapshot.hasData) {
                return Center(child: CircularProgressIndicator());
              }

              List<GroupModel> groups = groupSnapshot.data!;

              if (groups.isEmpty) {
                return Center(
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
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text(group.name),
                        subtitle: Text(
                            unreadCount > 0
                                ? '$unreadCount new activit${unreadCount == 1 ? 'y' : 'ies'}'
                                : 'No new activity'
                        ),
                        trailing: unreadCount > 0
                            ? Icon(Icons.fiber_manual_record, color: Colors.red, size: 12)
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
            child: Text('Close'),
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
        title: Text('Spendwise'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        elevation: 0,
        actions: [
          user != null ? StreamBuilder<int>(
            stream: _databaseService.streamUserGroups(user.uid).asyncMap((groups) async {
              print('🏠 HomeScreen: Processing ${groups.length} groups for notifications');
              int totalUnread = 0;

              for (GroupModel group in groups) {
                int unreadCount = await _databaseService.getUnreadActivityCount(user.uid, group.id);
                print('🏠 HomeScreen: Group ${group.name}: $unreadCount unread');
                totalUnread += unreadCount;
              }

              print('🏠 HomeScreen: Total unread activities: $totalUnread');
              return totalUnread;
            }),
            builder: (context, unreadSnapshot) {
              int totalUnread = unreadSnapshot.data ?? 0;

              print('🔔 HomeScreen notification badge: $totalUnread unread activities');
              print('🔔 Connection state: ${unreadSnapshot.connectionState}');
              if (unreadSnapshot.hasError) {
                print('❌ Notification stream error: ${unreadSnapshot.error}');
              }

              return IconButton(
                icon: Stack(
                  children: [
                    Icon(Icons.notifications_outlined),
                    if (totalUnread > 0)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          padding: EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          constraints: BoxConstraints(
                            minWidth: 16,
                            minHeight: 16,
                          ),
                          child: Text(
                            totalUnread > 99 ? '99+' : totalUnread.toString(),
                            style: TextStyle(
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
          ) : SizedBox.shrink(),

          Consumer<ThemeService>(
            builder: (context, themeService, child) {
              return IconButton(
                icon: Icon(themeService.currentThemeIcon),
                onPressed: () => themeService.toggleTheme(),
                tooltip: 'Toggle theme',
              );
            },
          ),

          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () {
              _navigateWithTransition(SettingsScreen());
            },
            tooltip: 'Settings',
          ),
        ],
      ),
      body: user == null
          ? Center(child: CircularProgressIndicator())
          : Column(
        children: [
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(20),
                bottomRight: Radius.circular(20),
              ),
            ),
            padding: EdgeInsets.fromLTRB(24, 0, 24, 24),
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
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 16),

                StreamBuilder<double>(
                  stream: _balanceController.stream,
                  initialData: _cachedBalance ?? 0.0,
                  builder: (context, balanceSnapshot) {
                    return Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.account_balance_wallet, color: Colors.white),
                          SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Your Balance',
                                style: TextStyle(
                                  color: Colors.blue.shade100,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                balanceSnapshot.hasData
                                    ? '€${balanceSnapshot.data!.toStringAsFixed(2)}'
                                    : '€0.00',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
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
                              ),
                            ],
                          ),
                          Spacer(),
                          TextButton(
                            onPressed: () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Smart Insights coming next!')),
                              );
                            },
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.insights, color: Colors.white, size: 16),
                                SizedBox(width: 4),
                                Text(
                                  'Insights',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          Expanded(
            child: Padding(
              padding: EdgeInsets.all(24),
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
                          _navigateWithTransition(GroupsScreen());
                        },
                        icon: Icon(Icons.add),
                        label: Text('New Group'),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),

                  Expanded(
                    child: StreamBuilder<List<GroupModel>>(
                      stream: _databaseService.streamUserGroups(user.uid),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return Center(child: CircularProgressIndicator());
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
                                SizedBox(height: 16),
                                Text(
                                  'No groups yet',
                                  style: TextStyle(
                                    fontSize: 18,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Create your first group to start\nsplitting expenses with friends!',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                                SizedBox(height: 24),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    _navigateWithTransition(GroupsScreen());
                                  },
                                  icon: Icon(Icons.add),
                                  label: Text('Create Group'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue.shade500,
                                    foregroundColor: Colors.white,
                                    padding: EdgeInsets.symmetric(
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
                          itemCount: groups.length,
                          itemBuilder: (context, index) {
                            GroupModel group = groups[index];
                            return Hero(
                              tag: 'group_${group.id}',
                              child: Card(
                                margin: EdgeInsets.only(bottom: 12),
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
                                    style: TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: Text(
                                    '${group.memberIds.length} members • ${group.currency}',
                                  ),
                                  trailing: Icon(Icons.arrow_forward_ios, size: 16),
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}