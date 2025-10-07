import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/student.dart';
import '../models/classroom.dart';
import '../utils/platform_utils.dart';

class ApiService {
  // Consistent API error type
  static ApiException _errorFromResponse(http.Response response) {
    try {
      final dynamic body = jsonDecode(response.body);
      final message = (body is Map && body['message'] is String)
          ? body['message'] as String
          : 'Request failed';
      final code = (body is Map && body['code'] is String)
          ? body['code'] as String
          : null;
      final fields = (body is Map && body['fields'] != null)
          ? body['fields']
          : null;
      return ApiException(
        statusCode: response.statusCode,
        message: message,
        code: code,
        fields: fields,
        rawBody: response.body,
      );
    } catch (_) {
      return ApiException(
        statusCode: response.statusCode,
        message: 'Request failed with status ${response.statusCode}',
        rawBody: response.body,
      );
    }
  }

  // Use platform-specific base URL
  static String get baseUrl => PlatformUtils.baseUrl;

  // Check if self-attendance window is active for a class (student-facing)
  static Future<Map<String, dynamic>> getSelfAttendanceStatus({
    required String studentToken,
    required String classQr,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/student/self-attendance/status/',
    ).replace(queryParameters: {'class_qr': classQr});
    final response = await http.get(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'X-Student-Token': studentToken,
      },
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw _errorFromResponse(response);
    }
  }

  // Attendance request workflow (student-initiated)
  static Future<Map<String, dynamic>> createAttendanceRequest({
    required String studentQr,
    required String classQr,
    String method = 'gps',
    double? studentLat,
    double? studentLng,
    Map<String, dynamic>? metadata,
    required String token,
  }) async {
    final payload = <String, dynamic>{
      'student_qr': studentQr,
      'class_qr': classQr,
      'method': method,
    };
    if (studentLat != null)
      payload['student_lat'] = double.parse(studentLat.toStringAsFixed(6));
    if (studentLng != null)
      payload['student_lng'] = double.parse(studentLng.toStringAsFixed(6));
    if (metadata != null) payload['metadata'] = metadata;

    final response = await http.post(
      Uri.parse('$baseUrl/attendance/requests/create/'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Token $token',
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw _errorFromResponse(response);
    }
  }

  static Future<Map<String, dynamic>> getPendingAttendanceRequests(
    String token,
  ) async {
    final response = await http.get(
      Uri.parse('$baseUrl/attendance/requests/pending/'),
      headers: {'Authorization': 'Token $token'},
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw _errorFromResponse(response);
    }
  }

  static Future<Map<String, dynamic>> approveAttendanceRequest({
    required String requestId,
    required String token,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/attendance/requests/$requestId/approve/'),
      headers: {'Authorization': 'Token $token'},
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw _errorFromResponse(response);
    }
  }

  static Future<Map<String, dynamic>> denyAttendanceRequest({
    required String requestId,
    required String token,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/attendance/requests/$requestId/deny/'),
      headers: {'Authorization': 'Token $token'},
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw _errorFromResponse(response);
    }
  }

  // Teacher login
  static Future<Map<String, dynamic>> teacherLogin(
    String username,
    String password,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/login/teacher/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw _errorFromResponse(response);
    }
  }

  // Parent login
  static Future<Map<String, dynamic>> parentLogin(
    String name,
    String email,
    String phone,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/login/parent/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name, 'email': email, 'phone': phone}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw _errorFromResponse(response);
    }
  }

  // Student login with username/password
  static Future<Map<String, dynamic>> studentLogin(
    String username,
    String password,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/login/student/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw _errorFromResponse(response);
    }
  }

  // Mark attendance
  static Future<Map<String, dynamic>> markAttendance(
    String studentQr,
    String classQr,
    String token, {
    bool isPresent = true,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/attendance/mark/'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Token $token',
      },
      body: jsonEncode({
        'student_qr': studentQr,
        'class_qr': classQr,
        'is_present': isPresent,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw _errorFromResponse(response);
    }
  }

  // Teacher opens a self-attendance window for a classroom
  static Future<Map<String, dynamic>> openSelfAttendanceWindow({
    required String classQr,
    required String token,
    int minutes = 10,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/teacher/self-attendance/open/'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Token $token',
      },
      body: jsonEncode({'class_qr': classQr, 'minutes': minutes}),
    );
    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw _errorFromResponse(response);
    }
  }

  static Future<Map<String, dynamic>> closeSelfAttendanceWindow({
    required String classQr,
    required String token,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/teacher/self-attendance/close/'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Token $token',
      },
      body: jsonEncode({'class_qr': classQr}),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw _errorFromResponse(response);
    }
  }

  // Student marks own attendance during active window
  static Future<Map<String, dynamic>> studentSelfMark({
    required String studentToken,
    required String classQr,
    double? lat,
    double? lng,
  }) async {
    final payload = <String, dynamic>{'class_qr': classQr};
    if (lat != null)
      payload['student_lat'] = double.parse(lat.toStringAsFixed(6));
    if (lng != null)
      payload['student_lng'] = double.parse(lng.toStringAsFixed(6));

    final response = await http.post(
      Uri.parse('$baseUrl/student/self-attendance/mark/'),
      headers: {
        'Content-Type': 'application/json',
        'X-Student-Token': studentToken,
      },
      body: jsonEncode(payload),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw _errorFromResponse(response);
    }
  }

  // Teacher live class attendance snapshot (real-time polling)
  static Future<Map<String, dynamic>> getLiveClassAttendance({
    required String token,
    required String classQr,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/teacher/class-attendance/live/',
    ).replace(queryParameters: {'class_qr': classQr});
    final response = await http.get(
      uri,
      headers: {
        'Authorization': 'Token $token',
        'Content-Type': 'application/json',
      },
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } else {
      throw _errorFromResponse(response);
    }
  }

  // Get classrooms
  static Future<List<Classroom>> getClassrooms(String token) async {
    List<Classroom> allClassrooms = [];
    String? nextUrl = '$baseUrl/classrooms/';

    while (nextUrl != null) {
      final response = await http.get(
        Uri.parse(nextUrl),
        headers: {'Authorization': 'Token $token'},
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final List<dynamic> data = responseData['results'] ?? [];
        allClassrooms.addAll(
          data.map((json) => Classroom.fromJson(json)).toList(),
        );

        // Check if there's a next page
        nextUrl = responseData['next'];
      } else {
        throw _errorFromResponse(response);
      }
    }

    return allClassrooms;
  }

  // Get students
  static Future<List<Student>> getStudents(String token) async {
    List<Student> allStudents = [];
    String? nextUrl = '$baseUrl/students/';

    while (nextUrl != null) {
      final response = await http.get(
        Uri.parse(nextUrl),
        headers: {'Authorization': 'Token $token'},
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final List<dynamic> data = responseData['results'] ?? [];
        allStudents.addAll(data.map((json) => Student.fromJson(json)).toList());

        // Check if there's a next page
        nextUrl = responseData['next'];
      } else {
        throw _errorFromResponse(response);
      }
    }

    return allStudents;
  }

  // Get parent children and attendance
  static Future<Map<String, dynamic>> getParentChildren(String parentId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/parent/$parentId/children/'),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw _errorFromResponse(response);
    }
  }

  // Get student attendance history
  static Future<Map<String, dynamic>> getStudentAttendanceHistory(
    String studentId,
  ) async {
    final response = await http.get(
      Uri.parse('$baseUrl/student/$studentId/attendance/'),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw _errorFromResponse(response);
    }
  }

  // Get teacher attendance history
  static Future<Map<String, dynamic>> getTeacherAttendanceHistory(
    String token,
  ) async {
    try {
      // Get device timezone offset in minutes
      final now = DateTime.now();
      final timezoneOffset = now.timeZoneOffset.inMinutes;

      final url = '$baseUrl/teacher/attendance/history/';

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Token $token',
          'X-Timezone-Offset': timezoneOffset.toString(),
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print('API Error: ${response.statusCode} - ${response.body}');
        throw Exception(
          'Failed to fetch teacher attendance history: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      print('Network Error: $e');
      throw Exception('Network error: $e');
    }
  }

  // Get teacher reports
  static Future<Map<String, dynamic>> getTeacherReports(
    String token, {
    String? fromDate,
    String? toDate,
  }) async {
    String url = '$baseUrl/teacher/reports/';
    if (fromDate != null || toDate != null) {
      final uri = Uri.parse(url);
      final queryParams = <String, String>{};
      if (fromDate != null) queryParams['from_date'] = fromDate;
      if (toDate != null) queryParams['to_date'] = toDate;
      url = uri.replace(queryParameters: queryParams).toString();
    }

    final response = await http.get(
      Uri.parse(url),
      headers: {'Authorization': 'Token $token'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw _errorFromResponse(response);
    }
  }

  // Get student weekly statistics
  static Future<Map<String, dynamic>> getStudentWeeklyStats(
    String studentId,
  ) async {
    final response = await http.get(
      Uri.parse('$baseUrl/student/$studentId/weekly-stats/'),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw _errorFromResponse(response);
    }
  }

  // Get students with high absence count
  static Future<Map<String, dynamic>> getStudentsWithAbsences(
    String token, {
    String? fromDate,
    String? toDate,
    required int absenceThreshold,
  }) async {
    String url = '$baseUrl/teacher/students-with-absences/';
    final uri = Uri.parse(url);
    final queryParams = <String, String>{
      'absence_threshold': absenceThreshold.toString(),
    };
    if (fromDate != null) queryParams['from_date'] = fromDate;
    if (toDate != null) queryParams['to_date'] = toDate;
    url = uri.replace(queryParameters: queryParams).toString();

    final response = await http.get(
      Uri.parse(url),
      headers: {'Authorization': 'Token $token'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(
        'Failed to fetch students with absences: ${response.body}',
      );
    }
  }

  // Send absence reports to parents
  static Future<Map<String, dynamic>> sendAbsenceReportsToParents(
    String token, {
    required List<String> studentIds,
    required int absenceThreshold,
    String? fromDate,
    String? toDate,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/teacher/send-absence-reports/'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Token $token',
      },
      body: jsonEncode({
        'student_ids': studentIds,
        'absence_threshold': absenceThreshold,
        'from_date': fromDate,
        'to_date': toDate,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to send absence reports: ${response.body}');
    }
  }

  // Parent Notifications
  static Future<Map<String, dynamic>> getParentNotifications(
    String parentId,
  ) async {
    final response = await http.get(
      Uri.parse('$baseUrl/parent/$parentId/notifications/'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw _errorFromResponse(response);
    }
  }

  static Future<Map<String, dynamic>> markNotificationAsRead(
    String notificationId,
  ) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/notifications/$notificationId/mark-read/'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw _errorFromResponse(response);
    }
  }

  static Future<Map<String, dynamic>> markAllNotificationsAsRead(
    String parentId,
  ) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/parent/$parentId/notifications/mark-all-read/'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw _errorFromResponse(response);
    }
  }

  // Delete a single notification
  static Future<void> deleteNotification(String notificationId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/notifications/$notificationId/'),
      headers: {'Content-Type': 'application/json'},
    );
    if (response.statusCode == 200 || response.statusCode == 204) {
      return;
    } else {
      throw _errorFromResponse(response);
    }
  }

  // Bulk delete notifications by ids; if ids is empty, delete all
  static Future<void> deleteParentNotifications(
    String parentId, {
    List<String>? ids,
  }) async {
    if (ids != null && ids.isNotEmpty) {
      // Try bulk endpoint first
      final response = await http.post(
        Uri.parse('$baseUrl/parent/$parentId/notifications/bulk-delete/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'ids': ids}),
      );
      if (response.statusCode == 200 || response.statusCode == 204) {
        return;
      }
      // Fallback to deleting one by one if bulk not supported
      if (response.statusCode == 404) {
        for (final id in ids) {
          await deleteNotification(id);
        }
        return;
      }
      throw _errorFromResponse(response);
    } else {
      // Delete all for parent
      final response = await http.delete(
        Uri.parse('$baseUrl/parent/$parentId/notifications/delete-all/'),
        headers: {'Content-Type': 'application/json'},
      );
      if (response.statusCode == 200 || response.statusCode == 204) {
        return;
      }
      // Fallback: if endpoint missing, delete individually
      if (response.statusCode == 404) {
        final data = await getParentNotifications(parentId);
        final items = (data['notifications'] as List<dynamic>)
            .map((e) => (e['id'] ?? '').toString())
            .where((e) => e.isNotEmpty)
            .toList();
        for (final id in items) {
          await deleteNotification(id);
        }
        return;
      }
      throw _errorFromResponse(response);
    }
  }

  // Enhanced Parent Reports
  static Future<Map<String, dynamic>> getParentDetailedReports(
    String parentId, {
    String? fromDate,
    String? toDate,
  }) async {
    String url = '$baseUrl/parent/$parentId/detailed-reports/';
    if (fromDate != null && toDate != null) {
      url += '?from_date=$fromDate&to_date=$toDate';
    }

    final response = await http.get(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw _errorFromResponse(response);
    }
  }

  // Send daily absence notifications to parents (not reports)
  static Future<Map<String, dynamic>> sendDailyAbsenceNotifications(
    String token, {
    required List<String> absentStudentIds,
    required String classroomName,
    required String date,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/teacher/send-daily-absence-notifications/'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Token $token',
      },
      body: jsonEncode({
        'absent_student_ids': absentStudentIds,
        'classroom_name': classroomName,
        'date': date,
        'notification_type':
            'daily_absence', // This distinguishes from teacher reports
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw _errorFromResponse(response);
    }
  }

  // Send teacher report notifications to parents (these will show in reports screen)
  static Future<Map<String, dynamic>> sendTeacherReportNotifications(
    String token, {
    required List<String> studentIds,
    required String reportMessage,
    required int absenceThreshold,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/teacher/send-report-notifications/'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Token $token',
      },
      body: jsonEncode({
        'student_ids': studentIds,
        'report_message': reportMessage,
        'absence_threshold': absenceThreshold,
        'notification_type':
            'teacher_report', // This distinguishes from daily absence
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw _errorFromResponse(response);
    }
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  final String? code;
  final dynamic fields;
  final String? rawBody;

  ApiException({
    required this.statusCode,
    required this.message,
    this.code,
    this.fields,
    this.rawBody,
  });

  @override
  String toString() => 'ApiException($statusCode, $code, $message)';
}
