import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/banking_service.dart';
import '../../services/database_service.dart';
import '../../models/group_model.dart';
import '../../models/user_model.dart';
import '../../models/expense_model.dart';
import '../../models/settlement_model.dart';

class BalancesScreen extends StatefulWidget {
  final String groupId;
  final List<UserModel> members;

  const BalancesScreen({
    Key? key,
    required this.groupId,
    required this.members,
  }) : super(key: key);

  @override
  _BalancesScreenState createState() => _BalancesScreenState();
}

class _BalancesScreenState extends State<BalancesScreen> with AutomaticKeepAliveClientMixin {
  final DatabaseService _databaseService = DatabaseService();

  @override
  bool get wantKeepAlive => true;

  // Enhanced balance calculation that respects settlements
  Map<String, double> _calculateCurrentBalances(
      List<ExpenseModel> expenses,
      List<SettlementModel> settlements,
      ) {
    print('🧮 === CALCULATING BALANCES WITH SETTLEMENTS ===');
    print('📝 Total expenses: ${expenses.length}');
    print('💰 Total settlements: ${settlements.length}');

    // Debug: Print all settlements
    for (var settlement in settlements) {
      print('🔍 Settlement: ${settlement.fromUserId} → ${settlement.toUserId} = €${settlement.amount}');
      print('   Settled expenses: ${settlement.settledExpenseIds}');
    }

    Map<String, double> balances = {};

    for (ExpenseModel expense in expenses) {
      print('\n📋 Processing expense ${expense.id}: €${expense.amount} paid by ${expense.paidBy}');

      // Check if this expense has any settlements
      List<SettlementModel> expenseSettlements = settlements
          .where((s) => s.settledExpenseIds.contains(expense.id))
          .toList();

      print('   Found ${expenseSettlements.length} settlements for this expense');

      if (expenseSettlements.isEmpty) {
        print('   ➡️ No settlements - calculating normally');
        // No settlements for this expense - calculate normally
        _addExpenseToBalances(balances, expense);
      } else {
        print('   ➡️ Has settlements - calculating unsettled portions only');
        // This expense has settlements - calculate only unsettled portions
        _addUnsettledExpenseToBalances(balances, expense, expenseSettlements);
      }

      print('   Current balances after this expense: $balances');
    }

    print('📊 Final balances: $balances');
    return balances;
  }

  void _addExpenseToBalances(Map<String, double> balances, ExpenseModel expense) {
    // Payer gets credit
    balances[expense.paidBy] = (balances[expense.paidBy] ?? 0) + expense.amount;

    // Split participants owe their share
    for (String participant in expense.splitBetween) {
      double amountOwed = expense.getAmountOwedBy(participant);
      balances[participant] = (balances[participant] ?? 0) - amountOwed;
    }
  }

  void _addUnsettledExpenseToBalances(
      Map<String, double> balances,
      ExpenseModel expense,
      List<SettlementModel> expenseSettlements,
      ) {
    print('    🔍 Checking unsettled portions for expense ${expense.id}');

    // Get all user pairs that have settled this expense
    Set<String> settledUserPairs = expenseSettlements
        .map((s) => '${s.fromUserId}-${s.toUserId}')
        .toSet();

    // Add reverse pairs (settlements work both ways)
    List<String> reversePairs = expenseSettlements
        .map((s) => '${s.toUserId}-${s.fromUserId}')
        .toList();
    settledUserPairs.addAll(reversePairs);

    print('    📋 Settled user pairs: $settledUserPairs');

    String payer = expense.paidBy;
    print('    💳 Payer: $payer');
    print('    👥 Split between: ${expense.splitBetween}');

    // For each participant in the expense
    for (String participant in expense.splitBetween) {
      double participantOwes = expense.getAmountOwedBy(participant);
      print('    🧮 $participant owes €${participantOwes.toStringAsFixed(2)}');

      if (participant == payer) {
        // Payer doesn't owe themselves
        print('    ⚠️ $participant is the payer - skipping');
        continue;
      }

      // Check if this debt has been settled
      bool isSettled = settledUserPairs.contains('$participant-$payer');
      print('    🔍 Checking if $participant-$payer is settled: $isSettled');

      if (!isSettled) {
        // This portion is NOT settled - include in balances
        print('    ➕ Adding to balances: $payer gets +€${participantOwes.toStringAsFixed(2)}, $participant gets -€${participantOwes.toStringAsFixed(2)}');
        balances[payer] = (balances[payer] ?? 0) + participantOwes;
        balances[participant] = (balances[participant] ?? 0) - participantOwes;
      } else {
        print('    ✅ Settled portion: $participant owes $payer €${participantOwes.toStringAsFixed(2)} for expense ${expense.id}');
      }
    }
  }

  // Calculate what still needs to be settled
  List<Settlement> _calculateUnsettledBalances(Map<String, double> currentBalances) {
    print('🎯 === CALCULATING UNSETTLED BALANCES ===');

    List<Settlement> neededSettlements = [];

    // Find debtors and creditors from current balances
    List<MapEntry<String, double>> debtors = [];
    List<MapEntry<String, double>> creditors = [];

    currentBalances.forEach((userId, balance) {
      if (balance < -0.01) {
        debtors.add(MapEntry(userId, -balance));
      } else if (balance > 0.01) {
        creditors.add(MapEntry(userId, balance));
      }
    });

    if (debtors.isEmpty || creditors.isEmpty) {
      print('✅ No debts remaining');
      return neededSettlements;
    }

    // Sort by amount (largest first)
    debtors.sort((a, b) => b.value.compareTo(a.value));
    creditors.sort((a, b) => b.value.compareTo(a.value));

    // Calculate what settlements are needed
    int i = 0, j = 0;
    while (i < debtors.length && j < creditors.length) {
      String debtor = debtors[i].key;
      String creditor = creditors[j].key;
      double debtAmount = debtors[i].value;
      double creditAmount = creditors[j].value;

      double settlementAmount = debtAmount < creditAmount ? debtAmount : creditAmount;

      if (settlementAmount > 0.01) {
        print('💡 Settlement needed: $debtor owes $creditor €${settlementAmount.toStringAsFixed(2)}');

        neededSettlements.add(Settlement(
          from: debtor,
          to: creditor,
          amount: settlementAmount,
        ));
      }

      debtors[i] = MapEntry(debtor, debtAmount - settlementAmount);
      creditors[j] = MapEntry(creditor, creditAmount - settlementAmount);

      if (debtors[i].value < 0.01) i++;
      if (creditors[j].value < 0.01) j++;
    }

    print('🎯 Total unsettled amounts: ${neededSettlements.length}');
    return neededSettlements;
  }

  // Calculate which expenses should be marked as settled
  List<String> _getExpensesToSettle(
      String fromUserId,
      String toUserId,
      double settlementAmount,
      List<ExpenseModel> expenses,
      List<SettlementModel> existingSettlements,
      ) {
    List<String> expensesToSettle = [];
    double remainingAmount = settlementAmount;

    // Get already settled expenses between these users
    Set<String> alreadySettledExpenseIds = existingSettlements
        .where((s) =>
    (s.fromUserId == fromUserId && s.toUserId == toUserId) ||
        (s.fromUserId == toUserId && s.toUserId == fromUserId))
        .expand((s) => s.settledExpenseIds)
        .toSet();

    // Find expenses where fromUser owes toUser
    for (ExpenseModel expense in expenses) {
      if (alreadySettledExpenseIds.contains(expense.id)) {
        continue; // Skip already settled expenses
      }

      // Check if fromUser owes toUser in this expense
      if (expense.paidBy == toUserId && expense.splitBetween.contains(fromUserId)) {
        double amountOwed = expense.getAmountOwedBy(fromUserId);

        if (remainingAmount >= amountOwed) {
          expensesToSettle.add(expense.id);
          remainingAmount -= amountOwed;

          if (remainingAmount < 0.01) {
            break; // We've covered the settlement amount
          }
        }
      }
    }

    return expensesToSettle;
  }

  UserModel _getUserById(String userId) {
    return widget.members.firstWhere(
          (member) => member.id == userId,
      orElse: () => UserModel(
        id: userId,
        name: 'Unknown User',
        email: '',
        groupIds: [],
        createdAt: DateTime.now(),
      ),
    );
  }

  String _formatAmount(double amount) {
    return '€${amount.abs().toStringAsFixed(2)}';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return WillPopScope(
      onWillPop: () async {
        // Always return 'refresh' when popping to trigger balance update in parent
        Navigator.pop(context, 'refresh');
        return false;
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text('Balances'),
          backgroundColor: theme.appBarTheme.backgroundColor,
          foregroundColor: theme.appBarTheme.foregroundColor,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, 'refresh'),
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.history),
              onPressed: () => _showSettlementHistory(),
              tooltip: 'Settlement History',
            ),
          ],
        ),
        body: StreamBuilder<List<ExpenseModel>>(
          stream: _databaseService.streamGroupExpenses(widget.groupId),
          builder: (context, expenseSnapshot) {
            return StreamBuilder<List<SettlementModel>>(
              stream: _databaseService.streamGroupSettlements(widget.groupId),
              builder: (context, settlementSnapshot) {
                if (expenseSnapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }

                // Calculate current balances using the NEW logic
                Map<String, double> currentBalances = {};
                List<Settlement> unsettledAmounts = [];

                if (expenseSnapshot.hasData) {
                  List<ExpenseModel> currentExpenses = expenseSnapshot.data!;
                  List<SettlementModel> settlements = settlementSnapshot.data ?? [];

                  // Use the new balance calculation method
                  currentBalances = _calculateCurrentBalances(currentExpenses, settlements);
                  unsettledAmounts = _calculateUnsettledBalances(currentBalances);
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    setState(() {});
                  },
                  child: SingleChildScrollView(
                    physics: AlwaysScrollableScrollPhysics(),
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
                              Icon(
                                Icons.account_balance,
                                color: colorScheme.onPrimary,
                                size: 48,
                              ),
                              SizedBox(height: 16),
                              Text(
                                'Group Balances',
                                style: TextStyle(
                                  color: colorScheme.onPrimary,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Considering settlements',
                                style: TextStyle(
                                  color: colorScheme.onPrimary.withOpacity(0.8),
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),

                        SizedBox(height: 24),

                        // Individual Balances
                        Container(
                          margin: EdgeInsets.symmetric(horizontal: 16),
                          child: Card(
                            color: theme.cardColor,
                            child: Column(
                              children: [
                                Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Row(
                                    children: [
                                      Icon(Icons.receipt_long, color: theme.primaryColor),
                                      SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Current Balances',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: colorScheme.onSurface,
                                          ),
                                        ),
                                      ),
                                      if (settlementSnapshot.hasData && settlementSnapshot.data!.isNotEmpty)
                                        Chip(
                                          label: Text('${settlementSnapshot.data!.length} settlements'),
                                          backgroundColor: Colors.green.shade100,
                                          labelStyle: TextStyle(
                                            color: Colors.green.shade700,
                                            fontSize: 12,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                ...widget.members.map((member) {
                                  double balance = currentBalances[member.id] ?? 0.0;
                                  return AnimatedContainer(
                                    duration: Duration(milliseconds: 300),
                                    child: ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: balance.abs() < 0.01
                                            ? Colors.grey.shade500
                                            : balance > 0
                                            ? Colors.green.shade500
                                            : Colors.red.shade500,
                                        child: Text(
                                          member.name.substring(0, 1).toUpperCase(),
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ),
                                      title: Text(
                                        member.name,
                                        style: TextStyle(color: colorScheme.onSurface),
                                      ),
                                      subtitle: Text(
                                        balance.abs() < 0.01
                                            ? 'All settled up'
                                            : balance > 0
                                            ? 'Is owed (after settlements)'
                                            : 'Owes (after settlements)',
                                        style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7)),
                                      ),
                                      trailing: Text(
                                        balance.abs() < 0.01 ? '€0.00' : _formatAmount(balance),
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: balance.abs() < 0.01
                                              ? Colors.grey.shade600
                                              : balance > 0
                                              ? Colors.green.shade600
                                              : Colors.red.shade600,
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ],
                            ),
                          ),
                        ),

                        SizedBox(height: 16),

                        // Unsettled amounts (what still needs to be settled)
                        if (unsettledAmounts.isNotEmpty) ...[
                          Container(
                            margin: EdgeInsets.symmetric(horizontal: 16),
                            child: Card(
                              color: theme.cardColor,
                              child: Column(
                                children: [
                                  Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Row(
                                      children: [
                                        Icon(Icons.swap_horiz, color: theme.primaryColor),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Still Need to Settle',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: colorScheme.onSurface,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  ...unsettledAmounts.map((settlement) {
                                    UserModel fromUser = _getUserById(settlement.from);
                                    UserModel toUser = _getUserById(settlement.to);

                                    return Container(
                                      decoration: BoxDecoration(
                                        border: Border(
                                          bottom: BorderSide(
                                            color: colorScheme.onSurface.withOpacity(0.1),
                                            width: 1,
                                          ),
                                        ),
                                      ),
                                      child: ListTile(
                                        leading: Container(
                                          padding: EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Colors.orange.shade500,
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Icon(Icons.arrow_forward, color: Colors.white),
                                        ),
                                        title: RichText(
                                          text: TextSpan(
                                            style: TextStyle(color: colorScheme.onSurface),
                                            children: [
                                              TextSpan(
                                                text: fromUser.name,
                                                style: TextStyle(fontWeight: FontWeight.bold),
                                              ),
                                              TextSpan(text: ' pays '),
                                              TextSpan(
                                                text: toUser.name,
                                                style: TextStyle(fontWeight: FontWeight.bold),
                                              ),
                                            ],
                                          ),
                                        ),
                                        subtitle: Text(
                                          'Tap to settle this amount',
                                          style: TextStyle(
                                            color: colorScheme.onSurface.withOpacity(0.6),
                                            fontSize: 12,
                                          ),
                                        ),
                                        trailing: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              _formatAmount(settlement.amount),
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.green.shade600,
                                              ),
                                            ),
                                            Icon(
                                              Icons.touch_app,
                                              size: 16,
                                              color: colorScheme.onSurface.withOpacity(0.4),
                                            ),
                                          ],
                                        ),
                                        onTap: () {
                                          _showSettleDialog(settlement, fromUser, toUser);
                                        },
                                      ),
                                    );
                                  }).toList(),
                                ],
                              ),
                            ),
                          ),
                        ] else ...[
                          Container(
                            margin: EdgeInsets.symmetric(horizontal: 16),
                            child: Card(
                              color: theme.cardColor,
                              child: Padding(
                                padding: EdgeInsets.all(32),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.check_circle,
                                      color: Colors.green.shade500,
                                      size: 64,
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      'All Settled!',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green.shade600,
                                      ),
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'All current expenses are settled',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: colorScheme.onSurface.withOpacity(0.6),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],

                        SizedBox(height: 100),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _showSettleDialog(Settlement settlement, UserModel fromUser, UserModel toUser) {
    SettlementMethod selectedMethod = SettlementMethod.bankTransfer;
    String notes = '';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.payment, color: Theme.of(context).primaryColor),
              SizedBox(width: 8),
              Expanded(child: Text('Settle Amount')),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Settlement Summary
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              fromUser.name,
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Icon(Icons.arrow_forward),
                          Expanded(
                            child: Text(
                              toUser.name,
                              textAlign: TextAlign.end,
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        _formatAmount(settlement.amount),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade600,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'This will settle outstanding expenses',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),

                SizedBox(height: 16),

                // Bank Account Info (if available)
                if (toUser.bankAccount != null) ...[
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(Icons.account_balance, color: Colors.green.shade600, size: 20),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${toUser.name}\'s Bank Account',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.copy, size: 18),
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: toUser.bankAccount!));
                                _showOverlayNotification(
                                  context,
                                  'IBAN copied to clipboard',
                                  Colors.green,
                                  Icons.check_circle,
                                );
                              },
                              tooltip: 'Copy IBAN',
                              color: Colors.green.shade600,
                            ),
                          ],
                        ),
                        SizedBox(height: 4),
                        Text(
                          BankingService.formatIBAN(toUser.bankAccount!),
                          style: TextStyle(
                            fontSize: 16,
                            fontFamily: 'monospace',
                            color: Colors.green.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: 16),
                ],

                // Payment Method
                DropdownButtonFormField<SettlementMethod>(
                  value: selectedMethod,
                  decoration: InputDecoration(
                    labelText: 'Payment Method',
                    border: OutlineInputBorder(),
                  ),
                  items: SettlementMethod.values.map((method) {
                    return DropdownMenuItem(
                      value: method,
                      child: Row(
                        children: [
                          Text(method.emoji),
                          SizedBox(width: 8),
                          Text(method.displayName),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (method) {
                    setDialogState(() {
                      selectedMethod = method!;
                    });
                  },
                ),

                SizedBox(height: 16),

                // Notes
                TextField(
                  decoration: InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                  onChanged: (value) => notes = value,
                ),

                SizedBox(height: 16),

                // Quick Actions Row
                if (toUser.bankAccount != null) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        try {
                          // Use the new smart banking method
                          bool success = await BankingService.openBankingAppSmart(
                            recipientIBAN: toUser.bankAccount!,
                            recipientName: toUser.name,
                            amount: settlement.amount,
                            description: 'Settlement: ${fromUser.name} to ${toUser.name}',
                          );

                          if (!success) {
                            _showOverlayNotification(
                              context,
                              'Feature coming soon',
                              Colors.orange.shade600,
                              Icons.warning,
                            );
                          }
                        } catch (e) {
                          _showOverlayNotification(
                            context,
                            'Error opening banking app. Please use the copy button above.',
                            Colors.red.shade600,
                            Icons.error,
                          );
                        }
                      },
                      icon: Icon(Icons.phone_android),
                      label: Text('Pay via Bank App'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Or mark as settled after payment:',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ] else ...[
                  // No bank account warning
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning, color: Colors.orange.shade600, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${toUser.name} hasn\'t added a bank account yet',
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => _confirmSettlement(
                settlement,
                fromUser,
                toUser,
                selectedMethod,
                notes.isEmpty ? null : notes,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
              ),
              child: Text('Mark as Settled'),
            ),
          ],
        ),
      ),
    );
  }

// Helper method for showing overlay notifications
  void _showOverlayNotification(BuildContext context, String message, Color backgroundColor, IconData icon) {
    final overlay = Overlay.of(context);
    late OverlayEntry overlayEntry;

    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        bottom: 80,
        left: 20,
        right: 20,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);

    // Remove after appropriate time based on message type
    int duration = backgroundColor == Colors.green ? 2 : 4;
    Future.delayed(Duration(seconds: duration), () {
      overlayEntry.remove();
    });
  }

  // Settlement confirmation with expense tracking
  Future<void> _confirmSettlement(
      Settlement settlement,
      UserModel fromUser,
      UserModel toUser,
      SettlementMethod method,
      String? notes,
      ) async {
    try {
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Recording settlement...')),
      );

      // Get current expenses and settlements
      List<ExpenseModel> expenses = await _databaseService.streamGroupExpenses(widget.groupId).first;
      List<SettlementModel> existingSettlements = await _databaseService.streamGroupSettlements(widget.groupId).first;

      // Calculate which expenses should be marked as settled
      List<String> expensesToSettle = _getExpensesToSettle(
        settlement.from,
        settlement.to,
        settlement.amount,
        expenses,
        existingSettlements,
      );

      // Create settlement record with expense tracking
      SettlementModel settlementModel = SettlementModel(
        id: _databaseService.generateSettlementId(),
        groupId: widget.groupId,
        fromUserId: settlement.from,
        toUserId: settlement.to,
        amount: settlement.amount,
        settledAt: DateTime.now(),
        method: method,
        notes: notes,
        settledExpenseIds: expensesToSettle, // Track which expenses are settled
      );

      await _databaseService.createSettlement(settlementModel);

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Settlement recorded! ${expensesToSettle.length} expenses settled.'),
          backgroundColor: Colors.green.shade600,
        ),
      );

      // Important: Pop with 'refresh' to trigger balance update in GroupDetailScreen
      Navigator.pop(context, 'refresh');

    } catch (e) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _showSettlementHistory() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  Icon(Icons.history, color: Colors.white),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Settlement History',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<List<SettlementModel>>(
                stream: _databaseService.streamGroupSettlements(widget.groupId),
                builder: (context, snapshot) {
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history, size: 64, color: Colors.grey.shade400),
                          SizedBox(height: 16),
                          Text('No settlements yet', style: TextStyle(fontSize: 18, color: Colors.grey.shade600)),
                          SizedBox(height: 8),
                          Text('Settlements track which expenses are settled', style: TextStyle(color: Colors.grey.shade500)),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: EdgeInsets.all(16),
                    itemCount: snapshot.data!.length,
                    itemBuilder: (context, index) {
                      SettlementModel settlement = snapshot.data![index];
                      UserModel fromUser = _getUserById(settlement.fromUserId);
                      UserModel toUser = _getUserById(settlement.toUserId);

                      return Card(
                        child: ListTile(
                          leading: Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.green.shade500,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(settlement.method.emoji),
                          ),
                          title: Text('${fromUser.name} → ${toUser.name}'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${settlement.method.displayName} • ${_formatDate(settlement.settledAt)}'),
                              if (settlement.settledExpenseIds.isNotEmpty)
                                Text(
                                  '${settlement.settledExpenseIds.length} expenses settled',
                                  style: TextStyle(fontSize: 12, color: Colors.green.shade600),
                                ),
                            ],
                          ),
                          trailing: Text(
                            _formatAmount(settlement.amount),
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade600),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

class Settlement {
  final String from;
  final String to;
  final double amount;

  Settlement({required this.from, required this.to, required this.amount});
}