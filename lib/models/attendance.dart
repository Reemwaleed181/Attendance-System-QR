class Attendance {
  final String id;
  final String studentId;
  final String studentName;
  final String classroomId;
  final String classroomName;
  final String teacherId;
  final String teacherName;
  final DateTime timestamp;
  final bool isPresent;

  Attendance({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.classroomId,
    required this.classroomName,
    required this.teacherId,
    required this.teacherName,
    required this.timestamp,
    required this.isPresent,
  });

  factory Attendance.fromJson(Map<String, dynamic> json) {
    return Attendance(
      id: json['id']?.toString() ?? '',
      studentId: json['student']?.toString() ?? '',
      studentName: json['student_name']?.toString() ?? '',
      classroomId: json['classroom']?.toString() ?? '',
      classroomName: json['classroom_name']?.toString() ?? '',
      teacherId: json['teacher']?.toString() ?? '',
      teacherName: json['teacher_name']?.toString() ?? '',
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '')?.toLocal() ?? DateTime.now().toLocal(),
      isPresent: json['is_present'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'student': studentId,
      'student_name': studentName,
      'classroom': classroomId,
      'classroom_name': classroomName,
      'teacher': teacherId,
      'teacher_name': teacherName,
      'timestamp': timestamp.toIso8601String(),
      'is_present': isPresent,
    };
  }
}
