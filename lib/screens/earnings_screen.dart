import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/order_provider.dart';

class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  Map<String, dynamic> _earningsData = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadEarnings();
  }

  Future<void> _loadEarnings() async {
    setState(() => _isLoading = true);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final data = await authProvider.getTodayStats();
    if (mounted) {
      setState(() {
        _earningsData = data;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final resultData    = _earningsData['result'] as Map<String, dynamic>? ?? {};
    final orderCount    = resultData['today_delivered_orders_count'] ?? 0;
    final riderEarning  = (resultData['totalEarnings'] ?? 0.0).toDouble();
    final cashInHand    = (resultData['today_delivered_orders_total_amount'] ?? 0.0).toDouble();
    final totalKms      = (resultData['totalKms'] ?? 0.0).toDouble();
    final avgRating     = (resultData['average_rating'] ?? 0.0).toDouble();

    final fmt  = NumberFormat('#,##0.00');
    final fmtK = NumberFormat('#,##0.0');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cash & Earnings'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadEarnings,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [

                    // ── Hero: Rider Earning ──────────────────────────────
                    _HeroCard(
                      icon: Icons.payments_rounded,
                      label: 'Rider Earning',
                      value: 'Rs ${fmt.format(riderEarning)}',
                    ),
                    const SizedBox(height: 14),

                    // ── Row: Cash in Hand | Orders Completed ─────────────
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _StatCard(
                              icon: Icons.account_balance_wallet_rounded,
                              iconColor: Colors.orange.shade700,
                              bgColor: Colors.orange.shade50,
                              borderColor: Colors.orange.shade300,
                              label: 'Cash in Hand',
                              value: 'Rs ${fmt.format(cashInHand)}',
                              subtitle: 'Collected today',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _StatCard(
                              icon: Icons.check_circle_rounded,
                              iconColor: Colors.green.shade700,
                              bgColor: Colors.green.shade50,
                              borderColor: Colors.green.shade300,
                              label: 'Orders Completed',
                              value: '$orderCount',
                              subtitle: 'Delivered today',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // ── Row: Total KMs | Avg Rating ──────────────────────
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _StatCard(
                              icon: Icons.route_rounded,
                              iconColor: Colors.blue.shade700,
                              bgColor: Colors.blue.shade50,
                              borderColor: Colors.blue.shade300,
                              label: 'Total KMs',
                              value: '${fmtK.format(totalKms)} km',
                              subtitle: 'Distance today',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _StatCard(
                              icon: Icons.star_rounded,
                              iconColor: Colors.amber.shade700,
                              bgColor: Colors.amber.shade50,
                              borderColor: Colors.amber.shade300,
                              label: 'Avg Rating',
                              value: fmtK.format(avgRating),
                              subtitle: 'Customer rating',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero gradient card (used for the primary metric)
// ─────────────────────────────────────────────────────────────────────────────
class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Card(
      elevation: 6,
      shadowColor: primary.withOpacity(0.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [primary, primary.withOpacity(0.75)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white.withOpacity(0.9), size: 26),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.95),
                    fontWeight: FontWeight.w600,
                    fontSize: 17,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              value,
              style: const TextStyle(
                fontSize: 38,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
            if (subtitle != null && subtitle!.isNotEmpty) ...
              [
                const SizedBox(height: 8),
                Text(
                  subtitle!,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 11,
                  ),
                ),
              ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Compact stat card (used for secondary metrics)
// ─────────────────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.borderColor,
    required this.label,
    required this.value,
    required this.subtitle,
    this.fullWidth = false,
  });

  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final Color borderColor;
  final String label;
  final String value;
  final String subtitle;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor, width: 1.5),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 18,
          vertical: fullWidth ? 18 : 20,
        ),
        child: fullWidth
            ? Row(
                children: [
                  _IconBubble(icon: icon, iconColor: iconColor, bgColor: borderColor.withOpacity(0.25)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: TextStyle(color: iconColor.withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(value, style: TextStyle(color: iconColor, fontSize: 24, fontWeight: FontWeight.bold)),
                        Text(subtitle, style: TextStyle(color: iconColor.withOpacity(0.6), fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _IconBubble(icon: icon, iconColor: iconColor, bgColor: borderColor.withOpacity(0.25)),
                  const SizedBox(height: 12),
                  Text(label, style: TextStyle(color: iconColor.withOpacity(0.8), fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(value, style: TextStyle(color: iconColor, fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(color: iconColor.withOpacity(0.6), fontSize: 11)),
                ],
              ),
      ),
    );
  }
}

class _IconBubble extends StatelessWidget {
  const _IconBubble({required this.icon, required this.iconColor, required this.bgColor});
  final IconData icon;
  final Color iconColor;
  final Color bgColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
      child: Icon(icon, color: iconColor, size: 22),
    );
  }
}
