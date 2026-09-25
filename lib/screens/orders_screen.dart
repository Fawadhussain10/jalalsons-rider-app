import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/order_provider.dart';
import '../providers/auth_provider.dart';
import '../services/firebase_service.dart';
import '../utils/app_colors.dart';
import '../utils/time_utils.dart';
import '../widgets/ui_kit.dart';
import 'main_navigation.dart';
import 'map_screen.dart';
import '../config/app_config.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 3, vsync: this);
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<OrderProvider>();
      if (!provider.hasLoadedOnce) provider.initializeOrders();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {}); // show/hide the clear button
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (mounted) context.read<OrderProvider>().setSearchQuery(value);
    });
  }

  void _clearSearch() {
    _searchController.clear();
    context.read<OrderProvider>().setSearchQuery('');
    setState(() {});
  }

  Future<void> _refresh() => context.read<OrderProvider>().initializeOrders();

  @override
  Widget build(BuildContext context) {
    final isClockedIn = context.select<AuthProvider, bool>((a) => a.isClockedIn);
    if (AppConfig.isAttendanceEnabled && !isClockedIn) {
      return const Scaffold(body: _ShiftGate());
    }

    return Scaffold(
      body: Column(
        children: [
          _Header(
            searchController: _searchController,
            onSearchChanged: _onSearchChanged,
            onClearSearch: _clearSearch,
          ),
          const SizedBox(height: 14),
          _PillTabs(controller: _tabController),
          const SizedBox(height: 6),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _OrderList(tab: _OrderTab.upcoming, onRefresh: _refresh),
                _OrderList(tab: _OrderTab.ongoing, onRefresh: _refresh),
                _OrderList(tab: _OrderTab.completed, onRefresh: _refresh),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header: greeting, today's live counters and search
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({
    required this.searchController,
    required this.onSearchChanged,
    required this.onClearSearch,
  });

  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final name = context.select<AuthProvider, String>((a) => a.currentRider?.name ?? 'Rider');
    final orders = context.watch<OrderProvider>();
    final firstName = name.split(' ').first;

    return InkHero(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${_greeting()},',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 14)),
                    const SizedBox(height: 2),
                    Text(firstName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                  ],
                ),
              ),
              _LiveDot(active: orders.hasLoadedOnce && orders.error == null),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _HeaderStat(label: 'Waiting', value: '${orders.availableCount}', icon: Icons.bolt_rounded),
              _HeaderStat(label: 'On the way', value: '${orders.acceptedCount}', icon: Icons.two_wheeler_rounded),
              _HeaderStat(
                  label: 'Delivered', value: '${orders.deliveredToday.length}', icon: Icons.task_alt_rounded),
              _HeaderStat(
                  label: 'Cash', value: formatRs(orders.totalCashToCollect), icon: Icons.payments_rounded),
            ],
          ),
          const SizedBox(height: 18),
          TextField(
            controller: searchController,
            onChanged: onSearchChanged,
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              hintText: 'Search name, phone or order no.',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: searchController.text.isEmpty
                  ? null
                  : IconButton(icon: const Icon(Icons.close_rounded), onPressed: onClearSearch),
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? const Color(0xFF34D399) : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(active ? 'Live' : 'Connecting',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _HeaderStat extends StatelessWidget {
  const _HeaderStat({required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: Colors.white.withValues(alpha: 0.55)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.55), fontSize: 11.5)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pill tab bar with live counts
// ─────────────────────────────────────────────────────────────────────────────

class _PillTabs extends StatelessWidget {
  const _PillTabs({required this.controller});
  final TabController controller;

  @override
  Widget build(BuildContext context) {
    final o = context.watch<OrderProvider>();
    final counts = [o.availableOrders.length, o.acceptedOrders.length, o.completedOrders.length];
    const labels = ['Upcoming', 'Ongoing', 'Completed'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        height: 48,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppColors.cardShadow,
        ),
        child: TabBar(
          controller: controller,
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          indicator: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(12),
          ),
          labelColor: Colors.white,
          unselectedLabelColor: AppColors.textSecondary,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          splashBorderRadius: BorderRadius.circular(12),
          tabs: [
            for (var i = 0; i < 3; i++)
              Tab(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(child: Text(labels[i], overflow: TextOverflow.fade, softWrap: false)),
                    if (counts[i] > 0) ...[
                      const SizedBox(width: 6),
                      _CountBubble(count: counts[i], selected: controller.index == i),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CountBubble extends StatelessWidget {
  const _CountBubble({required this.count, required this.selected});
  final int count;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: selected ? Colors.white.withValues(alpha: 0.25) : AppColors.primarySoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text('$count',
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w800, color: selected ? Colors.white : AppColors.primary)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Lists
// ─────────────────────────────────────────────────────────────────────────────

enum _OrderTab { upcoming, ongoing, completed }

class _OrderList extends StatelessWidget {
  const _OrderList({required this.tab, required this.onRefresh});
  final _OrderTab tab;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrderProvider>();
    final orders = switch (tab) {
      _OrderTab.upcoming => provider.availableOrders,
      _OrderTab.ongoing => provider.acceptedOrders,
      _OrderTab.completed => provider.completedOrders,
    };

    Widget body;
    if (!provider.hasLoadedOnce && provider.error == null) {
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: const [SkeletonCard(), SkeletonCard(), SkeletonCard()],
      );
    } else if (orders.isEmpty) {
      final searching = provider.query.isNotEmpty;
      final (icon, title, message) = searching
          ? (Icons.search_off_rounded, 'No matches', 'No order matches “${provider.query}”.')
          : provider.error != null
              ? (Icons.cloud_off_rounded, 'Connection problem', provider.error!)
              : switch (tab) {
                  _OrderTab.upcoming => (
                      Icons.inbox_rounded,
                      'No new orders',
                      'New orders for your branch appear here instantly.'
                    ),
                  _OrderTab.ongoing => (
                      Icons.two_wheeler_rounded,
                      'Nothing on the way',
                      'Accept an order from Upcoming to start delivering.'
                    ),
                  _OrderTab.completed => (
                      Icons.task_alt_rounded,
                      'No deliveries yet today',
                      'Orders you deliver today are listed here.'
                    ),
                };
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [EmptyState(icon: icon, title: title, message: message)],
      );
    } else {
      body = ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
        itemCount: orders.length,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: OrderCard(order: orders[i], mode: tab.name),
        ),
      );
    }

    return RefreshIndicator(color: AppColors.primary, onRefresh: onRefresh, child: body);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Order card
// ─────────────────────────────────────────────────────────────────────────────

({String label, Color color, IconData icon}) orderStatusStyle(Order order) {
  switch (order.status) {
    case OrderStatus.pending:
      return (label: 'NEW', color: AppColors.info, icon: Icons.fiber_new_rounded);
    case OrderStatus.accepted:
      return (label: 'PREPARING', color: AppColors.warning, icon: Icons.hourglass_top_rounded);
    case OrderStatus.pickedUp:
      return (label: 'DISPATCHED', color: AppColors.purple, icon: Icons.two_wheeler_rounded);
    case OrderStatus.delivered:
      return (label: 'DELIVERED', color: AppColors.success, icon: Icons.check_circle_rounded);
    case OrderStatus.cancelled:
      return (label: 'CANCELLED', color: AppColors.error, icon: Icons.cancel_rounded);
  }
}

class OrderCard extends StatelessWidget {
  const OrderCard({super.key, required this.order, required this.mode});

  final Order order;
  final String mode; // upcoming | ongoing | completed

  @override
  Widget build(BuildContext context) {
    final style = orderStatusStyle(order);
    final isUpcoming = mode == 'upcoming';
    final isOldOrder = order.createdAt.isBefore(TimeUtils.startOfToday());

    return PremiumCard(
      padding: EdgeInsets.zero,
      onTap: () => showOrderDetails(context, order),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 0),
            child: Row(
              children: [
                Text('#${order.reference}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
                const SizedBox(width: 8),
                if (isOldOrder)
                  const StatusChip(label: 'YESTERDAY', color: AppColors.warning, icon: Icons.history_rounded),
                const Spacer(),
                StatusChip(label: style.label, color: style.color, icon: style.icon),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              mode == 'completed' && order.deliveredAt != null
                  ? 'Delivered ${TimeUtils.relative(order.deliveredAt!)}'
                  : 'Placed ${TimeUtils.relative(order.createdAt)}',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const IconBadge(icon: Icons.person_rounded, color: AppColors.primary, size: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(order.customerName.isEmpty ? 'Customer' : order.customerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(order.deliveryAddress.isEmpty ? 'Address not provided' : order.deliveryAddress,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.35)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            decoration: const BoxDecoration(
              color: Color(0xFFFAFAFC),
              border: Border(top: BorderSide(color: AppColors.borderLight)),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(formatRs(order.amount),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _PaymentChip(order: order),
                        if (order.deliveryKms > 0) ...[
                          const SizedBox(width: 6),
                          StatusChip(
                            label: '${order.deliveryKms.toStringAsFixed(1)} km',
                            color: AppColors.textSecondary,
                            icon: Icons.route_rounded,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                if (isUpcoming) _AcceptButton(order: order),
                if (mode == 'ongoing') _OngoingAction(order: order),
                if (mode == 'completed')
                  const Icon(Icons.chevron_right_rounded, color: AppColors.textLight),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentChip extends StatelessWidget {
  const _PaymentChip({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    return order.isCashOnDelivery
        ? const StatusChip(label: 'COLLECT CASH', color: Color(0xFFB45309), icon: Icons.payments_rounded)
        : const StatusChip(label: 'PAID', color: AppColors.success, icon: Icons.verified_rounded);
  }
}

class _AcceptButton extends StatelessWidget {
  const _AcceptButton({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final busy = context.select<OrderProvider, bool>((p) => p.isBusy(order.id));
    return FilledButton.icon(
      onPressed: busy ? null : () => confirmAccept(context, order),
      style: FilledButton.styleFrom(minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 18)),
      icon: busy
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.check_rounded, size: 18),
      label: Text(busy ? 'Accepting' : 'Accept'),
    );
  }
}

class _OngoingAction extends StatelessWidget {
  const _OngoingAction({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    if (!order.isDispatched) {
      return const StatusChip(
        label: 'WAITING FOR DISPATCH',
        color: AppColors.textSecondary,
        icon: Icons.schedule_rounded,
      );
    }
    return FilledButton.icon(
      onPressed: () => startRide(context, order),
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        backgroundColor: AppColors.ink,
      ),
      icon: const Icon(Icons.navigation_rounded, size: 18),
      label: const Text('Start Ride'),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Actions shared by the card and the detail sheet
// ─────────────────────────────────────────────────────────────────────────────

Future<void> confirmAccept(BuildContext context, Order order) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const IconBadge(icon: Icons.delivery_dining_rounded, color: AppColors.primary, size: 52),
      title: Text('Accept #${order.reference}?', textAlign: TextAlign.center),
      content: Text(
        '${order.customerName}\n${formatRs(order.amount)} · ${order.paymentLabel}',
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Accept order')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  HapticFeedback.mediumImpact();
  final provider = context.read<OrderProvider>();
  final success = await provider.acceptOrder(order.id);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(success
        ? 'Order #${order.reference} accepted — find it in Ongoing'
        : (provider.error ?? 'Could not accept the order')),
    backgroundColor: success ? AppColors.success : AppColors.error,
  ));
}

void startRide(BuildContext context, Order order) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => MapScreen(order: order)));
}

Future<void> callCustomer(BuildContext context, String phone) async {
  final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  if (digits.isEmpty) return;
  final uri = Uri(scheme: 'tel', path: digits);
  if (!await launchUrl(uri) && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the phone app')));
  }
}

Future<void> openInGoogleMaps(BuildContext context, double lat, double lng) async {
  final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open Google Maps')));
  }
}

void showOrderDetails(BuildContext context, Order order) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => OrderDetailsSheet(order: order),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Detail sheet (live-updating)
// ─────────────────────────────────────────────────────────────────────────────

class OrderDetailsSheet extends StatefulWidget {
  const OrderDetailsSheet({super.key, required this.order});
  final Order order;

  @override
  State<OrderDetailsSheet> createState() => _OrderDetailsSheetState();
}

class _OrderDetailsSheetState extends State<OrderDetailsSheet> {
  late Order _order = widget.order;
  StreamSubscription<Map<String, dynamic>?>? _sub;

  @override
  void initState() {
    super.initState();
    // Only this order's document — not the whole collection.
    _sub = FirebaseService.streamOrder(widget.order.id).listen((data) {
      if (data == null || !mounted) return;
      try {
        setState(() => _order = Order.fromJson(data));
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final o = _order;
    final style = orderStatusStyle(o);
    final riderId = context.select<AuthProvider, String?>((a) => a.currentRider?.id);
    final mine = o.acceptedBy?.toString() == riderId;
    final hasLocation = o.deliveryLatitude != 0.0 && o.deliveryLongitude != 0.0;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('#${o.reference}',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
                    const SizedBox(height: 2),
                    Text('${o.branchName} · ${TimeUtils.relative(o.createdAt)}',
                        style: const TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
              StatusChip(label: style.label, color: style.color, icon: style.icon),
            ],
          ),
          const SizedBox(height: 16),
          _AmountBanner(order: o),
          const SizedBox(height: 14),
          const SectionTitle('Customer'),
          PremiumCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Column(
              children: [
                InfoRow(
                  icon: Icons.person_rounded,
                  label: 'Name',
                  value: o.customerName,
                ),
                const Divider(),
                InfoRow(
                  icon: Icons.phone_rounded,
                  label: 'Phone',
                  value: o.customerPhone,
                  trailing: o.customerPhone.isEmpty
                      ? null
                      : IconButton.filledTonal(
                          onPressed: () => callCustomer(context, o.customerPhone),
                          icon: const Icon(Icons.call_rounded),
                          color: AppColors.success,
                        ),
                ),
                const Divider(),
                InfoRow(
                  icon: Icons.location_on_rounded,
                  label: 'Delivery address',
                  value: o.deliveryAddress,
                  trailing: hasLocation
                      ? IconButton.filledTonal(
                          onPressed: () => openInGoogleMaps(context, o.deliveryLatitude, o.deliveryLongitude),
                          icon: const Icon(Icons.directions_rounded),
                          color: AppColors.info,
                        )
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SectionTitle('Items', trailing: Text('${o.items.length}', style: const TextStyle(color: AppColors.textSecondary))),
          PremiumCard(
            child: o.items.isEmpty
                ? const Text('No items listed', style: TextStyle(color: AppColors.textSecondary))
                : Column(
                    children: [
                      for (final item in o.items)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Text(item, style: const TextStyle(fontWeight: FontWeight.w600))),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 10),
          const SectionTitle('Progress'),
          PremiumCard(child: _Timeline(order: o)),
          const SizedBox(height: 20),
          if (o.status == OrderStatus.pending)
            _AcceptButtonLarge(order: o)
          else if (mine && o.status == OrderStatus.accepted)
            const _InfoBanner(
              icon: Icons.schedule_rounded,
              text: 'Waiting for the branch to dispatch this order. You will get a notification.',
            )
          else if (mine && o.status == OrderStatus.pickedUp)
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(context);
                startRide(context, o);
              },
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56), backgroundColor: AppColors.ink),
              icon: const Icon(Icons.navigation_rounded),
              label: const Text('Start Ride'),
            ),
        ],
      ),
    );
  }
}

class _AcceptButtonLarge extends StatelessWidget {
  const _AcceptButtonLarge({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final busy = context.select<OrderProvider, bool>((p) => p.isBusy(order.id));
    return FilledButton.icon(
      onPressed: busy
          ? null
          : () async {
              await confirmAccept(context, order);
              if (context.mounted) Navigator.maybePop(context);
            },
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
      icon: const Icon(Icons.check_rounded),
      label: Text(busy ? 'Accepting…' : 'Accept Order'),
    );
  }
}

class _AmountBanner extends StatelessWidget {
  const _AmountBanner({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final cod = order.isCashOnDelivery;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: cod ? AppColors.primaryGradient : AppColors.inkGradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cod ? 'Collect from customer' : 'Already paid',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(formatRs(order.amount),
                    style: const TextStyle(
                        color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.8)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              StatusChip(
                label: order.paymentLabel.toUpperCase(),
                color: Colors.white,
                background: Colors.white.withValues(alpha: 0.18),
              ),
              if (order.deliveryKms > 0) ...[
                const SizedBox(height: 8),
                Text('${order.deliveryKms.toStringAsFixed(1)} km',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.order});
  final Order order;

  @override
  Widget build(BuildContext context) {
    final steps = <(String, DateTime?, IconData)>[
      ('Order placed', order.createdAt, Icons.receipt_long_rounded),
      ('Accepted by you', order.acceptedAt, Icons.handshake_rounded),
      ('Dispatched', order.pickedUpAt, Icons.two_wheeler_rounded),
      ('Delivered', order.deliveredAt, Icons.check_circle_rounded),
    ];
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          _TimelineStep(
            title: steps[i].$1,
            time: steps[i].$2,
            icon: steps[i].$3,
            isLast: i == steps.length - 1,
            nextDone: i < steps.length - 1 && steps[i + 1].$2 != null,
          ),
        if (order.pickedUpAt != null && order.deliveredAt != null) ...[
          const Divider(height: 20),
          Row(
            children: [
              const Icon(Icons.timer_outlined, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Text('Ride time ${TimeUtils.duration(order.deliveredAt!.difference(order.pickedUpAt!))}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ],
      ],
    );
  }
}

class _TimelineStep extends StatelessWidget {
  const _TimelineStep({
    required this.title,
    required this.time,
    required this.icon,
    required this.isLast,
    required this.nextDone,
  });
  final String title;
  final DateTime? time;
  final IconData icon;
  final bool isLast;
  final bool nextDone;

  @override
  Widget build(BuildContext context) {
    final done = time != null;
    final color = done ? AppColors.success : AppColors.textLight;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 30,
            child: Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: done ? AppColors.successSoft : AppColors.canvas,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: nextDone ? AppColors.success.withValues(alpha: 0.4) : AppColors.border,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 4, bottom: isLast ? 0 : 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: done ? AppColors.textPrimary : AppColors.textLight,
                        )),
                  ),
                  Text(done ? TimeUtils.relative(time!) : 'Pending',
                      style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.infoSoft, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Icon(icon, color: AppColors.info),
          const SizedBox(width: 12),
          Expanded(
              child: Text(text,
                  style: const TextStyle(color: AppColors.accentDark, fontWeight: FontWeight.w600, height: 1.35))),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Attendance gate (only when attendance is switched on in AppConfig)
// ─────────────────────────────────────────────────────────────────────────────

class _ShiftGate extends StatelessWidget {
  const _ShiftGate();

  @override
  Widget build(BuildContext context) {
    return EmptyStateWithAction(
      icon: Icons.timer_outlined,
      title: 'Shift inactive',
      message: 'Clock in to start receiving and accepting delivery orders.',
      actionLabel: 'Go to Shift',
      onAction: () => TabNavigationNotification(0).dispatch(context),
    );
  }
}

class EmptyStateWithAction extends StatelessWidget {
  const EmptyStateWithAction({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          EmptyState(icon: icon, title: title, message: message),
          FilledButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}
