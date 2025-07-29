import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../models/expense_model.dart';
import '../../models/group_model.dart';
import '../../models/user_model.dart';
import '../../models/activity_log_model.dart';

class EditExpenseScreen extends StatefulWidget {
  final ExpenseModel expense;
  final GroupModel group;
  final List<UserModel> members;

  const EditExpenseScreen({
    Key? key,
    required this.expense,
    required this.group,
    required this.members,
  }) : super(key: key);

  @override
  _EditExpenseScreenState createState() => _EditExpenseScreenState();
}

class _EditExpenseScreenState extends State<EditExpenseScreen> {
  final DatabaseService _databaseService = DatabaseService();
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  String? _selectedPaidBy;
  List<String> _selectedSplitBetween = [];
  SplitType _splitType = SplitType.equal;
  ExpenseCategory _selectedCategory = ExpenseCategory.other;
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;

  // Custom split amounts - Map from userId to amount/percentage
  Map<String, TextEditingController> _customControllers = {};
  Map<String, double> _customSplits = {};

  // Store original values for comparison
  late ExpenseModel _originalExpense;

  @override
  void initState() {
    super.initState();
    _originalExpense = widget.expense;

    // Initialize form with current expense data
    _descriptionController.text = widget.expense.description;
    _amountController.text = widget.expense.amount.toString();
    _notesController.text = widget.expense.notes ?? '';

    _selectedPaidBy = widget.expense.paidBy;
    _selectedSplitBetween = List.from(widget.expense.splitBetween);
    _splitType = widget.expense.splitType;
    _selectedCategory = widget.expense.category;
    _selectedDate = widget.expense.date;

    // Initialize controllers for each member
    for (UserModel member in widget.members) {
      _customControllers[member.id] = TextEditingController();

      if (widget.expense.splitType != SplitType.equal &&
          widget.expense.customSplits.containsKey(member.id)) {
        double value = widget.expense.customSplits[member.id]!;
        _customControllers[member.id]!.text = value > 0 ? value.toStringAsFixed(widget.expense.splitType == SplitType.percentage ? 1 : 2) : '';
        _customSplits[member.id] = value;
      } else {
        _customSplits[member.id] = 0.0;
      }
    }

    // If it's equal split, calculate the amounts
    if (_splitType == SplitType.equal) {
      _updateEqualSplit();
    }

    // Listen to amount changes to update equal split
    _amountController.addListener(_updateEqualSplit);
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _amountController.dispose();
    _notesController.dispose();

    // Dispose custom controllers
    for (TextEditingController controller in _customControllers.values) {
      controller.dispose();
    }

    super.dispose();
  }

  void _updateEqualSplit() {
    if (_splitType == SplitType.equal && _selectedSplitBetween.isNotEmpty) {
      double totalAmount = double.tryParse(_amountController.text) ?? 0;
      double equalAmount = totalAmount / _selectedSplitBetween.length;

      for (String userId in _selectedSplitBetween) {
        _customControllers[userId]?.text = equalAmount.toStringAsFixed(2);
        _customSplits[userId] = equalAmount;
      }

      // Clear amounts for non-selected members
      for (String userId in widget.members.map((m) => m.id)) {
        if (!_selectedSplitBetween.contains(userId)) {
          _customControllers[userId]?.text = '0.00';
          _customSplits[userId] = 0.0;
        }
      }
    }
  }

  void _onSplitTypeChanged(SplitType? newType) {
    setState(() {
      _splitType = newType!;

      // Clear all custom splits when changing type
      for (String userId in widget.members.map((m) => m.id)) {
        _customControllers[userId]?.text = '';
        _customSplits[userId] = 0.0;
      }

      if (_splitType == SplitType.equal) {
        _updateEqualSplit();
      } else if (_splitType == SplitType.percentage) {
        // Initialize with equal percentages for currently selected members
        if (_selectedSplitBetween.isNotEmpty) {
          double equalPercentage = 100.0 / _selectedSplitBetween.length;
          for (String userId in _selectedSplitBetween) {
            _customControllers[userId]?.text = equalPercentage.toStringAsFixed(1);
            _customSplits[userId] = equalPercentage;
          }
        }
      }
    });
  }

  void _onCustomValueChanged(String userId, String value) {
    double amount = double.tryParse(value) ?? 0.0;
    _customSplits[userId] = amount;

    // Update selected split between based on who has values > 0
    setState(() {
      _selectedSplitBetween = _customSplits.entries
          .where((entry) => entry.value > 0)
          .map((entry) => entry.key)
          .toList();
    });
  }

  double _getTotalSplitAmount() {
    if (_splitType == SplitType.percentage) {
      return _customSplits.values.fold(0.0, (sum, percentage) => sum + percentage);
    } else {
      return _customSplits.values.fold(0.0, (sum, amount) => sum + amount);
    }
  }

  double _getRemainingAmount() {
    if (_splitType == SplitType.percentage) {
      return 100.0 - _getTotalSplitAmount();
    } else {
      double totalExpense = double.tryParse(_amountController.text) ?? 0;
      return totalExpense - _getTotalSplitAmount();
    }
  }

  bool _isValidSplit() {
    if (_splitType == SplitType.percentage) {
      double totalPercentage = _getTotalSplitAmount();
      return (100.0 - totalPercentage).abs() < 0.1; // Allow small rounding
    } else {
      double totalExpense = double.tryParse(_amountController.text) ?? 0;
      double totalSplit = _getTotalSplitAmount();
      return (totalExpense - totalSplit).abs() < 0.01;
    }
  }

  String _getSplitSuffix() {
    switch (_splitType) {
      case SplitType.equal:
      case SplitType.exact:
        return widget.group.currency;
      case SplitType.percentage:
        return '%';
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  List<String> _getChanges() {
    List<String> changes = [];

    if (_descriptionController.text.trim() != _originalExpense.description) {
      changes.add('Description: "${_originalExpense.description}" → "${_descriptionController.text.trim()}"');
    }

    double newAmount = double.tryParse(_amountController.text) ?? 0;
    if (newAmount != _originalExpense.amount) {
      changes.add('Amount: ${widget.group.currency} ${_originalExpense.amount.toStringAsFixed(2)} → ${widget.group.currency} ${newAmount.toStringAsFixed(2)}');
    }

    if (_selectedPaidBy != _originalExpense.paidBy) {
      String oldPayer = widget.members.firstWhere((m) => m.id == _originalExpense.paidBy, orElse: () => UserModel(id: '', name: 'Unknown', email: '', groupIds: [], createdAt: DateTime.now())).name;
      String newPayer = widget.members.firstWhere((m) => m.id == _selectedPaidBy, orElse: () => UserModel(id: '', name: 'Unknown', email: '', groupIds: [], createdAt: DateTime.now())).name;
      changes.add('Paid by: $oldPayer → $newPayer');
    }

    if (_selectedCategory != _originalExpense.category) {
      changes.add('Category: ${_originalExpense.category.displayName} → ${_selectedCategory.displayName}');
    }

    if (_selectedDate != _originalExpense.date) {
      changes.add('Date: ${_originalExpense.date.day}/${_originalExpense.date.month}/${_originalExpense.date.year} → ${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}');
    }

    if (_splitType != _originalExpense.splitType) {
      String oldType = _originalExpense.splitType.name;
      String newType = _splitType.name;
      changes.add('Split type: $oldType → $newType');
    }

    // Check for split changes
    if (_splitType != SplitType.equal) {
      Map<String, double> newCustomSplits = Map.fromEntries(
          _customSplits.entries.where((e) => e.value > 0)
      );

      if (_originalExpense.customSplits.toString() != newCustomSplits.toString()) {
        changes.add('Split amounts updated');
      }
    }

    String newNotes = _notesController.text.trim();
    String oldNotes = _originalExpense.notes ?? '';
    if (newNotes != oldNotes) {
      if (oldNotes.isEmpty && newNotes.isNotEmpty) {
        changes.add('Added notes');
      } else if (oldNotes.isNotEmpty && newNotes.isEmpty) {
        changes.add('Removed notes');
      } else if (oldNotes.isNotEmpty && newNotes.isNotEmpty) {
        changes.add('Updated notes');
      }
    }

    return changes;
  }

  Future<void> _updateExpense() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedPaidBy == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select who paid')),
      );
      return;
    }
    if (_selectedSplitBetween.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select who to split between')),
      );
      return;
    }
    if (!_isValidSplit()) {
      String message = _splitType == SplitType.percentage
          ? 'Percentages must add up to 100%'
          : 'Split amounts must equal the total expense amount';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUser = authService.currentUser;

      if (currentUser == null) return;

      // Prepare custom splits
      Map<String, double> customSplits = {};
      if (_splitType != SplitType.equal) {
        customSplits = Map.fromEntries(
            _customSplits.entries.where((e) => e.value > 0)
        );
      }

      // Create updated expense
      final updatedExpense = widget.expense.copyWith(
        description: _descriptionController.text.trim(),
        amount: double.parse(_amountController.text),
        paidBy: _selectedPaidBy!,
        splitBetween: _selectedSplitBetween,
        customSplits: customSplits,
        splitType: _splitType,
        category: _selectedCategory,
        date: _selectedDate,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      );

      // Get list of changes
      List<String> changes = _getChanges();

      if (changes.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No changes made'),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() => _isLoading = false);
        return;
      }

      // Update expense in database
      await _databaseService.updateExpense(updatedExpense);

      // Create activity log entry
      await _databaseService.addActivityLog(ActivityLogModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        groupId: widget.group.id,
        userId: currentUser.uid,
        userName: currentUser.displayName ?? currentUser.email ?? 'Unknown',
        type: ActivityType.expenseEdited,
        description: 'Edited expense "${updatedExpense.description}"',
        metadata: {
          'expenseId': widget.expense.id,
          'changes': changes,
          'originalExpense': _originalExpense.toMap(),
          'updatedExpense': updatedExpense.toMap(),
        },
        timestamp: DateTime.now(),
      ));

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Expense updated successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context, true); // Return true to indicate success

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update expense: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Edit Expense'),
        backgroundColor: theme.appBarTheme.backgroundColor,
        foregroundColor: theme.appBarTheme.foregroundColor,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Info banner
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.primaryColor.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info, color: theme.primaryColor),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Changes will be logged and visible to all group members.',
                        style: TextStyle(color: colorScheme.onSurface),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(height: 24),

              // Description
              TextFormField(
                controller: _descriptionController,
                style: TextStyle(color: colorScheme.onSurface),
                decoration: InputDecoration(
                  labelText: 'Description *',
                  labelStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
                  hintText: 'What was this expense for?',
                  hintStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.5)),
                  prefixIcon: Icon(Icons.description, color: theme.primaryColor),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: colorScheme.surface,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a description';
                  }
                  return null;
                },
              ),

              SizedBox(height: 16),

              // Amount
              TextFormField(
                controller: _amountController,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                style: TextStyle(color: colorScheme.onSurface),
                decoration: InputDecoration(
                  labelText: 'Amount *',
                  labelStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
                  hintText: '0.00',
                  hintStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.5)),
                  prefixIcon: Icon(Icons.euro, color: theme.primaryColor),
                  prefix: Text(
                    '${widget.group.currency} ',
                    style: TextStyle(color: colorScheme.onSurface),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: colorScheme.surface,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter an amount';
                  }
                  if (double.tryParse(value) == null || double.parse(value) <= 0) {
                    return 'Please enter a valid amount';
                  }
                  return null;
                },
              ),

              SizedBox(height: 16),

              // Category
              DropdownButtonFormField<ExpenseCategory>(
                value: _selectedCategory,
                style: TextStyle(color: colorScheme.onSurface),
                dropdownColor: theme.cardColor,
                decoration: InputDecoration(
                  labelText: 'Category',
                  labelStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
                  prefixIcon: Icon(Icons.category, color: theme.primaryColor),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: colorScheme.surface,
                ),
                items: ExpenseCategory.values.map((category) {
                  return DropdownMenuItem(
                    value: category,
                    child: Text('${category.emoji} ${category.displayName}'),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedCategory = value!;
                  });
                },
              ),

              SizedBox(height: 16),

              // Date
              InkWell(
                onTap: _selectDate,
                child: Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: colorScheme.outline),
                    borderRadius: BorderRadius.circular(12),
                    color: colorScheme.surface,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today, color: theme.primaryColor),
                      SizedBox(width: 12),
                      Text(
                        'Date: ${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                        style: TextStyle(
                          fontSize: 16,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      Spacer(),
                      Icon(Icons.arrow_drop_down, color: colorScheme.onSurface.withOpacity(0.6)),
                    ],
                  ),
                ),
              ),

              SizedBox(height: 24),

              // Who Paid
              Text(
                'Who Paid?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              SizedBox(height: 8),
              ...widget.members.map((member) {
                return RadioListTile<String>(
                  title: Text(
                    member.name,
                    style: TextStyle(color: colorScheme.onSurface),
                  ),
                  subtitle: Text(
                    member.email,
                    style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
                  ),
                  value: member.id,
                  groupValue: _selectedPaidBy,
                  activeColor: theme.primaryColor,
                  onChanged: (value) {
                    setState(() {
                      _selectedPaidBy = value;
                    });
                  },
                );
              }).toList(),

              SizedBox(height: 24),

              // Split Type Selection
              Text(
                'How to Split?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              SizedBox(height: 8),

              // Split type chips
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text('Equal'),
                    selected: _splitType == SplitType.equal,
                    onSelected: (selected) => _onSplitTypeChanged(SplitType.equal),
                    selectedColor: theme.primaryColor.withOpacity(0.3),
                    labelStyle: TextStyle(
                      color: _splitType == SplitType.equal
                          ? theme.primaryColor
                          : colorScheme.onSurface,
                      fontWeight: _splitType == SplitType.equal
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  ChoiceChip(
                    label: Text('Exact Amounts'),
                    selected: _splitType == SplitType.exact,
                    onSelected: (selected) => _onSplitTypeChanged(SplitType.exact),
                    selectedColor: theme.primaryColor.withOpacity(0.3),
                    labelStyle: TextStyle(
                      color: _splitType == SplitType.exact
                          ? theme.primaryColor
                          : colorScheme.onSurface,
                      fontWeight: _splitType == SplitType.exact
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  ChoiceChip(
                    label: Text('Percentage'),
                    selected: _splitType == SplitType.percentage,
                    onSelected: (selected) => _onSplitTypeChanged(SplitType.percentage),
                    selectedColor: theme.primaryColor.withOpacity(0.3),
                    labelStyle: TextStyle(
                      color: _splitType == SplitType.percentage
                          ? theme.primaryColor
                          : colorScheme.onSurface,
                      fontWeight: _splitType == SplitType.percentage
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),

              SizedBox(height: 16),

              // Split Between with Custom Amounts
              Text(
                'Split Between',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),

              // Show total and remaining amount for non-equal splits
              if (_splitType != SplitType.equal) ...[
                SizedBox(height: 8),
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _isValidSplit() ? Colors.green.shade50 : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _isValidSplit() ? Colors.green.shade200 : Colors.red.shade200,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Total ${_splitType == SplitType.percentage ? "Percentage" : "Split"}:',
                              style: TextStyle(fontWeight: FontWeight.w500)),
                          Text(
                            _splitType == SplitType.percentage
                                ? '${_getTotalSplitAmount().toStringAsFixed(1)}%'
                                : '${widget.group.currency} ${_getTotalSplitAmount().toStringAsFixed(2)}',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Remaining:', style: TextStyle(fontWeight: FontWeight.w500)),
                          Text(
                            _splitType == SplitType.percentage
                                ? '${_getRemainingAmount().toStringAsFixed(1)}%'
                                : '${widget.group.currency} ${_getRemainingAmount().toStringAsFixed(2)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _isValidSplit() ? Colors.green : Colors.red,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              SizedBox(height: 8),

              ...widget.members.map((member) {
                return Card(
                  margin: EdgeInsets.only(bottom: 8),
                  color: theme.cardColor,
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: Row(
                      children: [
                        if (_splitType == SplitType.equal) ...[
                          Checkbox(
                            value: _selectedSplitBetween.contains(member.id),
                            activeColor: theme.primaryColor,
                            onChanged: (bool? value) {
                              setState(() {
                                if (value == true) {
                                  _selectedSplitBetween.add(member.id);
                                } else {
                                  _selectedSplitBetween.remove(member.id);
                                }
                                _updateEqualSplit();
                              });
                            },
                          ),
                        ],
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                member.name,
                                style: TextStyle(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                member.email,
                                style: TextStyle(
                                  color: colorScheme.onSurface.withOpacity(0.7),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _customControllers[member.id],
                            keyboardType: TextInputType.numberWithOptions(decimal: true),
                            enabled: _splitType != SplitType.equal,
                            style: TextStyle(color: colorScheme.onSurface),
                            decoration: InputDecoration(
                              labelText: _getSplitSuffix(),
                              labelStyle: TextStyle(fontSize: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              filled: true,
                              fillColor: _splitType != SplitType.equal
                                  ? colorScheme.surface
                                  : colorScheme.surface.withOpacity(0.5),
                            ),
                            onChanged: (value) => _onCustomValueChanged(member.id, value),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),

              SizedBox(height: 16),

              // Notes (Optional)
              TextFormField(
                controller: _notesController,
                maxLines: 3,
                style: TextStyle(color: colorScheme.onSurface),
                decoration: InputDecoration(
                  labelText: 'Notes (Optional)',
                  labelStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
                  hintText: 'Any additional details...',
                  hintStyle: TextStyle(color: colorScheme.onSurface.withOpacity(0.5)),
                  prefixIcon: Icon(Icons.note, color: theme.primaryColor),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: colorScheme.surface,
                ),
              ),

              SizedBox(height: 32),

              // Update Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _updateExpense,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primaryColor,
                    foregroundColor: colorScheme.onPrimary,
                    padding: EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _isLoading
                      ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(colorScheme.onPrimary),
                    ),
                  )
                      : Text(
                    'Update Expense',
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