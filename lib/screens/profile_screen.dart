import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/auth_provider.dart';
import '../utils/app_colors.dart';
import '../widgets/ui_kit.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    final auth = context.read<AuthProvider>();
    try {
      await Future.wait([auth.fetchRiderStatistics(), auth.fetchAnalytics()]);
    } catch (e) {
      if (kDebugMode) print('Profile refresh failed: $e');
    }
    if (mounted) setState(() => _refreshing = false);
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const IconBadge(icon: Icons.logout_rounded, color: AppColors.error, size: 52),
        title: const Text('Log out?', textAlign: TextAlign.center),
        content: const Text(
          'You will stop receiving new order notifications on this phone.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Log out')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    await context.read<AuthProvider>().logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Future<void> _callEmergency() async {
    final uri = Uri(scheme: 'tel', path: '1122');
    if (!await launchUrl(uri) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the phone app')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rider = context.watch<AuthProvider>().currentRider;
    if (rider == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final initials = rider.name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).take(2).map((p) => p[0]).join().toUpperCase();
    final analytics = rider.analytics;
    final onTime = ((analytics?['on_time_delivery'] ?? 0) as num) * 100;
    final avgTime = (analytics?['average_delivery_time'] ?? '—').toString();

    return Scaffold(
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            InkHero(
              child: Column(
                children: [
                  Row(
                    children: [
                      const Text('Profile',
                          style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                      const Spacer(),
                      if (_refreshing)
                        const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 3),
                      boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.45), blurRadius: 24)],
                    ),
                    alignment: Alignment.center,
                    child: Text(initials.isEmpty ? 'R' : initials,
                        style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(height: 12),
                  Text(rider.name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(rider.email, style: TextStyle(color: Colors.white.withValues(alpha: 0.6))),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      if (rider.vehicleType.isNotEmpty)
                        StatusChip(
                          label: rider.vehicleType.toUpperCase(),
                          icon: Icons.two_wheeler_rounded,
                          color: Colors.white,
                          background: Colors.white.withValues(alpha: 0.14),
                        ),
                      StatusChip(
                        label: rider.rating > 0 ? '${rider.rating.toStringAsFixed(1)} RATING' : 'NO RATING YET',
                        icon: Icons.star_rounded,
                        color: AppColors.gold,
                        background: Colors.white.withValues(alpha: 0.14),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: _Stat(value: '${rider.todayCompletedOrders}', label: 'Today')),
                      const SizedBox(width: 12),
                      Expanded(child: _Stat(value: '${rider.completedOrders}', label: 'All-time')),
                      const SizedBox(width: 12),
                      Expanded(child: _Stat(value: '${onTime.round()}%', label: 'On time')),
                    ],
                  ),
                  const SizedBox(height: 12),
                  PremiumCard(
                    child: Row(
                      children: [
                        const IconBadge(icon: Icons.timer_rounded, color: AppColors.purple),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text('Average delivery time',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        Text(avgTime, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                      ],
                    ),
                  ),
                  const SectionTitle('Details'),
                  PremiumCard(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    child: Column(
                      children: [
                        InfoRow(icon: Icons.phone_rounded, label: 'Phone', value: rider.phone),
                        const Divider(),
                        InfoRow(icon: Icons.pin_rounded, label: 'Vehicle number', value: rider.vehicleNumber),
                        const Divider(),
                        InfoRow(icon: Icons.two_wheeler_rounded, label: 'Vehicle type', value: rider.vehicleType),
                        const Divider(),
                        InfoRow(icon: Icons.alternate_email_rounded, label: 'Login', value: rider.email),
                      ],
                    ),
                  ),
                  const SectionTitle('Security & help'),
                  PremiumCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        _ActionTile(
                          icon: Icons.lock_reset_rounded,
                          color: AppColors.info,
                          title: 'Change password',
                          subtitle: 'Your current password is required',
                          onTap: () => showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            useSafeArea: true,
                            builder: (_) => const ChangePasswordSheet(),
                          ),
                        ),
                        const Divider(indent: 16, endIndent: 16),
                        _ActionTile(
                          icon: Icons.sos_rounded,
                          color: AppColors.error,
                          title: 'Emergency SOS',
                          subtitle: 'Call Rescue 1122',
                          onTap: _callEmergency,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: _confirmLogout,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error, width: 1.2),
                      minimumSize: const Size.fromHeight(54),
                    ),
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Log out'),
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

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Column(
        children: [
          FittedBox(
            child: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: IconBadge(icon: icon, color: color),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppColors.textLight),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Change password: current password is verified by Odoo before anything changes
// ─────────────────────────────────────────────────────────────────────────────

class ChangePasswordSheet extends StatefulWidget {
  const ChangePasswordSheet({super.key});

  @override
  State<ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<ChangePasswordSheet> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  bool _showPasswords = false;
  bool _saving = false;
  String? _serverError;

  @override
  void dispose() {
    _current.dispose();
    _new.dispose();
    _confirm.dispose();
    super.dispose();
  }

  /// 0..4 — length, digits, letters+case mix, symbols.
  int _strength(String p) {
    var score = 0;
    if (p.length >= 8) score++;
    if (RegExp(r'\d').hasMatch(p)) score++;
    if (RegExp(r'[a-z]').hasMatch(p) && RegExp(r'[A-Z]').hasMatch(p)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(p)) score++;
    return score;
  }

  Future<void> _submit() async {
    setState(() => _serverError = null);
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final auth = context.read<AuthProvider>();
    final result = await auth.changePassword(_current.text, _new.text);
    if (!mounted) return;
    setState(() => _saving = false);

    if (!result.success) {
      setState(() => _serverError = result.message);
      return;
    }

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    navigator.pop();
    messenger.showSnackBar(SnackBar(
      content: Text(result.message),
      backgroundColor: AppColors.success,
    ));
    if (result.code == 'relogin_required') {
      navigator.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
    }
  }

  InputDecoration _decoration(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        suffixIcon: IconButton(
          icon: Icon(_showPasswords ? Icons.visibility_off_rounded : Icons.visibility_rounded),
          onPressed: () => setState(() => _showPasswords = !_showPasswords),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final strength = _strength(_new.text);
    const strengthLabels = ['Too weak', 'Weak', 'Fair', 'Good', 'Strong'];
    const strengthColors = [AppColors.error, AppColors.error, AppColors.warning, AppColors.info, AppColors.success];

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Change password',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4)),
              const SizedBox(height: 4),
              const Text('Enter your current password first. You will stay logged in.',
                  style: TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: 20),
              TextFormField(
                controller: _current,
                obscureText: !_showPasswords,
                textInputAction: TextInputAction.next,
                decoration: _decoration('Current password', Icons.lock_outline_rounded),
                validator: (v) => (v == null || v.isEmpty) ? 'Enter your current password' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _new,
                obscureText: !_showPasswords,
                textInputAction: TextInputAction.next,
                onChanged: (_) => setState(() {}),
                decoration: _decoration('New password', Icons.lock_rounded),
                validator: (v) {
                  if (v == null || v.trim().length < 4) return 'Use at least 4 characters';
                  if (v.length > 50) return 'Password is too long';
                  if (v == _current.text) return 'New password must be different';
                  return null;
                },
              ),
              if (_new.text.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (var i = 0; i < 4; i++)
                      Expanded(
                        child: Container(
                          height: 5,
                          margin: EdgeInsets.only(right: i < 3 ? 6 : 0),
                          decoration: BoxDecoration(
                            color: i < strength ? strengthColors[strength] : AppColors.border,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    const SizedBox(width: 10),
                    Text(strengthLabels[strength],
                        style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700, color: strengthColors[strength])),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              TextFormField(
                controller: _confirm,
                obscureText: !_showPasswords,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: _decoration('Confirm new password', Icons.check_circle_outline_rounded),
                validator: (v) => v != _new.text ? 'Passwords do not match' : null,
              ),
              if (_serverError != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primarySoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline_rounded, color: AppColors.error),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(_serverError!,
                              style: const TextStyle(color: AppColors.primaryDark, fontWeight: FontWeight.w600))),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 22),
              FilledButton(
                onPressed: _saving ? null : _submit,
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                child: _saving
                    ? const SizedBox(
                        width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : const Text('Update password'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
