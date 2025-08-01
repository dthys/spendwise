import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart';
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
  Intl.defaultLocale = 'nl_NL';

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
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [
              Locale('en', 'US'),
              Locale('nl', 'NL'),
              Locale('de', 'DE'),
              Locale('fr', 'FR'),
              Locale('es', 'ES'),
              Locale('it', 'IT'),
            ],
            locale: const Locale('nl', 'NL'),
            theme: AppThemes.lightTheme,
            darkTheme: AppThemes.darkTheme,
            themeMode: themeService.themeMode,

            // Use ExtendedSplashScreen for longer, smoother loading
            home: const ExtendedSplashScreen(),

            routes: {
              '/activity-log': (context) {
                final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
                return ActivityLogScreen(groupId: args['groupId']);
              },
            },

            builder: (context, child) {
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(1.0),
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

// New Extended Splash Screen that handles all initialization
class ExtendedSplashScreen extends StatefulWidget {
  const ExtendedSplashScreen({super.key});

  @override
  _ExtendedSplashScreenState createState() => _ExtendedSplashScreenState();
}

class _ExtendedSplashScreenState extends State<ExtendedSplashScreen> {
  bool _isInitialized = false;
  String _loadingText = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // Phase 1: Basic initialization
      setState(() {
        _loadingText = 'Setting up services...';
      });
      await Future.delayed(const Duration(milliseconds: 500));

      // Phase 2: Wait for providers to be ready
      setState(() {
        _loadingText = 'Loading user data...';
      });
      await Future.delayed(const Duration(milliseconds: 800));

      // Phase 3: Pre-warm cache and complete setup
      setState(() {
        _loadingText = 'Finalizing...';
      });
      await Future.delayed(const Duration(milliseconds: 500));

      // Mark as initialized
      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error during initialization: $e');
      }
      // Still proceed to avoid infinite loading
      setState(() {
        _isInitialized = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: Theme.of(context).primaryColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // App Logo/Icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.account_balance_wallet,
                  size: 40,
                  color: Theme.of(context).primaryColor,
                ),
              ),
              const SizedBox(height: 32),

              // App Name
              const Text(
                'Spendwise',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),

              // Tagline
              Text(
                'Smart expense splitting',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 48),

              // Loading indicator
              const CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              ),
              const SizedBox(height: 16),

              // Loading text
              Text(
                _loadingText,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Once initialized, show the auth wrapper
    return const AuthWrapper();
  }
}

// Optimized AuthWrapper with better silent handling
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  _AuthWrapperState createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _hasAuthenticatedBiometric = false;
  bool _servicesInitialized = false;
  bool _hasCheckedForUpdates = false;
  Timer? _bannerTimer;
  Timer? _updateCheckTimer;

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _updateCheckTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer4<AuthService, BiometricService, NotificationService, UpdateService>(
      builder: (context, authService, biometricService, notificationService, updateService, child) {

        // Initialize all services together when user is authenticated
        if (authService.currentUser != null && !_servicesInitialized) {
          _initializeAllServices(notificationService, updateService);
        }

        if (authService.isLoading) {
          return _buildLoadingScreen();
        }

        if (authService.currentUser != null) {
          // User is logged in - check biometric ONLY if not already authenticated
          if (biometricService.isBiometricEnabled && !_hasAuthenticatedBiometric) {
            return _buildBiometricScreen(biometricService, authService);
          } else {
            // Show home screen
            return _buildHomeScreen(authService);
          }
        } else {
          // Not logged in - reset flags
          _resetAuthenticationState();
          return LoginScreen();
        }
      },
    );
  }

  // Consolidated service initialization with ENHANCED SILENT MODE
  void _initializeAllServices(NotificationService notificationService, UpdateService updateService) {
    _servicesInitialized = true;

    // Run all initializations together to avoid multiple state changes
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        // Initialize services in parallel
        await Future.wait([
          _initializeNotifications(notificationService),
          _initializeUpdateService(updateService),
        ]);

        if (kDebugMode) {
          print('✅ All services initialized');
        }

        // CRITICAL: Enable UI updates for UpdateService AFTER app is fully loaded
        await Future.delayed(const Duration(milliseconds: 500));
        updateService.enableUIUpdates();

        // Start the delayed update check timer (15 seconds after full load)
        _scheduleBackgroundUpdateCheck(updateService);

      } catch (e) {
        if (kDebugMode) {
          print('❌ Service initialization error: $e');
        }
      }
    });
  }

  Future<void> _initializeNotifications(NotificationService notificationService) async {
    try {
      await notificationService.initialize(context);
      if (kDebugMode) {
        print('✅ Notifications initialized');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to initialize notifications: $e');
      }
    }
  }

  Future<void> _initializeUpdateService(UpdateService updateService) async {
    try {
      // Initialize in SILENT mode to prevent UI flashes
      await updateService.initialize();

      if (kDebugMode) {
        print('✅ UpdateService initialized (silent mode)');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Failed to initialize UpdateService: $e');
      }
    }
  }

  // Schedule update check much later to avoid any startup interference
  void _scheduleBackgroundUpdateCheck(UpdateService updateService) {
    if (_hasCheckedForUpdates) return;

    _updateCheckTimer = Timer(const Duration(seconds: 15), () async {
      if (!mounted) return;

      _hasCheckedForUpdates = true;

      try {
        if (kDebugMode) {
          print('🔄 Starting scheduled background update check...');
        }

        final updateAvailable = await updateService.checkForUpdatesOnce(silent: true);

        if (updateAvailable && mounted) {
          if (kDebugMode) {
            print('🔄 Update available! Showing subtle notification...');
          }
          // Small additional delay to ensure no interference
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) {
            _showUpdateBanner(updateService);
          }
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

  void _resetAuthenticationState() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_hasAuthenticatedBiometric || _servicesInitialized) {
        setState(() {
          _hasAuthenticatedBiometric = false;
          _servicesInitialized = false;
          _hasCheckedForUpdates = false;
        });
        _bannerTimer?.cancel();
        _updateCheckTimer?.cancel();
      }
    });
  }

  Widget _buildLoadingScreen() {
    return Scaffold(
      backgroundColor: Theme.of(context).primaryColor,
      body: const Center(
        child: CircularProgressIndicator(
          color: Colors.white,
          strokeWidth: 3,
        ),
      ),
    );
  }

  Widget _buildBiometricScreen(BiometricService biometricService, AuthService authService) {
    return FutureBuilder<bool>(
      future: biometricService.authenticateForAppAccess(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    biometricService.biometricIcon,
                    size: 64,
                    color: Theme.of(context).primaryColor,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Authenticating with ${biometricService.biometricTypeText}...',
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  CircularProgressIndicator(
                    color: Theme.of(context).primaryColor,
                  ),
                ],
              ),
            ),
          );
        }

        if (snapshot.data == false) {
          return _buildBiometricFailureScreen(biometricService, authService);
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

  Widget _buildBiometricFailureScreen(BiometricService biometricService, AuthService authService) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                _resetAuthenticationState();
              },
              child: const Text('Sign Out'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeScreen(AuthService authService) {
    return FutureBuilder<void>(
      future: ensureUserInFirestore(authService.currentUser!),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingScreen();
        }
        return const HomeScreen();
      },
    );
  }

  void _showUpdateBanner(UpdateService updateService) {
    if (!mounted) return;

    _bannerTimer?.cancel();

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

              await Future.delayed(const Duration(milliseconds: 100));

              if (mounted) {
                await UpdateDialog.showUpdateCheckDialog(
                  context,
                  updateService,
                  true,
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

      UserModel? existingUser = await dbService.getUser(user.uid);

      if (existingUser == null) {
        if (kDebugMode) {
          print('User not in Firestore, creating: ${user.email}');
        }
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
    }
  }
}