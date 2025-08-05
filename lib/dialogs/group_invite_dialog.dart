import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../models/group_model.dart';
import '../services/database_service.dart';

class GroupInviteDialog {
  static Future<void> showInviteDialog(
      BuildContext context,
      GroupModel group,
      DatabaseService databaseService,
      ) async {
    return showDialog(
      context: context,
      builder: (context) => _GroupInviteDialogWidget(
        group: group,
        databaseService: databaseService,
      ),
    );
  }
}

class _GroupInviteDialogWidget extends StatefulWidget {
  final GroupModel group;
  final DatabaseService databaseService;

  const _GroupInviteDialogWidget({
    required this.group,
    required this.databaseService,
  });

  @override
  _GroupInviteDialogWidgetState createState() => _GroupInviteDialogWidgetState();
}

class _GroupInviteDialogWidgetState extends State<_GroupInviteDialogWidget> {
  bool _isLoading = false;
  bool _isGenerating = false;
  GroupModel? _currentGroup;
  Map<String, dynamic>? _inviteStats;

  @override
  void initState() {
    super.initState();
    _currentGroup = widget.group;
    _loadInviteStats();
  }

  Future<void> _loadInviteStats() async {
    try {
      final stats = await widget.databaseService.getInviteCodeStats(widget.group.id);
      setState(() {
        _inviteStats = stats;
      });
    } catch (e) {
      print('Error loading invite stats: $e');
    }
  }

  Future<void> _generateInviteCode() async {
    setState(() => _isGenerating = true);

    try {
      final inviteCode = await widget.databaseService.generateInviteCode(
        widget.group.id,
        expiresIn: const Duration(days: 7), // Expire after 7 days
      );

      // Refresh group data
      final updatedGroup = await widget.databaseService.getGroup(widget.group.id);
      setState(() {
        _currentGroup = updatedGroup;
      });

      await _loadInviteStats();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invite code generated successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to generate invite code: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  Future<void> _regenerateInviteCode() async {
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Regenerate Invite Code'),
        content: const Text(
          'This will create a new invite code and invalidate the current one. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Regenerate'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isGenerating = true);

    try {
      await widget.databaseService.regenerateInviteCode(
        widget.group.id,
        expiresIn: const Duration(days: 7),
      );

      final updatedGroup = await widget.databaseService.getGroup(widget.group.id);
      setState(() {
        _currentGroup = updatedGroup;
      });

      await _loadInviteStats();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('New invite code generated!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to regenerate invite code: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isGenerating = false);
    }
  }

  Future<void> _disableInviteCode() async {
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disable Invite Code'),
        content: const Text(
          'This will disable the current invite code. People won\'t be able to join using this code anymore.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Disable', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      await widget.databaseService.disableInviteCode(widget.group.id);

      final updatedGroup = await widget.databaseService.getGroup(widget.group.id);
      setState(() {
        _currentGroup = updatedGroup;
      });

      await _loadInviteStats();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invite code disabled'),
          backgroundColor: Colors.orange,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to disable invite code: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _copyInviteCode() {
    if (_currentGroup?.inviteCode != null) {
      Clipboard.setData(ClipboardData(text: _currentGroup!.inviteCode!));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invite code copied to clipboard!'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _shareInviteCode() {
    if (_currentGroup?.inviteCode != null) {
      final inviteText = 'Join my group "${_currentGroup!.name}" on Spendwise!\n\n'
          'Use invite code: ${_currentGroup!.inviteCode!}\n\n'
          'Open the Spendwise app and enter this code to join our group.';

      Share.share(inviteText, subject: 'Join ${_currentGroup!.name} on Spendwise');
    }
  }

  String _getExpiryText() {
    if (_currentGroup?.inviteCodeExpiresAt == null) {
      return 'Never expires';
    }

    final expiresAt = _currentGroup!.inviteCodeExpiresAt!;
    final now = DateTime.now();
    final difference = expiresAt.difference(now);

    if (difference.isNegative) {
      return 'Expired';
    } else if (difference.inDays > 0) {
      return 'Expires in ${difference.inDays} day${difference.inDays != 1 ? 's' : ''}';
    } else if (difference.inHours > 0) {
      return 'Expires in ${difference.inHours} hour${difference.inHours != 1 ? 's' : ''}';
    } else {
      return 'Expires in ${difference.inMinutes} minute${difference.inMinutes != 1 ? 's' : ''}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasActiveCode = _currentGroup?.hasActiveInviteCode ?? false;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.link, color: Colors.blue),
          SizedBox(width: 8),
          Text('Group Invite Code'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Share this code with friends to let them join "${_currentGroup?.name ?? 'this group'}"',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),

            if (!hasActiveCode) ...[
              // No active code - show generate button
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  children: [
                    Icon(Icons.link_off, size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 8),
                    const Text('No active invite code'),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _isGenerating ? null : _generateInviteCode,
                      icon: _isGenerating
                          ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                          : const Icon(Icons.add_link),
                      label: Text(_isGenerating ? 'Generating...' : 'Generate Code'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade500,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Active code - show code and actions
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.link, color: Colors.green.shade600),
                        const SizedBox(width: 8),
                        const Text(
                          'Active Invite Code',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Invite code display
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade300),
                      ),
                      child: Text(
                        _currentGroup?.inviteCode ?? '',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    Text(
                      _getExpiryText(),
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Action buttons
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        TextButton.icon(
                          onPressed: _copyInviteCode,
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('Copy'),
                        ),
                        TextButton.icon(
                          onPressed: _shareInviteCode,
                          icon: const Icon(Icons.share, size: 16),
                          label: const Text('Share'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Stats
              if (_inviteStats != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Usage Statistics',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text('• ${_inviteStats!['totalInviteJoins']} people joined via invite code'),
                      Text('• ${_inviteStats!['currentMembers']} current members'),
                      if (_inviteStats!['maxMembers'] != null)
                        Text('• Max ${_inviteStats!['maxMembers']} members allowed'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Management buttons
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _isGenerating ? null : _regenerateInviteCode,
                      icon: _isGenerating
                          ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                          : const Icon(Icons.refresh),
                      label: const Text('Regenerate'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.orange.shade600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: _isLoading ? null : _disableInviteCode,
                      icon: _isLoading
                          ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                          : const Icon(Icons.link_off),
                      label: const Text('Disable'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.red.shade600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}