import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../dialogs/bank_account_dialog.dart';
import '../../services/auth_service.dart';
import '../../services/banking_service.dart';
import '../../services/theme_service.dart';
import '../../services/database_service.dart';
import '../../services/biometric_service.dart';
import '../../models/user_model.dart';
import '../../dialogs/auth_dialogs.dart';
import 'notification_settings_screen.dart';
import '../../services/update_service.dart';
import '../../dialogs/update_dialog.dart';
import 'package:share_plus/share_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final DatabaseService _databaseService = DatabaseService();
  UserModel? _currentUser;
  bool _isLoading = true;

  UpdateService? _updateService;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _initializeUpdateService();
  }

  Future<void> _initializeUpdateService() async {
    _updateService = Provider.of<UpdateService>(context, listen: false);
    await _updateService?.initialize();
  }

  Future<void> _checkForUpdates() async {
    if (_updateService == null) return;

    // Show loading indicator
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 16),
            Text('Checking for updates...'),
          ],
        ),
        duration: Duration(seconds: 2),
      ),
    );

    final updateAvailable = await _updateService!.checkForUpdates();

    if (mounted) {
      await UpdateDialog.showUpdateCheckDialog(
        context,
        _updateService!,
        updateAvailable,
      );
    }
  }

  Future<void> _loadUserData() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      if (authService.currentUser != null) {
        UserModel? user = await _databaseService.getUser(authService.currentUser!.uid);

        // If user doesn't exist in database or name is missing, create/update it
        if (user == null) {
          if (kDebugMode) {
            print('⚠️ User not found in database, creating user record');
          }
          // Create user record with Firebase Auth data
          user = UserModel(
            id: authService.currentUser!.uid,
            name: authService.currentUser!.displayName ?? 'User',
            email: authService.currentUser!.email ?? '',
            photoUrl: authService.currentUser!.photoURL,
            groupIds: [], // Initialize with empty list
            createdAt: DateTime.now(),
          );
          await _databaseService.createUser(user);
        } else if (user.name.isEmpty && authService.currentUser!.displayName != null) {
          // Update user with name from Firebase Auth if it's missing
          if (kDebugMode) {
            print('⚠️ User name missing in database, updating with Firebase Auth name');
          }
          user = user.copyWith(name: authService.currentUser!.displayName!);
          await _databaseService.updateUser(user);
        }

        setState(() {
          _currentUser = user;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error loading user data: $e');
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _showEditNameDialog() async {
    if (_currentUser == null) return;

    final TextEditingController nameController = TextEditingController(text: _currentUser!.name);

    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.person_outline, color: Colors.blue.shade500),
            const SizedBox(width: 8),
            const Text('Edit Name'),
          ],
        ),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            labelText: 'Full Name',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            prefixIcon: const Icon(Icons.person),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isNotEmpty) {
                try {
                  final updatedUser = _currentUser!.copyWith(name: nameController.text.trim());
                  await _databaseService.updateUser(updatedUser);
                  setState(() {
                    _currentUser = updatedUser;
                  });
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Name updated successfully'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Error updating name'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  String _getBiometricSubtitle(BiometricService biometricService) {
    if (!biometricService.isDeviceSupported) {
      return 'Not supported on this device';
    }

    if (!biometricService.isBiometricAvailable) {
      if (biometricService.availableBiometrics.isEmpty) {
        return 'No biometrics enrolled - tap to set up';
      }
      return 'Not available - check device settings';
    }

    if (biometricService.isBiometricEnabled) {
      return '${biometricService.biometricTypeText} enabled';
    }

    return 'Tap to enable ${biometricService.biometricTypeText}';
  }

  Future<void> _handleBiometricTap(BiometricService biometricService) async {
    // Refresh status first
    await biometricService.refreshBiometricStatus();

    if (!biometricService.isDeviceSupported) {
      _showBiometricInfoDialog(
        'Device Not Supported',
        'Biometric authentication is not supported on this device.',
        Icons.error,
        Colors.red,
      );
      return;
    }

    if (!biometricService.isBiometricAvailable) {
      if (biometricService.availableBiometrics.isEmpty) {
        _showBiometricInfoDialog(
          'No Biometrics Enrolled',
          'Please set up fingerprint or face unlock in your device settings first, then come back to enable biometric authentication.',
          Icons.settings,
          Colors.orange,
          showSettingsButton: true,
        );
      } else {
        _showBiometricInfoDialog(
          'Biometric Not Available',
          biometricService.biometricStatusMessage,
          Icons.warning,
          Colors.orange,
        );
      }
      return;
    }

    // Biometric is available, proceed with enable/disable
    await _setupBiometric();
  }

  Future<void> _showBiometricInfoDialog(
      String title,
      String message,
      IconData icon,
      Color color, {
        bool showSettingsButton = false,
      }) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          if (showSettingsButton)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please set up biometrics in your device Settings > Security'),
                    duration: Duration(seconds: 4),
                  ),
                );
              },
              child: const Text('Open Settings'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _setupBiometric() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final biometricService = Provider.of<BiometricService>(context, listen: false);

    if (!biometricService.isBiometricAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Biometric authentication is not available on this device')),
      );
      return;
    }

    if (biometricService.isBiometricEnabled) {
      // Show disable dialog
      bool? shouldDisable = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(biometricService.biometricIcon, color: Colors.orange.shade500),
              const SizedBox(width: 8),
              Text('Disable ${biometricService.biometricTypeText}'),
            ],
          ),
          content: const Text('Are you sure you want to disable biometric authentication?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: const Text('Disable', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );

      if (shouldDisable == true) {
        await biometricService.disableBiometric();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${biometricService.biometricTypeText} disabled')),
        );
      }
      return;
    }

    // Show enable dialog
    final passwordController = TextEditingController();
    bool isPasswordVisible = false;

    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Row(
            children: [
              Icon(biometricService.biometricIcon, color: Colors.blue.shade500),
              const SizedBox(width: 8),
              Text('Enable ${biometricService.biometricTypeText}'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(biometricService.biometricIcon, size: 64, color: Colors.blue.shade500),
              const SizedBox(height: 16),
              Text(
                'Enable ${biometricService.biometricTypeText} for quick and secure access to Spendwise.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: passwordController,
                obscureText: !isPasswordVisible,
                decoration: InputDecoration(
                  labelText: 'Confirm your password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(isPasswordVisible ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => isPasswordVisible = !isPasswordVisible),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.security, color: Colors.green.shade600, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your credentials will be stored securely on this device.',
                        style: TextStyle(fontSize: 12, color: Colors.green.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (passwordController.text.isNotEmpty) {
                  Navigator.pop(context, true);
                }
              },
              child: const Text('Enable'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && passwordController.text.isNotEmpty) {
      bool success = await biometricService.enableBiometric(
        authService.currentUser!.email!,
        passwordController.text,
      );

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${biometricService.biometricTypeText} enabled successfully'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to enable ${biometricService.biometricTypeText}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _shareApp() async {
    try {
      PackageInfo packageInfo = await PackageInfo.fromPlatform();

      // Your actual GitHub repository download link
      const String downloadLink = 'https://github.com/dthys/spendwise/releases/latest/download/app-release.apk';

      await Share.share(
        '📱 *Download Spendwise v${packageInfo.version}*\n\n'
            '💰 Split expenses with friends easily!\n'
            '✨ Track shared expenses and settle debts effortlessly\n'
            '🎯 Perfect for group trips, shared meals, and roommate expenses\n\n'
            '📥 *Download here:*\n$downloadLink\n\n'
            '⚠️ *Installation:* Enable "Install from unknown sources" in Settings > Security\n\n'
            '🔒 Safe & Secure • Made with ❤️',
        subject: 'Try Spendwise - Split Expenses App!',
      );

      // Optional: Track sharing for analytics
      if (kDebugMode) {
        print('App shared via link');
      }

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sharing app: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showSignOutDialog() async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.logout, color: Colors.red.shade500),
            const SizedBox(width: 8),
            const Text('Sign Out'),
          ],
        ),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await Provider.of<AuthService>(context, listen: false).signOut();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sign Out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _launchEmail() async {
    final Uri emailUri = Uri(
      scheme: 'mailto',
      path: 'support@spendwise.app',
      query: 'subject=Spendwise Support Request',
    );

    if (await canLaunchUrl(emailUri)) {
      await launchUrl(emailUri);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open email app')),
      );
    }
  }

  Future<void> _showBankAccountDialog() async {
    String? newIBAN = await BankAccountDialog.showAddBankAccountDialog(
      context,
      currentIBAN: _currentUser?.bankAccount,
    );

    if (newIBAN != null && _currentUser != null) {
      try {
        final updatedUser = _currentUser!.copyWith(bankAccount: newIBAN);
        await _databaseService.updateUser(updatedUser);
        setState(() {
          _currentUser = updatedUser;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bankrekening succesvol bijgewerkt'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fout bij bijwerken bankrekening'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _launchPlayStore() async {
    final Uri playStoreUri = Uri.parse('https://play.google.com/store/apps/details?id=com.yourcompany.spendwise');

    if (await canLaunchUrl(playStoreUri)) {
      await launchUrl(playStoreUri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Coming soon to Google Play Store!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        foregroundColor: Theme.of(context).appBarTheme.foregroundColor,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // User Profile Section
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    backgroundImage: _currentUser?.photoUrl != null
                        ? NetworkImage(_currentUser!.photoUrl!)
                        : null,
                    child: _currentUser?.photoUrl == null
                        ? const Icon(
                      Icons.person,
                      size: 50,
                      color: Colors.white,
                    )
                        : null,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _currentUser?.name ?? 'User',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _currentUser?.email ?? '',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Settings Options
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  // Account Section
                  _buildSectionHeader('Account'),
                  _buildSettingsTile(
                    icon: Icons.person_outline,
                    title: 'Edit Name',
                    subtitle: 'Change your display name',
                    onTap: _showEditNameDialog,
                  ),
                  _buildSettingsTile(
                    icon: Icons.email_outlined,
                    title: 'Email',
                    subtitle: _currentUser?.email ?? '',
                    onTap: () {
                      AuthDialogs.showChangeEmailDialog(context, _currentUser?.email ?? '');
                    },
                  ),
                  _buildSettingsTile(
                    icon: Icons.account_balance,
                    title: 'Bankrekening',
                    subtitle: _currentUser?.bankAccount != null
                        ? 'IBAN: ${BankingService.formatIBAN(_currentUser!.bankAccount!)}'
                        : 'Geen bankrekening toegevoegd',
                    onTap: _showBankAccountDialog,
                    trailing: _currentUser?.bankAccount != null
                        ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                        : Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey.shade400),
                  ),

                  const SizedBox(height: 24),

                  // Appearance Section
                  _buildSectionHeader('Appearance'),
                  Consumer<ThemeService>(
                    builder: (context, themeService, child) {
                      return _buildSettingsTile(
                        icon: themeService.currentThemeIcon,
                        title: 'Theme',
                        subtitle: themeService.currentThemeName,
                        onTap: () => themeService.toggleTheme(),
                        trailing: Switch(
                          value: themeService.themeMode == ThemeMode.dark,
                          onChanged: (value) => themeService.toggleTheme(),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  // Security Section
                  _buildSectionHeader('Security'),
                  Consumer<BiometricService>(
                    builder: (context, biometricService, child) {
                      return _buildSettingsTile(
                        icon: biometricService.biometricIcon,
                        title: 'Biometric Authentication',
                        subtitle: _getBiometricSubtitle(biometricService),
                        onTap: () => _handleBiometricTap(biometricService),
                        trailing: biometricService.isBiometricAvailable
                            ? Switch(
                          value: biometricService.isBiometricEnabled,
                          onChanged: (value) => _handleBiometricTap(biometricService),
                        )
                            : Icon(
                          Icons.info_outline,
                          color: Colors.orange.shade500,
                        ),
                      );
                    },
                  ),
                  _buildSettingsTile(
                    icon: Icons.lock_outline,
                    title: 'Change Password',
                    subtitle: 'Update your account password',
                    onTap: () {
                      AuthDialogs.showChangePasswordDialog(context);
                    },
                  ),

                  const SizedBox(height: 24),

                  // Notifications Section - Now simplified to single tile
                  _buildSectionHeader('Notifications'),
                  _buildSettingsTile(
                    icon: Icons.notifications_outlined,
                    title: 'Notification Settings',
                    subtitle: 'Manage your notification preferences',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const NotificationSettingsScreen(),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 24),

                  // Support Section
                  _buildSectionHeader('Support & Feedback'),
                  _buildSettingsTile(
                    icon: Icons.share,
                    title: 'Share Spendwise',
                    subtitle: 'Share this app with friends',
                    onTap: _shareApp,
                  ),
                  _buildSettingsTile(
                    icon: Icons.star_outline,
                    title: 'Rate Spendwise',
                    subtitle: 'Rate us on Google Play Store',
                    onTap: _launchPlayStore,
                  ),
                  _buildSettingsTile(
                    icon: Icons.support_agent,
                    title: 'Contact Support',
                    subtitle: 'Get help with your account',
                    onTap: _launchEmail,
                  ),
                  Consumer<UpdateService>(
                    builder: (context, updateService, child) {
                      return _buildSettingsTile(
                        icon: Icons.system_update,
                        title: 'Check for Updates',
                        subtitle: updateService.currentVersion != null
                            ? 'Current version: ${updateService.currentVersion}'
                            : 'Tap to check for updates',
                        onTap: _checkForUpdates,
                        trailing: updateService.isCheckingForUpdate
                            ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                            : updateService.updateAvailable
                            ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'NEW',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                            : Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey.shade400),
                      );
                    },
                  ),
                  Consumer<UpdateService>(
                    builder: (context, updateService, child) {
                      return _buildSettingsTile(
                        icon: Icons.info_outline,
                        title: 'About Spendwise',
                        subtitle: updateService.currentVersion != null
                            ? 'Version ${updateService.currentVersion}'
                            : 'Version 1.0.0',
                        onTap: () {
                          showAboutDialog(
                            context: context,
                            applicationName: 'Spendwise',
                            applicationVersion: updateService.currentVersion ?? '1.0.0',
                            applicationIcon: Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: Colors.blue.shade500,
                                borderRadius: BorderRadius.circular(15),
                              ),
                              child: const Icon(
                                Icons.account_balance_wallet,
                                color: Colors.white,
                                size: 30,
                              ),
                            ),
                            children: [
                              const Text('Split expenses with friends easily and efficiently.'),
                              const SizedBox(height: 16),
                              const Text('Made with ❤️ for easy expense sharing'),
                            ],
                          );
                        },
                      );
                    },
                  ),

                  const SizedBox(height: 32),

                  // Sign Out Button
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ElevatedButton.icon(
                      onPressed: _showSignOutDialog,
                      icon: const Icon(Icons.logout, color: Colors.white),
                      label: const Text(
                        'Sign Out',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade500,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).primaryColor,
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: Theme.of(context).cardColor,
      child: ListTile(
        leading: Icon(
          icon,
          color: Theme.of(context).primaryColor,
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 14,
          ),
        ),
        trailing: trailing ?? Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: Colors.grey.shade400,
        ),
        onTap: onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}