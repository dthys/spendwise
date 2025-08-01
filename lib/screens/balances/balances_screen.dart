import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/banking_service.dart';
import '../../services/database_service.dart';
import '../../models/user_model.dart';
import '../../models/expense_model.dart';
import '../../models/settlement_model.dart';
import '../../utils/number_formatter.dart';

class BalancesScreen extends StatefulWidget {
  final String groupId;
  final List<UserModel> members;

  const BalancesScreen({
    super.key,
    required this.groupId,
    required this.members,
  });

  @override
  _BalancesScreenState createState() => _BalancesScreenState();
}

class _BalancesScreenState extends State<BalancesScreen> with AutomaticKeepAliveClientMixin {
  final DatabaseService _databaseService = DatabaseService();
  final Set<String> _expandedMembers = <String>{};

  @override
  bool get wantKeepAlive => true;

  // Enhanced balance calculation that respects settlements
  Map<String, double> _calculateCurrentBalances(
      List<ExpenseModel> expenses,
      List<SettlementModel> settlements,
      String? viewingUserId,
      ) {
    return _databaseService.calculateUserSpecificBalances(expenses, settlements, viewingUserId);
  }

  // Calculate individual debts between members
  Map<String, List<IndividualDebt>> _calculateIndividualDebts(
      List<ExpenseModel> expenses,
      List<SettlementModel> settlements,
      String? viewingUserId,
      ) {
    return _databaseService.calculateIndividualDebtsWithSettlements(expenses, viewingUserId);
  }

  // Calculate who owes money TO a specific member (for creditors to see their debtors)
  List<IndividualDebt> _calculateDebtsOwedToMember(
      String memberId,
      List<ExpenseModel> expenses,
      List<SettlementModel> settlements,
      String? viewingUserId,
      ) {
    return _databaseService.calculateDebtsOwedToMember(memberId, expenses, viewingUserId);
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
    return NumberFormatter.formatCurrency(amount.abs());
  }

  // Sort members to put current user first
  List<UserModel> _getSortedMembers(String? currentUserId) {
    List<UserModel> sortedMembers = List.from(widget.members);

    if (currentUserId != null) {
      sortedMembers.sort((a, b) {
        if (a.id == currentUserId) return -1;
        if (b.id == currentUserId) return 1;
        return a.name.compareTo(b.name);
      });
    } else {
      sortedMembers.sort((a, b) => a.name.compareTo(b.name));
    }

    return sortedMembers;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentUserId = Provider.of<AuthService>(context, listen: false).currentUser?.uid;

    return WillPopScope(
      onWillPop: () async {
        Navigator.pop(context, 'refresh');
        return false;
      },
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('Balances'),
          backgroundColor: theme.appBarTheme.backgroundColor,
          foregroundColor: theme.appBarTheme.foregroundColor,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context, 'refresh'),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.history),
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
                  return const Center(child: CircularProgressIndicator());
                }

                Map<String, double> balances = {};
                Map<String, List<IndividualDebt>> individualDebts = {};
                Map<String, List<IndividualDebt>> creditorDebts = {};

                if (expenseSnapshot.hasData) {
                  List<ExpenseModel> expenses = expenseSnapshot.data!;
                  List<SettlementModel> settlements = settlementSnapshot.data ?? [];

                  balances = _calculateCurrentBalances(expenses, settlements, currentUserId);
                  individualDebts = _calculateIndividualDebts(expenses, settlements, currentUserId);

                  // Calculate debts owed TO each member (for creditors)
                  for (String memberId in widget.members.map((m) => m.id)) {
                    creditorDebts[memberId] = _calculateDebtsOwedToMember(memberId, expenses, settlements, currentUserId);
                  }
                }

                final sortedMembers = _getSortedMembers(currentUserId);

                return RefreshIndicator(
                  onRefresh: () async {
                    setState(() {});
                  },
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      children: [
                        // Header
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: theme.primaryColor,
                            borderRadius: const BorderRadius.only(
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
                              const SizedBox(height: 16),
                              Text(
                                'Group Balances',
                                style: TextStyle(
                                  color: colorScheme.onPrimary,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'Tap members to see and settle individual debts',
                                style: TextStyle(
                                  color: colorScheme.onPrimary.withOpacity(0.8),
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Member Cards with Expandable Sections
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            children: sortedMembers.map((member) {
                              double balance = balances[member.id] ?? 0.0;
                              List<IndividualDebt> memberOwes = individualDebts[member.id] ?? [];
                              List<IndividualDebt> memberIsOwed = creditorDebts[member.id] ?? [];
                              bool isExpanded = _expandedMembers.contains(member.id);
                              bool isCurrentUser = member.id == currentUserId;
                              bool hasAnyDebts = memberOwes.isNotEmpty || memberIsOwed.isNotEmpty;

                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                color: theme.cardColor,
                                child: Column(
                                  children: [
                                    // Main Member Tile
                                    ListTile(
                                      leading: CircleAvatar(
                                        backgroundColor: balance.abs() < 0.01
                                            ? Colors.grey.shade500
                                            : balance > 0
                                            ? Colors.green.shade500
                                            : Colors.red.shade500,
                                        child: Text(
                                          member.name.substring(0, 1).toUpperCase(),
                                          style: const TextStyle(color: Colors.white),
                                        ),
                                      ),
                                      title: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              member.name,
                                              style: TextStyle(
                                                color: colorScheme.onSurface,
                                                fontWeight: isCurrentUser ? FontWeight.bold : FontWeight.normal,
                                              ),
                                            ),
                                          ),
                                          if (isCurrentUser) ...[
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: theme.primaryColor,
                                                borderRadius: BorderRadius.circular(12),
                                              ),
                                              child: Text(
                                                'YOU',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: colorScheme.onPrimary,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                          ],
                                        ],
                                      ),
                                      subtitle: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              hasAnyDebts
                                                  ? (balance.abs() < 0.01
                                                  ? 'Has debts to settle'
                                                  : balance > 0
                                                  ? 'Is owed'
                                                  : 'Owes')
                                                  : 'All settled up',
                                              style: TextStyle(
                                                color: colorScheme.onSurface.withOpacity(0.7),
                                              ),
                                            ),
                                          ),
                                          if (hasAnyDebts) ...[
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.orange.shade100,
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                '${memberOwes.length + memberIsOwed.length} debt${(memberOwes.length + memberIsOwed.length) == 1 ? '' : 's'}',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.orange.shade700,
                                                ),
                                              ),
                                            ),
                                          ] else ...[
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.green.shade100,
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Text(
                                                'SETTLED',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.green.shade700,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            hasAnyDebts
                                                ? _formatAmount(balance)
                                                : NumberFormatter.formatCurrency(0),
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: !hasAnyDebts
                                                  ? Colors.green.shade600  // Green for settled
                                                  : balance.abs() < 0.01
                                                  ? Colors.grey.shade600
                                                  : balance > 0
                                                  ? Colors.green.shade600
                                                  : Colors.red.shade600,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Icon(
                                            hasAnyDebts
                                                ? (isExpanded
                                                ? Icons.keyboard_arrow_up
                                                : Icons.keyboard_arrow_down)
                                                : Icons.check_circle,
                                            color: hasAnyDebts
                                                ? colorScheme.onSurface.withOpacity(0.6)
                                                : Colors.green.shade600,
                                          ),
                                        ],
                                      ),
                                      onTap: () {
                                        // Only allow expansion if there are actual debts to show
                                        if (hasAnyDebts) {
                                          setState(() {
                                            if (isExpanded) {
                                              _expandedMembers.remove(member.id);
                                            } else {
                                              _expandedMembers.add(member.id);
                                            }
                                          });
                                        }
                                        // For settled members, do nothing - no setState call
                                      },
                                    ),

                                    // Expanded Section - Individual Debts
                                    AnimatedCrossFade(
                                      firstChild: const SizedBox.shrink(),
                                      secondChild: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                        child: Column(
                                          children: [
                                            Divider(color: colorScheme.onSurface.withOpacity(0.1)),

                                            // Show debts this member owes to others
                                            if (memberOwes.isNotEmpty) ...[
                                              Padding(
                                                padding: const EdgeInsets.symmetric(vertical: 8),
                                                child: Text(
                                                  '${member.name} owes:',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w500,
                                                    color: colorScheme.onSurface.withOpacity(0.8),
                                                  ),
                                                ),
                                              ),
                                              ...memberOwes.map((debt) {
                                                UserModel creditor = _getUserById(debt.creditorId);
                                                return GestureDetector(
                                                  onTap: () {
                                                    _showSettleDialog(
                                                      SimplifiedDebt(
                                                        fromUserId: debt.debtorId,
                                                        toUserId: debt.creditorId,
                                                        amount: debt.amount,
                                                        groupId: widget.groupId, // ADD this line
                                                      ),
                                                      member,
                                                      creditor,
                                                    );
                                                  },
                                                  child: Container(
                                                    margin: const EdgeInsets.only(bottom: 8),
                                                    padding: const EdgeInsets.all(12),
                                                    decoration: BoxDecoration(
                                                      color: Colors.red.shade50,
                                                      borderRadius: BorderRadius.circular(8),
                                                      border: Border.all(
                                                        color: Colors.red.shade200,
                                                        width: 1,
                                                      ),
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        CircleAvatar(
                                                          radius: 16,
                                                          backgroundColor: Colors.red.shade500,
                                                          child: Text(
                                                            creditor.name.substring(0, 1).toUpperCase(),
                                                            style: const TextStyle(
                                                              color: Colors.white,
                                                              fontSize: 12,
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(width: 12),
                                                        Expanded(
                                                          child: Column(
                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                            children: [
                                                              Text(
                                                                creditor.name,
                                                                style: TextStyle(
                                                                  fontWeight: FontWeight.w500,
                                                                  color: Colors.red.shade800,
                                                                ),
                                                              ),
                                                              Text(
                                                                'Tap to settle debt',
                                                                style: TextStyle(
                                                                  fontSize: 12,
                                                                  color: Colors.red.shade600,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        Column(
                                                          crossAxisAlignment: CrossAxisAlignment.end,
                                                          children: [
                                                            Text(
                                                              _formatAmount(debt.amount),
                                                              style: TextStyle(
                                                                fontSize: 14,
                                                                fontWeight: FontWeight.bold,
                                                                color: Colors.red.shade800,
                                                              ),
                                                            ),
                                                            Icon(
                                                              Icons.touch_app,
                                                              size: 14,
                                                              color: Colors.red.shade600,
                                                            ),
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                );
                                              }),
                                            ],

                                            // Show debts others owe to this member
                                            if (memberIsOwed.isNotEmpty) ...[
                                              if (memberOwes.isNotEmpty) const SizedBox(height: 16),
                                              Padding(
                                                padding: const EdgeInsets.symmetric(vertical: 8),
                                                child: Text(
                                                  'Others owe ${member.name}:',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w500,
                                                    color: colorScheme.onSurface.withOpacity(0.8),
                                                  ),
                                                ),
                                              ),
                                              ...memberIsOwed.map((debt) {
                                                UserModel debtor = _getUserById(debt.debtorId);
                                                return GestureDetector(
                                                  onTap: () {
                                                    _showSettleDialog(
                                                      SimplifiedDebt(
                                                        fromUserId: debt.debtorId,
                                                        toUserId: debt.creditorId,
                                                        amount: debt.amount,
                                                        groupId: widget.groupId, // ADD this line
                                                      ),
                                                      debtor,
                                                      member,
                                                    );
                                                  },
                                                  child: Container(
                                                    margin: const EdgeInsets.only(bottom: 8),
                                                    padding: const EdgeInsets.all(12),
                                                    decoration: BoxDecoration(
                                                      color: Colors.green.shade50,
                                                      borderRadius: BorderRadius.circular(8),
                                                      border: Border.all(
                                                        color: Colors.green.shade200,
                                                        width: 1,
                                                      ),
                                                    ),
                                                    child: Row(
                                                      children: [
                                                        CircleAvatar(
                                                          radius: 16,
                                                          backgroundColor: Colors.green.shade500,
                                                          child: Text(
                                                            debtor.name.substring(0, 1).toUpperCase(),
                                                            style: const TextStyle(
                                                              color: Colors.white,
                                                              fontSize: 12,
                                                            ),
                                                          ),
                                                        ),
                                                        const SizedBox(width: 12),
                                                        Expanded(
                                                          child: Column(
                                                            crossAxisAlignment: CrossAxisAlignment.start,
                                                            children: [
                                                              Text(
                                                                debtor.name,
                                                                style: TextStyle(
                                                                  fontWeight: FontWeight.w500,
                                                                  color: Colors.green.shade800,
                                                                ),
                                                              ),
                                                              Text(
                                                                'Tap to mark as settled',
                                                                style: TextStyle(
                                                                  fontSize: 12,
                                                                  color: Colors.green.shade600,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                        Column(
                                                          crossAxisAlignment: CrossAxisAlignment.end,
                                                          children: [
                                                            Text(
                                                              _formatAmount(debt.amount),
                                                              style: TextStyle(
                                                                fontSize: 14,
                                                                fontWeight: FontWeight.bold,
                                                                color: Colors.green.shade800,
                                                              ),
                                                            ),
                                                            Icon(
                                                              Icons.touch_app,
                                                              size: 14,
                                                              color: Colors.green.shade600,
                                                            ),
                                                          ],
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                );
                                              }),
                                            ],
                                          ],
                                        ),
                                      ),
                                      crossFadeState: (isExpanded && hasAnyDebts)
                                          ? CrossFadeState.showSecond
                                          : CrossFadeState.showFirst,
                                      duration: const Duration(milliseconds: 300),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),

                        // All Settled Message
                        if (balances.values.every((balance) => balance.abs() < 0.01)) ...[
                          const SizedBox(height: 24),
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            child: Card(
                              color: theme.cardColor,
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.check_circle,
                                      color: Colors.green.shade500,
                                      size: 64,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'All Settled!',
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green.shade600,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
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

                        const SizedBox(height: 100),
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


  void _showSettleDialog(SimplifiedDebt debt, UserModel fromUser, UserModel toUser) {
    SettlementMethod selectedMethod = SettlementMethod.bankTransfer;
    String notes = '';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.payment, color: Theme.of(context).primaryColor),
              const SizedBox(width: 8),
              const Expanded(child: Text('Settle Amount')),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Settlement Summary
                Container(
                  padding: const EdgeInsets.all(16),
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
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          const Icon(Icons.arrow_forward),
                          Expanded(
                            child: Text(
                              toUser.name,
                              textAlign: TextAlign.end,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _formatAmount(debt.amount),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade600,
                        ),
                      ),
                      const SizedBox(height: 4),
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

                const SizedBox(height: 16),

                // Bank Account Info (if available)
                if (toUser.bankAccount != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
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
                            const SizedBox(width: 8),
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
                              icon: const Icon(Icons.copy, size: 18),
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
                        const SizedBox(height: 4),
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
                  const SizedBox(height: 16),
                ],

                // Payment Method
                DropdownButtonFormField<SettlementMethod>(
                  value: selectedMethod,
                  decoration: const InputDecoration(
                    labelText: 'Payment Method',
                    border: OutlineInputBorder(),
                  ),
                  items: SettlementMethod.values.map((method) {
                    return DropdownMenuItem(
                      value: method,
                      child: Row(
                        children: [
                          Text(method.emoji),
                          const SizedBox(width: 8),
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

                const SizedBox(height: 16),

                // Notes
                TextField(
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                  onChanged: (value) => notes = value,
                ),

                const SizedBox(height: 16),

                // Quick Actions Row
                if (toUser.bankAccount != null) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        try {
                          bool success = await BankingService.openBankingAppSmart(
                            recipientIBAN: toUser.bankAccount!,
                            recipientName: toUser.name,
                            amount: debt.amount,
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
                      icon: const Icon(Icons.phone_android),
                      label: const Text('Pay via Bank App'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
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
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning, color: Colors.orange.shade600, size: 20),
                        const SizedBox(width: 8),
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
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => _confirmSettlement(
                debt,
                fromUser,
                toUser,
                selectedMethod,
                notes.isEmpty ? null : notes,
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
              ),
              child: const Text('Mark as Settled'),
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [
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
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
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
      SimplifiedDebt debt,
      UserModel fromUser,
      UserModel toUser,
      SettlementMethod method,
      String? notes,
      ) async {
    try {
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Processing settlement...')),
      );

      // Use the new settlement method with expense tracking
      await _databaseService.confirmSettlementWithExpenseTracking(
        debt,
        fromUser,
        toUser,
        method,
        notes,
      );

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Settlement recorded and expenses marked as settled!'),
          backgroundColor: Colors.green.shade600,
        ),
      );

      // Collapse the expanded section after settlement
      setState(() {
        _expandedMembers.remove(debt.fromUserId);
      });

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
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.history, color: Colors.white),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Settlement History',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
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
                          const SizedBox(height: 16),
                          Text('No settlements yet', style: TextStyle(fontSize: 18, color: Colors.grey.shade600)),
                          const SizedBox(height: 8),
                          Text('Settlements will appear here when debts are settled', style: TextStyle(color: Colors.grey.shade500)),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: snapshot.data!.length,
                    itemBuilder: (context, index) {
                      SettlementModel settlement = snapshot.data![index];
                      UserModel fromUser = _getUserById(settlement.fromUserId);
                      UserModel toUser = _getUserById(settlement.toUserId);

                      return Card(
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
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
                              if (settlement.notes != null && settlement.notes!.isNotEmpty)
                                Text(
                                  settlement.notes!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                    fontStyle: FontStyle.italic,
                                  ),
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
    // EU date format: DD/MM/YYYY instead of MM/DD/YYYY
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}

// Helper classes
class IndividualDebt {
  final String debtorId;
  final String creditorId;
  final double amount;

  IndividualDebt({
    required this.debtorId,
    required this.creditorId,
    required this.amount,
  });

  @override
  String toString() {
    return 'IndividualDebt(debtor: $debtorId, creditor: $creditorId, amount: €${amount.toStringAsFixed(2)})';
  }
}

