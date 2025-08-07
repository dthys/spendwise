import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../friends/friend_service.dart';
import '../services/auth_service.dart';
import '../models/group_model.dart';

class AddFriendDialog {
  static Future<GroupModel?> showAddFriendDialog(BuildContext context) {
    return showDialog<GroupModel?>(
      context: context,
      barrierDismissible: true,
      builder: (context) => const _AddFriendDialogWidget(),
    );
  }
}

class _AddFriendDialogWidget extends StatefulWidget {
  const _AddFriendDialogWidget();

  @override
  _AddFriendDialogWidgetState createState() => _AddFriendDialogWidgetState();
}

class _AddFriendDialogWidgetState extends State<_AddFriendDialogWidget> {
  final FriendService _friendService = FriendService();
  final TextEditingController _emailController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _addFriend() async {
    if (!_formKey.currentState!.validate()) return;

    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUser = authService.currentUser;

    if (currentUser == null) return;

    setState(() => _isLoading = true);

    try {
      String friendEmail = _emailController.text.trim();

      // Check if trying to add themselves
      if (friendEmail.toLowerCase() == currentUser.email?.toLowerCase()) {
        throw Exception('You cannot add yourself as a friend!');
      }

      GroupModel friendGroup = await _friendService.createFriendRelationship(
        currentUser.uid,
        friendEmail,
      );

      if (mounted) {
        Navigator.pop(context, friendGroup);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Added ${friendGroup.name.split(' & ')[1]} as friend!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error adding friend: $e');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.person_add, color: Colors.blue),
          SizedBox(width: 8),
          Text('Add Friend'),
        ],
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Add a friend by their email address to start sharing expenses.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Friend\'s Email',
                hintText: 'friend@example.com',
                prefixIcon: Icon(Icons.email),
                border: OutlineInputBorder(),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter an email address';
                }
                if (!value.contains('@')) {
                  return 'Please enter a valid email address';
                }
                return null;
              },
              enabled: !_isLoading,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info, color: Colors.blue.shade600, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'A personal group will be created for you and your friend.',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _addFriend,
          child: _isLoading
              ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
              : const Text('Add Friend'),
        ),
      ],
    );
  }
}