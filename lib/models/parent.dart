import 'student.dart';

class Parent {
  final String id;
  final String name;
  final String email;
  final String phone;
  final List<Student> children;
  final DateTime createdAt;
  final DateTime updatedAt;

  Parent({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.children,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Parent.fromJson(Map<String, dynamic> json) {
    return Parent(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      children: (json['children'] as List<dynamic>?)
          ?.map((child) => Student.fromJson(child))
          .toList() ?? [],
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'children': children.map((child) => child.toJson()).toList(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}
