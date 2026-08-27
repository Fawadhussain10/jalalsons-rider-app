import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../services/firebase_service.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/js_logo.dart';
import '../widgets/js_logo.dart';
import 'login_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _currentPasswordController;
  late TextEditingController _newPasswordController;
  late TextEditingController _confirmPasswordController;
  bool _isChangingPassword = false;

  @override
  void initState() {
    super.initState();
    _currentPasswordController = TextEditingController();
    _newPasswordController = TextEditingController();
    _confirmPasswordController = TextEditingController();
    
    // Initialize profile data when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeProfileData();
    });
  }

  void _initializeProfileData() async {
    final authProvider = context.read<AuthProvider>();
    
    try {
      // Fetch fresh statistics when profile screen loads
      await authProvider.fetchRiderStatistics();
      await authProvider.fetchAnalytics();
    } catch (e) {
      if (kDebugMode) {
        print('Error initializing profile data: $e');
      }
    }
  }

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _togglePasswordChange() {
    setState(() {
      _isChangingPassword = !_isChangingPassword;
    });
    
    if (!_isChangingPassword) {
      // Clear password fields when canceling
      _currentPasswordController.clear();
      _newPasswordController.clear();
      _confirmPasswordController.clear();
    }
  }

  void _changePassword() async {
    if (_formKey.currentState!.validate()) {
      final authProvider = context.read<AuthProvider>();
      
      try {
        // Show loading state
        authProvider.setLoading(true);
        
        // Call the API to change password
        final apiSuccess = await ApiService.changePassword(
          newPassword: _newPasswordController.text,
        );
        
        if (apiSuccess) {
          // Update password in Firestore as well
          final firestoreSuccess = await FirebaseService.updateUserPassword(
            authProvider.currentRider?.email ?? '',
            _newPasswordController.text,
          );
          
          if (firestoreSuccess) {
            // Success! Notify and Logout
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Password updated. Please login with your new password.'),
                  backgroundColor: Colors.black,
                  behavior: SnackBarBehavior.floating,
                ),
              );

              // Logout immediately
              await authProvider.logout();

              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                  (route) => false, // Remove all previous routes
                );
              }
            }
          } else {
            // API succeeded but Firestore failed
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Password changed in system but may cause auto-login issues. Please contact support.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        } else {
          // Password change failed
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to change password. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        // Handle error
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error changing password: $e'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        // Hide loading state
        authProvider.setLoading(false);
      }
    }
  }

  void _refreshProfile() async {
    final authProvider = context.read<AuthProvider>();
    
    try {
      // Show loading state
      authProvider.setLoading(true);
      
      // Refresh rider data and statistics
      await authProvider.refreshRiderData();
      await authProvider.fetchRiderStatistics();
      await authProvider.fetchAnalytics();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile refreshed successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to refresh profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      authProvider.setLoading(false);
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text(
          'Are you sure you want to logout? This will clear all your data and you will need to login again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final authProvider = context.read<AuthProvider>();
      
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('Logging out...'),
            ],
          ),
        ),
      );

      try {
        await authProvider.logout();
        
        if (mounted) {
          Navigator.of(context).pop(); // Close loading dialog
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const LoginScreen()),
          );
        }
      } catch (e) {
        if (mounted) {
          Navigator.of(context).pop(); // Close loading dialog
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Logout failed: ${e.toString()}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            JSLogoSmall(size: 28, showBorder: false),
            const SizedBox(width: 8),
            const Text('Profile'),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        actions: [
          Consumer<AuthProvider>(
            builder: (context, authProvider, child) {
              return IconButton(
                icon: authProvider.isLoading 
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                onPressed: authProvider.isLoading ? null : _refreshProfile,
                tooltip: 'Refresh Profile',
              );
            },
          ),
          IconButton(
            icon: Icon(_isChangingPassword ? Icons.close : Icons.lock),
            onPressed: _togglePasswordChange,
            tooltip: _isChangingPassword ? 'Cancel Password Change' : 'Change Password',
          ),
        ],
      ),
      body: Consumer<AuthProvider>(
        builder: (context, authProvider, child) {
          final rider = authProvider.currentRider;
          
          if (rider == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Profile Header
                _buildProfileHeader(rider),
                const SizedBox(height: 32),
                
                // Password Change Form
                _buildPasswordChangeForm(),
                const SizedBox(height: 32),
                
                // Personal Information (Read-only)
                _buildPersonalInformation(),
                const SizedBox(height: 32),
                //
                // // Online Status Toggle
                // _buildOnlineStatusToggle(authProvider),
                // const SizedBox(height: 32),
                //
                // Statistics
                _buildStatistics(),
                const SizedBox(height: 32),
                
                // Settings
                _buildSettings(),
                const SizedBox(height: 32),
                
                // Logout Button
                _buildLogoutButton(authProvider),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildProfileHeader(dynamic rider) {
    return Center(
      child: Column(
        children: [
          CircleAvatar(
            radius: 50,
            backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
            child: rider.profileImage != null
                ? ClipOval(
                    child: Image.network(
                      rider.profileImage!,
                      width: 100,
                      height: 100,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(
                          Icons.person,
                          size: 50,
                          color: Theme.of(context).colorScheme.primary,
                        );
                      },
                    ),
                  )
                : Icon(
                    Icons.person,
                    size: 50,
                    color: Theme.of(context).colorScheme.primary,
                  ),
          ),
          const SizedBox(height: 16),
          Text(
            rider.name,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            rider.email,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: rider.vehicleType == 'Motorcycle' 
                  ? Colors.orange.withOpacity(0.1)
                  : Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: rider.vehicleType == 'Motorcycle' ? Colors.orange : Colors.blue,
              ),
            ),
            child: Text(
              rider.vehicleType,
              style: TextStyle(
                color: rider.vehicleType == 'Motorcycle' ? Colors.orange : Colors.blue,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordChangeForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          if (_isChangingPassword) ...[
            Text(
              'Change Password',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            CustomTextField(
              controller: _currentPasswordController,
              labelText: 'Current Password',
              obscureText: true,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your current password';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            CustomTextField(
              controller: _newPasswordController,
              labelText: 'New Password',
              obscureText: true,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a new password';
                }
                if (value.length > 50) {
                  return 'Password is too long';
                }
                // Check if new password is different from current
                if (value == _currentPasswordController.text) {
                  return 'New password must be different from current password';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            CustomTextField(
              controller: _confirmPasswordController,
              labelText: 'Confirm New Password',
              obscureText: true,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please confirm your new password';
                }
                if (value != _newPasswordController.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            Consumer<AuthProvider>(
              builder: (context, authProvider, child) {
                return Row(
                  children: [
                    Expanded(
                      child: CustomButton(
                        text: authProvider.isLoading ? 'Changing...' : 'Change Password',
                        onPressed: authProvider.isLoading ? null : _changePassword,
                        isLoading: authProvider.isLoading,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: CustomButton(
                        text: 'Cancel',
                        onPressed: authProvider.isLoading ? null : _togglePasswordChange,
                        isOutlined: true,
                      ),
                    ),
                  ],
                );
              },
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildOnlineStatusToggle(AuthProvider authProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Online Status',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
            ),
          ),
          child: Row(
            children: [
              Icon(
                authProvider.currentRider?.isOnline == true
                    ? Icons.circle
                    : Icons.circle_outlined,
                color: authProvider.currentRider?.isOnline == true
                    ? Colors.green
                    : Colors.grey,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      authProvider.currentRider?.isOnline == true
                          ? 'Online'
                          : 'Offline',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      authProvider.currentRider?.isOnline == true
                          ? 'You can receive orders'
                          : 'You won\'t receive orders',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: authProvider.currentRider?.isOnline == true ?? false,
                onChanged: (value) {
                  authProvider.toggleOnlineStatus();
                },
                activeColor: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatistics() {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        final rider = authProvider.currentRider;
        if (rider == null) return const SizedBox.shrink();
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Statistics',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (authProvider.isLoading)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.check_circle,
                    title: "Today's Orders",
                    value: rider.todayCompletedOrders.toString(),
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildStatCard(
                    icon: Icons.star,
                    title: 'Avg Rating',
                    value: rider.rating.toStringAsFixed(1),
                    color: Colors.amber,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (rider.analytics != null) ...[
              Text(
                'Performance Analytics',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildAnalyticsRow('On-Time Delivery', '${((rider.analytics!['on_time_delivery'] ?? 0) * 100).toInt()}%', Colors.purple),
                    const Divider(),
                    _buildAnalyticsRow('Avg Delivery Time', '${rider.analytics!['average_delivery_time'] ?? "N/A"}', Colors.orange),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            title,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color.withOpacity(0.8),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSettings() {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Text(
          'Settings',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 16),

        // Help & Support — hidden
        // About — hidden
        _buildSettingTile(
          icon: Icons.sos,
          title: 'Emergency SOS',
          subtitle: 'Call emergency services',
          onTap: () async {
            final Uri telLaunchUri = Uri(
              scheme: 'tel',
              path: '1122', // Or local emergency number
            );
            if (await canLaunchUrl(telLaunchUri)) {
              await launchUrl(telLaunchUri);
            } else {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Could not launch phone app')),
                );
              }
            }
          },
          iconColor: Colors.red,
          textColor: Colors.red,
        ),
      ],
    );
      },
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
    Color? textColor,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: (iconColor ?? Theme.of(context).colorScheme.primary).withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          color: iconColor ?? Theme.of(context).colorScheme.primary,
          size: 20,
        ),
      ),
      title: Text(
        title, 
        style: textColor != null ? TextStyle(color: textColor, fontWeight: FontWeight.w600) : null
      ),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  Widget _buildPersonalInformation() {
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        final rider = authProvider.currentRider;
        if (rider == null) return const SizedBox.shrink();
        
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Personal Information',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            _buildInfoRow('Full Name', rider.name),
            const SizedBox(height: 12),
            _buildInfoRow('Phone Number', rider.phone),
            const SizedBox(height: 12),
            _buildInfoRow('Vehicle Number', rider.vehicleNumber),
            const SizedBox(height: 12),
            _buildInfoRow('Vehicle Type', rider.vehicleType),
            const SizedBox(height: 12),
            _buildInfoRow('Email', rider.email),
            const SizedBox(height: 12),
            // Total Earnings — hidden
            // Total KMs — hidden
          ],
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton(AuthProvider authProvider) {
    return CustomButton(
      text: 'Logout',
      onPressed: _confirmLogout,
      isOutlined: true,
      backgroundColor: Colors.red,
      textColor: Colors.red,
      width: double.infinity,
    );
  }
  Widget _buildAnalyticsRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}
