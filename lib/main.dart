import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart'; // ADD THIS
import 'package:intl/intl.dart'; // ADD THIS
import 'package:spendwise/services/database_service.dart';
import 'models/user_model.dart';
import 'services/auth_service.dart';
import 'services/theme_service.dart';
import 'services/biometric_service.dart';
import 'services/notification_service.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/splash/splash_screen.dart';
import 'screens/expenses/activity_log_screen.dart';
import 'services/update_service.dart';
import 'dialogs/update_dialog.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  // Set default locale for number formatting to EU format
  Intl.defaultLocale = 'nl_NL'; // Dutch locale uses comma for decimals

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => ThemeService()),
        ChangeNotifierProvider(create: (_) => BiometricService()),
        ChangeNotifierProvider(create: (_) => NotificationService()),
        ChangeNotifierProvider(create: (_) => UpdateService()),
      ],
      child: Consumer<ThemeService>(
        builder: (context, themeService, child) {
          return MaterialApp(
            title: 'Spendwise',
            debugShowCheckedModeBanner: false,

            // ADD LOCALIZATION SUPPORT
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [
              Locale('en', 'US'), // English (US)
              Locale('nl', 'NL'), // Dutch (Netherlands) - uses EU formatting
              Locale('de', 'DE'), // German (Germany) - uses EU formatting
              Locale('fr', 'FR'), // French (France) - uses EU formatting
              Locale('es', 'ES'), // Spanish (Spain) - uses EU formatting
              Locale('it', 'IT'), // Italian (Italy) - uses EU formatting
            ],
            // Set default locale to Dutch for EU number formatting
            locale: const Locale('nl', 'NL'),

            // Updated Theme Configuration
            theme: AppThemes.lightTheme,
            darkTheme: AppThemes.darkTheme,
            themeMode: themeService.themeMode,

            // Start with splash screen instead of AuthWrapper
            home: const SplashScreen(
              nextScreen: AuthWrapper(),
            ),

            // Add navigation routes
            routes: {
              '/activity-log': (context) {
                final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
                return ActivityLogScreen(groupId: args['groupId']);
              },
            },

            // Global theme overrides if needed
            builder: (context, child) {
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(1.0), // Prevent font scaling issues
                ),
                child: child!,
              );
            },
          );
        },
      ),
    );
  }
}

// Rest of your code remains exactly the same...
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  _AuthWrapperState createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _hasAuthenticatedBiometric = false;
  bool _notificationsInitialized = false;
  bool _updateServiceInitialized = false;
  bool _hasCheckedForUpdates = false;
  Timer? _bannerTimer;

  @override
  void dispose() {
    _bannerTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer4<AuthService, BiometricService, NotificationService, UpdateService>(
      builder: (context, authService, biometricService, notificationService, updateService, child) {

        // Initialize UpdateService when user is authenticated
        if (authService.currentUser != null && !_updateServiceInitialized) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            try {
              await updateService.initialize();
              setState(() {
                _updateServiceInitialized = true;
              });
              if (kDebugMode) {
                print('✅ UpdateService initialized');
              }

              // Background update check - no flash!
              if (!_hasCheckedForUpdates) {
                _checkForUpdatesInBackground(updateService);
              }
            } catch (e) {
              if (kDebugMode) {
                print('❌ Failed to initialize UpdateService: $e');
              }
            }
          });
        }

        // Initialize notifications when user is authenticated
        if (authService.currentUser != null && !_notificationsInitialized) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            try {
              await notificationService.initialize(context);
              setState(() {
                _notificationsInitialized = true;
              });
              if (kDebugMode) {
                print('✅ Notifications initialized');
              }
            } catch (e) {
              if (kDebugMode) {
                print('❌ Failed to initialize notifications: $e');
              }
            }
          });
        }

        if (authService.isLoading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (authService.currentUser != null) {
          // User is logged in - check biometric ONLY if not already authenticated
          if (biometricService.isBiometricEnabled && !_hasAuthenticatedBiometric) {
            return _buildBiometricScreen(biometricService, authService);
          } else {
            // No biometric required OR already authenticated
            return _buildHomeScreen(authService);
          }
        } else {
          // Not logged in - reset flags
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_hasAuthenticatedBiometric || _notificationsInitialized || _updateServiceInitialized) {
              setState(() {
                _hasAuthenticatedBiometric = false;
                _notificationsInitialized = false;
                _updateServiceInitialized = false;
                _hasCheckedForUpdates = false;
              });
              // Cancel any existing banner timer
              _bannerTimer?.cancel();
            }
          });

          return LoginScreen();
        }
      },
    );
  }

  Widget _buildBiometricScreen(BiometricService biometricService, AuthService authService) {
    return FutureBuilder<bool>(
      future: biometricService.authenticateForAppAccess(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    biometricService.biometricIcon,
                    size: 64,
                    color: Colors.blue.shade500,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Authenticating with ${biometricService.biometricTypeText}...',
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  const CircularProgressIndicator(),
                ],
              ),
            ),
          );
        }

        if (snapshot.data == false) {
          // Biometric failed, show alternative
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock,
                    size: 64,
                    color: Colors.red.shade500,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Authentication Required',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text('Please authenticate to access Spendwise'),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () async {
                      bool success = await biometricService.authenticateForAppAccess();
                      if (success) {
                        setState(() {
                          _hasAuthenticatedBiometric = true;
                        });
                      }
                    },
                    icon: Icon(biometricService.biometricIcon),
                    label: Text('Try ${biometricService.biometricTypeText} Again'),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () {
                      authService.signOut();
                      setState(() {
                        _hasAuthenticatedBiometric = false;
                        _notificationsInitialized = false;
                        _updateServiceInitialized = false;
                      });
                    },
                    child: const Text('Sign Out'),
                  ),
                ],
              ),
            ),
          );
        }

        // Biometric success - mark as authenticated and proceed
        WidgetsBinding.instance.addPostFrameCallback((_) {
          setState(() {
            _hasAuthenticatedBiometric = true;
          });
        });

        return _buildHomeScreen(authService);
      },
    );
  }

  Widget _buildHomeScreen(AuthService authService) {
    return FutureBuilder<void>(
      future: ensureUserInFirestore(authService.currentUser!),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return const HomeScreen();
      },
    );
  }

  /// Background update check - shows subtle notification instead of modal
  /// This runs completely in the background without blocking the UI
  Future<void> _checkForUpdatesInBackground(UpdateService updateService) async {
    if (_hasCheckedForUpdates) return;
    _hasCheckedForUpdates = true;

    // Run completely in background - no UI blocking
    _runInBackground(() async {
      try {
        // Wait for app to be fully loaded and settled
        await Future.delayed(const Duration(seconds: 5));

        if (!mounted) return;

        if (kDebugMode) {
          print('🔄 Background update check starting...');
        }
        final updateAvailable = await updateService.checkForUpdatesOnce(silent: true);

        if (updateAvailable && mounted) {
          if (kDebugMode) {
            print('🔄 Update available! Showing subtle notification...');
          }

          // Show subtle banner instead of blocking dialog
          _showUpdateBanner(updateService);
        } else {
          if (kDebugMode) {
            print('🔄 No updates available or widget not mounted');
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('❌ Background update check failed: $e');
        }
      }
    });
  }

  /// Helper to run async operations without awaiting (fire and forget)
  void _runInBackground(Future<void> Function() operation) {
    operation();
  }

  /// Shows a subtle material banner instead of a blocking dialog
  void _showUpdateBanner(UpdateService updateService) {
    if (!mounted) return;

    // Cancel any existing banner timer
    _bannerTimer?.cancel();

    // Show the banner
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        leading: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.blue.shade600,
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Icon(
            Icons.system_update,
            color: Colors.white,
            size: 20,
          ),
        ),
        backgroundColor: Colors.blue.shade50,
        surfaceTintColor: Colors.blue.shade100,
        shadowColor: Colors.blue.shade200,
        elevation: 2,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Update Available (v${updateService.latestVersion})',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade800,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'A new version is ready to download with improvements and bug fixes',
              style: TextStyle(
                color: Colors.blue.shade700,
                fontSize: 13,
                height: 1.2,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              _bannerTimer?.cancel();
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.blue.shade700,
            ),
            child: const Text('Later'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              _bannerTimer?.cancel();

              // Small delay to prevent any flash
              await Future.delayed(const Duration(milliseconds: 100));

              if (mounted) {
                await UpdateDialog.showUpdateCheckDialog(
                  context,
                  updateService,
                  true, // updateAvailable = true
                );
              }
            },
            icon: const Icon(Icons.download, size: 16),
            label: const Text('Update'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade600,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
          ),
        ],
      ),
    );

    // Auto-hide the banner after 12 seconds
    _bannerTimer = Timer(const Duration(seconds: 12), () {
      if (mounted) {
        try {
          ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
        } catch (e) {
          if (kDebugMode) {
            print('Banner already hidden: $e');
          }
        }
      }
    });

    if (kDebugMode) {
      print('✅ Update banner shown - will auto-hide in 12 seconds');
    }
  }

  Future<void> ensureUserInFirestore(User user) async {
    try {
      final DatabaseService dbService = DatabaseService();

      // Check if user exists in Firestore
      UserModel? existingUser = await dbService.getUser(user.uid);

      if (existingUser == null) {
        if (kDebugMode) {
          print('User not in Firestore, creating: ${user.email}');
        }
        // Create user in Firestore
        final userModel = UserModel.fromFirebaseUser(
          user.uid,
          user.displayName ?? 'User',
          user.email ?? '',
          user.photoURL,
        );
        await dbService.createUser(userModel);
        if (kDebugMode) {
          print('User created in Firestore successfully!');
        }
      } else {
        if (kDebugMode) {
          print('User already exists in Firestore: ${existingUser.email}');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error ensuring user in Firestore: $e');
      }
      // Don't block the UI for this
    }
  }
}