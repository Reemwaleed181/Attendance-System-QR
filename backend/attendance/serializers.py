from rest_framework import serializers
from .models import ClassRoom, Student, Parent, Teacher, Attendance, Notification, AttendanceRequest


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


class AttendanceRequestCreateSerializer(serializers.Serializer):
    student_qr = serializers.CharField(max_length=255)
    class_qr = serializers.CharField(max_length=255)
    method = serializers.ChoiceField(choices=['gps', 'qr', 'wifi'], default='gps')
    student_lat = serializers.DecimalField(max_digits=9, decimal_places=6, required=False, allow_null=True)
    student_lng = serializers.DecimalField(max_digits=9, decimal_places=6, required=False, allow_null=True)
    metadata = serializers.JSONField(required=False)

    def validate(self, data):
        # Validate referenced entities exist
        try:
            data['student'] = Student.objects.get(qr_code=data['student_qr'])
        except Student.DoesNotExist:
            raise serializers.ValidationError({'student_qr': ['Student with this QR does not exist.']})
        try:
            data['classroom'] = ClassRoom.objects.get(qr_code=data['class_qr'])
        except ClassRoom.DoesNotExist:
            raise serializers.ValidationError({'class_qr': ['Classroom with this QR does not exist.']})
        return data


class AttendanceRequestSerializer(serializers.ModelSerializer):
    student_name = serializers.CharField(source='student.name', read_only=True)
    classroom_name = serializers.CharField(source='classroom.name', read_only=True)
    approved_by_name = serializers.CharField(source='approved_by.name', read_only=True)

    class Meta:
        model = AttendanceRequest
        fields = [
            'id', 'student', 'student_name', 'classroom', 'classroom_name',
            'status', 'method', 'student_lat', 'student_lng', 'metadata',
            'created_at', 'expires_at', 'approved_by', 'approved_by_name', 'approved_at'
        ]


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
    
    def validate_phone(self, value):
        # Allow only digits, optional leading + not stored; normalize by stripping spaces
        raw = value.strip()
        digits = ''.join(ch for ch in raw if ch.isdigit())
        if not digits:
            raise serializers.ValidationError("Phone number is required.")
        if len(digits) < 7 or len(digits) > 15:
            raise serializers.ValidationError("Phone number must be 7-15 digits.")
        if not raw.replace('+', '').isdigit():
            raise serializers.ValidationError("Phone number must contain digits only.")
        return raw

    def validate(self, data):
        # Stepwise checks to provide precise error messages
        email_qs = Parent.objects.filter(email=data['email'])
        if not email_qs.exists():
            raise serializers.ValidationError({
                'email': ["No parent found with this email address."],
                'name': [],
                'phone': [],
            })

        name_qs = email_qs.filter(name=data['name'])
        if not name_qs.exists():
            raise serializers.ValidationError({
                'name': ["Name does not match our records for this email."],
                'email': [],
                'phone': [],
            })

        phone_qs = name_qs.filter(phone=data['phone'])
        if not phone_qs.exists():
            raise serializers.ValidationError({
                'phone': ["Phone number is incorrect."],
                'name': [],
                'email': [],
            })

        parent = phone_qs.first()
        data['parent'] = parent
        return data


class NotificationSerializer(serializers.ModelSerializer):
    student_name = serializers.CharField(source='student.name', read_only=True)
    student_id = serializers.CharField(source='student.id', read_only=True)
    parent_id = serializers.CharField(source='parent.id', read_only=True)
    timestamp = serializers.DateTimeField(source='created_at', read_only=True)

    class Meta:
        model = Notification
        fields = ['id', 'title', 'message', 'type', 'is_read', 'timestamp', 'student_name', 'student_id', 'parent_id']
