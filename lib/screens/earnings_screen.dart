import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/order_provider.dart';
import '../utils/app_colors.dart';
import '../utils/time_utils.dart';
import '../widgets/ui_kit.dart';
import 'orders_screen.dart' show showOrderDetails;

/// Cash & earnings for the current day (local midnight → now).
///
/// Server figures come from /api/rider/today-stats. The live order feed gives
/// instant numbers too, so the screen is correct even before the server answers
/// and refreshes itself whenever a delivery is completed.
class EarningsScreen extends StatefulWidget {
  const EarningsScreen({super.key});

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  Map<String, dynamic> _stats = {};
  bool _loading = false;
  DateTime? _updatedAt;
  int _lastDeliveredCount = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    final data = await context.read<AuthProvider>().getTodayStats();
    if (!mounted) return;
    setState(() {
      if (data.isNotEmpty) {
        _stats = data;
        _updatedAt = DateTime.now();
      }
      _loading = false;
    });
  }

  double _num(String key, double fallback) {
    final v = _stats[key];
    return v is num ? v.toDouble() : fallback;
  }

  @override
  Widget build(BuildContext context) {
    final orders = context.watch<OrderProvider>();
    final rider = context.watch<AuthProvider>().currentRider;

    final deliveredToday = orders.deliveredToday;
    // A new delivery changes cash, KMs and payout: fetch fresh server figures.
    if (_lastDeliveredCount != -1 && deliveredToday.length != _lastDeliveredCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
    _lastDeliveredCount = deliveredToday.length;
    final cash = _num('today_cash_collected', orders.totalCashToCollect);
    final deliveredCount = _num('today_delivered_orders_count', deliveredToday.length.toDouble()).toInt();
    final codCount = _num('today_cod_orders_count', orders.codOrders.length.toDouble()).toInt();
    final kmsToday = _num('today_kms', orders.kmsToday);
    final earningsToday = _num('today_earnings', 0);
    final unpaidEarnings = _num('unpaid_earnings', (rider?.totalEarnings ?? 0).toDouble());
    final unpaidKms = _num('unpaid_kms', rider?.totalKms ?? 0);
    final rating = _num('average_rating', rider?.rating ?? 0);
    final dateLabel = DateFormat('EEEE, d MMMM').format(DateTime.now());

    return Scaffold(
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            InkHero(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('Cash & Earnings',
                          style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                      const Spacer(),
                      if (_loading)
                        const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(dateLabel, style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
                  const SizedBox(height: 22),
                  Text('Cash to hand over',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Text(formatRs(cash),
                      style: const TextStyle(
                          color: Colors.white, fontSize: 40, fontWeight: FontWeight.w800, letterSpacing: -1.2)),
                  const SizedBox(height: 8),
                  Text(
                    '$codCount cash-on-delivery order${codCount == 1 ? '' : 's'} today · online payments excluded',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12.5),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.45,
                    children: [
                      _MetricTile(
                        icon: Icons.task_alt_rounded,
                        color: AppColors.success,
                        label: 'Delivered today',
                        value: '$deliveredCount',
                      ),
                      _MetricTile(
                        icon: Icons.route_rounded,
                        color: AppColors.info,
                        label: 'KMs today',
                        value: '${kmsToday.toStringAsFixed(1)} km',
                      ),
                      _MetricTile(
                        icon: Icons.account_balance_wallet_rounded,
                        color: AppColors.purple,
                        label: 'Earned today',
                        value: formatRs(earningsToday),
                      ),
                      _MetricTile(
                        icon: Icons.star_rounded,
                        color: AppColors.gold,
                        label: 'Rating',
                        value: rating > 0 ? rating.toStringAsFixed(1) : '—',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  PremiumCard(
                    child: Row(
                      children: [
                        const IconBadge(icon: Icons.savings_rounded, color: AppColors.primary, size: 46),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Pending payout',
                                  style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text(formatRs(unpaidEarnings),
                                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                              Text('${unpaidKms.toStringAsFixed(1)} km not yet paid by the office',
                                  style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  SectionTitle(
                    "Today's deliveries",
                    trailing: _updatedAt == null
                        ? null
                        : Text('Updated ${TimeUtils.timeOfDay(_updatedAt!)}',
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ),
                  if (deliveredToday.isEmpty)
                    const PremiumCard(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Center(
                          child: Text('No deliveries yet today',
                              style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    )
                  else
                    PremiumCard(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        children: [
                          for (var i = 0; i < deliveredToday.length; i++) ...[
                            if (i > 0) const Divider(indent: 16, endIndent: 16),
                            _DeliveryRow(order: deliveredToday[i]),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.icon, required this.color, required this.label, required this.value});
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon: icon, color: color, size: 36),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
          ),
          Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _DeliveryRow extends StatelessWidget {
  const _DeliveryRow({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => showOrderDetails(context, order),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('#${order.reference}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    '${order.customerName} · ${order.deliveredAt != null ? TimeUtils.timeOfDay(order.deliveredAt!) : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatRs(order.amount), style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                order.isCashOnDelivery
                    ? const StatusChip(label: 'CASH', color: Color(0xFFB45309))
                    : const StatusChip(label: 'PAID', color: AppColors.success),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
