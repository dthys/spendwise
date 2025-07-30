import 'package:flutter/material.dart';
import '../services/update_service.dart';
import 'update_dialog.dart';

class StartupUpdateDialog {
  static bool _hasShownThisSession = false;

  static Future<void> checkAndShowUpdateDialog(
      BuildContext context,
      UpdateService updateService,
      ) async {
    try {
      // Prevent showing multiple times in same session
      if (_hasShownThisSession) return;

      // Check for updates silently
      final updateAvailable = await updateService.checkForUpdates(silent: true);

      if (updateAvailable && context.mounted) {
        _hasShownThisSession = true;

        // Add a small delay to ensure UI is fully settled
        await Future.delayed(Duration(milliseconds: 500));

        if (context.mounted) {
          // Show startup update dialog with smooth animation
          await _showStartupUpdateDialog(context, updateService);
        }
      }
    } catch (e) {
      print('Startup update check failed: $e');
    }
  }

  static void resetSession() {
    _hasShownThisSession = false;
  }

  static Future<void> _showStartupUpdateDialog(
      BuildContext context,
      UpdateService updateService,
      ) async {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Update Available',
      barrierColor: Colors.black54,
      transitionDuration: Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return ScaleTransition(
          scale: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutBack,
          ),
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.system_update,
                    color: Colors.blue.shade600,
                    size: 24,
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Update Available',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.new_releases, color: Colors.green.shade600),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Version ${updateService.latestVersion}',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade700,
                                ),
                              ),
                              Text(
                                'Current: ${updateService.currentVersion}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.green.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (updateService.releaseNotes != null && updateService.releaseNotes!.isNotEmpty) ...[
                    SizedBox(height: 16),
                    Text(
                      'What\'s New:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.grey.shade800,
                      ),
                    ),
                    SizedBox(height: 8),
                    Container(
                      constraints: BoxConstraints(maxHeight: 120),
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: SingleChildScrollView(
                        child: Text(
                          updateService.releaseNotes!,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ),
                  ],

                  SizedBox(height: 16),
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.recommend, color: Colors.blue.shade600, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'We recommend updating to get the latest features, bug fixes, and security improvements.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.blue.shade700,
                              height: 1.3,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey.shade600,
                ),
                child: Text('Maybe Later'),
              ),
              SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.of(context).pop();
                  // Small delay to prevent flash
                  await Future.delayed(Duration(milliseconds: 100));
                  if (context.mounted) {
                    await UpdateDialog.showUpdateCheckDialog(
                      context,
                      updateService,
                      true,
                    );
                  }
                },
                icon: Icon(Icons.download, size: 18),
                label: Text('Update Now'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade600,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
            actionsPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
          ),
        );
      },
    );
  }
}