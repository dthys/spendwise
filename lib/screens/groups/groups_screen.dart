import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../models/group_model.dart';
import '../../models/user_model.dart';
import '../../dialogs/join_group_dialog.dart'; // ADD THIS IMPORT

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  _GroupsScreenState createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  final DatabaseService _databaseService = DatabaseService();
  final _formKey = GlobalKey<FormState>();
  final _groupNameController = TextEditingController();
  final _groupDescriptionController = TextEditingController();
  final _memberEmailController = TextEditingController();

  final List<UserModel> _selectedMembers = [];
  List<UserModel> _searchResults = [];
  bool _isSearching = false;
  bool _showSuggestions = false;
  bool _isLoading = false;
  String _selectedCurrency = 'EUR';

  final List<String> _currencies = ['EUR', 'USD', 'GBP', 'CHF', 'CAD'];

  @override
  void initState() {
    super.initState();
    _memberEmailController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _memberEmailController.removeListener(_onSearchChanged);
    _groupNameController.dispose();
    _groupDescriptionController.dispose();
    _memberEmailController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _memberEmailController.text.trim();

    if (query.isEmpty) {
      setState(() {
        _showSuggestions = false;
        _searchResults = [];
      });
      return;
    }

    if (query.length >= 2) {
      _searchPreviousMembers(query);
    }
  }

  Future<void> _searchPreviousMembers(String query) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    if (authService.currentUser == null) return;

    setState(() => _isSearching = true);

    try {
      List<UserModel> results = await _databaseService.searchPreviousMembers(
          authService.currentUser!.uid,
          query
      );

      setState(() {
        _searchResults = results;
        _showSuggestions = results.isNotEmpty;
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error searching: $e');
      }
    } finally {
      setState(() => _isSearching = false);
    }
  }

  void _selectSuggestedMember(UserModel member) {
    if (!_selectedMembers.any((selected) => selected.id == member.id)) {
      setState(() {
        _selectedMembers.add(member);
        _memberEmailController.clear();
        _showSuggestions = false;
        _searchResults = [];
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${member.name} added to group!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Widget _buildSearchSuggestions() {
    if (!_showSuggestions || _searchResults.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.history, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Text('Previous group members', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
          ),
          ...(_searchResults.map((member) => ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: Colors.blue.shade500,
              child: Text(member.name.substring(0, 1).toUpperCase(), style: const TextStyle(color: Colors.white)),
            ),
            title: Text(member.name),
            subtitle: Text(member.email),
            trailing: const Icon(Icons.add_circle_outline, size: 20),
            onTap: () => _selectSuggestedMember(member),
          ))),
        ],
      ),
    );
  }

  // NEW: Show join group dialog
  Future<void> _showJoinGroupDialog() async {
    final result = await JoinGroupDialog.showJoinGroupDialog(context);
    if (result != null) {
      // Navigate to the joined group or refresh the screen
      Navigator.pop(context, 'refresh');
    }
  }

  Future<void> _addMemberByEmail() async {
    if (_memberEmailController.text.trim().isEmpty) return;

    try {
      setState(() => _isLoading = true);

      String searchEmail = _memberEmailController.text.trim();
      if (kDebugMode) {
        print('=== SEARCHING FOR USER ===');
      }
      if (kDebugMode) {
        print('Search email: "$searchEmail"');
      }

      List<UserModel> users = await _databaseService.searchUsersByEmail(searchEmail);

      if (kDebugMode) {
        print('Search returned ${users.length} users');
      }

      if (users.isNotEmpty) {
        UserModel user = users.first;
        if (kDebugMode) {
          print('Found user: ${user.name} (${user.email})');
        }

        if (!_selectedMembers.any((member) => member.id == user.id)) {
          setState(() {
            _selectedMembers.add(user);
            _memberEmailController.clear();
          });

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${user.name} added to group!'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('User already added to group'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        if (kDebugMode) {
          print('No users found for email: $searchEmail');
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No user found with this email'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error searching for user: $e');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error searching for user: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _createGroup() async {
    if (!_formKey.currentState!.validate()) return;

    final authService = Provider.of<AuthService>(context, listen: false);
    if (authService.currentUser == null) return;

    try {
      setState(() => _isLoading = true);

      final group = GroupModel(
        id: '',
        name: _groupNameController.text.trim(),
        description: _groupDescriptionController.text.trim().isEmpty
            ? null
            : _groupDescriptionController.text.trim(),
        memberIds: [authService.currentUser!.uid],
        createdBy: authService.currentUser!.uid,
        createdAt: DateTime.now(),
        currency: _selectedCurrency,
      );

      String groupId = await _databaseService.createGroup(group);

      for (UserModel member in _selectedMembers) {
        await _databaseService.addUserToGroup(groupId, member.id);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Group "${group.name}" created successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context, 'refresh');

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create group: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Create Group'),
        backgroundColor: Colors.blue.shade500,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          // NEW: Join group button
          TextButton.icon(
            onPressed: _showJoinGroupDialog,
            icon: const Icon(Icons.group_add, color: Colors.white),
            label: const Text('Join', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Group Info Section
              Text(
                'Group Information',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 16),

              // Group Name
              TextFormField(
                controller: _groupNameController,
                decoration: InputDecoration(
                  labelText: 'Group Name *',
                  hintText: 'e.g., Weekend Trip, Shared Apartment',
                  prefixIcon: const Icon(Icons.group),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a group name';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              // Group Description
              TextFormField(
                controller: _groupDescriptionController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Description (Optional)',
                  hintText: 'What is this group for?',
                  prefixIcon: const Icon(Icons.description),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
              ),

              const SizedBox(height: 16),

              // Currency Selection
              DropdownButtonFormField<String>(
                value: _selectedCurrency,
                decoration: InputDecoration(
                  labelText: 'Currency',
                  prefixIcon: const Icon(Icons.currency_exchange),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.grey.shade50,
                ),
                items: _currencies.map((currency) {
                  return DropdownMenuItem(
                    value: currency,
                    child: Text(currency),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedCurrency = value!;
                  });
                },
              ),

              const SizedBox(height: 32),

              // Add Members Section
              Text(
                'Add Members',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Add friends by their email address',
                style: TextStyle(
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 16),

              // Add Member Input
              Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _memberEmailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: 'Friend\'s Name or Email',
                            hintText: 'Start typing...',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _isSearching
                                ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                                : null,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            filled: true,
                            fillColor: Colors.grey.shade50,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _addMemberByEmail,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade500,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isLoading
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                            : const Icon(Icons.add),
                      ),
                    ],
                  ),
                  _buildSearchSuggestions(),
                ],
              ),

              const SizedBox(height: 16),

              // Selected Members List
              if (_selectedMembers.isNotEmpty) ...[
                Text(
                  'Selected Members (${_selectedMembers.length})',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 8),
                ...(_selectedMembers.map((member) => Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue.shade500,
                      child: Text(
                        member.name.substring(0, 1).toUpperCase(),
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                    title: Text(member.name),
                    subtitle: Text(member.email),
                    trailing: IconButton(
                      icon: const Icon(Icons.remove_circle, color: Colors.red),
                      onPressed: () {
                        setState(() {
                          _selectedMembers.remove(member);
                        });
                      },
                    ),
                  ),
                ))),
                const SizedBox(height: 16),
              ],

              // NEW: Updated Info Card with invite code information
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info, color: Colors.blue.shade600),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Adding Members',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '• You can add members now by email address\n'
                          '• Only registered Spendwise users can be added\n'
                          '• After creating the group, you can generate an invite code in group settings\n'
                          '• Share the invite code with friends to let them join easily!',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.link, color: Colors.green.shade600, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Pro tip: Create the group first, then use invite codes to add members later!',
                              style: TextStyle(
                                color: Colors.green.shade700,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Create Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _createGroup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade500,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                      : const Text(
                    'Create Group',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}