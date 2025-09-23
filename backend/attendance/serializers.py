from rest_framework import serializers
from .models import ClassRoom, Student, Parent, Teacher, Attendance, Notification


class ClassRoomSerializer(serializers.ModelSerializer):
    class Meta:
        model = ClassRoom
        fields = ['id', 'name', 'qr_code', 'created_at', 'updated_at']


class StudentSerializer(serializers.ModelSerializer):
    classroom_name = serializers.CharField(read_only=True)
    
    class Meta:
        model = Student
        fields = ['id', 'name', 'qr_code', 'classroom', 'classroom_name', 'created_at', 'updated_at']


class ParentSerializer(serializers.ModelSerializer):
    children = StudentSerializer(many=True, read_only=True)
    
    class Meta:
        model = Parent
        fields = ['id', 'name', 'email', 'phone', 'children', 'created_at', 'updated_at']


class TeacherSerializer(serializers.ModelSerializer):
    class Meta:
        model = Teacher
        fields = ['id', 'name', 'user', 'created_at', 'updated_at']


class AttendanceSerializer(serializers.ModelSerializer):
    student_name = serializers.CharField(source='student.name', read_only=True)
    classroom_name = serializers.CharField(source='classroom.name', read_only=True)
    teacher_name = serializers.CharField(source='teacher.name', read_only=True)
    
    class Meta:
        model = Attendance
        fields = ['id', 'student', 'student_name', 'classroom', 'classroom_name', 
                 'teacher', 'teacher_name', 'timestamp', 'is_present']


class AttendanceMarkSerializer(serializers.Serializer):
    student_qr = serializers.CharField(max_length=255)
    class_qr = serializers.CharField(max_length=255)
    
    def validate_student_qr(self, value):
        try:
            Student.objects.get(qr_code=value)
        except Student.DoesNotExist:
            raise serializers.ValidationError("Student with this QR code does not exist.")
        return value
    
    def validate_class_qr(self, value):
        try:
            ClassRoom.objects.get(qr_code=value)
        except ClassRoom.DoesNotExist:
            raise serializers.ValidationError("Classroom with this QR code does not exist.")
        return value


class ParentLoginSerializer(serializers.Serializer):
    name = serializers.CharField(max_length=200)
    email = serializers.EmailField()
    phone = serializers.CharField(max_length=20)
    
    def validate(self, data):
        try:
            parent = Parent.objects.get(
                name=data['name'],
                email=data['email'],
                phone=data['phone']
            )
            data['parent'] = parent
        except Parent.DoesNotExist:
            raise serializers.ValidationError("Parent with these credentials does not exist.")
        return data


class NotificationSerializer(serializers.ModelSerializer):
    student_name = serializers.CharField(source='student.name', read_only=True)
    student_id = serializers.CharField(source='student.id', read_only=True)
    parent_id = serializers.CharField(source='parent.id', read_only=True)
    timestamp = serializers.DateTimeField(source='created_at', read_only=True)

    class Meta:
        model = Notification
        fields = ['id', 'title', 'message', 'type', 'is_read', 'timestamp', 'student_name', 'student_id', 'parent_id']
