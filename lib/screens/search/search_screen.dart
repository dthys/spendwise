// Enhanced screens/search/search_screen.dart with smooth animations
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../models/group_model.dart';
import '../../models/friend_balance_model.dart';
import '../groups/group_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  _SearchScreenState createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final DatabaseService _databaseService = DatabaseService();

  // Animation controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  List<GroupModel> _allGroups = [];
  List<FriendBalance> _allFriends = [];

  List<GroupModel> _filteredGroups = [];
  List<FriendBalance> _filteredFriends = [];

  bool _isLoading = true;
  bool _showingGroups = true;
  String _searchQuery = '';

  List<String> _recentSearches = [];

  @override
  void initState() {
    super.initState();

    // Initialize animation controllers
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 350),
      vsync: this,
    );

    // Setup animations
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _loadData();
    _searchController.addListener(_onSearchChanged);

    // Start animations
    _fadeController.forward();
    _slideController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUser = authService.currentUser;

      if (currentUser != null) {
        final groups = await _databaseService.getUserGroups(currentUser.uid);
        final friends = await _databaseService.getUserFriendsWithBalances(currentUser.uid);

        setState(() {
          _allGroups = groups;
          _allFriends = friends;
          _filteredGroups = groups;
          _filteredFriends = friends;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error loading search data: $e');
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      _searchQuery = query;
      _filterResults(query);
    });
  }

  void _filterResults(String query) {
    if (query.isEmpty) {
      setState(() {
        _filteredGroups = _allGroups;
        _filteredFriends = _allFriends;
      });
      return;
    }

    _filteredGroups = _allGroups.where((group) {
      return group.name.toLowerCase().contains(query) ||
          (group.description?.toLowerCase().contains(query) ?? false);
    }).toList();

    _filteredFriends = _allFriends.where((friendBalance) {
      return friendBalance.friend.name.toLowerCase().contains(query) ||
          friendBalance.friend.email.toLowerCase().contains(query);
    }).toList();
  }

  void _addToRecentSearches(String query) {
    if (query.trim().isEmpty) return;

    setState(() {
      _recentSearches.remove(query);
      _recentSearches.insert(0, query);
      if (_recentSearches.length > 10) {
        _recentSearches = _recentSearches.take(10).toList();
      }
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _filteredGroups = _allGroups;
      _filteredFriends = _allFriends;
    });
  }

  void _navigateToGroupDetail(String groupId) {
    _addToRecentSearches(_searchQuery);
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            GroupDetailScreen(groupId: groupId),
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
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  void _showFriendDetails(FriendBalance friendBalance) {
    _addToRecentSearches(_searchQuery);
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => _FriendDetailsDialog(friendBalance: friendBalance),
    );
  }

  Widget _buildSearchBar() {
    return Hero(
      tag: 'search_bar',
      child: Material(
        child: Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: TextField(
            controller: _searchController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Search groups and friends...',
              prefixIcon: Icon(Icons.search, color: Colors.grey.shade600),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                icon: Icon(Icons.clear, color: Colors.grey.shade600),
                onPressed: _clearSearch,
              )
                  : null,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildToggleButtons() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                  _showingGroups = true;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _showingGroups ? Theme.of(context).primaryColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.group,
                      color: _showingGroups ? Colors.white : Colors.grey.shade600,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Groups (${_filteredGroups.length})',
                      style: TextStyle(
                        color: _showingGroups ? Colors.white : Colors.grey.shade600,
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
                  _showingGroups = false;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: !_showingGroups ? Theme.of(context).primaryColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.people,
                      color: !_showingGroups ? Colors.white : Colors.grey.shade600,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Friends (${_filteredFriends.length})',
                      style: TextStyle(
                        color: !_showingGroups ? Colors.white : Colors.grey.shade600,
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

  Widget _buildRecentSearches() {
    if (_recentSearches.isEmpty || _searchQuery.isNotEmpty) {
      return const SizedBox.shrink();
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Searches',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _recentSearches.clear();
                    });
                  },
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _recentSearches.length,
              itemBuilder: (context, index) {
                return Container(
                  margin: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    label: Text(_recentSearches[index]),
                    onPressed: () {
                      _searchController.text = _recentSearches[index];
                      _onSearchChanged();
                    },
                    backgroundColor: Colors.grey.shade200,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _showingGroups
            ? _buildGroupsList()
            : _buildFriendsList(),
      ),
    );
  }

  Widget _buildGroupsList() {
    if (_filteredGroups.isEmpty) {
      return _buildEmptyState(
          _searchQuery.isEmpty ? 'No groups found' : 'No groups match "$_searchQuery"'
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _filteredGroups.length,
      itemBuilder: (context, index) {
        final group = _filteredGroups[index];
        return TweenAnimationBuilder<double>(
          duration: Duration(milliseconds: 300 + (index * 50)),
          tween: Tween(begin: 0.0, end: 1.0),
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(0, 20 * (1 - value)),
              child: Opacity(
                opacity: value,
                child: Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Hero(
                      tag: 'group_${group.id}',
                      child: CircleAvatar(
                        backgroundColor: Theme.of(context).primaryColor,
                        child: Text(
                          group.name.substring(0, 1).toUpperCase(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    title: Text(
                      group.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${group.memberIds.length} members • ${group.currency}'),
                        if (group.description != null && group.description!.isNotEmpty)
                          Text(
                            group.description!,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => _navigateToGroupDetail(group.id),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFriendsList() {
    if (_filteredFriends.isEmpty) {
      return _buildEmptyState(
          _searchQuery.isEmpty ? 'No friends found' : 'No friends match "$_searchQuery"'
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _filteredFriends.length,
      itemBuilder: (context, index) {
        final friendBalance = _filteredFriends[index];
        return TweenAnimationBuilder<double>(
          duration: Duration(milliseconds: 300 + (index * 50)),
          tween: Tween(begin: 0.0, end: 1.0),
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(0, 20 * (1 - value)),
              child: Opacity(
                opacity: value,
                child: Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
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
                    title: Text(
                      friendBalance.friend.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          friendBalance.balanceText,
                          style: TextStyle(
                            color: friendBalance.balanceColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '${friendBalance.sharedGroupsCount} shared group${friendBalance.sharedGroupsCount != 1 ? 's' : ''}',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          friendBalance.balanceIcon,
                          color: friendBalance.balanceColor,
                          size: 20,
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 14,
                          color: Colors.grey.shade400,
                        ),
                      ],
                    ),
                    onTap: () => _showFriendDetails(friendBalance),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Search'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildToggleButtons(),
          _buildRecentSearches(),
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }
}

// Friend Details Dialog with animations
class _FriendDetailsDialog extends StatefulWidget {
  final FriendBalance friendBalance;

  const _FriendDetailsDialog({required this.friendBalance});

  @override
  _FriendDetailsDialogState createState() => _FriendDetailsDialogState();
}

class _FriendDetailsDialogState extends State<_FriendDetailsDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              CircleAvatar(
                backgroundImage: widget.friendBalance.friend.photoUrl != null
                    ? NetworkImage(widget.friendBalance.friend.photoUrl!)
                    : null,
                backgroundColor: widget.friendBalance.balanceColor.withOpacity(0.2),
                child: widget.friendBalance.friend.photoUrl == null
                    ? Text(
                  widget.friendBalance.friend.name.substring(0, 1).toUpperCase(),
                  style: TextStyle(
                    color: widget.friendBalance.balanceColor,
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
                      widget.friendBalance.friend.name,
                      style: const TextStyle(fontSize: 18),
                    ),
                    Text(
                      widget.friendBalance.balanceText,
                      style: TextStyle(
                        color: widget.friendBalance.balanceColor,
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
                'Shared Groups (${widget.friendBalance.sharedGroupsCount}):',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.friendBalance.sharedGroupIds.length,
                  itemBuilder: (context, index) {
                    String groupId = widget.friendBalance.sharedGroupIds[index];
                    return FutureBuilder<GroupModel?>(
                      future: DatabaseService().getGroup(groupId),
                      builder: (context, snapshot) {
                        if (snapshot.hasData && snapshot.data != null) {
                          return TweenAnimationBuilder<double>(
                            duration: Duration(milliseconds: 200 + (index * 100)),
                            tween: Tween(begin: 0.0, end: 1.0),
                            builder: (context, value, child) {
                              return Transform.translate(
                                offset: Offset(20 * (1 - value), 0),
                                child: Opacity(
                                  opacity: value,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 2),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.group, size: 16, color: Colors.grey),
                                        const SizedBox(width: 8),
                                        Expanded(child: Text(snapshot.data!.name)),
                                        TextButton(
                                          onPressed: () {
                                            Navigator.pop(context);
                                            Navigator.push(
                                              context,
                                              PageRouteBuilder(
                                                pageBuilder: (context, animation, secondaryAnimation) =>
                                                    GroupDetailScreen(groupId: groupId),
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
                                                transitionDuration: const Duration(milliseconds: 300),
                                              ),
                                            );
                                          },
                                          child: const Text('View'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
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
      ),
    );
  }
}