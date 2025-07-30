import 'dart:convert';
import 'dart:io';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class UpdateService extends ChangeNotifier {
  static const String _githubApiUrl = 'https://api.github.com/repos/dthys/spendwise/releases/latest';
  static const String _githubToken = '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'; // Your GitHub token
  static bool _hasCheckedThisSession = false;

  bool _isCheckingForUpdate = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String? _latestVersion;
  String? _currentVersion;
  String? _downloadUrl;
  String? _releaseNotes;
  bool _updateAvailable = false;
  String? _lastError;

  // Getters
  bool get isCheckingForUpdate => _isCheckingForUpdate;
  bool get isDownloading => _isDownloading;
  double get downloadProgress => _downloadProgress;
  String? get latestVersion => _latestVersion;
  String? get currentVersion => _currentVersion;
  String? get downloadUrl => _downloadUrl;
  String? get releaseNotes => _releaseNotes;
  bool get updateAvailable => _updateAvailable;
  String? get lastError => _lastError;

  /// Initialize the service and get current app version
  Future<void> initialize() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _currentVersion = packageInfo.version;
      print('🔧 Initialized UpdateService - Current version: $_currentVersion');
      notifyListeners();
    } catch (e) {
      _lastError = 'Error getting package info: $e';
      print('❌ $_lastError');
    }
  }

  /// Check for updates only if not already checked this session
  Future<bool> checkForUpdatesOnce({bool silent = false}) async {
    if (_hasCheckedThisSession) {
      print('🔄 Update already checked this session, skipping...');
      return _updateAvailable;
    }

    final result = await checkForUpdates(silent: silent);
    _hasCheckedThisSession = true;
    print('✅ First update check completed for this session');
    return result;
  }

  /// Reset session flag (call when app restarts)
  static void resetSession() {
    _hasCheckedThisSession = false;
  }

  /// Check for updates from GitHub releases - WITH AUTHENTICATION
  Future<bool> checkForUpdates({bool silent = false}) async {
    if (_isCheckingForUpdate) return false;

    _isCheckingForUpdate = true;
    _updateAvailable = false;
    _lastError = null;
    if (!silent) notifyListeners();

    try {
      print('🔍 Checking for updates with authentication...');

      // Enhanced headers with authentication
      final headers = {
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'Spendwise-App/1.0',
        'Authorization': 'Bearer $_githubToken', // This increases your rate limit to 5,000/hour
        'X-GitHub-Api-Version': '2022-11-28',
      };

      final response = await http.get(
        Uri.parse(_githubApiUrl),
        headers: headers,
      ).timeout(Duration(seconds: 15));

      print('🌐 GitHub API response status: ${response.statusCode}');

      // Check rate limit headers for debugging
      final rateLimitRemaining = response.headers['x-ratelimit-remaining'];
      final rateLimitReset = response.headers['x-ratelimit-reset'];
      print('🔢 Rate limit remaining: $rateLimitRemaining');
      if (rateLimitReset != null) {
        final resetTime = DateTime.fromMillisecondsSinceEpoch(int.parse(rateLimitReset) * 1000);
        print('⏰ Rate limit resets at: $resetTime');
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        _latestVersion = data['tag_name']?.toString().replaceFirst('v', '') ?? data['name'];
        _releaseNotes = data['body'] ?? 'No release notes available';

        print('📦 Latest version from GitHub: $_latestVersion');
        print('📝 Release notes length: ${_releaseNotes?.length ?? 0} characters');

        // Find APK download URL with better debugging
        final assets = data['assets'] as List?;
        print('📎 Found ${assets?.length ?? 0} assets');

        if (assets != null && assets.isNotEmpty) {
          for (int i = 0; i < assets.length; i++) {
            final asset = assets[i];
            final name = asset['name']?.toString() ?? '';
            final downloadUrl = asset['browser_download_url']?.toString() ?? '';
            final size = asset['size'] ?? 0;

            print('📎 Asset $i: $name (${size} bytes)');

            if (name.toLowerCase().endsWith('.apk')) {
              _downloadUrl = downloadUrl;
              print('✅ Found APK: $name');
              print('🔗 Download URL: $downloadUrl');
              break;
            }
          }
        }

        if (_downloadUrl == null) {
          _lastError = 'No APK file found in release assets';
          print('❌ $_lastError');
        }

        // Compare versions
        if (_currentVersion != null && _latestVersion != null) {
          _updateAvailable = _isNewerVersion(_latestVersion!, _currentVersion!);
          print('🔄 Version comparison: $_currentVersion -> $_latestVersion = $_updateAvailable');
        }

        print('✅ Update check completed - Latest: $_latestVersion, Current: $_currentVersion, Available: $_updateAvailable');

      } else if (response.statusCode == 403) {
        // Handle rate limit or authentication issues
        try {
          final responseBody = json.decode(response.body);
          final message = responseBody['message']?.toString() ?? 'Unknown error';

          if (message.contains('rate limit')) {
            _lastError = 'GitHub rate limit exceeded. Please try again later.';
            print('⏰ $_lastError');
          } else if (message.contains('Bad credentials')) {
            _lastError = 'GitHub authentication failed. Please check your token.';
            print('🔑 $_lastError');
          } else {
            _lastError = 'GitHub API error: $message';
            print('❌ $_lastError');
          }
        } catch (e) {
          _lastError = 'Failed to check for updates: HTTP ${response.statusCode}';
          print('❌ $_lastError');
        }

        // Don't throw exception for rate limits, just return false
        return false;

      } else if (response.statusCode == 401) {
        _lastError = 'GitHub authentication failed. Please check your token.';
        print('🔑 $_lastError');
        return false;

      } else {
        _lastError = 'Failed to check for updates: HTTP ${response.statusCode}';
        print('❌ $_lastError');
        print('📝 Response body: ${response.body}');
        throw Exception(_lastError);
      }

    } catch (e) {
      _lastError = 'Error checking for updates: $e';
      print('❌ $_lastError');
      _updateAvailable = false;
    } finally {
      _isCheckingForUpdate = false;
      notifyListeners();
    }

    return _updateAvailable;
  }

  /// Compare version strings (enhanced debugging)
  bool _isNewerVersion(String latestVersion, String currentVersion) {
    try {
      print('🔍 Comparing versions: $currentVersion vs $latestVersion');

      final latest = latestVersion.split('.').map((s) => int.tryParse(s) ?? 0).toList();
      final current = currentVersion.split('.').map((s) => int.tryParse(s) ?? 0).toList();

      print('📊 Parsed latest: $latest');
      print('📊 Parsed current: $current');

      // Ensure both have same length by padding with zeros
      while (latest.length < 3) latest.add(0);
      while (current.length < 3) current.add(0);

      for (int i = 0; i < 3; i++) {
        print('🔢 Comparing part $i: ${current[i]} vs ${latest[i]}');
        if (latest[i] > current[i]) {
          print('✅ Newer version detected');
          return true;
        }
        if (latest[i] < current[i]) {
          print('⏪ Older version');
          return false;
        }
      }
      print('🟰 Same version');
      return false;
    } catch (e) {
      _lastError = 'Error comparing versions: $e';
      print('❌ $_lastError');
      return false;
    }
  }

  /// Check and request necessary permissions
  Future<bool> checkPermissions() async {
    try {
      print('🔒 Checking permissions...');

      if (!Platform.isAndroid) {
        print('✅ Not Android, skipping permission checks');
        return true;
      }

      // Get device info first
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final sdkInt = androidInfo.version.sdkInt;
      print('📱 Android SDK: $sdkInt');

      // For Android 13+ (API 33+), we need different approach
      if (sdkInt >= 33) {
        print('📱 Android 13+ detected - checking install permission only');

        // Only need install packages permission for Android 13+
        final installStatus = await Permission.requestInstallPackages.status;
        print('📦 Install packages permission status: $installStatus');

        if (!installStatus.isGranted) {
          print('📦 Requesting install packages permission...');
          final result = await Permission.requestInstallPackages.request();
          print('📦 Install packages after request: $result');
          return result.isGranted;
        }
        return true;
      }

      // For Android 11-12 (API 30-32)
      else if (sdkInt >= 30) {
        print('📱 Android 11-12 detected - checking storage and install permissions');

        // Check both permissions
        final installStatus = await Permission.requestInstallPackages.status;
        final storageStatus = await Permission.manageExternalStorage.status;

        print('📦 Install packages permission status: $installStatus');
        print('📁 Manage external storage status: $storageStatus');

        bool needsInstallPermission = !installStatus.isGranted;
        bool needsStoragePermission = !storageStatus.isGranted;

        if (needsInstallPermission) {
          final result = await Permission.requestInstallPackages.request();
          print('📦 Install packages after request: $result');
          needsInstallPermission = !result.isGranted;
        }

        if (needsStoragePermission) {
          final result = await Permission.manageExternalStorage.request();
          print('📁 Manage external storage after request: $result');
          needsStoragePermission = !result.isGranted;
        }

        return !needsInstallPermission && !needsStoragePermission;
      }

      // For Android 10 and below (API 29-)
      else {
        print('📱 Android 10- detected - checking storage and install permissions');

        final installStatus = await Permission.requestInstallPackages.status;
        final storageStatus = await Permission.storage.status;

        print('📦 Install packages permission status: $installStatus');
        print('📁 Storage permission status: $storageStatus');

        bool needsInstallPermission = !installStatus.isGranted;
        bool needsStoragePermission = !storageStatus.isGranted;

        if (needsInstallPermission) {
          final result = await Permission.requestInstallPackages.request();
          print('📦 Install packages after request: $result');
          needsInstallPermission = !result.isGranted;
        }

        if (needsStoragePermission) {
          final result = await Permission.storage.request();
          print('📁 Storage after request: $result');
          needsStoragePermission = !result.isGranted;
        }

        return !needsInstallPermission && !needsStoragePermission;
      }

    } catch (e) {
      _lastError = 'Error checking permissions: $e';
      print('❌ $_lastError');
      print('❌ Stack trace: ${StackTrace.current}');
      return false;
    }
  }

  /// Enhanced download with better error handling and debugging
  Future<String?> downloadUpdateWithProgress() async {
    if (_downloadUrl == null || _isDownloading) {
      _lastError = _downloadUrl == null ? 'No download URL available' : 'Already downloading';
      print('❌ $_lastError');
      return null;
    }

    // Check permissions first
    if (!await checkPermissions()) {
      _lastError = 'Required permissions not granted';
      print('❌ $_lastError');
      return null;
    }

    _isDownloading = true;
    _downloadProgress = 0.0;
    _lastError = null;
    notifyListeners();

    try {
      print('📥 Starting download from: $_downloadUrl');

      final request = http.Request('GET', Uri.parse(_downloadUrl!));
      request.headers.addAll({
        'User-Agent': 'Spendwise-App/1.0',
        'Accept': '*/*',
        'Accept-Encoding': 'identity', // Disable compression for easier progress tracking
      });

      final client = http.Client();
      final response = await client.send(request);
      print('📥 Download response status: ${response.statusCode}');
      print('📥 Response headers: ${response.headers}');

      if (response.statusCode == 200) {
        // Get storage directory with fallbacks
        Directory? directory = await _getStorageDirectory();

        if (directory == null) {
          throw Exception('Could not access storage directory');
        }

        final fileName = 'spendwise_${_latestVersion}.apk';
        final filePath = '${directory.path}/$fileName';
        final file = File(filePath);

        print('📁 Download path: $filePath');

        // Delete existing file if it exists
        if (await file.exists()) {
          await file.delete();
          print('🗑️ Deleted existing file');
        }

        final contentLength = response.contentLength ?? 0;
        print('📊 Content length: $contentLength bytes');

        int downloadedBytes = 0;
        final sink = file.openWrite();

        try {
          // FIXED: Use await for the stream processing
          await for (final chunk in response.stream) {
            sink.add(chunk);
            downloadedBytes += chunk.length;

            if (contentLength > 0) {
              _downloadProgress = downloadedBytes / contentLength;
            } else {
              _downloadProgress = 0.5; // Indeterminate progress
            }

            if (downloadedBytes % (1024 * 1024) < chunk.length) { // Log every MB
              print('📊 Downloaded: ${(downloadedBytes / 1024 / 1024).toStringAsFixed(1)} MB');
            }

            notifyListeners();
          }

          // Close the sink after stream is complete
          await sink.flush();
          await sink.close();
          client.close();

          print('✅ Download stream completed');
          _downloadProgress = 1.0;
          notifyListeners();

          // Verify the downloaded file
          if (await file.exists()) {
            final fileSize = await file.length();
            print('✅ APK downloaded successfully');
            print('📁 File path: $filePath');
            print('📊 File size: $fileSize bytes');
            print('📊 Expected size: $contentLength bytes');

            if (fileSize > 0) {
              // Additional verification - check if it's a valid APK by reading magic bytes
              try {
                final bytes = await file.openRead(0, 4).first;
                final magicBytes = bytes.sublist(0, 4);
                // APK files are ZIP files, should start with "PK"
                if (magicBytes[0] == 0x50 && magicBytes[1] == 0x4B) {
                  print('✅ File appears to be a valid APK (ZIP magic bytes found)');
                } else {
                  print('⚠️ Warning: File may not be a valid APK (magic bytes: $magicBytes)');
                }
              } catch (e) {
                print('⚠️ Could not verify file magic bytes: $e');
              }

              // Verify file size matches expected
              if (contentLength > 0 && fileSize != contentLength) {
                print('⚠️ Warning: File size mismatch - Downloaded: $fileSize, Expected: $contentLength');
                // Don't fail here, sometimes servers report slightly different sizes
              }

              return filePath;
            } else {
              throw Exception('Downloaded file is empty');
            }
          } else {
            throw Exception('Downloaded file does not exist');
          }

        } catch (e) {
          await sink.close();
          client.close();

          // Clean up partial file
          if (await file.exists()) {
            await file.delete();
            print('🗑️ Cleaned up partial download');
          }
          throw e;
        }
      } else {
        client.close();
        throw Exception('Failed to download APK: HTTP ${response.statusCode}\nHeaders: ${response.headers}');
      }
    } catch (e) {
      _lastError = 'Download failed: $e';
      print('❌ $_lastError');
      return null;
    } finally {
      _isDownloading = false;
      notifyListeners();
    }
  }

  /// Get the best available storage directory
  Future<Directory?> _getStorageDirectory() async {
    try {
      // Try external storage first (usually /storage/emulated/0/Android/data/...)
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        final downloadsDir = Directory('${externalDir.path}/downloads');
        await downloadsDir.create(recursive: true);
        print('📁 Using external storage: ${downloadsDir.path}');
        return downloadsDir;
      }
    } catch (e) {
      print('⚠️ External storage not available: $e');
    }

    try {
      // Fallback to app documents directory
      final appDir = await getApplicationDocumentsDirectory();
      final downloadsDir = Directory('${appDir.path}/downloads');
      await downloadsDir.create(recursive: true);
      print('📁 Using app documents: ${downloadsDir.path}');
      return downloadsDir;
    } catch (e) {
      print('❌ Could not access app documents: $e');
    }

    try {
      // Last resort - temporary directory
      final tempDir = await getTemporaryDirectory();
      print('📁 Using temporary directory: ${tempDir.path}');
      return tempDir;
    } catch (e) {
      print('❌ Could not access temporary directory: $e');
    }

    return null;
  }

  /// Enhanced installation with better debugging
  Future<bool> installUpdate(String apkPath) async {
    try {
      print('📱 Starting APK installation from: $apkPath');

      if (!Platform.isAndroid) {
        _lastError = 'Installation only supported on Android';
        print('❌ $_lastError');
        return false;
      }

      final file = File(apkPath);
      if (!await file.exists()) {
        _lastError = 'APK file does not exist: $apkPath';
        print('❌ $_lastError');
        return false;
      }

      final fileSize = await file.length();
      print('📊 APK file size: $fileSize bytes');

      if (fileSize == 0) {
        _lastError = 'APK file is empty';
        print('❌ $_lastError');
        return false;
      }

      // Check permissions again before installation
      final hasInstallPermission = await Permission.requestInstallPackages.isGranted;
      print('📦 Install permission granted: $hasInstallPermission');

      if (!hasInstallPermission) {
        _lastError = 'Install packages permission not granted';
        print('❌ $_lastError');
        return false;
      }

      // Get device info for installation strategy
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final sdkInt = androidInfo.version.sdkInt;
      print('📱 Android SDK: $sdkInt');
      print('📱 Android version: ${androidInfo.version.release}');

      // Try multiple installation approaches
      bool installed = false;

      // Approach 1: Standard VIEW intent
      if (!installed) {
        installed = await _tryInstallWithViewIntent(apkPath, sdkInt);
      }

      // Approach 2: Copy to public downloads and try again
      if (!installed) {
        installed = await _tryInstallFromPublicDownloads(apkPath);
      }

      // Approach 3: Use INSTALL_PACKAGE action
      if (!installed) {
        installed = await _tryInstallWithInstallPackageIntent(apkPath);
      }

      if (installed) {
        print('✅ Installation intent launched successfully');
      } else {
        _lastError = 'All installation methods failed';
        print('❌ $_lastError');
      }

      return installed;

    } catch (e) {
      _lastError = 'Error installing update: $e';
      print('❌ $_lastError');
      return false;
    }
  }

  Future<bool> _tryInstallWithViewIntent(String apkPath, int sdkInt) async {
    try {
      print('🔧 Trying VIEW intent installation...');

      AndroidIntent intent;

      if (sdkInt >= 24) {
        // Android 7.0+ - Use FileProvider
        final packageInfo = await PackageInfo.fromPlatform();
        final authority = '${packageInfo.packageName}.fileprovider';

        // Convert file path to content URI format
        String contentPath = apkPath;
        if (contentPath.startsWith('/storage/emulated/0/')) {
          contentPath = contentPath.replaceFirst('/storage/emulated/0/', '/external_files/');
        } else if (contentPath.contains('/Android/data/')) {
          contentPath = contentPath.replaceAll(RegExp(r'.*/Android/data/[^/]+/files/'), '/external_files/');
        }

        final contentUri = 'content://$authority$contentPath';
        print('🔗 Content URI: $contentUri');

        intent = AndroidIntent(
          action: 'android.intent.action.VIEW',
          data: contentUri,
          type: 'application/vnd.android.package-archive',
          flags: [
            Flag.FLAG_ACTIVITY_NEW_TASK,
            Flag.FLAG_GRANT_READ_URI_PERMISSION,
            Flag.FLAG_GRANT_WRITE_URI_PERMISSION,
          ],
        );
      } else {
        // Android 6.0 and below
        intent = AndroidIntent(
          action: 'android.intent.action.VIEW',
          data: 'file://$apkPath',
          type: 'application/vnd.android.package-archive',
          flags: [
            Flag.FLAG_ACTIVITY_NEW_TASK,
            Flag.FLAG_GRANT_READ_URI_PERMISSION,
          ],
        );
      }

      await intent.launch();
      print('✅ VIEW intent launched');
      return true;

    } catch (e) {
      print('❌ VIEW intent failed: $e');
      return false;
    }
  }

  Future<bool> _tryInstallFromPublicDownloads(String apkPath) async {
    try {
      print('🔧 Trying installation from public downloads...');

      final publicPath = '/storage/emulated/0/Download/spendwise_${_latestVersion}.apk';
      final sourceFile = File(apkPath);
      final targetFile = File(publicPath);

      // Copy to public Downloads folder
      await sourceFile.copy(publicPath);
      print('📁 Copied APK to: $publicPath');

      final intent = AndroidIntent(
        action: 'android.intent.action.VIEW',
        data: 'file://$publicPath',
        type: 'application/vnd.android.package-archive',
        flags: [
          Flag.FLAG_ACTIVITY_NEW_TASK,
          Flag.FLAG_GRANT_READ_URI_PERMISSION,
        ],
      );

      await intent.launch();
      print('✅ Public downloads install intent launched');
      return true;

    } catch (e) {
      print('❌ Public downloads install failed: $e');
      return false;
    }
  }

  Future<bool> _tryInstallWithInstallPackageIntent(String apkPath) async {
    try {
      print('🔧 Trying INSTALL_PACKAGE intent...');

      final intent = AndroidIntent(
        action: 'android.intent.action.INSTALL_PACKAGE',
        data: 'file://$apkPath',
        type: 'application/vnd.android.package-archive',
        flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
      );

      await intent.launch();
      print('✅ INSTALL_PACKAGE intent launched');
      return true;

    } catch (e) {
      print('❌ INSTALL_PACKAGE intent failed: $e');
      return false;
    }
  }

  /// Complete update flow with enhanced error handling
  Future<bool> downloadAndInstall() async {
    print('🚀 Starting complete update flow...');

    _lastError = null;

    final apkPath = await downloadUpdateWithProgress();
    if (apkPath != null) {
      print('📦 Download completed, starting installation...');
      return await installUpdate(apkPath);
    } else {
      print('❌ Download failed, cannot proceed with installation');
      return false;
    }
  }

  /// Reset update state
  void resetUpdateState() {
    _updateAvailable = false;
    _isDownloading = false;
    _downloadProgress = 0.0;
    _latestVersion = null;
    _downloadUrl = null;
    _releaseNotes = null;
    _lastError = null;
    notifyListeners();
  }

  /// Get formatted version info
  String getVersionInfo() {
    if (_currentVersion == null) return 'Version info unavailable';

    String info = 'Current: $_currentVersion';
    if (_updateAvailable && _latestVersion != null) {
      info += ' → Latest: $_latestVersion';
    }
    return info;
  }

  /// Get detailed debug information
  String getDebugInfo() {
    return '''
Debug Information:
- Current Version: $_currentVersion
- Latest Version: $_latestVersion
- Update Available: $_updateAvailable
- Download URL: $_downloadUrl
- Is Checking: $_isCheckingForUpdate
- Is Downloading: $_isDownloading
- Download Progress: ${(_downloadProgress * 100).toStringAsFixed(1)}%
- Last Error: $_lastError
- Platform: ${Platform.operatingSystem}
    ''';
  }
}