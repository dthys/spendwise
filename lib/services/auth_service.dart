import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/user_model.dart';
import 'database_service.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final DatabaseService _databaseService = DatabaseService();

  User? get currentUser => _auth.currentUser;
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  AuthService() {
    _auth.authStateChanges().listen((User? user) {
      _isLoading = false;
      notifyListeners();
    });
  }

  // Email/Password Registration - Simplified
  Future<String?> registerWithEmailAndPassword(String email, String password, String name) async {
    try {
      _isLoading = true;
      notifyListeners();

      UserCredential result = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password
      );

      // Update display name
      if (result.user != null) {
        await result.user!.updateDisplayName(name);
        await result.user!.reload();

        // Create user in Firestore IMMEDIATELY
        final userModel = UserModel.fromFirebaseUser(
          result.user!.uid,
          name,
          email,
          result.user!.photoURL,
        );
        await _databaseService.createUser(userModel);

        // Wait a moment to ensure Firestore write is complete
        await Future.delayed(Duration(milliseconds: 500));
      }

      _isLoading = false;
      notifyListeners();
      return null; // Success
    } catch (e) {
      _isLoading = false;
      notifyListeners();

      // Handle specific Firebase errors
      String errorMessage = 'Registration failed';
      if (e.toString().contains('email-already-in-use')) {
        errorMessage = 'Email is already registered';
      } else if (e.toString().contains('weak-password')) {
        errorMessage = 'Password is too weak';
      } else if (e.toString().contains('invalid-email')) {
        errorMessage = 'Invalid email address';
      }

      print('Registration error: $e'); // Debug
      return errorMessage;
    }
  }

  // Email/Password Sign In - Simplified
  Future<String?> signInWithEmailAndPassword(String email, String password) async {
    try {
      _isLoading = true;
      notifyListeners();

      UserCredential result = await _auth.signInWithEmailAndPassword(email: email, password: password);

      // Check if user exists in Firestore, create if not
      if (result.user != null) {
        UserModel? existingUser = await _databaseService.getUser(result.user!.uid);
        if (existingUser == null) {
          final userModel = UserModel.fromFirebaseUser(
            result.user!.uid,
            result.user!.displayName ?? 'User',
            email,
            result.user!.photoURL,
          );
          await _databaseService.createUser(userModel);
        }
      }

      _isLoading = false;
      notifyListeners();
      return null; // Success
    } catch (e) {
      _isLoading = false;
      notifyListeners();

      String errorMessage = 'Sign in failed';
      if (e.toString().contains('user-not-found')) {
        errorMessage = 'No account found with this email';
      } else if (e.toString().contains('wrong-password')) {
        errorMessage = 'Incorrect password';
      } else if (e.toString().contains('invalid-email')) {
        errorMessage = 'Invalid email address';
      }

      print('Sign in error: $e'); // Debug
      return errorMessage;
    }
  }

  // Google Sign In - Now working
  Future<String?> signInWithGoogle() async {
    try {
      _isLoading = true;
      notifyListeners();

      print('=== GOOGLE SIGN IN DEBUG ===');

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        _isLoading = false;
        notifyListeners();
        return 'Sign in cancelled';
      }

      print('Google user signed in: ${googleUser.email}');

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      UserCredential result = await _auth.signInWithCredential(credential);

      print('Firebase Auth successful: ${result.user?.uid}');

      // Create or update user in Firestore
      if (result.user != null) {
        try {
          UserModel? existingUser = await _databaseService.getUser(result.user!.uid);

          if (existingUser == null) {
            print('Creating new user in Firestore...');
            final userModel = UserModel.fromFirebaseUser(
              result.user!.uid,
              result.user!.displayName ?? 'Google User',
              result.user!.email ?? '',
              result.user!.photoURL,
            );

            print('User model: ${userModel.toMap()}');
            await _databaseService.createUser(userModel);
            print('User created successfully in Firestore!');
          } else {
            print('User already exists in Firestore: ${existingUser.email}');
          }
        } catch (firestoreError) {
          print('Firestore error: $firestoreError');
          // Continue anyway - don't fail the sign in
        }
      }

      _isLoading = false;
      notifyListeners();
      return null; // Success
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      print('Google Sign In error: $e'); // Debug
      return 'Google Sign In failed';
    }
  }

  // Sign Out
  Future<void> signOut() async {
    _isLoading = true;
    notifyListeners();

    await _auth.signOut();
    await _googleSignIn.signOut();

    _isLoading = false;
    notifyListeners();
  }

  // Change Password
  Future<String?> changePassword(String currentPassword, String newPassword) async {
    try {
      _isLoading = true;
      notifyListeners();

      User? user = _auth.currentUser;
      if (user == null) {
        _isLoading = false;
        notifyListeners();
        return 'No user logged in';
      }

      // Re-authenticate user with current password
      AuthCredential credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );

      await user.reauthenticateWithCredential(credential);

      // Update password
      await user.updatePassword(newPassword);

      _isLoading = false;
      notifyListeners();
      return null; // Success
    } catch (e) {
      _isLoading = false;
      notifyListeners();

      String errorMessage = 'Failed to change password';
      if (e.toString().contains('wrong-password')) {
        errorMessage = 'Current password is incorrect';
      } else if (e.toString().contains('weak-password')) {
        errorMessage = 'New password is too weak';
      } else if (e.toString().contains('requires-recent-login')) {
        errorMessage = 'Please sign out and sign in again before changing password';
      }

      print('Change password error: $e');
      return errorMessage;
    }
  }

// Change Email
  Future<String?> changeEmail(String newEmail, String currentPassword) async {
    try {
      _isLoading = true;
      notifyListeners();

      User? user = _auth.currentUser;
      if (user == null) {
        _isLoading = false;
        notifyListeners();
        return 'No user logged in';
      }

      // Re-authenticate user with current password
      AuthCredential credential = EmailAuthProvider.credential(
        email: user.email!,
        password: currentPassword,
      );

      await user.reauthenticateWithCredential(credential);

      // Update email
      await user.updateEmail(newEmail);

      // Update user in Firestore
      UserModel? currentUserModel = await _databaseService.getUser(user.uid);
      if (currentUserModel != null) {
        UserModel updatedUser = currentUserModel.copyWith(email: newEmail);
        await _databaseService.updateUser(updatedUser);
      }

      _isLoading = false;
      notifyListeners();
      return null; // Success
    } catch (e) {
      _isLoading = false;
      notifyListeners();

      String errorMessage = 'Failed to change email';
      if (e.toString().contains('email-already-in-use')) {
        errorMessage = 'This email is already in use';
      } else if (e.toString().contains('invalid-email')) {
        errorMessage = 'Invalid email address';
      } else if (e.toString().contains('wrong-password')) {
        errorMessage = 'Current password is incorrect';
      } else if (e.toString().contains('requires-recent-login')) {
        errorMessage = 'Please sign out and sign in again before changing email';
      }

      print('Change email error: $e');
      return errorMessage;
    }
  }

// Send email verification
  Future<String?> sendEmailVerification() async {
    try {
      User? user = _auth.currentUser;
      if (user == null) {
        return 'No user logged in';
      }

      if (user.emailVerified) {
        return 'Email is already verified';
      }

      await user.sendEmailVerification();
      return null; // Success
    } catch (e) {
      print('Send email verification error: $e');
      return 'Failed to send verification email';
    }
  }

// Check if email is verified
  bool get isEmailVerified {
    return _auth.currentUser?.emailVerified ?? false;
  }

  // Password Reset
  Future<String?> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
      return null; // Success
    } catch (e) {
      return 'Password reset failed';
    }
  }
}