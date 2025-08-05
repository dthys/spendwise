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

class _BalancesScreenState extends State<BalancesScreen>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  final DatabaseService _databaseService = DatabaseService();
  final Set<String> _expandedMembers = <String>{};
  final Set<String> _settlingDebts = <String>{}; // Track debts being settled

  // Animation controllers for smooth transitions
  late AnimationController _settlementAnimationController;
  late Animation<double> _settlementAnimation;

  // Data storage - completely separate from UI
  Map<String, double> _balances = {};
  Map<String, List<IndividualDebt>> _individualDebts = {};
  Map<String, List<IndividualDebt>> _creditorDebts = {};
  bool _isDataLoaded = false;

  // Stream subscriptions to manually control when we update
  late Stream<List<ExpenseModel>> _expenseStream;
  late Stream<List<SettlementModel>> _settlementStream;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _settlementAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _settlementAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _settlementAnimationController,
      curve: Curves.easeInOut,
    ));

    _expenseStream = _databaseService.streamGroupExpenses(widget.groupId);
    _settlementStream = _databaseService.streamGroupSettlements(widget.groupId);

    _loadInitialData();
  }

  @override
  void dispose() {
    _settlementAnimationController.dispose();
    super.dispose();
  }

  // Load data once and store it
  Future<void> _loadInitialData() async {
    final currentUserId = Provider.of<AuthService>(context, listen: false).currentUser?.uid;

    // Get current snapshot of data
    final expenses = await _databaseService.getGroupExpenses(widget.groupId);
    final settlements = await _databaseService.getGroupSettlements(widget.groupId);

    _updateCalculations(expenses, settlements, currentUserId);
  }

  // Update calculations and store results
  void _updateCalculations(
      List<ExpenseModel> expenses,
      List<SettlementModel> settlements,
      String? viewingUserId,
      ) {
    if (kDebugMode) {
      print('🔄 Updating calculations...');
    }

    // Calculate balances
    _balances = _databaseService.calculateUserSpecificBalances(expenses, settlements, viewingUserId);

    // Calculate individual debts
    final rawDebts = _databaseService.calculateIndividualDebtsWithSettlements(expenses, viewingUserId);
    _individualDebts = _calculateSimplifiedIndividualDebts(rawDebts);
    _creditorDebts = _calculateSimplifiedCreditorDebts(_individualDebts);

    _isDataLoaded = true;

    // Only update UI, don't recalculate
    if (mounted) {
      setState(() {});
    }
  }

  // Simplified debt calculation
  Map<String, List<IndividualDebt>> _calculateSimplifiedIndividualDebts(
      Map<String, List<IndividualDebt>> rawDebts,
      ) {
    // Net debt calculation
    Map<String, Map<String, double>> netDebtMatrix = {};
    for (String userId in widget.members.map((m) => m.id)) {
      netDebtMatrix[userId] = {};
      for (String otherUserId in widget.members.map((m) => m.id)) {
        if (userId != otherUserId) {
          netDebtMatrix[userId]![otherUserId] = 0.0;
        }
      }
    }

    for (String debtorId in rawDebts.keys) {
      for (IndividualDebt debt in rawDebts[debtorId] ?? []) {
        netDebtMatrix[debtorId]![debt.creditorId] =
            (netDebtMatrix[debtorId]![debt.creditorId] ?? 0.0) + debt.amount;
      }
    }

    Map<String, List<IndividualDebt>> simplifiedDebts = {};
    Set<String> processedPairs = {};

    for (String userId1 in widget.members.map((m) => m.id)) {
      List<IndividualDebt> userDebts = [];

      for (String userId2 in widget.members.map((m) => m.id)) {
        if (userId1 != userId2) {
          String pairKey1 = '${userId1}_${userId2}';
          String pairKey2 = '${userId2}_${userId1}';

          if (processedPairs.contains(pairKey1) || processedPairs.contains(pairKey2)) {
            continue;
          }

          double debt1to2 = netDebtMatrix[userId1]![userId2] ?? 0.0;
          double debt2to1 = netDebtMatrix[userId2]![userId1] ?? 0.0;
          double netDebt = debt1to2 - debt2to1;

          if (netDebt.abs() > 0.01) {
            if (netDebt > 0) {
              userDebts.add(IndividualDebt(
                debtorId: userId1,
                creditorId: userId2,
                amount: netDebt,
              ));
            } else {
              if (simplifiedDebts[userId2] == null) {
                simplifiedDebts[userId2] = [];
              }
              simplifiedDebts[userId2]!.add(IndividualDebt(
                debtorId: userId2,
                creditorId: userId1,
                amount: netDebt.abs(),
              ));
            }
          }

          processedPairs.add(pairKey1);
          processedPairs.add(pairKey2);
        }
      }

      if (userDebts.isNotEmpty) {
        simplifiedDebts[userId1] = userDebts;
      }
    }

    return simplifiedDebts;
  }

  // Calculate simplified creditor debts
  Map<String, List<IndividualDebt>> _calculateSimplifiedCreditorDebts(
      Map<String, List<IndividualDebt>> simplifiedDebts,
      ) {
    Map<String, List<IndividualDebt>> creditorDebts = {};

    for (String debtorId in simplifiedDebts.keys) {
      for (IndividualDebt debt in simplifiedDebts[debtorId] ?? []) {
        if (creditorDebts[debt.creditorId] == null) {
          creditorDebts[debt.creditorId] = [];
        }
        creditorDebts[debt.creditorId]!.add(debt);
      }
    }

    return creditorDebts;
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
    super.build(context);

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentUserId = Provider.of<AuthService>(context, listen: false).currentUser?.uid;

    // Show loading if data not ready
    if (!_isDataLoaded) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('Balances'),
          backgroundColor: theme.appBarTheme.backgroundColor,
          foregroundColor: theme.appBarTheme.foregroundColor,
          elevation: 0,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final sortedMembers = _getSortedMembers(currentUserId);

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
              icon: const Icon(Icons.refresh),
              onPressed: () async {
                setState(() {
                  _isDataLoaded = false;
                });
                await _loadInitialData();
              },
              tooltip: 'Refresh',
            ),
            IconButton(
              icon: const Icon(Icons.history),
              onPressed: () => _showSettlementHistory(),
              tooltip: 'Settlement History',
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () async {
            setState(() {
              _isDataLoaded = false;
            });
            await _loadInitialData();
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

                // Member Cards with Smooth Animations
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: sortedMembers.map((member) {
                      return _buildMemberCard(
                        member,
                        currentUserId,
                        theme,
                        colorScheme,
                      );
                    }).toList(),
                  ),
                ),

                // All Settled Message
                if (_balances.values.every((balance) => balance.abs() < 0.01)) ...[
                  const SizedBox(height: 24),
                  _buildAllSettledCard(theme, colorScheme),
                ],

                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMemberCard(
      UserModel member,
      String? currentUserId,
      ThemeData theme,
      ColorScheme colorScheme,
      ) {
    double balance = _balances[member.id] ?? 0.0;
    List<IndividualDebt> memberOwes = _individualDebts[member.id] ?? [];
    List<IndividualDebt> memberIsOwed = _creditorDebts[member.id] ?? [];
    bool isExpanded = _expandedMembers.contains(member.id);
    bool isCurrentUser = member.id == currentUserId;
    bool hasAnyDebts = memberOwes.isNotEmpty || memberIsOwed.isNotEmpty;

    // Filter out debts that are currently being settled
    memberOwes = memberOwes.where((debt) => !_settlingDebts.contains('${debt.debtorId}_${debt.creditorId}')).toList();
    memberIsOwed = memberIsOwed.where((debt) => !_settlingDebts.contains('${debt.debtorId}_${debt.creditorId}')).toList();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 8),
      child: Card(
        color: theme.cardColor,
        elevation: isExpanded ? 4 : 1,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Main Member Tile
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: hasAnyDebts ? () {
                  HapticFeedback.lightImpact();
                  // ONLY update UI state - no data changes
                  setState(() {
                    if (isExpanded) {
                      _expandedMembers.remove(member.id);
                    } else {
                      _expandedMembers.add(member.id);
                    }
                  });
                } : null,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      // Avatar
                      CircleAvatar(
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
                      const SizedBox(width: 12),

                      // Member info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    member.name,
                                    style: TextStyle(
                                      color: colorScheme.onSurface,
                                      fontWeight: isCurrentUser ? FontWeight.bold : FontWeight.normal,
                                      fontSize: 16,
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
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
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
                                      fontSize: 14,
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
                          ],
                        ),
                      ),

                      const SizedBox(width: 8),

                      // Amount and arrow
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            hasAnyDebts
                                ? _formatAmount(balance)
                                : NumberFormatter.formatCurrency(0),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: !hasAnyDebts
                                  ? Colors.green.shade600
                                  : balance.abs() < 0.01
                                  ? Colors.grey.shade600
                                  : balance > 0
                                  ? Colors.green.shade600
                                  : Colors.red.shade600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          AnimatedRotation(
                            turns: hasAnyDebts && isExpanded ? 0.5 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: Icon(
                              hasAnyDebts
                                  ? Icons.keyboard_arrow_down
                                  : Icons.check_circle,
                              color: hasAnyDebts
                                  ? colorScheme.onSurface.withOpacity(0.6)
                                  : Colors.green.shade600,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Expandable Content with smooth size transition
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: Container(
                width: double.infinity,
                child: (isExpanded && hasAnyDebts) ? Container(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        height: 1,
                        color: colorScheme.onSurface.withOpacity(0.1),
                        margin: const EdgeInsets.only(bottom: 16),
                      ),

                      // Show debts this member owes to others
                      if (memberOwes.isNotEmpty) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              '${member.name} owes:',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface.withOpacity(0.8),
                              ),
                            ),
                          ),
                        ),
                        ...memberOwes.map((debt) => _buildDebtCard(debt, member, true)),
                      ],

                      // Show debts others owe to this member
                      if (memberIsOwed.isNotEmpty) ...[
                        if (memberOwes.isNotEmpty) const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Text(
                              'Others owe ${member.name}:',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurface.withOpacity(0.8),
                              ),
                            ),
                          ),
                        ),
                        ...memberIsOwed.map((debt) => _buildDebtCard(debt, member, false)),
                      ],
                    ],
                  ),
                ) : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDebtCard(IndividualDebt debt, UserModel member, bool memberOwes) {
    final debtKey = '${debt.debtorId}_${debt.creditorId}';
    final isSettling = _settlingDebts.contains(debtKey);
    final otherUser = memberOwes ? _getUserById(debt.creditorId) : _getUserById(debt.debtorId);
    final color = memberOwes ? Colors.red : Colors.green;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: isSettling ? null : () {
            HapticFeedback.selectionClick();
            _showSettleDialog(
              SimplifiedDebt(
                fromUserId: debt.debtorId,
                toUserId: debt.creditorId,
                amount: debt.amount,
                groupId: widget.groupId,
              ),
              _getUserById(debt.debtorId),
              _getUserById(debt.creditorId),
            );
          },
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: isSettling ? 0.6 : 1.0,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: color.shade200,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: color.shade500,
                    child: Text(
                      otherUser.name.substring(0, 1).toUpperCase(),
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
                          otherUser.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: color.shade800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isSettling
                              ? 'Settling...'
                              : memberOwes
                              ? 'Tap to settle debt'
                              : 'Tap to mark as settled',
                          style: TextStyle(
                            fontSize: 12,
                            color: isSettling ? color.shade500 : color.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatAmount(debt.amount),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: color.shade800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: isSettling
                            ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(color.shade600),
                          ),
                        )
                            : Icon(
                          Icons.touch_app,
                          size: 14,
                          color: color.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAllSettledCard(ThemeData theme, ColorScheme colorScheme) {
    return Container(
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

  // Enhanced settlement confirmation with smooth animations
  Future<void> _confirmSettlement(
      SimplifiedDebt debt,
      UserModel fromUser,
      UserModel toUser,
      SettlementMethod method,
      String? notes,
      ) async {
    try {
      Navigator.pop(context);

      // Add debt to settling list immediately for instant UI feedback
      final debtKey = '${debt.fromUserId}_${debt.toUserId}';
      setState(() {
        _settlingDebts.add(debtKey);
      });

      // Start settlement animation
      _settlementAnimationController.forward();

      // Show processing message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                ),
              ),
              const SizedBox(width: 12),
              const Text('Processing settlement...'),
            ],
          ),
          duration: Duration(seconds: 5),
        ),
      );

      // Perform the settlement
      await _databaseService.confirmSettlementWithExpenseTracking(
        debt,
        fromUser,
        toUser,
        method,
        notes,
      );

      // Add a small delay for smooth animation
      await Future.delayed(const Duration(milliseconds: 500));

      // Remove from settling list and reload data
      setState(() {
        _settlingDebts.remove(debtKey);
        _expandedMembers.remove(debt.fromUserId); // Collapse after settlement
        _isDataLoaded = false; // Force reload
      });

      // Reload fresh data
      await _loadInitialData();

      // Reset animation
      _settlementAnimationController.reset();

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              const Text('Settlement recorded successfully!'),
            ],
          ),
          backgroundColor: Colors.green.shade600,
          duration: Duration(seconds: 2),
        ),
      );

    } catch (e) {
      // Remove from settling list on error
      final debtKey = '${debt.fromUserId}_${debt.toUserId}';
      setState(() {
        _settlingDebts.remove(debtKey);
      });

      // Reset animation
      _settlementAnimationController.reset();

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(child: Text('Failed: $e')),
            ],
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ),
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
                stream: _settlementStream,
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

                      return AnimatedContainer(
                        duration: Duration(milliseconds: 200 + (index * 50)),
                        child: Card(
                          margin: const EdgeInsets.only(bottom: 8),
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

// SimplifiedDebt class is imported from database_service.dart