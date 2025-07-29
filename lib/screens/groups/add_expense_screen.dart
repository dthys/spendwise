import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../models/activity_log_model.dart';
import '../../services/auth_service.dart';
import '../../services/database_service.dart';
import '../../models/group_model.dart';
import '../../models/expense_model.dart';
import '../../models/user_model.dart';

class AddExpenseScreen extends StatefulWidget {
  final GroupModel group;
  final List<UserModel> members;

  const AddExpenseScreen({
    Key? key,
    required this.group,
    required this.members,
  }) : super(key: key);

  @override
  _AddExpenseScreenState createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen> {
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

  @override
  void initState() {
    super.initState();
    final authService = Provider.of<AuthService>(context, listen: false);
    _selectedPaidBy = authService.currentUser?.uid;
    _selectedSplitBetween = widget.members.map((member) => member.id).toList();

    // Initialize controllers for each member
    for (UserModel member in widget.members) {
      _customControllers[member.id] = TextEditingController();
      _customSplits[member.id] = 0.0;
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
        // Initialize with equal percentages
        double equalPercentage = 100.0 / _selectedSplitBetween.length;
        for (String userId in _selectedSplitBetween) {
          _customControllers[userId]?.text = equalPercentage.toStringAsFixed(1);
          _customSplits[userId] = equalPercentage;
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

  String _getSplitLabel() {
    switch (_splitType) {
      case SplitType.equal:
        return 'Amount';
      case SplitType.exact:
        return 'Amount';
      case SplitType.percentage:
        return 'Percentage';
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

  Future<void> _addExpense() async {
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

      final expense = ExpenseModel(
        id: '', // Will be set by Firebase
        groupId: widget.group.id,
        description: _descriptionController.text.trim(),
        amount: double.parse(_amountController.text),
        paidBy: _selectedPaidBy!,
        splitBetween: _selectedSplitBetween,
        customSplits: customSplits,
        splitType: _splitType,
        category: _selectedCategory,
        date: _selectedDate,
        createdAt: DateTime.now(),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );

      print('🧪 Creating expense...');

      // FIXED: Create the expense with currentUserId parameter for notifications
      String expenseId = await _databaseService.createExpense(
        expense,
        currentUserId: currentUser.uid,  // Pass current user ID for notifications
      );

      print('✅ Expense created with ID: $expenseId and notifications sent');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('💰 Expense added successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      print('❌ Error in _addExpense: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add expense: $e'),
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
        title: Text('Add Expense'),
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
                    Icon(Icons.notifications_active, color: theme.primaryColor),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Group members will be notified about this expense.',
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

              // Add Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _addExpense,
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
                    'Add Expense',
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