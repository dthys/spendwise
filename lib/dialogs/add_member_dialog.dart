import 'package:flutter/material.dart';
import '../../services/database_service.dart';
import '../../models/group_model.dart';

class AddMemberDialog extends StatefulWidget {
  final GroupModel group;
  final VoidCallback? onMemberAdded;

  const AddMemberDialog({
    Key? key,
    required this.group,
    this.onMemberAdded,
  }) : super(key: key);

  @override
  _AddMemberDialogState createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<AddMemberDialog> {
  final DatabaseService _databaseService = DatabaseService();
  final TextEditingController _emailController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _addMember() async {
    if (_emailController.text.trim().isEmpty) {
      _showError('Please enter an email address');
      return;
    }

    try {
      setState(() => _isLoading = true);

      await _databaseService.addMemberToExistingGroup(
        widget.group.id,
        _emailController.text.trim(),
      );

      Navigator.pop(context);
      widget.onMemberAdded?.call();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Member added successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      _showError(e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Add Member to ${widget.group.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _emailController,
            decoration: InputDecoration(
              labelText: 'Email Address',
              hintText: 'Enter friend\'s email',
              prefixIcon: Icon(Icons.email),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            keyboardType: TextInputType.emailAddress,
            autofocus: true,
          ),
          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info, color: Colors.blue.shade600, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Only registered users can be added to groups',
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
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _addMember,
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
          ),
          child: _isLoading
              ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          )
              : Text('Add Member', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

// Helper function to show the dialog easily
Future<void> showAddMemberDialog(BuildContext context, GroupModel group, {VoidCallback? onMemberAdded}) {
  return showDialog(
    context: context,
    builder: (context) => AddMemberDialog(
      group: group,
      onMemberAdded: onMemberAdded,
    ),
  );
}