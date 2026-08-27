import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

class AttendanceModel {
  String? id;
  DateTime? attendanceDate;
  DateTime? clockIn;
  DateTime? clockOut;
  String? userId;
  String? companyId;
  String? type;
  String? lastType;
  String? breakTime;
  String? totalLoggedTime;
  bool isPushed;
  bool isUpdatedFromServer;
  String? serverUpdatedData;
  DateTime? userEnteredAt;

  AttendanceModel(
      {this.id,
      this.attendanceDate,
      this.clockIn,
      this.clockOut,
      this.userId,
      this.companyId,
      this.type,
      this.lastType,
      this.breakTime,
      this.totalLoggedTime,
      this.isPushed = false,
      this.isUpdatedFromServer = false,
      this.serverUpdatedData,
      this.userEnteredAt});

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'attendance_date': attendanceDate?.toIso8601String(),
      'clock_in': clockIn?.toIso8601String(),
      'clock_out': clockOut?.toIso8601String(),
      'user_id': userId,
      'company_id': companyId,
      'type': type,
      'last_type': lastType,
      'break_time': breakTime,
      'total_logged_time': totalLoggedTime,
      'is_pushed': isPushed ? 1 : 0,
      'is_updated_from_server': isUpdatedFromServer ? 1 : 0,
      'server_updated_data': serverUpdatedData,
      'userEnteredAt': userEnteredAt,
    };
  }

  factory AttendanceModel.fromMap(Map<String, dynamic> map) {
    DateTime? parseDate(dynamic value) {
      if (value == null) return null;
      final str = value.toString();
      try {
        // Try standard ISO8601 parsing first (handles T, Z, +, etc.)
        return DateTime.parse(str);
      } catch (_) {
        try {
          // If that fails, try custom format if it looks like the legacy format
          return DateFormat('yyyy-MM-dd HH:mm:ss').parseUtc(str);
        } catch (e) {
          if (kDebugMode) print('Error parsing date "$str": $e');
          return null;
        }
      }
    }

    return AttendanceModel(
      id: map['id']?.toString(),
      attendanceDate: parseDate(map['attendance_date']),
      clockIn: parseDate(map['clock_in']),
      clockOut: parseDate(map['clock_out']),
      userId: map['user_id']?.toString(),
      companyId: map['company_id']?.toString(),
      type: map['type']?.toString(),
      lastType: map['last_type']?.toString(),
      breakTime: map['break_time']?.toString(),
      totalLoggedTime: map['total_logged_time']?.toString(),
      isPushed: map['is_pushed'] == 1,
      isUpdatedFromServer: map['is_updated_from_server'] == 1,
      serverUpdatedData: map['server_updated_data']?.toString(),
      userEnteredAt: parseDate(map['user_entered_at']),
    );
  }

  // Getters and Setters
  String get getId => id ?? '';

  set setId(String value) => id = value;

  String get getUserId => userId ?? '';

  set setUserId(String value) => userId = value;

  String get getCompanyId => companyId ?? '';

  set setCompanyId(String value) => companyId = value;

  DateTime? get getAttendanceDate => attendanceDate;

  set setAttendanceDate(DateTime value) => attendanceDate = value;

  DateTime? get getClockIn => clockIn;

  set setClockIn(DateTime value) => clockIn = value;

  DateTime? get getClockOut => clockOut;

  set setClockOut(DateTime value) => clockOut = value;

  String get getType => type ?? '';

  set setType(String value) => type = value;

  String get getBreakTime => breakTime ?? '';

  set setBreakTime(String value) => breakTime = value;

  String get getTotalLoggedTime => totalLoggedTime ?? '';

  set setTotalLoggedTime(String value) => totalLoggedTime = value;

  bool get isPushedStatus => isPushed;

  set setPushedStatus(bool value) => isPushed = value;

  bool get isUpdatedFromServerStatus => isUpdatedFromServer;

  set setUpdatedFromServerStatus(bool value) => isUpdatedFromServer = value;

  String get getServerUpdatedData => serverUpdatedData ?? '';

  set setServerUpdatedData(String value) => serverUpdatedData = value;
}
