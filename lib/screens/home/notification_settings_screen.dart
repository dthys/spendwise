import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/notification_service.dart';

class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Notification Settings'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Consumer<NotificationService>(
            builder: (context, notificationService, child) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with info
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Theme.of(context).primaryColor.withOpacity(0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.notifications_active,
                          color: Theme.of(context).primaryColor,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Stay Updated',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).primaryColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Choose which notifications you want to receive',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Expense Notifications Section
                  _buildSectionHeader('Expense Notifications', context),
                  _buildNotificationTile(
                    context: context,
                    icon: Icons.add_circle_outline,
                    iconColor: Colors.green,
                    title: 'Expense Added',
                    subtitle: 'Get notified when new expenses are added to your groups',
                    value: notificationService.expenseAddedEnabled,
                    onChanged: notificationService.setExpenseAddedEnabled,
                  ),
                  _buildNotificationTile(
                    context: context,
                    icon: Icons.edit_outlined,
                    iconColor: Colors.blue,
                    title: 'Expense Edited',
                    subtitle: 'Get notified when expenses are modified',
                    value: notificationService.expenseEditedEnabled,
                    onChanged: notificationService.setExpenseEditedEnabled,
                  ),
                  _buildNotificationTile(
                    context: context,
                    icon: Icons.delete_outline,
                    iconColor: Colors.red,
                    title: 'Expense Deleted',
                    subtitle: 'Get notified when expenses are removed',
                    value: notificationService.expenseDeletedEnabled,
                    onChanged: notificationService.setExpenseDeletedEnabled,
                  ),

                  const SizedBox(height: 24),

                  // Group & Member Notifications Section
                  _buildSectionHeader('Group & Member Notifications', context),
                  _buildNotificationTile(
                    context: context,
                    icon: Icons.person_add_outlined,
                    iconColor: Colors.green,
                    title: 'Member Added',
                    subtitle: 'Get notified when new members join your groups',
                    value: notificationService.memberAddedEnabled,
                    onChanged: notificationService.setMemberAddedEnabled,
                  ),
                  _buildNotificationTile(
                    context: context,
                    icon: Icons.person_remove_outlined,
                    iconColor: Colors.orange,
                    title: 'Member Removed',
                    subtitle: 'Get notified when members leave your groups',
                    value: notificationService.memberRemovedEnabled,
                    onChanged: notificationService.setMemberRemovedEnabled,
                  ),
                  _buildNotificationTile(
                    context: context,
                    icon: Icons.group_add_outlined,
                    iconColor: Colors.purple,
                    title: 'Group Created',
                    subtitle: 'Get notified when you\'re added to new groups',
                    value: notificationService.groupCreatedEnabled,
                    onChanged: notificationService.setGroupCreatedEnabled,
                  ),

                  const SizedBox(height: 32),

                  // Test Notification Section
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        await notificationService.sendTestNotification();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Row(
                              children: [
                                Icon(Icons.check_circle, color: Colors.white),
                                SizedBox(width: 8),
                                Text('Test notification sent successfully!'),
                              ],
                            ),
                            backgroundColor: Colors.green,
                            duration: const Duration(seconds: 3),
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.send, color: Colors.white),
                      label: const Text(
                        'Send Test Notification',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Info footer
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: Colors.grey.shade600,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'You can change these settings anytime. Notifications help you stay updated with group activities.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 12, top: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).primaryColor,
        ),
      ),
    );
  }

  Widget _buildNotificationTile({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Theme.of(context).cardColor,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: iconColor,
            size: 24,
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 14,
            height: 1.3,
          ),
        ),
        trailing: Switch(
          value: value,
          onChanged: onChanged,
          activeColor: Theme.of(context).primaryColor,
        ),
        onTap: () => onChanged(!value),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}