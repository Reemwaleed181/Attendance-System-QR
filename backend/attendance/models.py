from django.db import models
from django.contrib.auth.models import User
import uuid


class ClassRoom(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name = models.CharField(max_length=100, unique=True)
    qr_code = models.CharField(max_length=255, unique=True)
    # Optional geofence center and radius (meters)
    latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    radius_meters = models.PositiveIntegerField(default=50)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return self.name

    class Meta:
        verbose_name = "Class Room"
        verbose_name_plural = "Class Rooms"


class Student(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name = models.CharField(max_length=200)
    qr_code = models.CharField(max_length=255, unique=True)
    classroom = models.ForeignKey(ClassRoom, on_delete=models.CASCADE, related_name='students')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    @property
    def classroom_name(self):
        """Return the classroom name, with fallback if classroom is None"""
        return self.classroom.name if self.classroom else "Not Assigned"

    def __str__(self):
        return f"{self.name} - {self.classroom_name}"

    class Meta:
        verbose_name = "Student"
        verbose_name_plural = "Students"


class Parent(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name = models.CharField(max_length=200)
    email = models.EmailField(unique=True)
    phone = models.CharField(max_length=20)
    children = models.ManyToManyField(Student, related_name='parents', blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.name} ({self.email})"

    class Meta:
        verbose_name = "Parent"
        verbose_name_plural = "Parents"


class Teacher(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE)
    name = models.CharField(max_length=200)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return self.name

    class Meta:
        verbose_name = "Teacher"
        verbose_name_plural = "Teachers"


class Attendance(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name='attendances')
    classroom = models.ForeignKey(ClassRoom, on_delete=models.CASCADE, related_name='attendances')
    teacher = models.ForeignKey(Teacher, on_delete=models.CASCADE, related_name='attendances')
    timestamp = models.DateTimeField(auto_now_add=True)
    is_present = models.BooleanField(default=True)
    # Optional recorded student location at time of attendance
    student_lat = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    student_lng = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)

    def __str__(self):
        return f"{self.student.name} - {self.classroom.name} - {self.timestamp.strftime('%Y-%m-%d %H:%M')}"

    class Meta:
        verbose_name = "Attendance"
        verbose_name_plural = "Attendances"


class StudentAuth(models.Model):
    """Simple credential store for students (CSV-importable)."""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    student = models.OneToOneField(Student, on_delete=models.CASCADE, related_name='auth')
    username = models.CharField(max_length=150, unique=True)
    # Store a salted hash in production; here we keep a plain field placeholder to be set by importer
    password = models.CharField(max_length=128)
    token = models.CharField(max_length=64, unique=True, blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.username} -> {self.student.name}"


class SelfAttendanceWindow(models.Model):
    """When a teacher enables student self-recording for a classroom."""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    classroom = models.ForeignKey(ClassRoom, on_delete=models.CASCADE, related_name='self_windows')
    teacher = models.ForeignKey(Teacher, on_delete=models.CASCADE, related_name='self_windows')
    opened_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    is_active = models.BooleanField(default=True)

    class Meta:
        indexes = [
            models.Index(fields=['classroom', 'expires_at', 'is_active']),
        ]

    def __str__(self):
        return f"Window({self.classroom.name}) by {self.teacher.name}"

class Notification(models.Model):
    NOTIFICATION_TYPES = [
        ('absence', 'Absence Alert'),
        ('daily_absence', 'Daily Absence Alert'),
        ('teacher_report', 'Teacher Report'),
        ('late', 'Late Arrival'),
        ('report', 'Attendance Report'),
        ('general', 'General'),
    ]
    
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    parent = models.ForeignKey(Parent, on_delete=models.CASCADE, related_name='notifications')
    student = models.ForeignKey(Student, on_delete=models.CASCADE, null=True, blank=True)
    title = models.CharField(max_length=200)
    message = models.TextField()
    type = models.CharField(max_length=20, choices=NOTIFICATION_TYPES, default='general')
    is_read = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"{self.parent.name} - {self.title}"

    class Meta:
        verbose_name = "Notification"
        verbose_name_plural = "Notifications"
        ordering = ['-created_at']


class AttendanceRequest(models.Model):
    STATUS_PENDING = 'pending'
    STATUS_APPROVED = 'approved'
    STATUS_DENIED = 'denied'
    STATUS_EXPIRED = 'expired'

    STATUS_CHOICES = [
        (STATUS_PENDING, 'Pending'),
        (STATUS_APPROVED, 'Approved'),
        (STATUS_DENIED, 'Denied'),
        (STATUS_EXPIRED, 'Expired'),
    ]

    METHOD_GPS = 'gps'
    METHOD_QR = 'qr'
    METHOD_WIFI = 'wifi'

    METHOD_CHOICES = [
        (METHOD_GPS, 'GPS'),
        (METHOD_QR, 'QR'),
        (METHOD_WIFI, 'WiFi'),
    ]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    student = models.ForeignKey(Student, on_delete=models.CASCADE, related_name='attendance_requests')
    classroom = models.ForeignKey(ClassRoom, on_delete=models.CASCADE, related_name='attendance_requests')
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default=STATUS_PENDING)
    method = models.CharField(max_length=20, choices=METHOD_CHOICES, default=METHOD_GPS)
    student_lat = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    student_lng = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    metadata = models.JSONField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField(null=True, blank=True)
    approved_by = models.ForeignKey(Teacher, null=True, blank=True, on_delete=models.SET_NULL, related_name='approved_attendance_requests')
    approved_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f"Request({self.student.name} -> {self.classroom.name}) [{self.status}]"
