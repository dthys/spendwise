import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/database_service.dart';
import '../../services/auth_service.dart';
import '../../models/activity_log_model.dart';

class ActivityLogScreen extends StatefulWidget {
  final String groupId;

  const ActivityLogScreen({Key? key, required this.groupId}) : super(key: key);

  @override
  _ActivityLogScreenState createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends State<ActivityLogScreen> {
  final DatabaseService _databaseService = DatabaseService();

  @override
  void initState() {
    super.initState();

    // Mark activities as seen when opening activity log
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final authService = Provider.of<AuthService>(context, listen: false);
      if (authService.currentUser != null) {
        await _databaseService.updateLastSeenActivity(
            authService.currentUser!.uid,
            widget.groupId
        );

        // Force a small delay to ensure the database update is processed
        await Future.delayed(Duration(milliseconds: 100));

        // Trigger a rebuild to update any parent widgets
        if (mounted) {
          setState(() {});
        }
      }
    });
  }

  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Activity Log'),
        backgroundColor: theme.appBarTheme.backgroundColor,
        foregroundColor: theme.appBarTheme.foregroundColor,
        elevation: 0,
      ),
      body: StreamBuilder<List<ActivityLogModel>>(
        stream: _databaseService.streamGroupActivityLogs(widget.groupId),
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
                    Icons.history,
                    size: 64,
                    color: colorScheme.onSurface.withOpacity(0.5),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'No activity yet',
                    style: TextStyle(
                      fontSize: 18,
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Group activities will appear here',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            );
          }

          List<ActivityLogModel> activities = snapshot.data!;

          return ListView.builder(
            padding: EdgeInsets.all(16),
            itemCount: activities.length,
            itemBuilder: (context, index) {
              ActivityLogModel activity = activities[index];

              return Card(
                margin: EdgeInsets.only(bottom: 8),
                color: theme.cardColor,
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _getActivityColor(activity.type),
                    child: Text(
                      activity.type.emoji,
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                  title: Text(
                    activity.description,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'By ${activity.userName}',
                        style: TextStyle(color: colorScheme.onSurface.withOpacity(0.8)),
                      ),
                      Text(
                        _formatTimestamp(activity.timestamp),
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                  isThreeLine: true,
                  onTap: () {
                    if (activity.metadata.isNotEmpty) {
                      _showActivityDetails(context, activity);
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  Color _getActivityColor(ActivityType type) {
    switch (type) {
      case ActivityType.expenseAdded:
        return Colors.green.shade500;
      case ActivityType.expenseEdited:
        return Colors.orange.shade500;
      case ActivityType.expenseDeleted:
        return Colors.red.shade500;
      case ActivityType.memberAdded:
        return Colors.blue.shade500;
      case ActivityType.memberRemoved:
        return Colors.purple.shade500;
      case ActivityType.groupCreated:
        return Colors.teal.shade500;
      default:
        return Colors.grey.shade500;
    }
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays == 1 ? '' : 's'} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours == 1 ? '' : 's'} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes == 1 ? '' : 's'} ago';
    } else {
      return 'Just now';
    }
  }

  void _showActivityDetails(BuildContext context, ActivityLogModel activity) {
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).dialogBackgroundColor,
        title: Text(
          activity.type.displayName,
          style: TextStyle(color: colorScheme.onSurface),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'By: ${activity.userName}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Time: ${activity.timestamp.day}/${activity.timestamp.month}/${activity.timestamp.year} ${activity.timestamp.hour}:${activity.timestamp.minute.toString().padLeft(2, '0')}',
                style: TextStyle(color: colorScheme.onSurface),
              ),
              SizedBox(height: 16),
              Text(
                'Details:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              SizedBox(height: 8),
              if (activity.type == ActivityType.expenseEdited && activity.metadata['changes'] != null) ...[
                ...List<String>.from(activity.metadata['changes']).map((change) =>
                    Padding(
                      padding: EdgeInsets.only(bottom: 4),
                      child: Text(
                        '• $change',
                        style: TextStyle(color: colorScheme.onSurface),
                      ),
                    )
                ),
              ] else ...[
                Text(
                  activity.description,
                  style: TextStyle(color: colorScheme.onSurface),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context, true); // Return true to indicate activities were seen
            },
            child: Text('Close'),
          ),
        ],
      ),
    );
  }
}