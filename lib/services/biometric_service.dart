import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class BiometricService extends ChangeNotifier {
  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  static const String _biometricEnabledKey = 'biometric_enabled';
  static const String _biometricCredentialsKey = 'biometric_credentials';

  bool _isBiometricEnabled = false;
  bool _isBiometricAvailable = false;
  bool _isDeviceSupported = false;
  List<BiometricType> _availableBiometrics = [];

  bool get isBiometricEnabled => _isBiometricEnabled;
  bool get isBiometricAvailable => _isBiometricAvailable;
  bool get isDeviceSupported => _isDeviceSupported;
  List<BiometricType> get availableBiometrics => _availableBiometrics;

  BiometricService() {
    _initializeBiometric();
  }

  Future<void> _initializeBiometric() async {
    try {
      if (kDebugMode) {
        print('🔍 Initializing biometric authentication...');
      }

      // Check if device supports biometric
      _isDeviceSupported = await _localAuth.isDeviceSupported();
      if (kDebugMode) {
        print('📱 Device supported: $_isDeviceSupported');
      }

      if (!_isDeviceSupported) {
        if (kDebugMode) {
          print('❌ Device does not support biometric authentication');
        }
        notifyListeners();
        return;
      }

      // Check if biometric is available (hardware + enrolled)
      _isBiometricAvailable = await _localAuth.canCheckBiometrics;
      if (kDebugMode) {
        print('🔐 Can check biometrics: $_isBiometricAvailable');
      }

      if (_isBiometricAvailable) {
        _availableBiometrics = await _localAuth.getAvailableBiometrics();
        if (kDebugMode) {
          print('📋 Available biometrics: $_availableBiometrics');
        }
      } else {
        if (kDebugMode) {
          print('⚠️ Biometric not available - checking why...');
        }

        // Try to get more specific info
        try {
          await _localAuth.authenticate(
            localizedReason: 'Test biometric availability',
            options: const AuthenticationOptions(
              biometricOnly: true,
              stickyAuth: false,
            ),
          );
        } catch (e) {
          if (kDebugMode) {
            print('🔍 Biometric test error: $e');
          }
          if (e.toString().contains('NotEnrolled')) {
            if (kDebugMode) {
              print('👆 No biometrics enrolled on device');
            }
          } else if (e.toString().contains('NotAvailable')) {
            if (kDebugMode) {
              print('📱 Biometric hardware not available');
            }
          }
        }
      }

      // Load user's biometric preference
      String? enabled = await _secureStorage.read(key: _biometricEnabledKey);
      _isBiometricEnabled = enabled == 'true' && _isBiometricAvailable;

      if (kDebugMode) {
        print('✅ Biometric initialization complete:');
      }
      if (kDebugMode) {
        print('   - Device supported: $_isDeviceSupported');
      }
      if (kDebugMode) {
        print('   - Available: $_isBiometricAvailable');
      }
      if (kDebugMode) {
        print('   - User enabled: $_isBiometricEnabled');
      }
      if (kDebugMode) {
        print('   - Types: $_availableBiometrics');
      }

      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error initializing biometric: $e');
      }
      _isBiometricAvailable = false;
      _isDeviceSupported = false;
      notifyListeners();
    }
  }

  String get biometricTypeText {
    if (_availableBiometrics.isEmpty) return 'Not available';

    if (_availableBiometrics.contains(BiometricType.face)) {
      return 'Face ID';
    } else if (_availableBiometrics.contains(BiometricType.fingerprint)) {
      return 'Fingerprint';
    } else if (_availableBiometrics.contains(BiometricType.iris)) {
      return 'Iris';
    } else if (_availableBiometrics.contains(BiometricType.strong)) {
      return 'Biometric';
    } else if (_availableBiometrics.contains(BiometricType.weak)) {
      return 'Screen Lock';
    } else {
      return 'Biometric';
    }
  }

  IconData get biometricIcon {
    if (_availableBiometrics.isEmpty) return Icons.security;

    if (_availableBiometrics.contains(BiometricType.face)) {
      return Icons.face;
    } else if (_availableBiometrics.contains(BiometricType.fingerprint)) {
      return Icons.fingerprint;
    } else {
      return Icons.security;
    }
  }

  String get biometricStatusMessage {
    if (!_isDeviceSupported) {
      return 'Biometric authentication is not supported on this device';
    }

    if (!_isBiometricAvailable) {
      if (_availableBiometrics.isEmpty) {
        return 'No biometrics enrolled. Please set up fingerprint or face unlock in your device settings.';
      }
      return 'Biometric authentication is not available. Please check your device settings.';
    }

    return 'Biometric authentication is available';
  }

  Future<bool> authenticateWithBiometric({
    required String reason,
    bool biometricOnly = false,
  }) async {
    try {
      if (kDebugMode) {
        print('🔐 Attempting biometric authentication...');
      }

      if (!_isDeviceSupported) {
        if (kDebugMode) {
          print('❌ Device not supported');
        }
        throw PlatformException(
          code: 'NotSupported',
          message: 'Biometric authentication is not supported on this device',
        );
      }

      if (!_isBiometricAvailable) {
        if (kDebugMode) {
          print('❌ Biometric not available');
        }
        throw PlatformException(
          code: 'NotAvailable',
          message: biometricStatusMessage,
        );
      }

      final bool authenticated = await _localAuth.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          biometricOnly: biometricOnly,
          stickyAuth: true,
        ),
      );

      if (kDebugMode) {
        print('🔐 Authentication result: $authenticated');
      }
      return authenticated;
    } on PlatformException catch (e) {
      if (kDebugMode) {
        print('❌ Biometric authentication error: $e');
      }

      if (e.code == 'NotEnrolled') {
        throw PlatformException(
          code: 'NotEnrolled',
          message: 'No biometrics enrolled. Please set up fingerprint or face unlock in your device settings.',
        );
      }

      return false;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Unexpected biometric error: $e');
      }
      return false;
    }
  }

  Future<bool> enableBiometric(String userEmail, String password) async {
    try {
      if (kDebugMode) {
        print('🔐 Enabling biometric authentication...');
      }

      // Check availability again
      if (!_isBiometricAvailable) {
        await _initializeBiometric(); // Refresh status
        if (!_isBiometricAvailable) {
          throw PlatformException(
            code: 'NotAvailable',
            message: biometricStatusMessage,
          );
        }
      }

      // First verify with biometric
      bool authenticated = await authenticateWithBiometric(
        reason: 'Enable biometric authentication for Spendwise',
        biometricOnly: true,
      );

      if (!authenticated) {
        if (kDebugMode) {
          print('❌ Biometric authentication failed');
        }
        return false;
      }

      // Store encrypted credentials for future auto-login
      await _secureStorage.write(
        key: _biometricCredentialsKey,
        value: '$userEmail:$password', // In production, encrypt this better
      );

      await _secureStorage.write(key: _biometricEnabledKey, value: 'true');

      _isBiometricEnabled = true;
      notifyListeners();

      if (kDebugMode) {
        print('✅ Biometric authentication enabled successfully');
      }
      return true;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error enabling biometric: $e');
      }
      return false;
    }
  }

  Future<void> disableBiometric() async {
    try {
      await _secureStorage.delete(key: _biometricEnabledKey);
      await _secureStorage.delete(key: _biometricCredentialsKey);

      _isBiometricEnabled = false;
      notifyListeners();

      if (kDebugMode) {
        print('✅ Biometric authentication disabled');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error disabling biometric: $e');
      }
    }
  }

  Future<Map<String, String>?> getBiometricCredentials() async {
    try {
      if (!_isBiometricEnabled) return null;

      String? credentials = await _secureStorage.read(key: _biometricCredentialsKey);
      if (credentials == null) return null;

      List<String> parts = credentials.split(':');
      if (parts.length != 2) return null;

      return {
        'email': parts[0],
        'password': parts[1],
      };
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error getting biometric credentials: $e');
      }
      return null;
    }
  }

  Future<bool> authenticateForAppAccess() async {
    if (!_isBiometricEnabled) return true; // Not enabled, allow access

    try {
      return await authenticateWithBiometric(
        reason: 'Authenticate to access Spendwise',
        biometricOnly: true,
      );
    } catch (e) {
      if (kDebugMode) {
        print('❌ App access authentication failed: $e');
      }
      return false;
    }
  }

  // Method to refresh biometric status (useful for settings screen)
  Future<void> refreshBiometricStatus() async {
    await _initializeBiometric();
  }

  // Check if user should be prompted to set up biometrics
  bool get shouldPromptForBiometric {
    return _isDeviceSupported &&
        _isBiometricAvailable &&
        !_isBiometricEnabled &&
        _availableBiometrics.isNotEmpty;
  }
}