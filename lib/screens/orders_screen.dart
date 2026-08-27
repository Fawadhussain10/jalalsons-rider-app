import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/order_provider.dart';
import '../providers/auth_provider.dart';
import '../services/firebase_service.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_text_field.dart';
import '../utils/app_colors.dart';
import 'main_navigation.dart';
import 'map_screen.dart';
import '../widgets/js_logo.dart';
import '../config/app_config.dart';

// Import ButtonSize enum
import '../widgets/custom_button.dart' show ButtonSize;

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Initialize orders from Firestore
      context.read<OrderProvider>().initializeOrders();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final isClockedIn = authProvider.isClockedIn;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            JSLogoSmall(size: 28, showBorder: false),
            const SizedBox(width: 8),
            const Text('Orders'),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              context.read<OrderProvider>().initializeOrders();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Theme.of(context).colorScheme.primary,
          unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
          indicatorColor: Theme.of(context).colorScheme.primary,
          tabs: const [
            Tab(text: 'Upcoming'),
            Tab(text: 'Ongoing'),
            Tab(text: 'Completed'),
          ],
        ),
      ),
      body: (AppConfig.isAttendanceEnabled && !isClockedIn) 
        ? _buildShiftGateBanner()
        : Column(
            children: [
              // Tab Views
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildAvailableOrders(),
                    _buildActiveOrders(),
                    _buildCompletedOrders(),
                  ],
                ),
              ),
            ],
          ),
    );
  }

  Widget _buildShiftGateBanner() {
    return Container(
      width: double.infinity,
      color: Colors.white,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Elegant Icon Container
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.04),
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.primary.withOpacity(0.08), width: 1.5),
                ),
                child: Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 60,
                        color: AppColors.primary,
                      ),
                      Positioned(
                        bottom: 40,
                        right: 15,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.lock,
                            size: 16,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40),
              
              // Descriptive Text
              const Text(
                'Shift Inactive',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Clock-In to start receiving and accepting delivery orders in your area.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.black54,
                  height: 1.4,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 48),
              
              // Branded Action Button
              Container(
                width: double.infinity,
                height: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.15),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: () {
                    // Dispatch notification to switch to the Shift tab (index 0)
                    TabNavigationNotification(0).dispatch(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'GO TO SHIFT TAB',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
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

  Widget _buildAvailableOrders() {
    return Consumer<OrderProvider>(
      builder: (context, orderProvider, child) {
        final availableOrders = orderProvider.availableOrders;

        if (availableOrders.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('No available orders'),
                Text('Check back later for new orders'),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16.0),
          itemCount: availableOrders.length,
          itemBuilder: (context, index) {
            final order = availableOrders[index];
            return _buildOrderCard(order, isAvailable: true);
          },
        );
      },
    );
  }

  Widget _buildActiveOrders() {
    return Consumer<OrderProvider>(
      builder: (context, orderProvider, child) {
        final activeOrders = orderProvider.acceptedOrders;

        if (activeOrders.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.delivery_dining, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('No active orders'),
                Text('Accept an order to get started'),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16.0),
          itemCount: activeOrders.length,
          itemBuilder: (context, index) {
            final order = activeOrders[index];
            return _buildOrderCard(order, isAvailable: false);
          },
        );
      },
    );
  }

  Widget _buildCompletedOrders() {
    return Consumer<OrderProvider>(
      builder: (context, orderProvider, child) {
        final completedOrders = orderProvider.completedOrders;

        if (completedOrders.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text('No completed orders'),
                Text('Completed orders will appear here'),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16.0),
          itemCount: completedOrders.length,
          itemBuilder: (context, index) {
            final order = completedOrders[index];
            return _buildCompletedOrderCard(order);
          },
        );
      },
    );
  }

  Widget _buildOrderCard(dynamic order, {required bool isAvailable}) {
    final statusColor = _getStatusColor(order.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12.0, left: 8.0, right: 8.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            if (!isAvailable) {
              _showOrderDetails(order);
            }
          },
          child: Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.white,  
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                // Left side - Delivery location (more prominent)
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Delivery location - now more prominent
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.location_on,
                              size: 20,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Delivery Location',
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  order.deliveryAddress,
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Colors.grey.shade800,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 12),
                      
                      // Order number - now under delivery location
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Order #${order.reference}',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(width: 16),
                
                // Right side - Amount and action
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Amount
                      Text(
                        '${order.amount.toStringAsFixed(0)}',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.green.shade600,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      
                      const SizedBox(height: 8),
                      
                      // Status or action button
                      if (isAvailable)
                        Container(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => _acceptOrder(order),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              'Accept',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            order.status?.toString().split('.').last.toUpperCase() ?? 'PENDING',
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompletedOrderCard(dynamic order) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12.0, left: 8.0, right: 8.0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            _showCompletedOrderDetails(order);
          },
          child: Container(
            padding: const EdgeInsets.all(16.0),
            decoration: BoxDecoration(
              color: Colors.white,  
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                // Left side - Delivery location
                Expanded(
                  flex: 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Delivery location
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.location_on,
                              size: 20,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Delivered',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  order.deliveryAddress,
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Colors.grey.shade800,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      
                      const SizedBox(height: 12),
                      
                      // Order number
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Order #${order.reference}',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(width: 16),
                
                // Right side - Amount and status
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Amount
                      Text(
                        '${order.amount.toStringAsFixed(0)}',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.grey.shade800,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      
                      const SizedBox(height: 8),
                      
                      // Completed status
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'COMPLETED',
                          style: TextStyle(
                            color: Colors.grey.shade700,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Color _getPriorityColor(OrderPriority priority) {
  //   switch (priority) {
  //     case OrderPriority.high:
  //       return Colors.red;
  //     case OrderPriority.medium:
  //       return Colors.orange;
  //     case OrderPriority.low:
  //       return Colors.green;
  //     case OrderPriority.urgent:
  //       return Colors.red[900]!;
  //   }
  // }

  Color _getStatusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return Colors.orange;
      case OrderStatus.accepted:
        return AppColors.primary;
      case OrderStatus.pickedUp:
        return Colors.purple;
      case OrderStatus.delivered:
        return Colors.green;
      case OrderStatus.cancelled:
        return Colors.red;
    }
  }

  void _acceptOrder(dynamic order) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Accept Order'),
        content: Text('Are you sure you want to accept this order from ${order.customerName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          CustomButton(
            text: 'Accept',
            onPressed: () {
              Navigator.pop(context);
              context.read<OrderProvider>().acceptOrder(order.id, 'current_rider_id');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Order accepted! Navigate to ${order.customerName}'),
                  backgroundColor: Colors.green,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showOrderDetails(dynamic order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => OrderDetailsBottomSheet(order: order),
    );
  }

  void _showCompletedOrderDetails(dynamic order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => CompletedOrderDetailsBottomSheet(order: order),
    );
  }
}

class OrderDetailsBottomSheet extends StatefulWidget {
  final dynamic order;

  const OrderDetailsBottomSheet({super.key, required this.order});

  @override
  State<OrderDetailsBottomSheet> createState() => _OrderDetailsBottomSheetState();
}

class _OrderDetailsBottomSheetState extends State<OrderDetailsBottomSheet> {
  dynamic _currentOrder;
  StreamSubscription<List<Map<String, dynamic>>>? _orderStreamSubscription;

  @override
  void initState() {
    super.initState();
    _currentOrder = widget.order;
    
    // Listen to real-time updates for this specific order
    _listenToOrderUpdates();
  }

  @override
  void dispose() {
    _orderStreamSubscription?.cancel();
    super.dispose();
  }

  void _listenToOrderUpdates() {
    // Store the current order ID for comparison
    final currentOrderId = _currentOrder.id.toString();
    
    // Listen to Firestore for this specific order
    _orderStreamSubscription = FirebaseService.streamOrders().listen((orders) {
      if (!mounted) return;
      
      try {
        // Find the updated order by comparing IDs (convert both to strings for safety)
        final updatedOrder = orders.firstWhere(
          (order) => order['id']?.toString() == currentOrderId,
        );
        
        // Create new Order object from updated JSON
        final newOrder = Order.fromJson(updatedOrder);
        
        // Only update if something actually changed (to avoid unnecessary rebuilds)
        if (newOrder.id == _currentOrder.id) {
          setState(() {
            _currentOrder = newOrder;
          });
        }
      } catch (e) {
        // Order not found in the stream, which can happen if:
        // - Order was removed
        // - Order doesn't exist
        // - Stream hasn't received the order yet
        // This is normal and we don't need to handle it
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(top:  25.0),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(0),
          topRight: Radius.circular(0),
        ),
      ),
      child: Column(
        children: [
          // Header with back button and handle bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade200, width: 1),
              ),
            ),
            child: Row(
              children: [
                // Back button
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.arrow_back,
                    color: Colors.grey.shade700,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 8),
                // Title
                Expanded(
                  child: Text(
                    'Order Details',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ),
                // Handle bar
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
          
          // Scrollable content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // Customer Section
                  Text(
                    'Customer',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Customer Profile
                  Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: Icon(
                          Icons.person,
                          size: 30,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _currentOrder.customerName,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                            Text(
                              _currentOrder.deliveryAddress,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_currentOrder.deliveryLatitude != 0.0 && _currentOrder.deliveryLongitude != 0.0)
                        IconButton(
                          icon: const Icon(Icons.directions, color: Colors.blue),
                          onPressed: () => _openInGoogleMaps(_currentOrder.deliveryLatitude, _currentOrder.deliveryLongitude),
                          tooltip: 'Open in Google Maps',
                        ),
                    ],
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Order Section
                  Text(
                    'Order',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Order Summary Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.chat_bubble_outline,
                          size: 24,
                          color: Colors.black,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Order #${_currentOrder.id}',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black,
                                ),
                              ),
                              Text(
                                '${_currentOrder.items.length} item${_currentOrder.items.length != 1 ? 's' : ''}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Order Items
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.primary, style: BorderStyle.solid),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_currentOrder.items.isNotEmpty) ...[
                          Text(
                            'Order Items (${_currentOrder.items.length}):',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: _currentOrder.items.map<Widget>((item) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppColors.primary.withOpacity(0.2), width: 1),
                              ),
                              child: Text(
                                item,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                            )).toList(),
                          ),
                        ] else ...[
                          Center(
                            child: Text(
                              'No items specified',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Order Amount
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${_currentOrder.amount.toStringAsFixed(0)} ${_currentOrder.currency}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Delivery Section
                  Text(
                    'Delivery',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Delivery Location Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 24,
                          color: Colors.black,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _currentOrder.customerName,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black,
                                ),
                              ),
                              Text(
                                _currentOrder.deliveryAddress,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_currentOrder.deliveryLatitude != 0.0 && _currentOrder.deliveryLongitude != 0.0)
                          IconButton(
                            icon: const Icon(Icons.directions, color: Colors.blue),
                            onPressed: () => _openInGoogleMaps(_currentOrder.deliveryLatitude, _currentOrder.deliveryLongitude),
                            tooltip: 'Open in Google Maps',
                          ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 32),
                  
                  // Start Ride Button - Only show if order is dispatched
                  _buildStartRideButton(context, _currentOrder),
                  
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Build Start Ride button based on order state
  Widget _buildStartRideButton(BuildContext context, dynamic order) {
    // Check if order has stateTrail and is in dispatched state
    final stateTrail = order.stateTrail as Map<String, dynamic>?;
    final dispatchedState = stateTrail?['dispatched'];
    final isDispatched = dispatchedState != null && dispatchedState['at'] != null;
    
    if (!isDispatched) {
      // Order is not dispatched yet - show disabled button with message
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          children: [
            Icon(
              Icons.schedule,
              color: Colors.grey.shade600,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              'Order Not Dispatched Yet',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            // const SizedBox(height: 4),
            // Text(
            //   'Wait for the order to be dispatched before starting your ride',
            //   style: TextStyle(
            //     fontSize: 14,
            //     color: Colors.grey.shade600,
            //   ),
            //   textAlign: TextAlign.center,
            // ),
          ],
        ),
      );
    }
    
    // Order is dispatched - show Start Ride button
    return SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => MapScreen(order: order),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        'Start Ride',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
      ),
    );
  }

  Future<void> _openInGoogleMaps(double lat, double lng) async {
    final url = 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng';
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open Google Maps app')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error opening Google Maps: $e');
    }
  }
}

class CompletedOrderDetailsBottomSheet extends StatefulWidget {
  final dynamic order;

  const CompletedOrderDetailsBottomSheet({super.key, required this.order});

  @override
  State<CompletedOrderDetailsBottomSheet> createState() => _CompletedOrderDetailsBottomSheetState();
}

class _CompletedOrderDetailsBottomSheetState extends State<CompletedOrderDetailsBottomSheet> {
  dynamic _currentOrder;
  StreamSubscription<List<Map<String, dynamic>>>? _orderStreamSubscription;

  @override
  void initState() {
    super.initState();
    _currentOrder = widget.order;
    
    // Listen to real-time updates for this specific order
    _listenToOrderUpdates();
  }

  @override
  void dispose() {
    _orderStreamSubscription?.cancel();
    super.dispose();
  }

  void _listenToOrderUpdates() {
    // Store the current order ID for comparison
    final currentOrderId = _currentOrder.id.toString();
    
    // Listen to Firestore for this specific order
    _orderStreamSubscription = FirebaseService.streamOrders().listen((orders) {
      if (!mounted) return;
      
      try {
        // Find the updated order by comparing IDs (convert both to strings for safety)
        final updatedOrder = orders.firstWhere(
          (order) => order['id']?.toString() == currentOrderId,
        );
        
        // Create new Order object from updated JSON
        final newOrder = Order.fromJson(updatedOrder);
        
        // Only update if something actually changed (to avoid unnecessary rebuilds)
        if (newOrder.id == _currentOrder.id) {
          setState(() {
            _currentOrder = newOrder;
          });
        }
      } catch (e) {
        // Order not found in the stream, which can happen if:
        // - Order was removed
        // - Order doesn't exist
        // - Stream hasn't received the order yet
        // This is normal and we don't need to handle it
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Column(
        children: [
          // Professional Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade200, width: 1),
              ),
            ),
            child: Column(
              children: [
                // Handle bar
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                // Header content
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        Icons.close,
                        color: Colors.grey.shade600,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Order #${_currentOrder.id}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade800,
                            ),
                          ),
                          Text(
                            'Completed Delivery',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        'COMPLETED',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Scrollable content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Customer Information Card
                  _buildCustomerCard(),
                  
                  const SizedBox(height: 12),
                  
                  // Order Summary Card
                  _buildOrderSummaryCard(),
                  
                  const SizedBox(height: 12),
                  
                  // Delivery Metrics Card
                  _buildDeliveryMetricsCard(),
                  
                  const SizedBox(height: 12),
                  
                  // Payment Information Card
                  _buildPaymentCard(),
                  
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.person_outline,
                size: 20,
                color: Colors.blue.shade600,
              ),
              const SizedBox(width: 8),
              Text(
                'Customer',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildCompactInfoRow('Name', _currentOrder.customerName),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildCompactInfoRow('Address', _currentOrder.deliveryAddress),
              ),
              if (_currentOrder.deliveryLatitude != 0.0 && _currentOrder.deliveryLongitude != 0.0)
                IconButton(
                  icon: const Icon(Icons.directions, color: Colors.blue),
                  onPressed: () => _openInGoogleMaps(_currentOrder.deliveryLatitude, _currentOrder.deliveryLongitude),
                  tooltip: 'Open in Google Maps',
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrderSummaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.shopping_bag_outlined,
                size: 20,
                color: Colors.orange.shade600,
              ),
              const SizedBox(width: 8),
              Text(
                'Order Items (${_currentOrder.items.length})',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_currentOrder.items.isNotEmpty) ...[
            ...(_currentOrder.items.take(3).map<Widget>((item) => Container(
              margin: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.orange.shade400,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            )).toList()),
            if (_currentOrder.items.length > 3) ...[
              const SizedBox(height: 4),
              Text(
                '+${_currentOrder.items.length - 3} more items',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ] else ...[
            Text(
              'No items specified',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDeliveryMetricsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.timeline_outlined,
                size: 20,
                color: Colors.purple.shade600,
              ),
              const SizedBox(width: 8),
              Text(
                'Delivery Metrics',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildCompactMetricItem(
                  'Time',
                  _getDeliveryTime(),
                  Icons.access_time,
                  AppColors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildCompactMetricItem(
                  'Distance',
                  _getTravelDistance(),
                  Icons.straighten,
                  Colors.green,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.payment_outlined,
                size: 20,
                color: Colors.green.shade600,
              ),
              const SizedBox(width: 8),
              Text(
                'Payment',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildCompactInfoRow('Status', _getPaymentStatus()),
        ],
      ),
    );
  }

  Widget _buildCompactInfoRow(String label, String value) {
    return Row(
      children: [
        Text(
          '$label:',
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade800,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactMetricItem(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 18,
            color: color,
          ),
          const SizedBox(height: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }


  String _getDeliveryTime() {
    // Calculate time from start ride to delivered from Firestore stateTrail
    final stateTrail = _currentOrder.stateTrail as Map<String, dynamic>?;
    final dispatchedAt = stateTrail?['dispatched']?['at'];
    final deliveredAt = stateTrail?['delivered']?['at'];

    DateTime? toDateTime(dynamic value) {
      try {
        if (value == null) return null;
        if (value is DateTime) return value;
        if (value is String && value.isNotEmpty) return DateTime.parse(value);
        if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
        if (value is double) return DateTime.fromMillisecondsSinceEpoch(value.toInt());
      } catch (_) {}
      return null;
    }

    final startTime = toDateTime(dispatchedAt);
    final endTime = toDateTime(deliveredAt);

    if (startTime != null && endTime != null && endTime.isAfter(startTime)) {
      final duration = endTime.difference(startTime);
      if (duration.inHours > 0) {
        final minutes = duration.inMinutes % 60;
        return '${duration.inHours}h ${minutes}m';
      }
      return '${duration.inMinutes}m';
    }
    return 'N/A';
  }

  String _getTravelDistance() {
    // Get travel distance from Firestore order data
    // Check if distance is stored in the order document
    try {
      final dynamic maybeDistance = (_currentOrder as dynamic).distance;
      if (maybeDistance != null) {
        final numDistance = (maybeDistance is num)
            ? maybeDistance
            : num.tryParse(maybeDistance.toString());
        if (numDistance != null && numDistance > 0) {
          return '${numDistance.toStringAsFixed(1)} km';
        }
      }
    } catch (_) {
      // distance not present on model
    }
    
    // Fallback: calculate from customer location if available
    try {
      // Optional fallback if customer location is a Map on the model
      final customer = (_currentOrder as dynamic).customer;
      if (customer is Map) {
        final location = customer['location'];
        if (location is Map && location['latitude'] != null && location['longitude'] != null) {
          return '—';
        }
      }
    } catch (_) {}
    
    return 'N/A';
  }

  String _getPaymentStatus() {
    if (_currentOrder.amount > 0) {
      return '${_currentOrder.amount.toStringAsFixed(0)} ${_currentOrder.currency}';
    }
    return 'Already Paid';
  }

  Future<void> _openInGoogleMaps(double lat, double lng) async {
    final url = 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng';
    final uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open Google Maps app')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error opening Google Maps: $e');
    }
  }
}
