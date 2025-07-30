import 'dart:convert';
import 'dart:io';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:android_intent_plus/android_intent.dart';

class UpdateService extends ChangeNotifier {
  static const String _githubApiUrl = 'https://api.github.com/repos/dthys/spendwise/releases/latest';

  bool _isCheckingForUpdate = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String? _latestVersion;
  String? _currentVersion;
  String? _downloadUrl;
  String? _releaseNotes;
  bool _updateAvailable = false;

  // Getters
  bool get isCheckingForUpdate => _isCheckingForUpdate;
  bool get isDownloading => _isDownloading;
  double get downloadProgress => _downloadProgress;
  String? get latestVersion => _latestVersion;
  String? get currentVersion => _currentVersion;
  String? get downloadUrl => _downloadUrl;
  String? get releaseNotes => _releaseNotes;
  bool get updateAvailable => _updateAvailable;

  /// Initialize the service and get current app version
  Future<void> initialize() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _currentVersion = packageInfo.version;
      notifyListeners();
    } catch (e) {
      print('❌ Error getting package info: $e');
    }
  }

  /// Check for updates from GitHub releases
  Future<bool> checkForUpdates({bool silent = false}) async {
    if (_isCheckingForUpdate) return false;

    _isCheckingForUpdate = true;
    _updateAvailable = false;
    if (!silent) notifyListeners();

    try {
      final response = await http.get(
        Uri.parse(_githubApiUrl),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      ).timeout(Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        _latestVersion = data['tag_name']?.toString().replaceFirst('v', '') ?? data['name'];
        _releaseNotes = data['body'] ?? 'No release notes available';

        // Find APK download URL
        final assets = data['assets'] as List?;
        if (assets != null && assets.isNotEmpty) {
          for (final asset in assets) {
            final name = asset['name']?.toString().toLowerCase() ?? '';
            if (name.endsWith('.apk')) {
              _downloadUrl = asset['browser_download_url'];
              break;
            }
          }
        }

        // Compare versions
        if (_currentVersion != null && _latestVersion != null) {
          _updateAvailable = _isNewerVersion(_latestVersion!, _currentVersion!);
        }

        print('✅ Update check completed - Latest: $_latestVersion, Current: $_currentVersion, Available: $_updateAvailable');

      } else {
        print('❌ Failed to check for updates: ${response.statusCode}');
        throw Exception('Failed to fetch release info');
      }
    } catch (e) {
      print('❌ Error checking for updates: $e');
      _updateAvailable = false;
    } finally {
      _isCheckingForUpdate = false;
      notifyListeners();
    }

    return _updateAvailable;
  }

  /// Compare version strings (simple semantic versioning)
  bool _isNewerVersion(String latestVersion, String currentVersion) {
    try {
      final latest = latestVersion.split('.').map(int.parse).toList();
      final current = currentVersion.split('.').map(int.parse).toList();

      // Ensure both have same length by padding with zeros
      while (latest.length < 3) latest.add(0);
      while (current.length < 3) current.add(0);

      for (int i = 0; i < 3; i++) {
        if (latest[i] > current[i]) return true;
        if (latest[i] < current[i]) return false;
      }
      return false; // Versions are equal
    } catch (e) {
      print('❌ Error comparing versions: $e');
      return false;
    }
  }

  /// Download the APK file
  Future<String?> downloadUpdate() async {
    if (_downloadUrl == null || _isDownloading) return null;

    _isDownloading = true;
    _downloadProgress = 0.0;
    notifyListeners();

    try {
      final response = await http.get(Uri.parse(_downloadUrl!));

      if (response.statusCode == 200) {
        final directory = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
        final filePath = '${directory.path}/spendwise_${_latestVersion}.apk';

        final file = File(filePath);

        // Write file with progress tracking
        final bytes = response.bodyBytes;
        await file.writeAsBytes(bytes);

        _downloadProgress = 1.0;
        notifyListeners();

        print('✅ APK downloaded to: $filePath');
        return filePath;
      } else {
        throw Exception('Failed to download APK: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error downloading update: $e');
      return null;
    } finally {
      _isDownloading = false;
      notifyListeners();
    }
  }

  /// Download with progress tracking using stream
  Future<String?> downloadUpdateWithProgress() async {
    if (_downloadUrl == null || _isDownloading) return null;

    _isDownloading = true;
    _downloadProgress = 0.0;
    notifyListeners();

    try {
      final request = http.Request('GET', Uri.parse(_downloadUrl!));
      final response = await http.Client().send(request);

      if (response.statusCode == 200) {
        final directory = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
        final filePath = '${directory.path}/spendwise_${_latestVersion}.apk';
        final file = File(filePath);

        final contentLength = response.contentLength ?? 0;
        int downloadedBytes = 0;

        final sink = file.openWrite();

        await response.stream.listen(
              (chunk) {
            sink.add(chunk);
            downloadedBytes += chunk.length;

            if (contentLength > 0) {
              _downloadProgress = downloadedBytes / contentLength;
              notifyListeners();
            }
          },
          onDone: () async {
            await sink.close();
            _downloadProgress = 1.0;
            notifyListeners();
          },
          onError: (error) {
            sink.close();
            throw error;
          },
        ).asFuture();

        print('✅ APK downloaded to: $filePath');
        return filePath;
      } else {
        throw Exception('Failed to download APK: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error downloading update: $e');
      return null;
    } finally {
      _isDownloading = false;
      notifyListeners();
    }
  }

  /// Install the APK (Android only)
  Future<bool> installUpdate(String apkPath) async {
    try {
      if (Platform.isAndroid) {
        final intent = AndroidIntent(
          action: 'android.intent.action.VIEW',
          data: 'file://$apkPath',
          type: 'application/vnd.android.package-archive',
          flags: [Flag.FLAG_ACTIVITY_NEW_TASK, Flag.FLAG_GRANT_READ_URI_PERMISSION],
        );

        await intent.launch();
        return true;
      }
      return false;
    } catch (e) {
      print('❌ Error installing update: $e');
      return false;
    }
  }

  /// Complete update flow: download and install
  Future<bool> downloadAndInstall() async {
    final apkPath = await downloadUpdateWithProgress();
    if (apkPath != null) {
      return await installUpdate(apkPath);
    }
    return false;
  }

  /// Reset update state
  void resetUpdateState() {
    _updateAvailable = false;
    _isDownloading = false;
    _downloadProgress = 0.0;
    _latestVersion = null;
    _downloadUrl = null;
    _releaseNotes = null;
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
}