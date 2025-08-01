import 'dart:async';
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
import '../config/app_config.dart';

class UpdateService extends ChangeNotifier {
  static const String _githubApiUrl = AppConfig.githubApiUrl;
  static const String _githubToken = AppConfig.githubToken;
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

  // NEW: Silent initialization flag to prevent UI flashes
  bool _isSilentMode = true;

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

  /// Initialize the service and get current app version - SILENT MODE
  Future<void> initialize() async {
    _isSilentMode = true; // Start in silent mode

    try {
      // Validate token is configured
      if (_githubToken.isEmpty || _githubToken == 'YOUR_NEW_GITHUB_TOKEN_HERE') {
        _lastError = 'GitHub token not configured';
        if (kDebugMode) {
          print('❌ $_lastError - Please configure your GitHub token in app_config.dart');
        }
        return;
      }

      final packageInfo = await PackageInfo.fromPlatform();
      _currentVersion = packageInfo.version;
      if (kDebugMode) {
        print('🔧 Initialized UpdateService - Current version: $_currentVersion');
      }

      // DON'T notify listeners during silent initialization
      // notifyListeners(); // REMOVED

    } catch (e) {
      _lastError = 'Error getting package info: $e';
      if (kDebugMode) {
        print('❌ $_lastError');
      }
    }
  }

  /// Enable UI updates after app is fully loaded
  void enableUIUpdates() {
    _isSilentMode = false;
    if (kDebugMode) {
      print('🔊 UpdateService UI updates enabled');
    }
  }

  /// Override notifyListeners to respect silent mode
  @override
  void notifyListeners() {
    if (!_isSilentMode) {
      super.notifyListeners();
    }
  }

  /// Check for updates only if not already checked this session - SILENT BY DEFAULT
  Future<bool> checkForUpdatesOnce({bool silent = true}) async {
    if (_hasCheckedThisSession) {
      if (kDebugMode) {
        print('🔄 Update already checked this session, skipping...');
      }
      return _updateAvailable;
    }

    final result = await checkForUpdates(silent: silent);
    _hasCheckedThisSession = true;
    if (kDebugMode) {
      print('✅ First update check completed for this session');
    }
    return result;
  }

  /// Reset session flag (call when app restarts)
  static void resetSession() {
    _hasCheckedThisSession = false;
  }

  /// Check for updates from GitHub releases - ENHANCED SILENT MODE
  Future<bool> checkForUpdates({bool silent = true}) async {
    if (_isCheckingForUpdate) return false;

    _isCheckingForUpdate = true;
    _updateAvailable = false;
    _lastError = null;

    // Only notify listeners if not in silent mode
    if (!silent && !_isSilentMode) {
      notifyListeners();
    }

    try {
      if (kDebugMode) {
        print('🔍 Checking for updates with authentication... (silent: $silent)');
      }

      // Enhanced headers with authentication
      final headers = {
        'Accept': 'application/vnd.github.v3+json',
        'User-Agent': 'Spendwise-App/1.0',
        'Authorization': 'Bearer $_githubToken',
        'X-GitHub-Api-Version': '2022-11-28',
      };

      final response = await http.get(
        Uri.parse(_githubApiUrl),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      if (kDebugMode) {
        print('🌐 GitHub API response status: ${response.statusCode}');
      }

      // Check rate limit headers for debugging
      final rateLimitRemaining = response.headers['x-ratelimit-remaining'];
      final rateLimitReset = response.headers['x-ratelimit-reset'];
      if (kDebugMode) {
        print('🔢 Rate limit remaining: $rateLimitRemaining');
      }
      if (rateLimitReset != null) {
        final resetTime = DateTime.fromMillisecondsSinceEpoch(int.parse(rateLimitReset) * 1000);
        if (kDebugMode) {
          print('⏰ Rate limit resets at: $resetTime');
        }
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        _latestVersion = data['tag_name']?.toString().replaceFirst('v', '') ?? data['name'];
        _releaseNotes = data['body'] ?? 'No release notes available';

        if (kDebugMode) {
          print('📦 Latest version from GitHub: $_latestVersion');
        }
        if (kDebugMode) {
          print('📝 Release notes length: ${_releaseNotes?.length ?? 0} characters');
        }

        // Find APK download URL
        final assets = data['assets'] as List?;
        if (kDebugMode) {
          print('📎 Found ${assets?.length ?? 0} assets');
        }

        if (assets != null && assets.isNotEmpty) {
          for (int i = 0; i < assets.length; i++) {
            final asset = assets[i];
            final name = asset['name']?.toString() ?? '';
            final downloadUrl = asset['browser_download_url']?.toString() ?? '';
            final size = asset['size'] ?? 0;

            if (kDebugMode) {
              print('📎 Asset $i: $name ($size bytes)');
            }

            if (name.toLowerCase().endsWith('.apk')) {
              _downloadUrl = downloadUrl;
              if (kDebugMode) {
                print('✅ Found APK: $name');
              }
              if (kDebugMode) {
                print('🔗 Download URL: $downloadUrl');
              }
              break;
            }
          }
        }

        if (_downloadUrl == null) {
          _lastError = 'No APK file found in release assets';
          if (kDebugMode) {
            print('❌ $_lastError');
          }
        }

        // Compare versions
        if (_currentVersion != null && _latestVersion != null) {
          _updateAvailable = _isNewerVersion(_latestVersion!, _currentVersion!);
          if (kDebugMode) {
            print('🔄 Version comparison: $_currentVersion -> $_latestVersion = $_updateAvailable');
          }
        }

        if (kDebugMode) {
          print('✅ Update check completed - Latest: $_latestVersion, Current: $_currentVersion, Available: $_updateAvailable');
        }

      } else if (response.statusCode == 403) {
        // Handle rate limit or authentication issues
        try {
          final responseBody = json.decode(response.body);
          final message = responseBody['message']?.toString() ?? 'Unknown error';

          if (message.contains('rate limit')) {
            _lastError = 'GitHub rate limit exceeded. Please try again later.';
            if (kDebugMode) {
              print('⏰ $_lastError');
            }
          } else if (message.contains('Bad credentials')) {
            _lastError = 'GitHub authentication failed. Please check your token.';
            if (kDebugMode) {
              print('🔑 $_lastError');
            }
          } else {
            _lastError = 'GitHub API error: $message';
            if (kDebugMode) {
              print('❌ $_lastError');
            }
          }
        } catch (e) {
          _lastError = 'Failed to check for updates: HTTP ${response.statusCode}';
          if (kDebugMode) {
            print('❌ $_lastError');
          }
        }

        return false;

      } else if (response.statusCode == 401) {
        _lastError = 'GitHub authentication failed. Please check your token.';
        if (kDebugMode) {
          print('🔑 $_lastError');
        }
        return false;

      } else {
        _lastError = 'Failed to check for updates: HTTP ${response.statusCode}';
        if (kDebugMode) {
          print('❌ $_lastError');
        }
        if (kDebugMode) {
          print('📝 Response body: ${response.body}');
        }
        throw Exception(_lastError);
      }

    } catch (e) {
      _lastError = 'Error checking for updates: $e';
      if (kDebugMode) {
        print('❌ $_lastError');
      }
      _updateAvailable = false;
    } finally {
      _isCheckingForUpdate = false;

      // Only notify listeners if not in silent mode
      if (!silent && !_isSilentMode) {
        notifyListeners();
      }
    }

    return _updateAvailable;
  }

  /// Compare version strings (enhanced debugging)
  bool _isNewerVersion(String latestVersion, String currentVersion) {
    try {
      if (kDebugMode) {
        print('🔍 Comparing versions: $currentVersion vs $latestVersion');
      }

      final latest = latestVersion.split('.').map((s) => int.tryParse(s) ?? 0).toList();
      final current = currentVersion.split('.').map((s) => int.tryParse(s) ?? 0).toList();

      if (kDebugMode) {
        print('📊 Parsed latest: $latest');
      }
      if (kDebugMode) {
        print('📊 Parsed current: $current');
      }

      // Ensure both have same length by padding with zeros
      while (latest.length < 3) {
        latest.add(0);
      }
      while (current.length < 3) {
        current.add(0);
      }

      for (int i = 0; i < 3; i++) {
        if (kDebugMode) {
          print('🔢 Comparing part $i: ${current[i]} vs ${latest[i]}');
        }
        if (latest[i] > current[i]) {
          if (kDebugMode) {
            print('✅ Newer version detected');
          }
          return true;
        }
        if (latest[i] < current[i]) {
          if (kDebugMode) {
            print('⏪ Older version');
          }
          return false;
        }
      }
      if (kDebugMode) {
        print('🟰 Same version');
      }
      return false;
    } catch (e) {
      _lastError = 'Error comparing versions: $e';
      if (kDebugMode) {
        print('❌ $_lastError');
      }
      return false;
    }
  }

  /// Check and request necessary permissions
  Future<bool> checkPermissions() async {
    try {
      if (kDebugMode) {
        print('🔒 Checking permissions...');
      }

      if (!Platform.isAndroid) {
        if (kDebugMode) {
          print('✅ Not Android, skipping permission checks');
        }
        return true;
      }

      // Get device info first
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final sdkInt = androidInfo.version.sdkInt;
      if (kDebugMode) {
        print('📱 Android SDK: $sdkInt');
      }

      // For Android 13+ (API 33+), we need different approach
      if (sdkInt >= 33) {
        if (kDebugMode) {
          print('📱 Android 13+ detected - checking install permission only');
        }

        // Only need install packages permission for Android 13+
        final installStatus = await Permission.requestInstallPackages.status;
        if (kDebugMode) {
          print('📦 Install packages permission status: $installStatus');
        }

        if (!installStatus.isGranted) {
          if (kDebugMode) {
            print('📦 Requesting install packages permission...');
          }
          final result = await Permission.requestInstallPackages.request();
          if (kDebugMode) {
            print('📦 Install packages after request: $result');
          }
          return result.isGranted;
        }
        return true;
      }

      // For Android 11-12 (API 30-32)
      else if (sdkInt >= 30) {
        if (kDebugMode) {
          print('📱 Android 11-12 detected - checking storage and install permissions');
        }

        // Check both permissions
        final installStatus = await Permission.requestInstallPackages.status;
        final storageStatus = await Permission.manageExternalStorage.status;

        if (kDebugMode) {
          print('📦 Install packages permission status: $installStatus');
        }
        if (kDebugMode) {
          print('📁 Manage external storage status: $storageStatus');
        }

        bool needsInstallPermission = !installStatus.isGranted;
        bool needsStoragePermission = !storageStatus.isGranted;

        if (needsInstallPermission) {
          final result = await Permission.requestInstallPackages.request();
          if (kDebugMode) {
            print('📦 Install packages after request: $result');
          }
          needsInstallPermission = !result.isGranted;
        }

        if (needsStoragePermission) {
          final result = await Permission.manageExternalStorage.request();
          if (kDebugMode) {
            print('📁 Manage external storage after request: $result');
          }
          needsStoragePermission = !result.isGranted;
        }

        return !needsInstallPermission && !needsStoragePermission;
      }

      // For Android 10 and below (API 29-)
      else {
        if (kDebugMode) {
          print('📱 Android 10- detected - checking storage and install permissions');
        }

        final installStatus = await Permission.requestInstallPackages.status;
        final storageStatus = await Permission.storage.status;

        if (kDebugMode) {
          print('📦 Install packages permission status: $installStatus');
        }
        if (kDebugMode) {
          print('📁 Storage permission status: $storageStatus');
        }

        bool needsInstallPermission = !installStatus.isGranted;
        bool needsStoragePermission = !storageStatus.isGranted;

        if (needsInstallPermission) {
          final result = await Permission.requestInstallPackages.request();
          if (kDebugMode) {
            print('📦 Install packages after request: $result');
          }
          needsInstallPermission = !result.isGranted;
        }

        if (needsStoragePermission) {
          final result = await Permission.storage.request();
          if (kDebugMode) {
            print('📁 Storage after request: $result');
          }
          needsStoragePermission = !result.isGranted;
        }

        return !needsInstallPermission && !needsStoragePermission;
      }

    } catch (e) {
      _lastError = 'Error checking permissions: $e';
      if (kDebugMode) {
        print('❌ $_lastError');
      }
      if (kDebugMode) {
        print('❌ Stack trace: ${StackTrace.current}');
      }
      return false;
    }
  }

  /// Enhanced download with better error handling and debugging
  Future<String?> downloadUpdateWithProgress() async {
    if (_downloadUrl == null || _isDownloading) {
      _lastError = _downloadUrl == null ? 'No download URL available' : 'Already downloading';
      if (kDebugMode) {
        print('❌ $_lastError');
      }
      return null;
    }

    // Check permissions first
    if (!await checkPermissions()) {
      _lastError = 'Required permissions not granted';
      if (kDebugMode) {
        print('❌ $_lastError');
      }
      return null;
    }

    _isDownloading = true;
    _downloadProgress = 0.0;
    _lastError = null;

    // Always notify during actual download
    notifyListeners();

    try {
      if (kDebugMode) {
        print('📥 Starting PRIVATE REPO download...');
      }

      // For private repos, we need to get the asset ID and use the API
      int? assetId = await _getAssetId();
      if (assetId == null) {
        throw Exception('Could not find APK asset ID');
      }

      if (kDebugMode) {
        print('📥 Using GitHub Asset API with ID: $assetId');
      }

      // Use GitHub Assets API for private repos
      final apiUrl = 'https://api.github.com/repos/dthys/spendwise/releases/assets/$assetId';

      final request = http.Request('GET', Uri.parse(apiUrl));
      request.headers.addAll({
        'Accept': 'application/octet-stream',
        'Authorization': 'Bearer $_githubToken',
        'User-Agent': 'Spendwise-App/1.0',
        'X-GitHub-Api-Version': '2022-11-28',
      });

      final client = http.Client();
      final response = await client.send(request).timeout(const Duration(seconds: 30));

      if (kDebugMode) {
        print('📥 API Download response status: ${response.statusCode}');
      }
      if (kDebugMode) {
        print('📥 Content-Type: ${response.headers['content-type']}');
      }

      if (response.statusCode == 200) {
        // Verify we got binary content, not JSON/HTML
        final contentType = response.headers['content-type'] ?? '';
        if (contentType.contains('application/json') || contentType.contains('text/html')) {
          client.close();
          throw Exception('Got $contentType instead of binary APK data');
        }

        // Continue with download
        Directory? directory = await _getStorageDirectory();

        if (directory == null) {
          client.close();
          throw Exception('Could not access storage directory');
        }

        final fileName = 'spendwise_$_latestVersion.apk';
        final filePath = '${directory.path}/$fileName';
        final file = File(filePath);

        if (kDebugMode) {
          print('📁 Download path: $filePath');
        }

        if (await file.exists()) {
          await file.delete();
          if (kDebugMode) {
            print('🗑️ Deleted existing file');
          }
        }

        final contentLength = response.contentLength ?? 0;
        if (kDebugMode) {
          print('📊 Content length: $contentLength bytes');
        }

        int downloadedBytes = 0;
        final sink = file.openWrite();

        try {
          await for (final chunk in response.stream) {
            sink.add(chunk);
            downloadedBytes += chunk.length;

            if (contentLength > 0) {
              _downloadProgress = downloadedBytes / contentLength;
            } else {
              _downloadProgress = 0.5;
            }

            if (downloadedBytes % (512 * 1024) < chunk.length) {
              if (kDebugMode) {
                print('📊 Downloaded: ${(downloadedBytes / 1024 / 1024).toStringAsFixed(1)} MB');
              }
            }

            notifyListeners();
          }

          await sink.flush();
          await sink.close();
          client.close();

          _downloadProgress = 1.0;
          notifyListeners();

          if (await file.exists()) {
            final fileSize = await file.length();
            if (kDebugMode) {
              print('✅ APK downloaded successfully - Size: $fileSize bytes');
            }

            if (fileSize > 1024) {
              return filePath;
            } else {
              throw Exception('Downloaded file is too small: $fileSize bytes');
            }
          } else {
            throw Exception('Downloaded file does not exist');
          }

        } catch (e) {
          await sink.close();
          client.close();
          if (await file.exists()) {
            await file.delete();
          }
          rethrow;
        }

      } else if (response.statusCode == 404) {
        client.close();
        throw Exception('Asset not found - check if release and APK exist');
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        client.close();
        throw Exception('Authentication failed - check GitHub token permissions');
      } else {
        client.close();
        throw Exception('Download failed: HTTP ${response.statusCode}');
      }

    } catch (e) {
      _lastError = 'Download failed: $e';
      if (kDebugMode) {
        print('❌ $_lastError');
      }
      return null;
    } finally {
      _isDownloading = false;
      notifyListeners();
    }
  }

  /// Get the asset ID for the APK file from the latest release
  Future<int?> _getAssetId() async {
    try {
      if (kDebugMode) {
        print('🔍 Getting asset ID from GitHub API...');
      }

      final headers = {
        'Accept': 'application/vnd.github.v3+json',
        'Authorization': 'Bearer $_githubToken',
        'User-Agent': 'Spendwise-App/1.0',
        'X-GitHub-Api-Version': '2022-11-28',
      };

      final response = await http.get(
        Uri.parse(_githubApiUrl),
        headers: headers,
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final assets = data['assets'] as List?;

        if (assets != null && assets.isNotEmpty) {
          for (final asset in assets) {
            final name = asset['name']?.toString() ?? '';
            if (name.toLowerCase().endsWith('.apk')) {
              final assetId = asset['id'];
              if (kDebugMode) {
                print('✅ Found APK asset: $name (ID: $assetId)');
              }
              return assetId;
            }
          }
        }
      } else {
        if (kDebugMode) {
          print('❌ GitHub API error: ${response.statusCode}');
        }
        if (kDebugMode) {
          print('Response: ${response.body}');
        }
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting asset ID: $e');
      }
      return null;
    }
  }

  /// Get the best available storage directory
  Future<Directory?> _getStorageDirectory() async {
    try {
      // Try external storage first
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        final downloadsDir = Directory('${externalDir.path}/downloads');
        await downloadsDir.create(recursive: true);
        if (kDebugMode) {
          print('📁 Using external storage: ${downloadsDir.path}');
        }
        return downloadsDir;
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ External storage not available: $e');
      }
    }

    try {
      // Fallback to app documents directory
      final appDir = await getApplicationDocumentsDirectory();
      final downloadsDir = Directory('${appDir.path}/downloads');
      await downloadsDir.create(recursive: true);
      if (kDebugMode) {
        print('📁 Using app documents: ${downloadsDir.path}');
      }
      return downloadsDir;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Could not access app documents: $e');
      }
    }

    try {
      // Last resort - temporary directory
      final tempDir = await getTemporaryDirectory();
      if (kDebugMode) {
        print('📁 Using temporary directory: ${tempDir.path}');
      }
      return tempDir;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Could not access temporary directory: $e');
      }
    }

    return null;
  }

  /// Enhanced installation with better debugging
  Future<bool> installUpdate(String apkPath) async {
    try {
      if (kDebugMode) {
        print('📱 Starting APK installation from: $apkPath');
      }

      if (!Platform.isAndroid) {
        _lastError = 'Installation only supported on Android';
        if (kDebugMode) {
          print('❌ $_lastError');
        }
        return false;
      }

      final file = File(apkPath);
      if (!await file.exists()) {
        _lastError = 'APK file does not exist: $apkPath';
        if (kDebugMode) {
          print('❌ $_lastError');
        }
        return false;
      }

      final fileSize = await file.length();
      if (kDebugMode) {
        print('📊 APK file size: $fileSize bytes');
      }

      if (fileSize == 0) {
        _lastError = 'APK file is empty';
        if (kDebugMode) {
          print('❌ $_lastError');
        }
        return false;
      }

      // Check permissions again before installation
      final hasInstallPermission = await Permission.requestInstallPackages.isGranted;
      if (kDebugMode) {
        print('📦 Install permission granted: $hasInstallPermission');
      }

      if (!hasInstallPermission) {
        _lastError = 'Install packages permission not granted';
        if (kDebugMode) {
          print('❌ $_lastError');
        }
        return false;
      }

      // Get device info for installation strategy
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final sdkInt = androidInfo.version.sdkInt;
      if (kDebugMode) {
        print('📱 Android SDK: $sdkInt');
      }
      if (kDebugMode) {
        print('📱 Android version: ${androidInfo.version.release}');
      }

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
        if (kDebugMode) {
          print('✅ Installation intent launched successfully');
        }
      } else {
        _lastError = 'All installation methods failed';
        if (kDebugMode) {
          print('❌ $_lastError');
        }
      }

      return installed;

    } catch (e) {
      _lastError = 'Error installing update: $e';
      if (kDebugMode) {
        print('❌ $_lastError');
      }
      return false;
    }
  }

  Future<bool> _tryInstallWithViewIntent(String apkPath, int sdkInt) async {
    try {
      if (kDebugMode) {
        print('🔧 Trying VIEW intent installation...');
      }

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
        if (kDebugMode) {
          print('🔗 Content URI: $contentUri');
        }

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
      if (kDebugMode) {
        print('✅ VIEW intent launched');
      }
      return true;

    } catch (e) {
      if (kDebugMode) {
        print('❌ VIEW intent failed: $e');
      }
      return false;
    }
  }

  Future<bool> _tryInstallFromPublicDownloads(String apkPath) async {
    try {
      if (kDebugMode) {
        print('🔧 Trying installation from public downloads...');
      }

      final publicPath = '/storage/emulated/0/Download/spendwise_$_latestVersion.apk';
      final sourceFile = File(apkPath);

      // Copy to public Downloads folder
      await sourceFile.copy(publicPath);
      if (kDebugMode) {
        print('📁 Copied APK to: $publicPath');
      }

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
      if (kDebugMode) {
        print('✅ Public downloads install intent launched');
      }
      return true;

    } catch (e) {
      if (kDebugMode) {
        print('❌ Public downloads install failed: $e');
      }
      return false;
    }
  }

  Future<bool> _tryInstallWithInstallPackageIntent(String apkPath) async {
    try {
      if (kDebugMode) {
        print('🔧 Trying INSTALL_PACKAGE intent...');
      }

      final intent = AndroidIntent(
        action: 'android.intent.action.INSTALL_PACKAGE',
        data: 'file://$apkPath',
        type: 'application/vnd.android.package-archive',
        flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
      );

      await intent.launch();
      if (kDebugMode) {
        print('✅ INSTALL_PACKAGE intent launched');
      }
      return true;

    } catch (e) {
      if (kDebugMode) {
        print('❌ INSTALL_PACKAGE intent failed: $e');
      }
      return false;
    }
  }

  /// Complete update flow with enhanced error handling
  Future<bool> downloadAndInstall() async {
    if (kDebugMode) {
      print('🚀 Starting complete update flow...');
    }

    _lastError = null;

    // Enable UI updates during actual download/install process
    final wasSilent = _isSilentMode;
    _isSilentMode = false;

    try {
      final apkPath = await downloadUpdateWithProgress();
      if (apkPath != null) {
        if (kDebugMode) {
          print('📦 Download completed, starting installation...');
        }
        return await installUpdate(apkPath);
      } else {
        if (kDebugMode) {
          print('❌ Download failed, cannot proceed with installation');
        }
        return false;
      }
    } finally {
      // Restore previous silent state
      _isSilentMode = wasSilent;
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

    // Only notify if not in silent mode
    if (!_isSilentMode) {
      notifyListeners();
    }
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
- Silent Mode: $_isSilentMode
    ''';
  }
}