import 'package:flutter/material.dart';

class LoadingSkeletons {

  // Skeleton for expense list items
  static Widget expenseListSkeleton() {
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 16),
      itemCount: 6,
      itemBuilder: (context, index) => _ExpenseItemSkeleton(),
    );
  }

  // Skeleton for group list items
  static Widget groupListSkeleton() {
    return ListView.builder(
      padding: EdgeInsets.all(24),
      itemCount: 4,
      itemBuilder: (context, index) => _GroupItemSkeleton(),
    );
  }

  // Skeleton for balance card
  static Widget balanceCardSkeleton() {
    return _BalanceCardSkeleton();
  }

  // Skeleton for activity log
  static Widget activityLogSkeleton() {
    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: 8,
      itemBuilder: (context, index) => _ActivityItemSkeleton(),
    );
  }
}

class _ExpenseItemSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: _ShimmerBox(
          width: 40,
          height: 40,
          borderRadius: 20,
        ),
        title: _ShimmerBox(
          width: double.infinity,
          height: 16,
          borderRadius: 4,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 4),
            _ShimmerBox(
              width: 120,
              height: 14,
              borderRadius: 4,
            ),
            SizedBox(height: 2),
            _ShimmerBox(
              width: 80,
              height: 12,
              borderRadius: 4,
            ),
          ],
        ),
        trailing: _ShimmerBox(
          width: 60,
          height: 20,
          borderRadius: 4,
        ),
      ),
    );
  }
}

class _GroupItemSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: _ShimmerBox(
          width: 40,
          height: 40,
          borderRadius: 20,
        ),
        title: _ShimmerBox(
          width: double.infinity,
          height: 18,
          borderRadius: 4,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 4),
            _ShimmerBox(
              width: 140,
              height: 14,
              borderRadius: 4,
            ),
          ],
        ),
        trailing: _ShimmerBox(
          width: 16,
          height: 16,
          borderRadius: 2,
        ),
      ),
    );
  }
}

class _BalanceCardSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _ShimmerBox(
            width: 24,
            height: 24,
            borderRadius: 4,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ShimmerBox(
                  width: 100,
                  height: 14,
                  borderRadius: 4,
                ),
                SizedBox(height: 4),
                _ShimmerBox(
                  width: 120,
                  height: 20,
                  borderRadius: 4,
                ),
              ],
            ),
          ),
          _ShimmerBox(
            width: 80,
            height: 32,
            borderRadius: 8,
          ),
        ],
      ),
    );
  }
}

class _ActivityItemSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: _ShimmerBox(
          width: 40,
          height: 40,
          borderRadius: 20,
        ),
        title: _ShimmerBox(
          width: double.infinity,
          height: 16,
          borderRadius: 4,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 4),
            _ShimmerBox(
              width: 100,
              height: 14,
              borderRadius: 4,
            ),
            SizedBox(height: 2),
            _ShimmerBox(
              width: 60,
              height: 12,
              borderRadius: 4,
            ),
          ],
        ),
      ),
    );
  }
}

class _ShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const _ShimmerBox({
    required this.width,
    required this.height,
    this.borderRadius = 0,
  });

  @override
  _ShimmerBoxState createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(milliseconds: 1500),
      vsync: this,
    );
    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(_animation.value - 1, 0),
              end: Alignment(_animation.value, 0),
              colors: isDark ? [
                Colors.grey.shade800,
                Colors.grey.shade700,
                Colors.grey.shade800,
              ] : [
                Colors.grey.shade300,
                Colors.grey.shade100,
                Colors.grey.shade300,
              ],
            ),
          ),
        );
      },
    );
  }
}