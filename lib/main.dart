import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthService()),
        ChangeNotifierProvider(create: (_) => ThemeService()),
        ChangeNotifierProvider(create: (_) => BiometricService()),
        ChangeNotifierProvider(create: (_) => NotificationService()), // Add this
      ],
      child: Consumer<ThemeService>(
        builder: (context, themeService, child) {
          return MaterialApp(
            title: 'Spendwise',
            debugShowCheckedModeBanner: false,

            // Updated Theme Configuration
            theme: AppThemes.lightTheme,
            darkTheme: AppThemes.darkTheme,
            themeMode: themeService.themeMode,

            // Start with splash screen instead of AuthWrapper
            home: SplashScreen(
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
                  textScaleFactor: 1.0, // Prevent font scaling issues
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

class AuthWrapper extends StatefulWidget {
  @override
  _AuthWrapperState createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _hasAuthenticatedBiometric = false; // Track if we've already done biometric auth
  bool _notificationsInitialized = false; // Track notification initialization

  @override
  Widget build(BuildContext context) {
    return Consumer3<AuthService, BiometricService, NotificationService>(
      builder: (context, authService, biometricService, notificationService, child) {
        // Initialize notifications when user is authenticated
        if (authService.currentUser != null && !_notificationsInitialized) {
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            try {
              await notificationService.initialize(context);
              setState(() {
                _notificationsInitialized = true;
              });
              print('✅ Notifications initialized');
            } catch (e) {
              print('❌ Failed to initialize notifications: $e');
            }
          });
        }

        if (authService.isLoading) {
          return Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (authService.currentUser != null) {
          // User is logged in - check biometric ONLY if not already authenticated
          if (biometricService.isBiometricEnabled && !_hasAuthenticatedBiometric) {
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
                          SizedBox(height: 16),
                          Text(
                            'Authenticating with ${biometricService.biometricTypeText}...',
                            style: TextStyle(fontSize: 16),
                          ),
                          SizedBox(height: 24),
                          CircularProgressIndicator(),
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
                          SizedBox(height: 16),
                          Text(
                            'Authentication Required',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text('Please authenticate to access Spendwise'),
                          SizedBox(height: 24),
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
                          SizedBox(height: 16),
                          TextButton(
                            onPressed: () {
                              authService.signOut();
                              setState(() {
                                _hasAuthenticatedBiometric = false;
                                _notificationsInitialized = false;
                              });
                            },
                            child: Text('Sign Out'),
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
          } else {
            // No biometric required OR already authenticated
            return _buildHomeScreen(authService);
          }
        } else {
          // Not logged in - reset flags
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_hasAuthenticatedBiometric || _notificationsInitialized) {
              setState(() {
                _hasAuthenticatedBiometric = false;
                _notificationsInitialized = false;
              });
            }
          });

          return LoginScreen();
        }
      },
    );
  }

  Widget _buildHomeScreen(AuthService authService) {
    return FutureBuilder<void>(
      future: ensureUserInFirestore(authService.currentUser!),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return HomeScreen();
      },
    );
  }

  Future<void> ensureUserInFirestore(User user) async {
    try {
      final DatabaseService dbService = DatabaseService();

      // Check if user exists in Firestore
      UserModel? existingUser = await dbService.getUser(user.uid);

      if (existingUser == null) {
        print('User not in Firestore, creating: ${user.email}');
        // Create user in Firestore
        final userModel = UserModel.fromFirebaseUser(
          user.uid,
          user.displayName ?? 'User',
          user.email ?? '',
          user.photoURL,
        );
        await dbService.createUser(userModel);
        print('User created in Firestore successfully!');
      } else {
        print('User already exists in Firestore: ${existingUser.email}');
      }
    } catch (e) {
      print('Error ensuring user in Firestore: $e');
      // Don't block the UI for this
    }
  }
}