import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/activity_log_model.dart';
import '../models/user_model.dart';
import '../services/database_service.dart';

class NotificationService extends ChangeNotifier {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final DatabaseService _databaseService = DatabaseService();

  // Notification preferences keys
  static const String _expenseAddedKey = 'notify_expense_added';
  static const String _expenseEditedKey = 'notify_expense_edited';
  static const String _expenseDeletedKey = 'notify_expense_deleted';
  static const String _memberAddedKey = 'notify_member_added';
  static const String _memberRemovedKey = 'notify_member_removed';
  static const String _groupCreatedKey = 'notify_group_created';

  // Current notification preferences
  bool _expenseAddedEnabled = true;
  bool _expenseEditedEnabled = true;
  bool _expenseDeletedEnabled = true;
  bool _memberAddedEnabled = true;
  bool _memberRemovedEnabled = true;
  bool _groupCreatedEnabled = true;

  // Getters for preferences
  bool get expenseAddedEnabled => _expenseAddedEnabled;
  bool get expenseEditedEnabled => _expenseEditedEnabled;
  bool get expenseDeletedEnabled => _expenseDeletedEnabled;
  bool get memberAddedEnabled => _memberAddedEnabled;
  bool get memberRemovedEnabled => _memberRemovedEnabled;
  bool get groupCreatedEnabled => _groupCreatedEnabled;

  String? _fcmToken;
  String? get fcmToken => _fcmToken;

  BuildContext? _navigatorContext;
  GlobalKey<NavigatorState>? _navigatorKey;

  // In-app notification queue
  final List<NotificationData> _pendingNotifications = [];

  Future<void> initialize(BuildContext context, {GlobalKey<NavigatorState>? navigatorKey}) async {
    _navigatorContext = context;
    _navigatorKey = navigatorKey;

    await _initializeFirebaseMessaging();
    await _loadNotificationPreferences();

    print('✅ Simple Notification Service initialized');
  }

  Future<void> _initializeFirebaseMessaging() async {
    try {
      // Request permission
      NotificationSettings settings = await _firebaseMessaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        print('✅ Firebase Messaging permissions granted');

        // Get FCM token
        _fcmToken = await _firebaseMessaging.getToken();
        print('📱 FCM Token: $_fcmToken');

        // Handle foreground messages
        FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

        // Handle background messages
        FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundMessage);

        // Handle app launch from notification
        RemoteMessage? initialMessage = await _firebaseMessaging.getInitialMessage();
        if (initialMessage != null) {
          _handleBackgroundMessage(initialMessage);
        }

        // Listen for token refresh
        _firebaseMessaging.onTokenRefresh.listen((newToken) {
          _fcmToken = newToken;
          print('🔄 FCM Token refreshed: $newToken');
        });
      } else {
        print('❌ Firebase Messaging permissions denied');
      }
    } catch (e) {
      print('❌ Error initializing Firebase Messaging: $e');
    }
  }

  void _handleForegroundMessage(RemoteMessage message) {
    print('🔔 Foreground Firebase message received: ${message.notification?.title}');
    _showInAppNotification(
      title: message.notification?.title ?? 'Notification',
      body: message.notification?.body ?? '',
      groupId: message.data['groupId'],
    );
  }

  void _handleBackgroundMessage(RemoteMessage message) {
    print('🔔 Background Firebase message received: ${message.notification?.title}');
    final data = message.data;
    if (data['groupId'] != null) {
      _navigateToActivityLog(data['groupId']);
    }
  }

  void _navigateToActivityLog(String groupId) {
    print('🚀 Navigating to activity log for group: $groupId');

    if (_navigatorKey?.currentState != null) {
      _navigatorKey!.currentState!.pushNamed(
        '/activity-log',
        arguments: {'groupId': groupId},
      );
    } else if (_navigatorContext != null) {
      Navigator.of(_navigatorContext!).pushNamed(
        '/activity-log',
        arguments: {'groupId': groupId},
      );
    }
  }

  // Create and send notification for new activity
  Future<void> sendActivityNotification(ActivityLogModel activity, String currentUserId) async {
    try {
      // Don't send notification for actions by current user
      if (activity.userId == currentUserId) {
        return;
      }

      // Check if this type of notification is enabled
      if (!_isNotificationTypeEnabled(activity.type)) {
        print('📵 Notification disabled for type: ${activity.type}');
        return;
      }

      // Get group details
      final group = await _databaseService.getGroup(activity.groupId);
      if (group == null) {
        print('❌ Group not found for notification');
        return;
      }

      // Create notification content
      final title = _getNotificationTitle(activity.type, group.name);
      final body = _getNotificationBody(activity);

      // Show in-app notification
      _showInAppNotification(
        title: title,
        body: body,
        groupId: activity.groupId,
        activityType: activity.type,
      );

      print('✅ In-app notification shown for: ${activity.description}');
    } catch (e) {
      print('❌ Error sending activity notification: $e');
    }
  }

  void _showInAppNotification({
    required String title,
    required String body,
    String? groupId,
    ActivityType? activityType,
  }) {
    final notification = NotificationData(
      title: title,
      body: body,
      groupId: groupId,
      activityType: activityType,
      timestamp: DateTime.now(),
    );

    _pendingNotifications.add(notification);

    // Show as overlay notification
    _showOverlayNotification(notification);
  }

  void _showOverlayNotification(NotificationData notification) {
    if (_navigatorContext == null) return;

    final overlay = Overlay.of(_navigatorContext!);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 10,
        left: 16,
        right: 16,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).primaryColor.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: InkWell(
              onTap: () {
                overlayEntry.remove();
                if (notification.groupId != null) {
                  _navigateToActivityLog(notification.groupId!);
                }
              },
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Theme.of(context).primaryColor,
                    radius: 20,
                    child: Text(
                      _getNotificationIcon(notification.activityType),
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          notification.title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 4),
                        Text(
                          notification.body,
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.8),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Theme.of(context).primaryColor,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);

    // Auto-remove after 4 seconds
    Future.delayed(Duration(seconds: 4), () {
      if (overlayEntry.mounted) {
        overlayEntry.remove();
      }
    });
  }

  bool _isNotificationTypeEnabled(ActivityType type) {
    switch (type) {
      case ActivityType.expenseAdded:
        return _expenseAddedEnabled;
      case ActivityType.expenseEdited:
        return _expenseEditedEnabled;
      case ActivityType.expenseDeleted:
        return _expenseDeletedEnabled;
      case ActivityType.memberAdded:
        return _memberAddedEnabled;
      case ActivityType.memberRemoved:
        return _memberRemovedEnabled;
      case ActivityType.groupCreated:
        return _groupCreatedEnabled;
      default:
        return true;
    }
  }

  String _getNotificationTitle(ActivityType type, String groupName) {
    switch (type) {
      case ActivityType.expenseAdded:
        return '💰 New expense in $groupName';
      case ActivityType.expenseEdited:
        return '✏️ Expense updated in $groupName';
      case ActivityType.expenseDeleted:
        return '🗑️ Expense deleted in $groupName';
      case ActivityType.memberAdded:
        return '👥 New member in $groupName';
      case ActivityType.memberRemoved:
        return '👤 Member left $groupName';
      case ActivityType.groupCreated:
        return '🎉 Welcome to $groupName';
      default:
        return '📝 Activity in $groupName';
    }
  }

  String _getNotificationBody(ActivityLogModel activity) {
    return '${activity.userName}: ${activity.description}';
  }

  String _getNotificationIcon(ActivityType? type) {
    switch (type) {
      case ActivityType.expenseAdded:
        return '💰';
      case ActivityType.expenseEdited:
        return '✏️';
      case ActivityType.expenseDeleted:
        return '🗑️';
      case ActivityType.memberAdded:
        return '👥';
      case ActivityType.memberRemoved:
        return '👤';
      case ActivityType.groupCreated:
        return '🎉';
      default:
        return '📝';
    }
  }

  // Test notification method
  Future<void> sendTestNotification() async {
    _showInAppNotification(
      title: '🧪 Test Notification',
      body: 'This is a test in-app notification from Spendwise!',
      groupId: 'test_group',
      activityType: ActivityType.other,
    );
    print('🧪 Test in-app notification shown');
  }

  // Notification preference methods (unchanged)
  Future<void> _loadNotificationPreferences() async {
    final prefs = await SharedPreferences.getInstance();

    _expenseAddedEnabled = prefs.getBool(_expenseAddedKey) ?? true;
    _expenseEditedEnabled = prefs.getBool(_expenseEditedKey) ?? true;
    _expenseDeletedEnabled = prefs.getBool(_expenseDeletedKey) ?? true;
    _memberAddedEnabled = prefs.getBool(_memberAddedKey) ?? true;
    _memberRemovedEnabled = prefs.getBool(_memberRemovedKey) ?? true;
    _groupCreatedEnabled = prefs.getBool(_groupCreatedKey) ?? true;

    notifyListeners();
  }

  Future<void> setExpenseAddedEnabled(bool enabled) async {
    _expenseAddedEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_expenseAddedKey, enabled);
    notifyListeners();
  }

  Future<void> setExpenseEditedEnabled(bool enabled) async {
    _expenseEditedEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_expenseEditedKey, enabled);
    notifyListeners();
  }

  Future<void> setExpenseDeletedEnabled(bool enabled) async {
    _expenseDeletedEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_expenseDeletedKey, enabled);
    notifyListeners();
  }

  Future<void> setMemberAddedEnabled(bool enabled) async {
    _memberAddedEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_memberAddedKey, enabled);
    notifyListeners();
  }

  Future<void> setMemberRemovedEnabled(bool enabled) async {
    _memberRemovedEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_memberRemovedKey, enabled);
    notifyListeners();
  }

  Future<void> setGroupCreatedEnabled(bool enabled) async {
    _groupCreatedEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_groupCreatedKey, enabled);
    notifyListeners();
  }
}

// Data class for notifications
class NotificationData {
  final String title;
  final String body;
  final String? groupId;
  final ActivityType? activityType;
  final DateTime timestamp;

  NotificationData({
    required this.title,
    required this.body,
    this.groupId,
    this.activityType,
    required this.timestamp,
  });
}