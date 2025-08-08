import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateService extends ChangeNotifier {
  // Your app's Play Store package name
  static const String _packageName = 'com.dthys.spendwise';
  static const String _playStoreUrl = 'https://play.google.com/store/apps/details?id=$_packageName';
  static const String _playStoreApiUrl = 'https://play.google.com/store/apps/details?id=$_packageName&gl=US';

  static bool _hasCheckedThisSession = false;

  bool _isCheckingForUpdate = false;
  String? _latestVersion;
  String? _currentVersion;
  String? _releaseNotes;
  bool _updateAvailable = false;
  String? _lastError;

  // Silent initialization flag to prevent UI flashes
  bool _isSilentMode = true;

  // Getters
  bool get isCheckingForUpdate => _isCheckingForUpdate;
  String? get latestVersion => _latestVersion;
  String? get currentVersion => _currentVersion;
  String? get releaseNotes => _releaseNotes;
  bool get updateAvailable => _updateAvailable;
  String? get lastError => _lastError;

  /// Initialize the service and get current app version - SILENT MODE
  Future<void> initialize() async {
    _isSilentMode = true; // Start in silent mode

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      _currentVersion = packageInfo.version;
      if (kDebugMode) {
        print('🔧 Initialized UpdateService - Current version: $_currentVersion');
      }
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

  /// Check for updates by parsing Play Store page - ENHANCED SILENT MODE
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
        print('🔍 Checking for updates from Play Store... (silent: $silent)');
      }

      final response = await http.get(
        Uri.parse(_playStoreApiUrl),
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'en-US,en;q=0.5',
          'Accept-Encoding': 'gzip, deflate',
          'Connection': 'keep-alive',
        },
      ).timeout(const Duration(seconds: 15));

      if (kDebugMode) {
        print('🌐 Play Store response status: ${response.statusCode}');
      }

      if (response.statusCode == 200) {
        final htmlContent = response.body;

        // Parse version from Play Store HTML
        _latestVersion = _parseVersionFromHtml(htmlContent);

        // Parse release notes (what's new section)
        _releaseNotes = _parseReleaseNotesFromHtml(htmlContent);

        if (kDebugMode) {
          print('📦 Latest version from Play Store: $_latestVersion');
        }
        if (kDebugMode) {
          print('📝 Release notes length: ${_releaseNotes?.length ?? 0} characters');
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

      } else {
        _lastError = 'Failed to check for updates: HTTP ${response.statusCode}';
        if (kDebugMode) {
          print('❌ $_lastError');
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

  /// Parse version number from Play Store HTML
  String? _parseVersionFromHtml(String html) {
    try {
      // Look for version in various possible locations in the HTML
      final patterns = [
        RegExp(r'"softwareVersion"\s*:\s*"([^"]+)"'),
        RegExp(r'Current Version</div>[^<]*<span[^>]*>([^<]+)</span>'),
        RegExp(r'Version\s*([0-9]+(?:\.[0-9]+)*(?:\.[0-9]+)*)', caseSensitive: false),
      ];

      for (final pattern in patterns) {
        final match = pattern.firstMatch(html);
        if (match != null && match.group(1) != null) {
          String version = match.group(1)!.trim();
          // Clean up version string
          version = version.replaceAll(RegExp(r'[^\d\.]'), '');
          if (version.isNotEmpty && RegExp(r'^\d+(\.\d+)*$').hasMatch(version)) {
            if (kDebugMode) {
              print('✅ Found version using pattern: $version');
            }
            return version;
          }
        }
      }

      if (kDebugMode) {
        print('⚠️ Could not parse version from Play Store page');
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error parsing version: $e');
      }
      return null;
    }
  }

  /// Parse release notes from Play Store HTML
  String? _parseReleaseNotesFromHtml(String html) {
    try {
      // Look for "What's new" section in various possible locations
      final patterns = [
        RegExp(r'"recentChangesHTML"\s*:\s*"([^"]*)"'),
        RegExp(r"What's new</h2>[^<]*<div[^>]*>([^<]+)</div>", caseSensitive: false),
        RegExp(r'Recent changes[^<]*<div[^>]*>([^<]+)</div>', caseSensitive: false),
      ];

      for (final pattern in patterns) {
        final match = pattern.firstMatch(html);
        if (match != null && match.group(1) != null) {
          String notes = match.group(1)!
              .replaceAll('\\n', '\n')
              .replaceAll('\\u003c', '<')
              .replaceAll('\\u003e', '>')
              .replaceAll('&lt;', '<')
              .replaceAll('&gt;', '>')
              .replaceAll('&amp;', '&')
              .trim();

          if (notes.isNotEmpty) {
            if (kDebugMode) {
              print('✅ Found release notes');
            }
            return notes;
          }
        }
      }

      return 'Check the Play Store for the latest updates and improvements.';
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error parsing release notes: $e');
      }
      return 'Check the Play Store for the latest updates and improvements.';
    }
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

  /// Open Play Store for update
  Future<bool> openPlayStoreForUpdate() async {
    try {
      if (kDebugMode) {
        print('📱 Opening Play Store for update...');
      }

      final Uri playStoreUri = Uri.parse(_playStoreUrl);

      if (await canLaunchUrl(playStoreUri)) {
        await launchUrl(
          playStoreUri,
          mode: LaunchMode.externalApplication,
        );
        if (kDebugMode) {
          print('✅ Play Store opened successfully');
        }
        return true;
      } else {
        _lastError = 'Could not open Play Store';
        if (kDebugMode) {
          print('❌ $_lastError');
        }
        return false;
      }
    } catch (e) {
      _lastError = 'Error opening Play Store: $e';
      if (kDebugMode) {
        print('❌ $_lastError');
      }
      return false;
    }
  }

  /// Reset update state
  void resetUpdateState() {
    _updateAvailable = false;
    _latestVersion = null;
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
- Play Store URL: $_playStoreUrl
- Is Checking: $_isCheckingForUpdate
- Last Error: $_lastError
- Silent Mode: $_isSilentMode
- Package Name: $_packageName
    ''';
  }
}