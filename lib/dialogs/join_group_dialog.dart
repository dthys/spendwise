import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/group_model.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';

class JoinGroupDialog {
  static Future<GroupModel?> showJoinGroupDialog(BuildContext context) async {
    return await showDialog<GroupModel?>(
      context: context,
      builder: (context) => const _JoinGroupDialogWidget(),
      // Add this to prevent keyboard from affecting dialog layout
      barrierDismissible: true,
      useSafeArea: true, // This helps with layout
    );
  }
}

class _JoinGroupDialogWidget extends StatefulWidget {
  const _JoinGroupDialogWidget();

  @override
  _JoinGroupDialogWidgetState createState() => _JoinGroupDialogWidgetState();
}

class _JoinGroupDialogWidgetState extends State<_JoinGroupDialogWidget> {
  final TextEditingController _codeController = TextEditingController();
  final DatabaseService _databaseService = DatabaseService();

  bool _isLoading = false;
  bool _isSearching = false;
  GroupModel? _previewGroup;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _codeController.addListener(_onCodeChanged);
  }

  @override
  void dispose() {
    _codeController.removeListener(_onCodeChanged);
    _codeController.dispose();
    super.dispose();
  }

  void _onCodeChanged() {
    final code = _codeController.text.trim().toUpperCase();

    // Clear previous results
    setState(() {
      _previewGroup = null;
      _errorMessage = null;
    });

    // Start searching when code is 6 characters (typical invite code length)
    if (code.length == 6) {
      _searchGroup(code);
    }
  }

  Future<void> _searchGroup(String code) async {
    setState(() {
      _isSearching = true;
    });

    try {
      final group = await _databaseService.getGroupByInviteCode(code);

      setState(() {
        if (group != null) {
          _previewGroup = group;
          _errorMessage = null;
        } else {
          _previewGroup = null;
          _errorMessage = 'Invalid or expired invite code';
        }
      });
    } catch (e) {
      setState(() {
        _previewGroup = null;
        _errorMessage = 'Error searching for group: $e';
      });
    } finally {
      setState(() {
        _isSearching = false;
      });
    }
  }

  Future<void> _joinGroup() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUser = authService.currentUser;

    if (currentUser == null || _previewGroup == null) return;

    setState(() => _isLoading = true);

    try {
      final joinedGroup = await _databaseService.joinGroupWithInviteCode(
        _codeController.text.trim(),
        currentUser.uid,
      );

      // FIXED: Return the joined group here
      if (mounted && joinedGroup != null) {
        Navigator.pop(context, joinedGroup);  // This returns the GroupModel
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.group_add, color: Colors.blue),
          SizedBox(width: 8),
          Text('Join Group'),
        ],
      ),
      content: Container(
        width: double.maxFinite,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.4, // Max 40% height
        ),
        child: SingleChildScrollView( // Add scroll capability
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter the invite code to join a group',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),

              // Code input field
              TextField(
                controller: _codeController,
                decoration: InputDecoration(
                  labelText: 'Invite Code',
                  hintText: 'Enter 6-character code',
                  prefixIcon: const Icon(Icons.vpn_key),
                  suffixIcon: _isSearching
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                textCapitalization: TextCapitalization.characters,
                maxLength: 6,
                onChanged: (value) {
                  // Auto-format to uppercase
                  if (value != value.toUpperCase()) {
                    _codeController.value = TextEditingValue(
                      text: value.toUpperCase(),
                      selection: _codeController.selection,
                    );
                  }
                },
              ),
              const SizedBox(height: 16),

              // Preview or error
              if (_errorMessage != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error, color: Colors.red.shade600, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: Colors.red.shade700),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (_previewGroup != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.green.shade500,
                            radius: 20,
                            child: Text(
                              _previewGroup!.name.substring(0, 1).toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _previewGroup!.name,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (_previewGroup!.description != null)
                                  Text(
                                    _previewGroup!.description!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.check_circle,
                            color: Colors.green.shade600,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(Icons.people, size: 16, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            '${_previewGroup!.memberIds.length} members',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                          ),
                          const SizedBox(width: 16),
                          Icon(Icons.currency_exchange, size: 16, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text(
                            _previewGroup!.currency,
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ] else if (_codeController.text.length < 6) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info, color: Colors.blue.shade600, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Enter a 6-character invite code to preview the group',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: (_previewGroup != null && !_isLoading) ? _joinGroup : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green.shade500,
            foregroundColor: Colors.white,
          ),
          child: _isLoading
              ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          )
              : const Text('Join Group'),
        ),
      ],
    );
  }
}