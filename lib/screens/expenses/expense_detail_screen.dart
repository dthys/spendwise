import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../models/expense_model.dart';
import '../../models/group_model.dart';
import '../../models/user_model.dart';
import '../../models/activity_log_model.dart';
import 'edit_expense_screen.dart';

class ExpenseDetailScreen extends StatefulWidget {
  final ExpenseModel expense;
  final GroupModel group;
  final List<UserModel> members;

  const ExpenseDetailScreen({
    Key? key,
    required this.expense,
    required this.group,
    required this.members,
  }) : super(key: key);

  @override
  _ExpenseDetailScreenState createState() => _ExpenseDetailScreenState();
}

class _ExpenseDetailScreenState extends State<ExpenseDetailScreen> {
  final DatabaseService _databaseService = DatabaseService();
  bool _isDeleting = false;

  String _formatCurrency(double amount) {
    return '${widget.group.currency} ${amount.toStringAsFixed(2)}';
  }

  UserModel? _getUserById(String userId) {
    try {
      return widget.members.firstWhere((member) => member.id == userId);
    } catch (e) {
      return null;
    }
  }

  bool _canUserEdit() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUser = authService.currentUser;

    if (currentUser == null) return false;

    // Allow editing if user paid for the expense or is group creator
    return widget.expense.paidBy == currentUser.uid ||
        widget.group.createdBy == currentUser.uid;
  }

  Future<void> _editExpense() async {
    if (!_canUserEdit()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You can only edit expenses you paid for'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditExpenseScreen(
          expense: widget.expense,
          group: widget.group,
          members: widget.members,
        ),
      ),
    );

    if (result == true) {
      // Expense was updated, go back to refresh group detail
      Navigator.pop(context, true);
    }
  }

  Future<void> _deleteExpense() async {
    if (!_canUserEdit()) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You can only delete expenses you paid for'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUser = authService.currentUser;

    if (currentUser == null) return;

    // Show confirmation dialog
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).dialogBackgroundColor,
        title: Text(
          'Delete Expense',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        content: Text(
          'Are you sure you want to delete "${widget.expense.description}"?\n\nThis action cannot be undone and will be visible to all group members.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isDeleting = true);

    try {
      // Create activity log entry
      await _databaseService.addActivityLog(ActivityLogModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        groupId: widget.group.id,
        userId: currentUser.uid,
        userName: currentUser.displayName ?? currentUser.email ?? 'Unknown',
        type: ActivityType.expenseDeleted,
        description: 'Deleted expense "${widget.expense.description}" (${_formatCurrency(widget.expense.amount)})',
        metadata: {
          'expenseId': widget.expense.id,
          'originalExpense': widget.expense.toMap(),
        },
        timestamp: DateTime.now(),
      ));

      // Delete the expense
      await _databaseService.deleteExpense(widget.expense.id);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Expense deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );

      // Go back to group detail
      Navigator.pop(context, true);

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete expense: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final paidByUser = _getUserById(widget.expense.paidBy);
    final canEdit = _canUserEdit();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Expense Details'),
        backgroundColor: theme.appBarTheme.backgroundColor,
        foregroundColor: theme.appBarTheme.foregroundColor,
        elevation: 0,
        actions: [
          if (canEdit) ...[
            IconButton(
              icon: Icon(Icons.edit),
              onPressed: _editExpense,
            ),
            IconButton(
              icon: Icon(Icons.delete),
              onPressed: _isDeleting ? null : _deleteExpense,
            ),
          ],
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.primaryColor,
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: colorScheme.onPrimary.withOpacity(0.2),
                    child: Text(
                      widget.expense.category.emoji,
                      style: TextStyle(fontSize: 30),
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    widget.expense.description,
                    style: TextStyle(
                      color: colorScheme.onPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 8),
                  Text(
                    _formatCurrency(widget.expense.amount),
                    style: TextStyle(
                      color: colorScheme.onPrimary,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 24),

            // Details Cards
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  // Basic Info Card
                  Card(
                    color: theme.cardColor,
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Details',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          SizedBox(height: 16),
                          _buildDetailRow('Category', '${widget.expense.category.emoji} ${widget.expense.category.displayName}'),
                          _buildDetailRow('Date', '${widget.expense.date.day}/${widget.expense.date.month}/${widget.expense.date.year}'),
                          _buildDetailRow('Added on', '${widget.expense.createdAt.day}/${widget.expense.createdAt.month}/${widget.expense.createdAt.year}'),
                          if (widget.expense.notes != null)
                            _buildDetailRow('Notes', widget.expense.notes!),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 16),

                  // Paid By Card
                  Card(
                    color: theme.cardColor,
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Paid By',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          SizedBox(height: 16),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: Colors.green.shade500,
                              child: Text(
                                paidByUser?.name.substring(0, 1).toUpperCase() ?? '?',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                            title: Text(
                              paidByUser?.name ?? 'Unknown User',
                              style: TextStyle(color: colorScheme.onSurface),
                            ),
                            subtitle: Text(
                              paidByUser?.email ?? '',
                              style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
                            ),
                            trailing: Text(
                              _formatCurrency(widget.expense.amount),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  SizedBox(height: 16),

                  // Split Between Card
                  Card(
                    color: theme.cardColor,
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Split Between (${widget.expense.splitBetween.length} people)',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          SizedBox(height: 16),
                          ...widget.expense.splitBetween.map((userId) {
                            final user = _getUserById(userId);
                            final userShare = widget.expense.getAmountOwedBy(userId);

                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: theme.primaryColor,
                                child: Text(
                                  user?.name.substring(0, 1).toUpperCase() ?? '?',
                                  style: TextStyle(color: colorScheme.onPrimary),
                                ),
                              ),
                              title: Text(
                                user?.name ?? 'Unknown User',
                                style: TextStyle(color: colorScheme.onSurface),
                              ),
                              subtitle: Text(
                                user?.email ?? '',
                                style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
                              ),
                              trailing: Text(
                                _formatCurrency(userShare),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                            );
                          }).toList(),
                        ],
                      ),
                    ),
                  ),

                  // Permissions notice
                  if (!canEdit) ...[
                    SizedBox(height: 16),
                    Container(
                      padding: EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info, color: Colors.orange.shade600),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'You can only edit or delete expenses you paid for.',
                              style: TextStyle(color: Colors.orange.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  SizedBox(height: 100), // Bottom padding
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: colorScheme.onSurface.withOpacity(0.7),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}