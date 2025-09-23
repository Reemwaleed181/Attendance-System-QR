class Student {
  final String id;
  final String name;
  final String qrCode;
  final String classroomId;
  final String classroomName;
  final DateTime createdAt;
  final DateTime updatedAt;

  Student({
    required this.id,
    required this.name,
    required this.qrCode,
    required this.classroomId,
    required this.classroomName,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Student.fromJson(Map<String, dynamic> json) {
    return Student(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      qrCode: json['qr_code']?.toString() ?? '',
      classroomId: json['classroom']?.toString() ?? '',
      classroomName: json['classroom_name']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'qr_code': qrCode,
      'classroom': classroomId,
      'classroom_name': classroomName,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
