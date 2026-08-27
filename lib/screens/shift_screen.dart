import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/auth_provider.dart';
import '../models/attendance_model.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../utils/app_colors.dart';

class ShiftScreen extends StatefulWidget {
  const ShiftScreen({Key? key}) : super(key: key);

  @override
  State<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends State<ShiftScreen> {
  Timer? _timer;
  DateTime _currentTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _startTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().fetchAttendanceHistory();
    });
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _currentTime = DateTime.now();
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final isOnline = authProvider.rider?.isOnline ?? false;
    final isClockedIn = authProvider.isClockedIn;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Shift Status', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: () => authProvider.fetchAttendanceHistory(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),
              // Subtle Status Indicator
              _buildStatusIndicator(isClockedIn, isOnline),
              
              if (isClockedIn) ...[
                const SizedBox(height: 24),
                _buildLiveSessionCard(context, authProvider),
              ],
              
              const SizedBox(height: 32),
              
              // Refined Clock Display
              _buildClockSection(context),
              
              const SizedBox(height: 48),
              
              // Simplified Action Buttons
              _buildActionButtons(context, authProvider, isClockedIn),
              
              const SizedBox(height: 48),
              
              // Attendance History Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Attendance History',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  TextButton(
                    onPressed: () => authProvider.fetchAttendanceHistory(),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(50, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text('Refresh', style: TextStyle(color: Theme.of(context).primaryColor, fontSize: 13)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Attendance List
              if (authProvider.attendanceHistory.isEmpty)
                _buildEmptyState()
              else
                ...authProvider.attendanceHistory.map((att) => _buildAttendanceCard(att)).toList(),
              
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(bool isClockedIn, bool isOnline) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isClockedIn ? Colors.blue.withOpacity(0.05) : Colors.grey.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isClockedIn ? Colors.blue.withOpacity(0.1) : Colors.grey.withOpacity(0.1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: isClockedIn ? Colors.green : Colors.grey[400],
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            isClockedIn ? 'Online & On Shift' : 'Off Duty',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isClockedIn ? AppColors.primary : Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveSessionCard(BuildContext context, AuthProvider authProvider) {
    if (!authProvider.isClockedIn || authProvider.clockInTime == null) return const SizedBox.shrink();

    final clockInTime = authProvider.clockInTime!;
    final duration = DateTime.now().difference(clockInTime);
    
    String formatDuration(Duration d) {
      String twoDigits(int n) => n.toString().padLeft(2, '0');
      final h = twoDigits(d.inHours);
      final m = twoDigits(d.inMinutes.remainder(60));
      final s = twoDigits(d.inSeconds.remainder(60));
      return '$h:$m:$s';
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildSessionStat(
                  'CLOCK IN',
                  DateFormat('hh:mm a').format(clockInTime),
                  Icons.login_rounded,
                ),
              ),
              Container(width: 1, height: 40, color: Colors.grey.shade100),
              Expanded(
                child: _buildSessionStat(
                  'TOTAL TIME',
                  formatDuration(duration),
                  Icons.timer_outlined,
                  valueColor: Theme.of(context).primaryColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today_outlined, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 12),
                Text(
                  'Daily Shift:',
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
                const Spacer(),
                const Text(
                  '09:00 AM - 06:00 PM', // Dummy as requested
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionStat(String label, String value, IconData icon, {Color? valueColor}) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: Colors.grey[400]),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey[400], letterSpacing: 0.5),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: valueColor ?? Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildClockSection(BuildContext context) {
    return Center(
      child: Column(
        children: [
          Text(
            DateFormat('hh:mm:ss a').format(_currentTime),
            style: const TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w300,
              color: Colors.black,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            DateFormat('EEEE, MMMM d').format(_currentTime).toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey[500],
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, AuthProvider authProvider, bool isClockedIn) {
    if (authProvider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Center(
      child: Column(
        children: [
          SizedBox(
            width: 240,
            height: 56,
            child: ElevatedButton(
              onPressed: () async {
                bool success;
                if (isClockedIn) {
                  success = await authProvider.endShift();
                } else {
                  success = await authProvider.startShift();
                }
                
                if (!mounted) return;
                
                if (success) {
                  _showSuccessSheet(context, !isClockedIn);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(authProvider.error ?? 'Error processing request'),
                      backgroundColor: Colors.black87,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: isClockedIn ? Colors.black : Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
              ),
              child: Text(
                isClockedIn ? 'CLOCK OUT' : 'START SHIFT',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSuccessSheet(BuildContext context, bool clockingIn) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              clockingIn ? Icons.check_circle_outline : Icons.logout_outlined,
              color: clockingIn ? Colors.green : Colors.black,
              size: 56,
            ),
            const SizedBox(height: 24),
            Text(
              clockingIn ? 'Shift Activated' : 'Shift Completed',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              clockingIn 
                ? 'Your attendance has been recorded. You can now start receiving orders.' 
                : 'Your work session has ended. Have a great rest!',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 15, height: 1.5),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: TextButton(
                onPressed: () => Navigator.pop(ctx),
                style: TextButton.styleFrom(
                  backgroundColor: Colors.grey[100],
                  foregroundColor: Colors.black87,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('DISMISS', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceCard(AttendanceModel attendance) {
    final clockInTime = attendance.clockIn != null
        ? DateFormat('hh:mm:ss a').format(attendance.clockIn!.toLocal())
        : '--:--:--';
    final clockoutTime = attendance.clockOut != null
        ? DateFormat('hh:mm:ss a').format(attendance.clockOut!.toLocal())
        : '--:--:--';

    final date = attendance.attendanceDate != null
        ? DateFormat('yyyy-MM-dd').format(attendance.attendanceDate!)
        : '';

    final isToday = attendance.attendanceDate != null &&
        attendance.attendanceDate!.year == DateTime.now().year &&
        attendance.attendanceDate!.month == DateTime.now().month &&
        attendance.attendanceDate!.day == DateTime.now().day;

    String calculateTotalLoggedTime() {
      if (attendance.clockIn == null) return '--:--:--';
      if (attendance.clockOut == null && !isToday) return '--:--:--';

      final endTime = attendance.clockOut ?? DateTime.now();
      final duration = endTime.difference(attendance.clockIn!);

      final hours = duration.inHours.toString().padLeft(2, '0');
      final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
      final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');

      return '$hours:$minutes:$seconds';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withOpacity(0.05),
        border: Border.all(color: Theme.of(context).primaryColor.withOpacity(0.2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildTimeLabel('IN', clockInTime),
              _buildTimeLabel('OUT', clockoutTime),
              _buildTimeLabel('TOTAL', calculateTotalLoggedTime(), color: Theme.of(context).primaryColor),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (attendance.clockOut == null && isToday)
                _buildStatusTag('ACTIVE', AppColors.primary.withOpacity(0.08), AppColors.primary)
              else
                _buildStatusTag('COMPLETED', Colors.green.shade50, Colors.green.shade700),
              Text(
                date,
                style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeLabel(String label, String time, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey[400]),
        ),
        const SizedBox(height: 2),
        Text(
          time,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color ?? Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusTag(String label, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 10),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(Icons.calendar_today_outlined, size: 40, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'No attendance records',
            style: TextStyle(color: Colors.grey[400], fontSize: 14),
          ),
        ],
      ),
    );
  }
}
