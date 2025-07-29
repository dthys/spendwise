import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../models/group_model.dart';
import '../../models/user_model.dart';
import '../../dialogs/bank_account_dialog.dart';
import '../../services/banking_service.dart';

class GroupSettingsScreen extends StatefulWidget {
  final GroupModel group;

  const GroupSettingsScreen({Key? key, required this.group}) : super(key: key);

  @override
  _GroupSettingsScreenState createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> {
  final DatabaseService _databaseService = DatabaseService();
  final TextEditingController _emailController = TextEditingController();

  List<UserModel> _members = [];
  UserModel? _currentUser; // Voeg deze toe
  bool _isLoading = true;
  bool _isAddingMember = false;

  @override
  void initState() {
    super.initState();
    _loadMembers();
    _loadCurrentUser(); // Voeg deze toe
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUser() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      if (authService.currentUser != null) {
        UserModel? user = await _databaseService.getUser(authService.currentUser!.uid);
        setState(() {
          _currentUser = user;
        });
      }
    } catch (e) {
      print('Error loading current user: $e');
    }
  }

  Future<void> _loadMembers() async {
    try {
      setState(() => _isLoading = true);
      List<UserModel> members = await _databaseService.getGroupMembers(widget.group.id);
      setState(() {
        _members = members;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Failed to load members: $e');
    }
  }

  Future<void> _addMember() async {
    if (_emailController.text.trim().isEmpty) {
      _showError('Please enter an email address');
      return;
    }

    try {
      setState(() => _isAddingMember = true);

      await _databaseService.addMemberToExistingGroup(
        widget.group.id,
        _emailController.text.trim(),
      );

      _emailController.clear();
      await _loadMembers(); // Refresh members list

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Member added successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      _showError(e.toString());
    } finally {
      setState(() => _isAddingMember = false);
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
          SnackBar(
            content: Text('Bankrekening succesvol bijgewerkt'),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fout bij bijwerken bankrekening'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleLeaveOrDeleteGroup() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUserId = authService.currentUser?.uid;

    if (currentUserId == null) return;

    // Check if user can leave and get status
    Map<String, dynamic> canLeave = await _databaseService.canUserLeaveGroup(
      widget.group.id,
      currentUserId,
    );

    bool isLastMember = canLeave['isLastMember'] ?? false;

    if (!canLeave['canLeave'] && !isLastMember) {
      _showError(canLeave['reason']);
      return;
    }

    // Show appropriate dialog based on whether user is last member
    if (isLastMember) {
      _showDeleteGroupDialog();
    } else {
      _showLeaveGroupDialog();
    }
  }

  Future<void> _showLeaveGroupDialog() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUserId = authService.currentUser?.uid;

    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Leave Group'),
        content: Text('Are you sure you want to leave "${widget.group.name}"?\n\nThis action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: Text('Leave Group', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _databaseService.leaveGroup(widget.group.id, currentUserId!);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully left the group'),
            backgroundColor: Colors.green,
          ),
        );

        Navigator.of(context).popUntil((route) => route.isFirst);
      } catch (e) {
        _showError(e.toString());
      }
    }
  }

  Future<void> _showDeleteGroupDialog() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUserId = authService.currentUser?.uid;

    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('Delete Group'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('You are the last member of "${widget.group.name}".'),
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Deleting this group will:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 4),
                  Text('• Permanently delete all expenses'),
                  Text('• Remove all settlements'),
                  Text('• Delete all activity history'),
                  Text('• This action cannot be undone'),
                ],
              ),
            ),
            SizedBox(height: 12),
            Text('Are you sure you want to delete this group?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Delete Group', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        // Show loading indicator
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('Deleting group...'),
              ],
            ),
          ),
        );

        await _databaseService.deleteGroupCompletely(widget.group.id, currentUserId!);

        // Close loading dialog
        Navigator.pop(context);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Group deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );

        Navigator.of(context).popUntil((route) => route.isFirst);
      } catch (e) {
        // Close loading dialog
        Navigator.pop(context);
        _showError('Failed to delete group: $e');
      }
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

  void _showMemberOptions(UserModel member) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUserId = authService.currentUser?.uid;
    final isCurrentUser = member.id == currentUserId;
    final isCreator = widget.group.isCreator(currentUserId ?? '');

    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Theme.of(context).primaryColor,
                backgroundImage: member.photoUrl != null
                    ? NetworkImage(member.photoUrl!)
                    : null,
                child: member.photoUrl == null
                    ? Text(
                  member.name.substring(0, 1).toUpperCase(),
                  style: TextStyle(color: Colors.white),
                )
                    : null,
              ),
              title: Text(member.name),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(member.email),
                  if (member.bankAccount != null)
                    Row(
                      children: [
                        Icon(Icons.account_balance, size: 16, color: Colors.green),
                        SizedBox(width: 4),
                        Text(
                          'Bank account added',
                          style: TextStyle(
                            color: Colors.green,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            Divider(),

            // Bank Account option (only for current user)
            if (isCurrentUser)
              ListTile(
                leading: Icon(
                  Icons.account_balance,
                  color: _currentUser?.bankAccount != null ? Colors.green : Colors.grey,
                ),
                title: Text('Bank Account'),
                subtitle: Text(
                  _currentUser?.bankAccount != null
                      ? 'IBAN: ${BankingService.formatIBAN(_currentUser!.bankAccount!)}'
                      : 'Add bank account for payments',
                ),
                trailing: _currentUser?.bankAccount != null
                    ? Icon(Icons.check_circle, color: Colors.green, size: 20)
                    : Icon(Icons.add, color: Colors.grey),
                onTap: () {
                  Navigator.pop(context);
                  _showBankAccountDialog();
                },
              ),

            if (!isCurrentUser && isCreator)
              ListTile(
                leading: Icon(Icons.remove_circle, color: Colors.red),
                title: Text('Remove from Group'),
                onTap: () {
                  Navigator.pop(context);
                  _removeMember(member);
                },
              ),
            ListTile(
              leading: Icon(Icons.email),
              title: Text('Send Email'),
              onTap: () {
                Navigator.pop(context);
                _showError('Email functionality coming soon!');
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removeMember(UserModel member) async {
    // Show confirmation dialog
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove Member'),
        content: Text('Are you sure you want to remove ${member.name} from the group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Remove', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Check if member has outstanding balances
      Map<String, double> balances = await _databaseService.calculateGroupBalancesWithSettlements(widget.group.id);
      double memberBalance = balances[member.id] ?? 0.0;

      if (memberBalance.abs() > 0.01) {
        _showError('Cannot remove ${member.name} - they have outstanding balances (€${memberBalance.toStringAsFixed(2)})');
        return;
      }

      await _databaseService.removeUserFromGroup(widget.group.id, member.id);
      await _loadMembers(); // Refresh members list

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${member.name} removed from group'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      _showError('Failed to remove member: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUserId = authService.currentUser?.uid;
    final isCreator = widget.group.isCreator(currentUserId ?? '');

    return Scaffold(
      appBar: AppBar(
        title: Text('Group Settings'),
        backgroundColor: theme.appBarTheme.backgroundColor,
        foregroundColor: theme.appBarTheme.foregroundColor,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Group Info Card
            Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: theme.primaryColor,
                          radius: 25,
                          child: Text(
                            widget.group.name.substring(0, 1).toUpperCase(),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.group.name,
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (widget.group.description != null)
                                Text(
                                  widget.group.description!,
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                                  ),
                                ),
                              Text(
                                'Currency: ${widget.group.currency}',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface.withOpacity(0.6),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 24),

            // Add Member Section
            Text(
              'Add Member',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      hintText: 'Enter email address',
                      prefixIcon: Icon(Icons.email),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                ),
                SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _isAddingMember ? null : _addMember,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primaryColor,
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isAddingMember
                      ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                      : Icon(Icons.add, color: Colors.white),
                ),
              ],
            ),

            SizedBox(height: 24),

            // Members Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Members (${_members.length})',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),

            // Members List
            ...(_members.map((member) {
              final isCurrentUser = member.id == currentUserId;
              final isMemberCreator = widget.group.isCreator(member.id);

              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: theme.primaryColor,
                    backgroundImage: member.photoUrl != null
                        ? NetworkImage(member.photoUrl!)
                        : null,
                    child: member.photoUrl == null
                        ? Text(
                      member.name.substring(0, 1).toUpperCase(),
                      style: TextStyle(color: Colors.white),
                    )
                        : null,
                  ),
                  title: Row(
                    children: [
                      Expanded(child: Text(member.name)),
                      if (isCurrentUser)
                        Container(
                          margin: EdgeInsets.only(left: 8),
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'You',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.blue.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      if (isMemberCreator)
                        Container(
                          margin: EdgeInsets.only(left: 8),
                          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Creator',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      if (member.bankAccount != null)
                        Container(
                          margin: EdgeInsets.only(left: 8),
                          child: Icon(
                            Icons.account_balance,
                            size: 16,
                            color: Colors.green,
                          ),
                        ),
                    ],
                  ),
                  subtitle: Text(member.email),
                  trailing: Icon(Icons.more_vert),
                  onTap: () => _showMemberOptions(member),
                ),
              );
            }).toList()),

            SizedBox(height: 32),

            // Leave/Delete Group Section - Updated with smart logic
            Card(
              color: _members.length <= 1 ? Colors.red.shade50 : Colors.orange.shade50,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _members.length <= 1 ? Icons.delete_forever : Icons.exit_to_app,
                          color: _members.length <= 1 ? Colors.red.shade600 : Colors.orange.shade600,
                        ),
                        SizedBox(width: 8),
                        Text(
                          _members.length <= 1 ? 'Delete Group' : 'Leave Group',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _members.length <= 1 ? Colors.red.shade700 : Colors.orange.shade700,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      _members.length <= 1
                          ? 'You are the last member of this group. Leaving will permanently delete the entire group, including all expenses and history.'
                          : 'You can only leave if you have no outstanding balances.',
                      style: TextStyle(
                        color: _members.length <= 1 ? Colors.red.shade600 : Colors.orange.shade600,
                        fontSize: 14,
                      ),
                    ),
                    SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _handleLeaveOrDeleteGroup,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _members.length <= 1 ? Colors.red.shade600 : Colors.orange.shade600,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(_members.length <= 1 ? 'Delete Group' : 'Leave Group'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}