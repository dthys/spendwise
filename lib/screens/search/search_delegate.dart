// screens/search/search_delegate.dart
import 'package:flutter/material.dart';
import '../../services/database_service.dart';
import '../../models/group_model.dart';
import '../../models/friend_balance_model.dart';
import '../groups/group_detail_screen.dart';

class SpendwiseSearchDelegate extends SearchDelegate<String> {
  final DatabaseService _databaseService = DatabaseService();
  final String userId;

  SpendwiseSearchDelegate(this.userId);

  @override
  String get searchFieldLabel => 'Search groups and friends...';

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: Icon(Icons.clear),
        onPressed: () {
          query = '';
          showSuggestions(context);
        },
      ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.arrow_back),
      onPressed: () {
        close(context, '');
      },
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    if (query.trim().isEmpty) {
      return _buildEmptyState('Enter a search term');
    }

    return FutureBuilder<Map<String, dynamic>>(
      future: _databaseService.searchAll(query, userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return _buildEmptyState('Error occurred while searching');
        }

        final data = snapshot.data!;
        final groups = data['groups'] as List<GroupModel>;
        final friends = data['friends'] as List<FriendBalance>;
        final totalResults = data['totalResults'] as int;

        if (totalResults == 0) {
          return _buildEmptyState('No results found for "$query"');
        }

        return _buildSearchResults(context, groups, friends);
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.trim().isEmpty) {
      return FutureBuilder<List<String>>(
        future: _databaseService.getSearchSuggestions(userId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return _buildEmptyState('Start typing to search...');
          }

          final suggestions = snapshot.data!;

          if (suggestions.isEmpty) {
            return _buildEmptyState('No suggestions available');
          }

          return ListView.builder(
            itemCount: suggestions.length,
            itemBuilder: (context, index) {
              final suggestion = suggestions[index];
              return ListTile(
                leading: Icon(Icons.history, color: Colors.grey),
                title: Text(suggestion),
                onTap: () {
                  query = suggestion;
                  showResults(context);
                },
              );
            },
          );
        },
      );
    }

    // Show filtered suggestions based on current query
    return FutureBuilder<Map<String, dynamic>>(
      future: _databaseService.searchAll(query, userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData) {
          return _buildEmptyState('No suggestions');
        }

        final data = snapshot.data!;
        final groups = data['groups'] as List<GroupModel>;
        final friends = data['friends'] as List<FriendBalance>;

        return _buildSearchSuggestions(context, groups, friends);
      },
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search,
            size: 64,
            color: Colors.grey.shade400,
          ),
          SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade600,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(BuildContext context, List<GroupModel> groups, List<FriendBalance> friends) {
    return ListView(
      children: [
        if (groups.isNotEmpty) ...[
          _buildSectionHeader('Groups', groups.length),
          ...groups.map((group) => _buildGroupTile(context, group)),
          SizedBox(height: 16),
        ],
        if (friends.isNotEmpty) ...[
          _buildSectionHeader('Friends', friends.length),
          ...friends.map((friend) => _buildFriendTile(context, friend)),
        ],
      ],
    );
  }

  Widget _buildSearchSuggestions(BuildContext context, List<GroupModel> groups, List<FriendBalance> friends) {
    List<Widget> suggestionTiles = [];

    // Add group suggestions
    for (var group in groups.take(3)) {
      suggestionTiles.add(
        ListTile(
          leading: CircleAvatar(
            backgroundColor: Colors.blue,
            radius: 16,
            child: Icon(Icons.group, color: Colors.white, size: 16),
          ),
          title: Text(group.name),
          subtitle: Text('${group.memberIds.length} members'),
          onTap: () {
            query = group.name;
            showResults(context);
          },
        ),
      );
    }

    // Add friend suggestions
    for (var friendBalance in friends.take(3)) {
      suggestionTiles.add(
        ListTile(
          leading: CircleAvatar(
            radius: 16,
            backgroundImage: friendBalance.friend.photoUrl != null
                ? NetworkImage(friendBalance.friend.photoUrl!)
                : null,
            backgroundColor: friendBalance.balanceColor.withOpacity(0.2),
            child: friendBalance.friend.photoUrl == null
                ? Text(
              friendBalance.friend.name.substring(0, 1).toUpperCase(),
              style: TextStyle(
                color: friendBalance.balanceColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            )
                : null,
          ),
          title: Text(friendBalance.friend.name),
          subtitle: Text(friendBalance.balanceText),
          onTap: () {
            query = friendBalance.friend.name;
            showResults(context);
          },
        ),
      );
    }

    if (suggestionTiles.isEmpty) {
      return _buildEmptyState('No suggestions for "$query"');
    }

    return ListView(children: suggestionTiles);
  }

  Widget _buildSectionHeader(String title, int count) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        '$title ($count)',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade700,
        ),
      ),
    );
  }

  Widget _buildGroupTile(BuildContext context, GroupModel group) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.blue,
        child: Text(
          group.name.substring(0, 1).toUpperCase(),
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(
        group.name,
        style: TextStyle(fontWeight: FontWeight.w600),
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
      trailing: Icon(Icons.arrow_forward_ios, size: 16),
      onTap: () {
        close(context, group.name);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => GroupDetailScreen(groupId: group.id),
          ),
        );
      },
    );
  }

  Widget _buildFriendTile(BuildContext context, FriendBalance friendBalance) {
    return ListTile(
      leading: CircleAvatar(
        radius: 20,
        backgroundImage: friendBalance.friend.photoUrl != null
            ? NetworkImage(friendBalance.friend.photoUrl!)
            : null,
        backgroundColor: friendBalance.balanceColor.withOpacity(0.2),
        child: friendBalance.friend.photoUrl == null
            ? Text(
          friendBalance.friend.name.substring(0, 1).toUpperCase(),
          style: TextStyle(
            color: friendBalance.balanceColor,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        )
            : null,
      ),
      title: Text(
        friendBalance.friend.name,
        style: TextStyle(fontWeight: FontWeight.w600),
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
            size: 16,
          ),
          Icon(
            Icons.arrow_forward_ios,
            size: 14,
            color: Colors.grey.shade400,
          ),
        ],
      ),
      onTap: () {
        close(context, friendBalance.friend.name);
        _showFriendDetails(context, friendBalance);
      },
    );
  }

  void _showFriendDetails(BuildContext context, FriendBalance friendBalance) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    friendBalance.friend.name,
                    style: TextStyle(fontSize: 18),
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
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 8),
            Container(
              constraints: BoxConstraints(maxHeight: 200),
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
                          padding: EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Icon(Icons.group, size: 16, color: Colors.grey),
                              SizedBox(width: 8),
                              Expanded(child: Text(snapshot.data!.name)),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(dialogContext); // Close the dialog
                                  Navigator.push(
                                    context, // Use the original context for navigation
                                    MaterialPageRoute(
                                      builder: (context) => GroupDetailScreen(groupId: groupId),
                                    ),
                                  );
                                },
                                child: Text('View'),
                              ),
                            ],
                          ),
                        );
                      }
                      return SizedBox.shrink();
                    },
                  );
                },
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }
}