import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/update_service.dart';

class UpdateDialog {
  /// Show update available dialog
  static Future<void> showUpdateAvailableDialog(
      BuildContext context,
      UpdateService updateService,
      ) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.system_update, color: Colors.blue.shade500),
            SizedBox(width: 8),
            Text('Update Available'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.new_releases, color: Colors.blue.shade600, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Version ${updateService.latestVersion} is now available!',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            Text(
              'Current version: ${updateService.currentVersion}',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            if (updateService.releaseNotes != null) ...[
              SizedBox(height: 12),
              Text(
                'What\'s new:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 4),
              Container(
                constraints: BoxConstraints(maxHeight: 150),
                child: SingleChildScrollView(
                  child: Text(
                    updateService.releaseNotes!,
                    style: TextStyle(
                      fontSize: 13,
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
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange.shade600, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'The app will close during installation. You may need to enable "Install from unknown sources" in your device settings.',
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showDownloadDialog(context, updateService);
            },
            child: Text('Update Now'),
          ),
        ],
      ),
    );
  }

  /// Show download progress dialog
  static void _showDownloadDialog(
      BuildContext context,
      UpdateService updateService,
      ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _DownloadProgressDialog(updateService: updateService),
    );
  }

  /// Show update check result dialog
  static Future<void> showUpdateCheckDialog(
      BuildContext context,
      UpdateService updateService,
      bool updateAvailable,
      ) async {
    if (updateAvailable) {
      await showUpdateAvailableDialog(context, updateService);
    } else {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green.shade500),
              SizedBox(width: 8),
              Text('Up to Date'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle_outline, size: 64, color: Colors.green.shade500),
              SizedBox(height: 16),
              Text(
                'You\'re running the latest version of Spendwise!',
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8),
              Text(
                'Version ${updateService.currentVersion}',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Great!'),
            ),
          ],
        ),
      );
    }
  }
}

class _DownloadProgressDialog extends StatefulWidget {
  final UpdateService updateService;

  const _DownloadProgressDialog({required this.updateService});

  @override
  _DownloadProgressDialogState createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    final success = await widget.updateService.downloadAndInstall();

    if (mounted) {
      if (success) {
        // Download successful, installation intent launched
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Update downloaded! Please follow the installation prompts.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 4),
          ),
        );
      } else {
        // Download failed
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to download update. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UpdateService>(
      builder: (context, updateService, child) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.download, color: Colors.blue.shade500),
              SizedBox(width: 8),
              Text('Downloading...'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                value: updateService.downloadProgress > 0 ? updateService.downloadProgress : null,
              ),
              SizedBox(height: 16),
              Text(
                updateService.downloadProgress > 0
                    ? 'Downloading... ${(updateService.downloadProgress * 100).toInt()}%'
                    : 'Preparing download...',
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8),
              if (updateService.downloadProgress > 0)
                LinearProgressIndicator(
                  value: updateService.downloadProgress,
                  backgroundColor: Colors.grey.shade300,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade500),
                ),
              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade600, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Please don\'t close the app during download.',
                        style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}