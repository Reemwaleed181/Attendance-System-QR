import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/student.dart';
import '../models/classroom.dart';
import '../utils/platform_utils.dart';

class ApiService {
  // Use platform-specific base URL
  static String get baseUrl => PlatformUtils.baseUrl;
  
  // Teacher login
  static Future<Map<String, dynamic>> teacherLogin(String username, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/login/teacher/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
      }),
    );
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Login failed: ${response.body}');
    }
  }
  
  // Parent login
  static Future<Map<String, dynamic>> parentLogin(String name, String email, String phone) async {
    final response = await http.post(
      Uri.parse('$baseUrl/login/parent/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'email': email,
        'phone': phone,
      }),
    );
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Login failed: ${response.body}');
    }
  }
  
  // Mark attendance
  static Future<Map<String, dynamic>> markAttendance(String studentQr, String classQr, String token, {bool isPresent = true}) async {
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
      throw Exception('Failed to mark attendance: ${response.body}');
    }
  }
  
  // Get classrooms
  static Future<List<Classroom>> getClassrooms(String token) async {
    List<Classroom> allClassrooms = [];
    String? nextUrl = '$baseUrl/classrooms/';
    
    while (nextUrl != null) {
      final response = await http.get(
        Uri.parse(nextUrl),
        headers: {
          'Authorization': 'Token $token',
        },
      );
      
      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final List<dynamic> data = responseData['results'] ?? [];
        allClassrooms.addAll(data.map((json) => Classroom.fromJson(json)).toList());
        
        // Check if there's a next page
        nextUrl = responseData['next'];
      } else {
        throw Exception('Failed to fetch classrooms: ${response.body}');
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
        headers: {
          'Authorization': 'Token $token',
        },
      );
      
      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final List<dynamic> data = responseData['results'] ?? [];
        allStudents.addAll(data.map((json) => Student.fromJson(json)).toList());
        
        // Check if there's a next page
        nextUrl = responseData['next'];
      } else {
        throw Exception('Failed to fetch students: ${response.body}');
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
      throw Exception('Failed to fetch parent data: ${response.body}');
    }
  }
  
  // Get student attendance history
  static Future<Map<String, dynamic>> getStudentAttendanceHistory(String studentId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/student/$studentId/attendance/'),
    );
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch attendance history: ${response.body}');
    }
  }
  
  // Get teacher attendance history
  static Future<Map<String, dynamic>> getTeacherAttendanceHistory(String token) async {
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
        throw Exception('Failed to fetch teacher attendance history: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Network Error: $e');
      throw Exception('Network error: $e');
    }
  }
  
  // Get teacher reports
  static Future<Map<String, dynamic>> getTeacherReports(String token, {String? fromDate, String? toDate}) async {
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
      headers: {
        'Authorization': 'Token $token',
      },
    );
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch teacher reports: ${response.body}');
    }
  }
  
  // Get student weekly statistics
  static Future<Map<String, dynamic>> getStudentWeeklyStats(String studentId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/student/$studentId/weekly-stats/'),
    );
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch student weekly stats: ${response.body}');
    }
  }
  
  // Get students with high absence count
  static Future<Map<String, dynamic>> getStudentsWithAbsences(String token, {String? fromDate, String? toDate, required int absenceThreshold}) async {
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
      headers: {
        'Authorization': 'Token $token',
      },
    );
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to fetch students with absences: ${response.body}');
    }
  }
  
  // Send absence reports to parents
  static Future<Map<String, dynamic>> sendAbsenceReportsToParents(String token, {required List<String> studentIds, required int absenceThreshold}) async {
    final response = await http.post(
      Uri.parse('$baseUrl/teacher/send-absence-reports/'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Token $token',
      },
      body: jsonEncode({
        'student_ids': studentIds,
        'absence_threshold': absenceThreshold,
      }),
    );
    
    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to send absence reports: ${response.body}');
    }
  }

  // Parent Notifications
  static Future<Map<String, dynamic>> getParentNotifications(String parentId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/parent/$parentId/notifications/'),
      headers: {
        'Content-Type': 'application/json',
      },
    );
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get notifications: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> markNotificationAsRead(String notificationId) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/notifications/$notificationId/mark-read/'),
      headers: {
        'Content-Type': 'application/json',
      },
    );
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to mark notification as read: ${response.body}');
    }
  }

  static Future<Map<String, dynamic>> markAllNotificationsAsRead(String parentId) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/parent/$parentId/notifications/mark-all-read/'),
      headers: {
        'Content-Type': 'application/json',
      },
    );
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to mark all notifications as read: ${response.body}');
    }
  }

  // Enhanced Parent Reports
  static Future<Map<String, dynamic>> getParentDetailedReports(String parentId, {String? fromDate, String? toDate}) async {
    String url = '$baseUrl/parent/$parentId/detailed-reports/';
    if (fromDate != null && toDate != null) {
      url += '?from_date=$fromDate&to_date=$toDate';
    }
    
    final response = await http.get(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
      },
    );
    
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to get detailed reports: ${response.body}');
    }
  }

  // Send daily absence notifications to parents (not reports)
  static Future<Map<String, dynamic>> sendDailyAbsenceNotifications(String token, {required List<String> absentStudentIds, required String classroomName, required String date}) async {
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
        'notification_type': 'daily_absence', // This distinguishes from teacher reports
      }),
    );
    
    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to send daily absence notifications: ${response.body}');
    }
  }

  // Send teacher report notifications to parents (these will show in reports screen)
  static Future<Map<String, dynamic>> sendTeacherReportNotifications(String token, {required List<String> studentIds, required String reportMessage, required int absenceThreshold}) async {
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
        'notification_type': 'teacher_report', // This distinguishes from daily absence
      }),
    );
    
    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to send teacher report notifications: ${response.body}');
    }
  }
}
