import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';
import '../providers/order_provider.dart';
import '../widgets/custom_button.dart';
import '../utils/app_colors.dart';
import '../widgets/js_logo.dart';
import 'proof_of_delivery_screen.dart';

class OrderDetailsScreen extends StatefulWidget {
  final String orderId;

  const OrderDetailsScreen({
    super.key,
    required this.orderId,
  });

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  @override
  Widget build(BuildContext context) {
    return Consumer<OrderProvider>(
      builder: (context, orderProvider, child) {
        final order = orderProvider.getOrderById(widget.orderId);
        
        if (order == null) {
          return Scaffold(
            appBar: AppBar(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              JSLogoSmall(size: 28, showBorder: false),
              const SizedBox(width: 8),
              const Text('Order Details'),
            ],
          ),
        ),
            body: const Center(child: Text('Order not found')),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            JSLogoSmall(size: 28, showBorder: false),
            const SizedBox(width: 8),
            Text('Order #${order.id}'),
          ],
        ),
            backgroundColor: Theme.of(context).colorScheme.surface,
            elevation: 0,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildOrderHeader(order),
                const SizedBox(height: 24),
                _buildCustomerInfo(order),
                const SizedBox(height: 24),
                _buildOrderDetails(order),
                const SizedBox(height: 24),
                _buildAddresses(order),
                const SizedBox(height: 24),
                _buildTimeline(order),
                const SizedBox(height: 32),
                _buildActionButtons(order, orderProvider),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOrderHeader(dynamic order) {
    final statusColor = _getStatusColor(order.status);
    final priorityColor = _getPriorityColor(order.priority);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Order #${order.reference}',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor),
                  ),
                  child: Text(
                    order.status?.toString().split('.').last.toUpperCase() ?? 'PENDING',
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Amount',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                    Text(
                      '\$${order.amount.toStringAsFixed(2)}',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: priorityColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: priorityColor),
                  ),
                  child: Text(
                    order.priority?.toString().split('.').last.toUpperCase() ?? 'MEDIUM',
                    style: TextStyle(
                      color: priorityColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerInfo(dynamic order) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Customer Information',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  child: Icon(
                    Icons.person,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.customerName,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Customer ID: ${order.id}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderDetails(dynamic order) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Order Details',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            _buildDetailRow('Order ID', '#${order.id}'),
            _buildDetailRow('Order Date', _formatDate(order.createdAt)),
            _buildDetailRow('Accepted Date', order.acceptedAt != null 
                ? _formatDate(order.acceptedAt)
                : 'Not accepted yet'),
            _buildDetailRow('Rider ID', order.riderId ?? 'Not assigned'),
          ],
        ),
      ),
    );
  }

  Widget _buildAddresses(dynamic order) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Addresses',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            _buildAddressCard(
              'Pickup Location',
              order.pickupAddress,
              Icons.location_on,
              Colors.green,
              lat: order.pickupLatitude,
              lng: order.pickupLongitude,
            ),
            const SizedBox(height: 16),
            _buildAddressCard(
              'Delivery Location',
              order.deliveryAddress,
              Icons.location_on_outlined,
              Colors.red,
              lat: order.deliveryLatitude,
              lng: order.deliveryLongitude,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddressCard(String title, String address, IconData icon, Color color, {double? lat, double? lng}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  address,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          if (lat != null && lng != null && lat != 0.0 && lng != 0.0)
            IconButton(
              icon: Icon(Icons.directions, color: Theme.of(context).colorScheme.primary),
              onPressed: () => _openInGoogleMaps(lat, lng),
              tooltip: 'Open in Google Maps',
            ),
        ],
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

  Widget _buildTimeline(dynamic order) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Order Timeline',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            _buildTimelineItem(
              'Order Created',
              _formatDate(order.timestamps['created']),
              Icons.shopping_cart,
              Colors.blue,
              true,
            ),
            _buildTimelineItem(
              'Order Accepted',
              order.timestamps['accepted'] != null 
                  ? _formatDate(order.timestamps['accepted'])
                  : 'Pending',
              Icons.check_circle,
              Colors.green,
              order.timestamps['accepted'] != null,
            ),
            _buildTimelineItem(
              'Order Picked Up',
              order.timestamps['pickedUp'] != null 
                  ? _formatDate(order.timestamps['pickedUp'])
                  : 'Pending',
              Icons.local_shipping,
              Colors.orange,
              order.timestamps['pickedUp'] != null,
            ),
            _buildTimelineItem(
              'Order Delivered',
              order.timestamps['delivered'] != null 
                  ? _formatDate(order.timestamps['delivered'])
                  : 'Pending',
              Icons.done_all,
              Colors.green,
              order.timestamps['delivered'] != null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineItem(String title, String time, IconData icon, Color color, bool isCompleted) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isCompleted ? color : Colors.grey[300],
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              icon,
              color: isCompleted ? Colors.white : Colors.grey[600],
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: isCompleted ? Colors.black : Colors.grey[600],
                  ),
                ),
                Text(
                  time,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isCompleted ? Colors.grey[600] : Colors.grey[400],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(dynamic order, OrderProvider orderProvider) {
    if (order.status == OrderStatus.accepted) {
      return Column(
        children: [
          CustomButton(
            text: 'Mark as Picked Up',
            onPressed: () => _updateOrderStatus(orderProvider, OrderStatus.pickedUp),
            backgroundColor: Colors.orange,
          ),
          const SizedBox(height: 12),
          CustomButton(
            text: 'Cancel Order',
            onPressed: () => _updateOrderStatus(orderProvider, OrderStatus.cancelled),
            isOutlined: true,
            backgroundColor: Colors.red,
            textColor: Colors.red,
          ),
        ],
      );
    } else if (order.status == OrderStatus.pickedUp) {
      return CustomButton(
        text: 'Mark as Delivered',
        icon: Icons.camera_alt,
        onPressed: () => _navigateToPOD(order),
        backgroundColor: Colors.green,
      );
    }
    
    return const SizedBox.shrink();
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[600],
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return Colors.orange;
      case OrderStatus.accepted:
        return Colors.blue;
      case OrderStatus.pickedUp:
        return Colors.purple;
      case OrderStatus.delivered:
        return Colors.green;
      case OrderStatus.cancelled:
        return Colors.red;
    }
  }

  Color _getPriorityColor(OrderPriority priority) {
    switch (priority) {
      case OrderPriority.high:
        return Colors.red;
      case OrderPriority.medium:
        return Colors.orange;
      case OrderPriority.low:
        return Colors.green;
      case OrderPriority.urgent:
        return Colors.red[900]!;
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'N/A';
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _navigateToPOD(dynamic order) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProofOfDeliveryScreen(
          order: order as Order,
        ),
      ),
    );

    if (result == true) {
      // POD submitted successfully, now mark as delivered locally to update UI
      // The API call for POD already happened in the screen, but we need to update the status in provider
      if (mounted) {
        final orderProvider = Provider.of<OrderProvider>(context, listen: false);
        _updateOrderStatus(orderProvider, OrderStatus.delivered);
      }
    }
  }

  void _updateOrderStatus(OrderProvider orderProvider, OrderStatus newStatus) async {
    // For delivered status, we assume POD handled the API call if it came from POD screen
    // But updateOrderStatus in provider might also make an API call. 
    // Ideally updateOrderStatus should check if it's already updated or we just update local state.
    // For now, let's proceed with the existing flow which is robust enough.
    
    final success = await orderProvider.updateOrderStatus(widget.orderId, newStatus);
    
    if (!mounted) return;

    if (success) {
      // If order was successfully delivered, refresh rider statistics
      if (newStatus == OrderStatus.delivered) {
        final authProvider = context.read<AuthProvider>();
        await authProvider.fetchRiderStatistics();
        if (!mounted) return;
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Order status updated to ${newStatus.toString().split('.').last.toUpperCase()}'),
          backgroundColor: Colors.green,
        ),
      );
      
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to update order status'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
