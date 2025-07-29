import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';

class AuthDialogs {

  // Change Password Dialog
  static Future<void> showChangePasswordDialog(BuildContext context) async {
    final _formKey = GlobalKey<FormState>();
    final _currentPasswordController = TextEditingController();
    final _newPasswordController = TextEditingController();
    final _confirmPasswordController = TextEditingController();
    bool _isCurrentPasswordVisible = false;
    bool _isNewPasswordVisible = false;
    bool _isConfirmPasswordVisible = false;

    return showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.lock_outline, color: Colors.blue.shade500),
              SizedBox(width: 8),
              Text('Change Password'),
            ],
          ),
          content: Container(
            width: double.maxFinite,
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Current Password
                  TextFormField(
                    controller: _currentPasswordController,
                    obscureText: !_isCurrentPasswordVisible,
                    decoration: InputDecoration(
                      labelText: 'Current Password',
                      prefixIcon: Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_isCurrentPasswordVisible ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _isCurrentPasswordVisible = !_isCurrentPasswordVisible),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your current password';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 16),

                  // New Password
                  TextFormField(
                    controller: _newPasswordController,
                    obscureText: !_isNewPasswordVisible,
                    decoration: InputDecoration(
                      labelText: 'New Password',
                      prefixIcon: Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(_isNewPasswordVisible ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _isNewPasswordVisible = !_isNewPasswordVisible),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a new password';
                      }
                      if (value.length < 6) {
                        return 'Password must be at least 6 characters';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 16),

                  // Confirm New Password
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: !_isConfirmPasswordVisible,
                    decoration: InputDecoration(
                      labelText: 'Confirm New Password',
                      prefixIcon: Icon(Icons.lock),
                      suffixIcon: IconButton(
                        icon: Icon(_isConfirmPasswordVisible ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _isConfirmPasswordVisible = !_isConfirmPasswordVisible),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please confirm your new password';
                      }
                      if (value != _newPasswordController.text) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            Consumer<AuthService>(
              builder: (context, authService, child) {
                return ElevatedButton(
                  onPressed: authService.isLoading ? null : () async {
                    if (_formKey.currentState!.validate()) {
                      final error = await authService.changePassword(
                        _currentPasswordController.text,
                        _newPasswordController.text,
                      );

                      if (error == null) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Password changed successfully'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(error),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  child: authService.isLoading
                      ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : Text('Change Password'),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // Change Email Dialog
  static Future<void> showChangeEmailDialog(BuildContext context, String currentEmail) async {
    final _formKey = GlobalKey<FormState>();
    final _newEmailController = TextEditingController();
    final _passwordController = TextEditingController();
    bool _isPasswordVisible = false;

    return showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.email_outlined, color: Colors.blue.shade500),
              SizedBox(width: 8),
              Text('Change Email'),
            ],
          ),
          content: Container(
            width: double.maxFinite,
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Current Email (display only)
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.email, color: Colors.grey.shade600),
                        SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Current Email', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            Text(currentEmail, style: TextStyle(fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 16),

                  // New Email
                  TextFormField(
                    controller: _newEmailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'New Email',
                      prefixIcon: Icon(Icons.email_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter a new email';
                      }
                      if (!value.contains('@')) {
                        return 'Please enter a valid email';
                      }
                      if (value == currentEmail) {
                        return 'New email must be different from current email';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 16),

                  // Password Confirmation
                  TextFormField(
                    controller: _passwordController,
                    obscureText: !_isPasswordVisible,
                    decoration: InputDecoration(
                      labelText: 'Current Password',
                      prefixIcon: Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_isPasswordVisible ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter your current password';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            Consumer<AuthService>(
              builder: (context, authService, child) {
                return ElevatedButton(
                  onPressed: authService.isLoading ? null : () async {
                    if (_formKey.currentState!.validate()) {
                      final error = await authService.changeEmail(
                        _newEmailController.text.trim(),
                        _passwordController.text,
                      );

                      if (error == null) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Email changed successfully'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(error),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  child: authService.isLoading
                      ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : Text('Change Email'),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // Biometric Setup Dialog
  static Future<void> showBiometricSetupDialog(BuildContext context, String email, String password) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.fingerprint, color: Colors.blue.shade500),
            SizedBox(width: 8),
            Text('Enable Biometric'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fingerprint, size: 64, color: Colors.blue.shade500),
            SizedBox(height: 16),
            Text(
              'Enable biometric authentication for quick and secure access to Spendwise.',
              textAlign: TextAlign.center,
            ),
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
                  Icon(Icons.info, color: Colors.orange.shade600, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your credentials will be stored securely on this device.',
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
            child: Text('Not Now'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              // This would be handled by the BiometricService
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Biometric authentication setup...')),
              );
            },
            child: Text('Enable'),
          ),
        ],
      ),
    );
  }
}