from rest_framework import status, generics, permissions
import uuid
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response
from rest_framework.authtoken.models import Token
from django.contrib.auth import authenticate
from django.contrib.auth.models import User
from django.utils import timezone
from datetime import datetime, date, timedelta
from .models import ClassRoom, Student, Parent, Teacher, Attendance, Notification, AttendanceRequest, StudentAuth, SelfAttendanceWindow
from .serializers import (
    ClassRoomSerializer, StudentSerializer, ParentSerializer, 
    TeacherSerializer, AttendanceSerializer, AttendanceMarkSerializer,
    ParentLoginSerializer, NotificationSerializer, AttendanceRequestCreateSerializer, AttendanceRequestSerializer
)

def get_local_date_key(timestamp, timezone_offset=None):
    """
    Convert UTC timestamp to local timezone and return date key in YYYY-MM-DD format
    If timezone_offset is provided (in minutes), use it; otherwise use Django's local timezone
    """
    if timezone_offset is not None:
        # Use the provided timezone offset (from client device)
        from datetime import timedelta
        local_timestamp = timestamp + timedelta(minutes=timezone_offset)
    else:
        # Fallback to Django's local timezone
        local_timestamp = timezone.localtime(timestamp)
    
    return local_timestamp.date().isoformat()


def api_error(message, http_status, *, code=None, details=None, fields=None):
    """
    Unified API error response helper.
    """
    payload = {
        'message': message,
        'status': http_status,
    }
    if code is not None:
        payload['code'] = code
    if details is not None:
        payload['details'] = details
    if fields is not None:
        payload['fields'] = fields
    return Response(payload, status=http_status)


def _haversine_distance_meters(lat1, lon1, lat2, lon2):
    """
    Calculate distance between two lat/lng points in meters.
    """
    from math import radians, sin, cos, sqrt, atan2
    R = 6371000.0
    dlat = radians(float(lat2) - float(lat1))
    dlon = radians(float(lon2) - float(lon1))
    a = sin(dlat/2)**2 + cos(radians(float(lat1))) * cos(radians(float(lat2))) * sin(dlon/2)**2
    c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return R * c


def _within_geofence(classroom: ClassRoom, lat, lng) -> bool:
    if classroom.latitude is None or classroom.longitude is None:
        return True  # No geofence configured; allow by default
    if lat is None or lng is None:
        return False
    distance = _haversine_distance_meters(classroom.latitude, classroom.longitude, lat, lng)
    return distance <= max(10, classroom.radius_meters)


class ClassRoomListView(generics.ListAPIView):
    queryset = ClassRoom.objects.all()
    serializer_class = ClassRoomSerializer
    permission_classes = [permissions.IsAuthenticated]


class StudentListView(generics.ListAPIView):
    queryset = Student.objects.all()
    serializer_class = StudentSerializer
    permission_classes = [permissions.IsAuthenticated]


@api_view(['POST'])
@permission_classes([permissions.IsAuthenticated])
def mark_attendance(request):
    """
    Mark attendance for a student in a specific classroom
    """
    serializer = AttendanceMarkSerializer(data=request.data)
    if serializer.is_valid():
        student_qr = serializer.validated_data['student_qr']
        class_qr = serializer.validated_data['class_qr']
        is_present = request.data.get('is_present', True)  # Default to present when scanned
        
        try:
            student = Student.objects.get(qr_code=student_qr)
            classroom = ClassRoom.objects.get(qr_code=class_qr)
            teacher = Teacher.objects.get(user=request.user)
            
            # Check if attendance already marked for today
            today = timezone.now().date()
            existing_attendance = Attendance.objects.filter(
                student=student,
                classroom=classroom,
                teacher=teacher,
                timestamp__date=today
            ).first()
            
            if existing_attendance:
                # Update existing attendance if different
                if existing_attendance.is_present != is_present:
                    existing_attendance.is_present = is_present
                    existing_attendance.save()
                    return Response({
                        'message': 'Attendance updated successfully',
                        'attendance': AttendanceSerializer(existing_attendance).data
                    }, status=status.HTTP_200_OK)
                else:
                    return Response({
                        'message': 'Attendance already marked for this student today',
                        'attendance': AttendanceSerializer(existing_attendance).data
                    }, status=status.HTTP_200_OK)
            
            # Create new attendance record
            attendance = Attendance.objects.create(
                student=student,
                classroom=classroom,
                teacher=teacher,
                is_present=is_present
            )
            
          
            
            return Response({
                'message': 'Attendance marked successfully',
                'attendance': AttendanceSerializer(attendance).data
            }, status=status.HTTP_201_CREATED)
            
        except Student.DoesNotExist:
            return api_error('Student not found', status.HTTP_404_NOT_FOUND, code='student_not_found')
        except ClassRoom.DoesNotExist:
            return api_error('Classroom not found', status.HTTP_404_NOT_FOUND, code='classroom_not_found')
        except Teacher.DoesNotExist:
            return api_error('Teacher profile not found', status.HTTP_404_NOT_FOUND, code='teacher_not_found')
    
    return api_error('Invalid data', status.HTTP_400_BAD_REQUEST, code='invalid_input', fields=serializer.errors)


@api_view(['POST'])
@permission_classes([permissions.AllowAny])
def create_attendance_request(request):
    """
    Student creates an attendance request for a classroom (by QR) with optional GPS.
    """
    serializer = AttendanceRequestCreateSerializer(data=request.data)
    if not serializer.is_valid():
        return api_error('Invalid data', status.HTTP_400_BAD_REQUEST, code='invalid_input', fields=serializer.errors)

    data = serializer.validated_data
    student = data['student']
    classroom = data['classroom']
    method = data.get('method', 'gps')
    student_lat = data.get('student_lat')
    student_lng = data.get('student_lng')
    metadata = data.get('metadata')

    # Prevent multiple active pending requests for the same student/classroom today
    today = timezone.now().date()
    existing = AttendanceRequest.objects.filter(
        student=student, classroom=classroom, status=AttendanceRequest.STATUS_PENDING,
        created_at__date=today
    ).first()
    if existing:
        return Response({'message': 'Existing pending request found', 'request': AttendanceRequestSerializer(existing).data}, status=status.HTTP_200_OK)

    # Simple geofence validation at request time (informative; final validation on approval)
    geofence_ok = _within_geofence(classroom, student_lat, student_lng)
    if method == 'gps' and not geofence_ok:
        return api_error('Location is outside classroom geofence', status.HTTP_400_BAD_REQUEST, code='outside_geofence')

    # Create request with short expiry window (e.g., 10 minutes)
    expires_at = timezone.now() + timedelta(minutes=10)
    attendance_request = AttendanceRequest.objects.create(
        student=student,
        classroom=classroom,
        method=method,
        student_lat=student_lat,
        student_lng=student_lng,
        metadata=metadata,
        expires_at=expires_at,
    )

    return Response({'message': 'Attendance request created', 'request': AttendanceRequestSerializer(attendance_request).data}, status=status.HTTP_201_CREATED)


@api_view(['GET'])
@permission_classes([permissions.IsAuthenticated])
def list_pending_attendance_requests(request):
    """
    Teacher lists pending attendance requests for their classrooms (today).
    """
    try:
        teacher = Teacher.objects.get(user=request.user)
    except Teacher.DoesNotExist:
        return api_error('Teacher not found', status.HTTP_404_NOT_FOUND, code='teacher_not_found')

    today = timezone.now().date()
    pending = AttendanceRequest.objects.filter(
        classroom__attendances__teacher=teacher,
        status=AttendanceRequest.STATUS_PENDING,
        created_at__date=today
    ).select_related('student', 'classroom').distinct().order_by('-created_at')

    return Response({'requests': AttendanceRequestSerializer(pending, many=True).data}, status=status.HTTP_200_OK)


def _approve_request(attendance_request: AttendanceRequest, teacher: Teacher):
    # Final geofence recheck on approval if GPS
    if attendance_request.method == AttendanceRequest.METHOD_GPS and attendance_request.classroom.latitude is not None:
        if not _within_geofence(attendance_request.classroom, attendance_request.student_lat, attendance_request.student_lng):
            return False, 'Location outside geofence at approval time'

    # Create attendance record if not already created today
    today = timezone.now().date()
    existing_attendance = Attendance.objects.filter(
        student=attendance_request.student,
        classroom=attendance_request.classroom,
        teacher=teacher,
        timestamp__date=today
    ).first()
    if existing_attendance is None:
        Attendance.objects.create(
            student=attendance_request.student,
            classroom=attendance_request.classroom,
            teacher=teacher,
            is_present=True,
        )

    attendance_request.status = AttendanceRequest.STATUS_APPROVED
    attendance_request.approved_by = teacher
    attendance_request.approved_at = timezone.now()
    attendance_request.save()
    return True, None


@api_view(['POST'])
@permission_classes([permissions.IsAuthenticated])
def approve_attendance_request(request, request_id):
    try:
        teacher = Teacher.objects.get(user=request.user)
    except Teacher.DoesNotExist:
        return api_error('Teacher not found', status.HTTP_404_NOT_FOUND, code='teacher_not_found')

    try:
        attendance_request = AttendanceRequest.objects.select_related('student', 'classroom').get(id=request_id)
    except AttendanceRequest.DoesNotExist:
        return api_error('Request not found', status.HTTP_404_NOT_FOUND, code='request_not_found')

    if attendance_request.status != AttendanceRequest.STATUS_PENDING:
        return api_error('Request is not pending', status.HTTP_400_BAD_REQUEST, code='invalid_status')

    if attendance_request.expires_at and attendance_request.expires_at < timezone.now():
        attendance_request.status = AttendanceRequest.STATUS_EXPIRED
        attendance_request.save()
        return api_error('Request expired', status.HTTP_400_BAD_REQUEST, code='expired')

    ok, err = _approve_request(attendance_request, teacher)
    if not ok:
        return api_error(err or 'Approval failed', status.HTTP_400_BAD_REQUEST, code='approval_failed')

    return Response({'message': 'Request approved', 'request': AttendanceRequestSerializer(attendance_request).data}, status=status.HTTP_200_OK)


@api_view(['POST'])
@permission_classes([permissions.IsAuthenticated])
def deny_attendance_request(request, request_id):
    try:
        Teacher.objects.get(user=request.user)
    except Teacher.DoesNotExist:
        return api_error('Teacher not found', status.HTTP_404_NOT_FOUND, code='teacher_not_found')

    try:
        attendance_request = AttendanceRequest.objects.get(id=request_id)
    except AttendanceRequest.DoesNotExist:
        return api_error('Request not found', status.HTTP_404_NOT_FOUND, code='request_not_found')

    if attendance_request.status != AttendanceRequest.STATUS_PENDING:
        return api_error('Request is not pending', status.HTTP_400_BAD_REQUEST, code='invalid_status')

    attendance_request.status = AttendanceRequest.STATUS_DENIED
    attendance_request.save()
    return Response({'message': 'Request denied', 'request': AttendanceRequestSerializer(attendance_request).data}, status=status.HTTP_200_OK)


@api_view(['POST'])
@permission_classes([permissions.IsAuthenticated])
def mark_absence(request):
    """
    Mark a student as absent for a specific classroom
    """
    serializer = AttendanceMarkSerializer(data=request.data)
    if serializer.is_valid():
        student_qr = serializer.validated_data['student_qr']
        class_qr = serializer.validated_data['class_qr']
        
        try:
            student = Student.objects.get(qr_code=student_qr)
            classroom = ClassRoom.objects.get(qr_code=class_qr)
            teacher = Teacher.objects.get(user=request.user)
            
            # Check if attendance already marked for today
            today = timezone.now().date()
            existing_attendance = Attendance.objects.filter(
                student=student,
                classroom=classroom,
                teacher=teacher,
                timestamp__date=today
            ).first()
            
            if existing_attendance:
                return Response({
                    'message': 'Attendance already marked for this student today',
                    'attendance': AttendanceSerializer(existing_attendance).data
                }, status=status.HTTP_200_OK)
            
            # Create new attendance record (marked as absent)
            attendance = Attendance.objects.create(
                student=student,
                classroom=classroom,
                teacher=teacher,
                is_present=False
            )
            
            # Note: Daily absence notifications are now sent via the frontend API call
            # to avoid duplicate notifications
            
            return Response({
                'message': 'Absence marked successfully',
                'attendance': AttendanceSerializer(attendance).data
            }, status=status.HTTP_201_CREATED)
            
        except Student.DoesNotExist:
            return api_error('Student not found', status.HTTP_404_NOT_FOUND, code='student_not_found')
        except ClassRoom.DoesNotExist:
            return api_error('Classroom not found', status.HTTP_404_NOT_FOUND, code='classroom_not_found')
        except Teacher.DoesNotExist:
            return api_error('Teacher profile not found', status.HTTP_404_NOT_FOUND, code='teacher_not_found')
    
    return api_error('Invalid data', status.HTTP_400_BAD_REQUEST, code='invalid_input', fields=serializer.errors)


@api_view(['POST'])
@permission_classes([permissions.AllowAny])
def teacher_login(request):
    """
    Teacher login endpoint
    """
    username = request.data.get('username')
    password = request.data.get('password')
    
    if not username or not password:
        return api_error('Username and password required', status.HTTP_400_BAD_REQUEST, code='missing_credentials', fields={
            'username': ['This field is required.'] if not username else [],
            'password': ['This field is required.'] if not password else [],
        })
    
    # Distinguish username vs password errors
    try:
        user_obj = User.objects.get(username=username)
    except User.DoesNotExist:
        return api_error('Invalid username', status.HTTP_401_UNAUTHORIZED, code='invalid_username', fields={
            'username': ['Invalid username'],
            'password': [],
        })

    # Check password
    user = authenticate(username=username, password=password)
    if user is None:
        return api_error('Invalid password', status.HTTP_401_UNAUTHORIZED, code='invalid_password', fields={
            'username': [],
            'password': ['Invalid password'],
        })

    if hasattr(user, 'teacher'):
        token, created = Token.objects.get_or_create(user=user)
        return Response({
            'token': token.key,
            'teacher': TeacherSerializer(user.teacher).data
        }, status=status.HTTP_200_OK)
    
    return api_error('Account is not a teacher', status.HTTP_403_FORBIDDEN, code='not_teacher')


@api_view(['POST'])
@permission_classes([permissions.AllowAny])
def parent_login(request):
    """
    Parent login endpoint using name, email, and phone
    """
    serializer = ParentLoginSerializer(data=request.data)
    if serializer.is_valid():
        parent = serializer.validated_data['parent']
        return Response({
            'message': 'Login successful',
            'parent': ParentSerializer(parent).data
        }, status=status.HTTP_200_OK)
    
    # Pass through field-specific messages from serializer
    return api_error('Invalid parent credentials', status.HTTP_400_BAD_REQUEST, code='invalid_input', fields=serializer.errors)


@api_view(['POST'])
@permission_classes([permissions.AllowAny])
def student_login(request):
    """Student username/password login. Returns short-lived token stored on StudentAuth."""
    username = request.data.get('username')
    password = request.data.get('password')
    if not username or not password:
        return api_error('Username and password required', status.HTTP_400_BAD_REQUEST, code='missing_credentials', fields={
            'username': ['Required'] if not username else [],
            'password': ['Required'] if not password else [],
        })
    try:
        auth = StudentAuth.objects.select_related('student__classroom').get(username=username)
    except StudentAuth.DoesNotExist:
        return api_error('Invalid username', status.HTTP_401_UNAUTHORIZED, code='invalid_username')
    if auth.password != password:
        return api_error('Invalid password', status.HTTP_401_UNAUTHORIZED, code='invalid_password')

    # Issue a simple token (UUID) for client use
    if not auth.token:
        auth.token = uuid.uuid4().hex
    else:
        # rotate token on login
        auth.token = uuid.uuid4().hex
    auth.save()

    return Response({
        'token': auth.token,
        'student': StudentSerializer(auth.student).data,
        'classroom': ClassRoomSerializer(auth.student.classroom).data,
    }, status=status.HTTP_200_OK)


def _get_active_window_for_class(classroom: ClassRoom):
    now = timezone.now()
    return SelfAttendanceWindow.objects.filter(classroom=classroom, is_active=True, expires_at__gt=now).order_by('-opened_at').first()


@api_view(['GET'])
@permission_classes([permissions.AllowAny])
def self_attendance_status(request):
    """Return whether self-attendance is currently enabled for a classroom for a given student token."""
    token = request.headers.get('X-Student-Token') or request.GET.get('student_token')
    class_qr = request.GET.get('class_qr')
    if not token or not class_qr:
        return api_error('Missing token or class_qr', status.HTTP_400_BAD_REQUEST, code='missing_parameters')
    try:
        auth = StudentAuth.objects.select_related('student__classroom').get(token=token)
    except StudentAuth.DoesNotExist:
        return api_error('Invalid token', status.HTTP_401_UNAUTHORIZED, code='invalid_token')
    try:
        classroom = ClassRoom.objects.get(qr_code=class_qr)
    except ClassRoom.DoesNotExist:
        return api_error('Classroom not found', status.HTTP_404_NOT_FOUND, code='classroom_not_found')
    window = _get_active_window_for_class(classroom)
    return Response({
        'enabled': bool(window),
        'expires_at': window.expires_at.isoformat() if window else None,
    }, status=status.HTTP_200_OK)


@api_view(['POST'])
@permission_classes([permissions.IsAuthenticated])
def open_self_attendance_window(request):
    """Teacher enables student self-recording for a classroom for a short time window."""
    class_qr = request.data.get('class_qr')
    minutes = int(request.data.get('minutes', 10))
    if not class_qr:
        return api_error('class_qr required', status.HTTP_400_BAD_REQUEST, code='missing_parameters', fields={'class_qr': ['Required']})
    try:
        teacher = Teacher.objects.get(user=request.user)
        classroom = ClassRoom.objects.get(qr_code=class_qr)
    except (Teacher.DoesNotExist, ClassRoom.DoesNotExist):
        return api_error('Teacher or classroom not found', status.HTTP_404_NOT_FOUND, code='not_found')

    # Close any previous active window for this class
    SelfAttendanceWindow.objects.filter(classroom=classroom, is_active=True).update(is_active=False)
    window = SelfAttendanceWindow.objects.create(
        classroom=classroom,
        teacher=teacher,
        expires_at=timezone.now() + timedelta(minutes=max(1, min(30, minutes))),
        is_active=True,
    )
    return Response({
        'message': 'Self attendance enabled',
        'expires_at': window.expires_at.isoformat(),
    }, status=status.HTTP_201_CREATED)


@api_view(['POST'])
@permission_classes([permissions.IsAuthenticated])
def close_self_attendance_window(request):
    """Teacher closes any active window for a classroom immediately."""
    class_qr = request.data.get('class_qr')
    if not class_qr:
        return api_error('class_qr required', status.HTTP_400_BAD_REQUEST, code='missing_parameters', fields={'class_qr': ['Required']})
    try:
        Teacher.objects.get(user=request.user)
        classroom = ClassRoom.objects.get(qr_code=class_qr)
    except (Teacher.DoesNotExist, ClassRoom.DoesNotExist):
        return api_error('Teacher or classroom not found', status.HTTP_404_NOT_FOUND, code='not_found')
    updated = SelfAttendanceWindow.objects.filter(classroom=classroom, is_active=True).update(is_active=False, expires_at=timezone.now())
    return Response({'message': 'Self attendance disabled', 'closed': updated}, status=status.HTTP_200_OK)

@api_view(['POST'])
@permission_classes([permissions.AllowAny])
def student_self_mark(request):
    """Student marks own attendance during an active window, with optional GPS geofence check."""
    token = request.headers.get('X-Student-Token') or request.data.get('student_token')
    class_qr = request.data.get('class_qr')
    student_lat = request.data.get('student_lat')
    student_lng = request.data.get('student_lng')
    if not token or not class_qr:
        return api_error('Missing token or class_qr', status.HTTP_400_BAD_REQUEST, code='missing_parameters')
    try:
        auth = StudentAuth.objects.select_related('student__classroom').get(token=token)
    except StudentAuth.DoesNotExist:
        return api_error('Invalid token', status.HTTP_401_UNAUTHORIZED, code='invalid_token')
    student = auth.student
    if not student.classroom:
        return api_error('Student not linked to a classroom', status.HTTP_400_BAD_REQUEST, code='student_no_class')
    try:
        classroom = ClassRoom.objects.get(qr_code=class_qr)
    except ClassRoom.DoesNotExist:
        return api_error('Classroom not found', status.HTTP_404_NOT_FOUND, code='classroom_not_found')
    if classroom.id != student.classroom.id:
        return api_error('Student not in this classroom', status.HTTP_403_FORBIDDEN, code='wrong_class')

    window = _get_active_window_for_class(classroom)
    if not window:
        return api_error('Self attendance window not active', status.HTTP_403_FORBIDDEN, code='no_active_window')

    # Geofence: use classroom geofence if defined
    if not _within_geofence(classroom, student_lat, student_lng):
        return api_error('Outside of teacher location', status.HTTP_403_FORBIDDEN, code='outside_geofence')

    # Record attendance under the teacher who opened the window
    today = timezone.now().date()
    existing = Attendance.objects.filter(
        student=student,
        classroom=classroom,
        teacher=window.teacher,
        timestamp__date=today
    ).first()
    if existing:
        # Ensure marked present and bump timestamp to reflect the current action
        changed = False
        if not existing.is_present:
            existing.is_present = True
            changed = True
        # Update timestamp so live feed during the window can include it
        existing.timestamp = timezone.now()
        existing.save(update_fields=['is_present', 'timestamp'] if changed else ['timestamp'])
        return Response({'message': 'Attendance already recorded', 'attendance': AttendanceSerializer(existing).data}, status=status.HTTP_200_OK)

    attendance = Attendance.objects.create(
        student=student,
        classroom=classroom,
        teacher=window.teacher,
        is_present=True,
        student_lat=student_lat,
        student_lng=student_lng,
    )
    return Response({'message': 'Attendance recorded successfully', 'attendance': AttendanceSerializer(attendance).data}, status=status.HTTP_201_CREATED)


@api_view(['GET'])
@permission_classes([permissions.IsAuthenticated])
def teacher_live_class_attendance(request):
    """Return latest present attendance records for a class today to support lightweight polling."""
    class_qr = request.GET.get('class_qr')
    if not class_qr:
        return api_error('class_qr required', status.HTTP_400_BAD_REQUEST, code='missing_parameters', fields={'class_qr': ['Required']})
    try:
        teacher = Teacher.objects.get(user=request.user)
        classroom = ClassRoom.objects.get(qr_code=class_qr)
    except (Teacher.DoesNotExist, ClassRoom.DoesNotExist):
        return api_error('Teacher or classroom not found', status.HTTP_404_NOT_FOUND, code='not_found')

    # Only return records created during the CURRENT active self-attendance window
    now = timezone.now()
    window = SelfAttendanceWindow.objects.filter(
        classroom=classroom, teacher=teacher, is_active=True, expires_at__gt=now
    ).order_by('-opened_at').first()

    if not window:
        return Response({'records': []}, status=status.HTTP_200_OK)

    # Only today, only marked present by this teacher, and created after the window opened
    today = now.date()
    records = Attendance.objects.filter(
        classroom=classroom,
        teacher=teacher,
        timestamp__date=today,
        timestamp__gte=window.opened_at,
        is_present=True,
    ).select_related('student').order_by('-timestamp')[:100]

    payload = []
    for rec in records:
        payload.append({
            'student_id': str(rec.student.id),
            'student_name': rec.student.name,
            'timestamp': rec.timestamp.isoformat(),
        })

    return Response({'records': payload}, status=status.HTTP_200_OK)

@api_view(['GET'])
@permission_classes([permissions.AllowAny])
def parent_children_attendance(request, parent_id):
    """
    Get children and their attendance records for a parent
    """
    try:
        parent = Parent.objects.get(id=parent_id)
        # Optimize query by selecting related classroom data
        children = parent.children.select_related('classroom').all()
        
        # Get attendance records for today
        today = timezone.now().date()
        attendance_records = Attendance.objects.filter(
            student__in=children,
            timestamp__date=today
        ).select_related('student', 'classroom', 'teacher')
        
        # Organize data
        children_data = []
        for child in children:
            child_attendance = attendance_records.filter(student=child)
            # Ensure child has classroom data
            if not hasattr(child, 'classroom') or child.classroom is None:
                print(f"Warning: Student {child.name} has no classroom assigned")
            
            children_data.append({
                'student': StudentSerializer(child).data,
                'attendance_today': AttendanceSerializer(child_attendance, many=True).data,
                'is_present_today': child_attendance.exists()
            })
        
        return Response({
            'parent': ParentSerializer(parent).data,
            'children': children_data
        }, status=status.HTTP_200_OK)
        
    except Parent.DoesNotExist:
        return api_error('Parent not found', status.HTTP_404_NOT_FOUND, code='parent_not_found')


@api_view(['GET'])
@permission_classes([permissions.AllowAny])
def student_attendance_history(request, student_id):
    """
    Get attendance history for a specific student
    """
    try:
        student = Student.objects.select_related('classroom').get(id=student_id)
        attendance_records = Attendance.objects.filter(
            student=student
        ).order_by('-timestamp').select_related('classroom', 'teacher')
        
        return Response({
            'student': StudentSerializer(student).data,
            'attendance_history': AttendanceSerializer(attendance_records, many=True).data
        }, status=status.HTTP_200_OK)
        
    except Student.DoesNotExist:
        return api_error('Student not found', status.HTTP_404_NOT_FOUND, code='student_not_found')


@api_view(['GET'])
@permission_classes([permissions.IsAuthenticated])
def teacher_attendance_history(request):
    """
    Get attendance history for all students marked by the authenticated teacher
    """
    try:
        # Get the teacher from the authenticated user
        teacher = Teacher.objects.get(user=request.user)
        
        # Get timezone offset from request headers (in minutes)
        timezone_offset = request.META.get('HTTP_X_TIMEZONE_OFFSET')
        if timezone_offset:
            try:
                timezone_offset = int(timezone_offset)
            except (ValueError, TypeError):
                timezone_offset = None
        
        # Get all attendance records marked by this teacher
        attendance_records = Attendance.objects.filter(
            teacher=teacher
        ).order_by('-timestamp').select_related('student', 'classroom')
        
        # Group by date for better organization using device timezone
        attendance_by_date = {}
        total_records = 0
        
        for record in attendance_records:
            # Convert UTC timestamp to device timezone for date grouping
            date_key = get_local_date_key(record.timestamp, timezone_offset)
            if date_key not in attendance_by_date:
                attendance_by_date[date_key] = []
            attendance_by_date[date_key].append(AttendanceSerializer(record).data)
            total_records += 1
        
        # Calculate teacher's attendance statistics
        present_count = attendance_records.filter(is_present=True).count()
        absent_count = attendance_records.filter(is_present=False).count()
        attendance_rate = (present_count / total_records) if total_records > 0 else 0
        
        # Get unique students and classrooms
        unique_students = attendance_records.values('student__id').distinct().count()
        unique_classrooms = attendance_records.values('classroom__id').distinct().count()
        
        return Response({
            'teacher': TeacherSerializer(teacher).data,
            'attendance_by_date': attendance_by_date,
            'total_records': total_records,
            'statistics': {
                'present_count': present_count,
                'absent_count': absent_count,
                'attendance_rate': round(attendance_rate * 100, 2),
                'unique_students': unique_students,
                'unique_classrooms': unique_classrooms,
            }
        }, status=status.HTTP_200_OK)
        
    except Teacher.DoesNotExist:
        return api_error('Teacher not found', status.HTTP_404_NOT_FOUND, code='teacher_not_found')
    except Exception as e:
        return api_error('An error occurred while fetching attendance history', status.HTTP_500_INTERNAL_SERVER_ERROR, code='server_error', details=str(e))


@api_view(['GET'])
@permission_classes([permissions.IsAuthenticated])
def teacher_reports(request):
    """
    Get attendance reports and statistics for the authenticated teacher
    """
    try:
        # Get the teacher from the authenticated user
        teacher = Teacher.objects.get(user=request.user)
        
        # Get date range from query parameters (required)
        from_date = request.GET.get('from_date')
        to_date = request.GET.get('to_date')
        
        if not from_date or not to_date:
            return api_error('Both from_date and to_date parameters are required', status.HTTP_400_BAD_REQUEST, code='missing_parameters', fields={'from_date': ['Required'] if not from_date else [], 'to_date': ['Required'] if not to_date else []})
        
        try:
            from_date = datetime.strptime(from_date, '%Y-%m-%d').date()
            to_date = datetime.strptime(to_date, '%Y-%m-%d').date()
        except ValueError:
            return api_error('Invalid date format. Use YYYY-MM-DD format', status.HTTP_400_BAD_REQUEST, code='invalid_date_format')
        
        # Get attendance records in date range
        attendance_records = Attendance.objects.filter(
            teacher=teacher,
            timestamp__date__range=[from_date, to_date]
        ).select_related('student', 'classroom')
        
        # Calculate statistics based on teacher's actual actions only
        total_attendance = attendance_records.count()
        present_count = attendance_records.filter(is_present=True).count()
        absent_count = attendance_records.filter(is_present=False).count()
        
        # Calculate attendance rate based on actual records (not theoretical)
        attendance_rate = (present_count / total_attendance) if total_attendance > 0 else 0
        
        # Get unique students and classrooms from teacher's actual actions
        unique_students = attendance_records.values('student__id').distinct().count()
        unique_classrooms = attendance_records.values('classroom__id').distinct().count()
        
        # Daily attendance summary based on teacher's actual actions
        daily_summary = {}
        for record in attendance_records:
            date_key = record.timestamp.date().isoformat()
            if date_key not in daily_summary:
                daily_summary[date_key] = {'present': 0, 'absent': 0, 'total': 0}
            daily_summary[date_key]['total'] += 1
            if record.is_present:
                daily_summary[date_key]['present'] += 1
            else:
                daily_summary[date_key]['absent'] += 1
        
        return Response({
            'teacher': TeacherSerializer(teacher).data,
            'date_range': {
                'from': from_date.isoformat(),
                'to': to_date.isoformat()
            },
            'statistics': {
                'total_attendance': total_attendance,
                'present_count': present_count,
                'absent_count': absent_count,
                'attendance_rate': round(attendance_rate, 2),
                'unique_students': unique_students,
                'unique_classrooms': unique_classrooms
            },
            'daily_summary': daily_summary
        }, status=status.HTTP_200_OK)
        
    except Teacher.DoesNotExist:
        return api_error('Teacher not found', status.HTTP_404_NOT_FOUND, code='teacher_not_found')


@api_view(['GET'])
@permission_classes([permissions.AllowAny])
def student_weekly_stats(request, student_id):
    """
    Get weekly attendance statistics for a specific student
    """
    try:
        student = Student.objects.select_related('classroom').get(id=student_id)
        
        # Get current week's attendance records (Sunday to Thursday)
        today = timezone.now().date()
        # Calculate start of week (Sunday)
        # weekday() returns 0=Monday, 1=Tuesday, ..., 6=Sunday
        # We need to go back to the previous Sunday
        days_since_sunday = (today.weekday() + 1) % 7  # 0=Sunday, 1=Monday, ..., 6=Saturday
        start_of_week = today - timezone.timedelta(days=days_since_sunday)
        # End of week is Thursday (4 days after Sunday)
        end_of_week = start_of_week + timezone.timedelta(days=4)
        
        # Get attendance records for this week
        weekly_attendance = Attendance.objects.filter(
            student=student,
            timestamp__date__range=[start_of_week, end_of_week]
        ).order_by('timestamp__date')
        
        # Calculate statistics
        total_days = 5  # Assuming 5 school days per week
        present_days = weekly_attendance.filter(is_present=True).count()
        # Only count actual school days that have records
        actual_school_days = weekly_attendance.count()
        absent_days = max(0, actual_school_days - present_days)
        attendance_rate = present_days / actual_school_days if actual_school_days > 0 else 0.0
        
        # Create daily data for the week (Sunday to Thursday)
        weekly_data = []
        for i in range(5):  # Sunday to Thursday
            current_date = start_of_week + timezone.timedelta(days=i)
            day_attendance = weekly_attendance.filter(timestamp__date=current_date).first()
            is_present = day_attendance.is_present if day_attendance else False
            
            weekly_data.append({
                'date': current_date.isoformat(),
                'day_name': current_date.strftime('%A'),
                'is_present': is_present,
                'classroom': day_attendance.classroom.name if day_attendance else None
            })
        
        return Response({
            'student': StudentSerializer(student).data,
            'week_range': {
                'start': start_of_week.isoformat(),
                'end': end_of_week.isoformat()
            },
            'total_days': total_days,
            'present_days': present_days,
            'absent_days': absent_days,
            'attendance_rate': round(attendance_rate, 2),
            'weekly_data': weekly_data
        }, status=status.HTTP_200_OK)
        
    except Student.DoesNotExist:
        return Response({'error': 'Student not found'}, status=status.HTTP_404_NOT_FOUND)


@api_view(['GET'])
@permission_classes([permissions.IsAuthenticated])
def teacher_students_with_absences(request):
    """
    Get students with high absence count for the authenticated teacher
    """
    try:
        # Get the teacher from the authenticated user
        teacher = Teacher.objects.get(user=request.user)
        
        # Get parameters
        absence_threshold = int(request.GET.get('absence_threshold', 3))
        from_date = request.GET.get('from_date')
        to_date = request.GET.get('to_date')
        
        if not from_date or not to_date:
            return api_error('Both from_date and to_date parameters are required', status.HTTP_400_BAD_REQUEST, code='missing_parameters', fields={'from_date': ['Required'] if not from_date else [], 'to_date': ['Required'] if not to_date else []})
        
        try:
            from_date = datetime.strptime(from_date, '%Y-%m-%d').date()
            to_date = datetime.strptime(to_date, '%Y-%m-%d').date()
        except ValueError:
            return api_error('Invalid date format. Use YYYY-MM-DD format', status.HTTP_400_BAD_REQUEST, code='invalid_date_format')
        
        # Get attendance records in date range for this teacher
        attendance_records = Attendance.objects.filter(
            teacher=teacher,
            timestamp__date__range=[from_date, to_date],
            is_present=False  # Only count absences
        ).select_related('student', 'classroom')
        
        # Count absences per student
        student_absence_count = {}
        for record in attendance_records:
            student_id = record.student.id
            if student_id not in student_absence_count:
                student_absence_count[student_id] = {
                    'student': record.student,
                    'classroom': record.classroom,
                    'absence_count': 0
                }
            student_absence_count[student_id]['absence_count'] += 1
        
        # Filter students with absences >= threshold
        students_with_high_absences = []
        for student_data in student_absence_count.values():
            if student_data['absence_count'] >= absence_threshold:
                students_with_high_absences.append({
                    'id': str(student_data['student'].id),
                    'name': student_data['student'].name,
                    'classroom_name': student_data['classroom'].name,
                    'absence_count': student_data['absence_count']
                })
        
        # Sort by absence count (highest first)
        students_with_high_absences.sort(key=lambda x: x['absence_count'], reverse=True)
        
        return Response({
            'teacher': TeacherSerializer(teacher).data,
            'date_range': {
                'from': from_date.isoformat(),
                'to': to_date.isoformat()
            },
            'absence_threshold': absence_threshold,
            'students': students_with_high_absences,
            'total_students': len(students_with_high_absences)
        }, status=status.HTTP_200_OK)
        
    except Teacher.DoesNotExist:
        return api_error('Teacher not found', status.HTTP_404_NOT_FOUND, code='teacher_not_found')
    except Exception as e:
        return api_error('An error occurred while fetching students with absences', status.HTTP_500_INTERNAL_SERVER_ERROR, code='server_error', details=str(e))


@api_view(['POST'])
@permission_classes([permissions.IsAuthenticated])
def teacher_send_absence_reports(request):
    """
    Send absence reports to parents of students with high absences
    """
    try:
        # Get the teacher from the authenticated user
        teacher = Teacher.objects.get(user=request.user)
        
        # Get request data
        student_ids = request.data.get('student_ids', [])
        absence_threshold = request.data.get('absence_threshold', 3)
        from_date = request.data.get('from_date')
        to_date = request.data.get('to_date')
        
        if not student_ids:
            return api_error('No student IDs provided', status.HTTP_400_BAD_REQUEST, code='missing_parameters', fields={'student_ids': ['Required']})
        
        # Use provided date range or fallback to current week
        if from_date and to_date:
            try:
                from_date = datetime.strptime(from_date, '%Y-%m-%d').date()
                to_date = datetime.strptime(to_date, '%Y-%m-%d').date()
            except ValueError:
                return api_error('Invalid date format. Use YYYY-MM-DD format', status.HTTP_400_BAD_REQUEST, code='invalid_date_format')
        else:
            # Fallback to current week calculation
            today = timezone.now().date()
            days_since_sunday = (today.weekday() + 1) % 7
            from_date = today - timedelta(days=days_since_sunday)
            to_date = from_date + timedelta(days=4)
        
        # Get students and their parents
        students = Student.objects.filter(id__in=student_ids)
        reports_sent = []
        
        for student in students:
            # Get parents of this student
            parents = student.parents.all()
            
            # Count absences for this student in the specified date range
            weekly_absences = Attendance.objects.filter(
                student=student,
                is_present=False,
                timestamp__date__range=[from_date, to_date]
            ).count()
            
            for parent in parents:
                # Create report data
                report_data = {
                    'student_name': student.name,
                    'classroom_name': student.classroom.name if student.classroom else 'Unknown',
                    'parent_name': parent.name,
                    'parent_email': parent.email,
                    'parent_phone': parent.phone,
                    'absent_days': weekly_absences,
                    'absence_threshold': absence_threshold,
                    'teacher_name': f"{teacher.user.first_name} {teacher.user.last_name}".strip() or teacher.user.username,
                    'warning_message': f"Dear Parent, {student.name} was absent {weekly_absences} time(s) from {from_date} to {to_date}. Please ensure regular attendance for better academic performance.",
                    'sent_at': timezone.now().isoformat()
                }
                reports_sent.append(report_data)
                
                # Create report notification for the parent
                create_report_notification(student, parent, report_data)
                
                # Log the report
                print(f"Absence Report Sent: {report_data}")
        
        return Response({
            'message': f'Reports sent to {len(reports_sent)} parents',
            'teacher': TeacherSerializer(teacher).data,
            'absence_threshold': absence_threshold,
            'date_range': {
                'from': from_date.isoformat(),
                'to': to_date.isoformat()
            },
            'reports_sent': reports_sent,
            'total_reports': len(reports_sent)
        }, status=status.HTTP_200_OK)
        
    except Teacher.DoesNotExist:
        return api_error('Teacher not found', status.HTTP_404_NOT_FOUND, code='teacher_not_found')
    except Exception as e:
        return api_error('An error occurred while sending reports', status.HTTP_500_INTERNAL_SERVER_ERROR, code='server_error', details=str(e))


@api_view(['POST'])
@permission_classes([permissions.IsAuthenticated])
def teacher_send_daily_absence_notifications(request):
    """
    Send daily absence notifications to parents (not reports)
    """
    try:
        teacher = Teacher.objects.get(user=request.user)
        data = request.data
        
        absent_student_ids = data.get('absent_student_ids', [])
        classroom_name = data.get('classroom_name', 'Unknown Class')
        date = data.get('date', timezone.now().date().isoformat())
        
        notifications_sent = []
        
        for student_id in absent_student_ids:
            try:
                student = Student.objects.get(id=student_id)
                parents = student.parents.all()
                
                for parent in parents:
                    # Create daily absence notification
                    notification = create_daily_absence_notification(student, parent, classroom_name, date)
                    if notification:
                        notifications_sent.append({
                            'student_name': student.name,
                            'parent_name': parent.name,
                            'notification_id': str(notification.id)
                        })
                        
            except Student.DoesNotExist:
                continue
        
        return Response({
            'message': f'Daily absence notifications sent successfully',
            'notifications_sent': len(notifications_sent),
            'details': notifications_sent
        }, status=status.HTTP_200_OK)
        
    except Teacher.DoesNotExist:
        return api_error('Teacher profile not found', status.HTTP_404_NOT_FOUND, code='teacher_not_found')
    except Exception as e:
        return api_error('An error occurred while sending daily absence notifications', status.HTTP_500_INTERNAL_SERVER_ERROR, code='server_error', details=str(e))


@api_view(['POST'])
@permission_classes([permissions.IsAuthenticated])
def teacher_send_report_notifications(request):
    """
    Send teacher report notifications to parents (these will show in reports screen)
    """
    try:
        teacher = Teacher.objects.get(user=request.user)
        data = request.data
        
        student_ids = data.get('student_ids', [])
        report_message = data.get('report_message', '')
        absence_threshold = data.get('absence_threshold', 3)
        
        notifications_sent = []
        
        for student_id in student_ids:
            try:
                student = Student.objects.get(id=student_id)
                parents = student.parents.all()
                
                # Count absences for this student in the current week
                today = timezone.now().date()
                days_since_sunday = (today.weekday() + 1) % 7
                start_of_week = today - timedelta(days=days_since_sunday)
                end_of_week = start_of_week + timedelta(days=4)
                
                weekly_absences = Attendance.objects.filter(
                    student=student,
                    is_present=False,
                    timestamp__date__range=[start_of_week, end_of_week]
                ).count()
                
                for parent in parents:
                    # Create teacher report notification
                    notification = create_teacher_report_notification(
                        student, parent, report_message, weekly_absences, absence_threshold
                    )
                    if notification:
                        notifications_sent.append({
                            'student_name': student.name,
                            'parent_name': parent.name,
                            'notification_id': str(notification.id)
                        })
                        
            except Student.DoesNotExist:
                continue
        
        return Response({
            'message': f'Teacher report notifications sent successfully',
            'notifications_sent': len(notifications_sent),
            'details': notifications_sent
        }, status=status.HTTP_200_OK)
        
    except Teacher.DoesNotExist:
        return api_error('Teacher profile not found', status.HTTP_404_NOT_FOUND, code='teacher_not_found')
    except Exception as e:
        return api_error('An error occurred while sending teacher report notifications', status.HTTP_500_INTERNAL_SERVER_ERROR, code='server_error', details=str(e))


# Notification Views
@api_view(['GET'])
@permission_classes([permissions.AllowAny])
def parent_notifications(request, parent_id):
    """
    Get all notifications for a parent
    """
    try:
        parent = Parent.objects.get(id=parent_id)
        notifications = Notification.objects.filter(parent=parent).order_by('-created_at')
        
        return Response({
            'notifications': NotificationSerializer(notifications, many=True).data
        }, status=status.HTTP_200_OK)
        
    except Parent.DoesNotExist:
        return api_error('Parent not found', status.HTTP_404_NOT_FOUND, code='parent_not_found')
    except Exception as e:
        return api_error('An error occurred while fetching notifications', status.HTTP_500_INTERNAL_SERVER_ERROR, code='server_error', details=str(e))


@api_view(['PATCH'])
@permission_classes([permissions.AllowAny])
def mark_notification_as_read(request, notification_id):
    """
    Mark a specific notification as read
    """
    try:
        notification = Notification.objects.get(id=notification_id)
        notification.is_read = True
        notification.save()
        
        return Response({
            'message': 'Notification marked as read',
            'notification': NotificationSerializer(notification).data
        }, status=status.HTTP_200_OK)
        
    except Notification.DoesNotExist:
        return api_error('Notification not found', status.HTTP_404_NOT_FOUND, code='notification_not_found')
    except Exception as e:
        return api_error('An error occurred while marking notification as read', status.HTTP_500_INTERNAL_SERVER_ERROR, code='server_error', details=str(e))


@api_view(['PATCH'])
@permission_classes([permissions.AllowAny])
def mark_all_notifications_as_read(request, parent_id):
    """
    Mark all notifications for a parent as read
    """
    try:
        parent = Parent.objects.get(id=parent_id)
        updated_count = Notification.objects.filter(parent=parent, is_read=False).update(is_read=True)
        
        return Response({
            'message': f'{updated_count} notifications marked as read',
            'updated_count': updated_count
        }, status=status.HTTP_200_OK)
        
    except Parent.DoesNotExist:
        return api_error('Parent not found', status.HTTP_404_NOT_FOUND, code='parent_not_found')
    except Exception as e:
        return api_error('An error occurred while marking notifications as read', status.HTTP_500_INTERNAL_SERVER_ERROR, code='server_error', details=str(e))


def create_report_notification(student, parent, report_data):
    """
    Helper function to create report notifications for the app
    """
    try:
        # Create report notification message
        report_message = f"Attendance Report: {student.name} has {report_data.get('absent_days', 0)} absences this week in {report_data.get('classroom_name', 'Unknown Class')}. {report_data.get('warning_message', '')}"
        
        notification = Notification.objects.create(
            parent=parent,
            student=student,
            title=f'Attendance Report - {student.name}',
            message=report_message,
            type='teacher_report'  # Changed from 'report' to 'teacher_report' so it shows in reports screen
        )
        print(f"Created report notification: {notification.id}")
        return notification
    except Exception as e:
        print(f"Error creating report notification: {e}")
        return None


def create_daily_absence_notification(student, parent, classroom_name, date):
    """
    Helper function to create daily absence notifications (not reports)
    """
    try:
        # Check if notification already exists for this student, parent, and date
        existing_notification = Notification.objects.filter(
            parent=parent,
            student=student,
            type='daily_absence',
            created_at__date=date
        ).first()
        
        if existing_notification:
            print(f"Daily absence notification already exists for {student.name} on {date}")
            return existing_notification
        
        notification = Notification.objects.create(
            parent=parent,
            student=student,
            title=f'Daily Absence Alert - {student.name}',
            message=f'Alert: {student.name} was absent today ({date}) in {classroom_name}. Please ensure regular attendance.',
            type='daily_absence'
        )
        print(f"Created daily absence notification: {notification.id}")
        return notification
    except Exception as e:
        print(f"Error creating daily absence notification: {e}")
        return None


def create_teacher_report_notification(student, parent, report_message, weekly_absences, absence_threshold):
    """
    Helper function to create teacher report notifications (these will show in reports screen)
    """
    try:
        notification = Notification.objects.create(
            parent=parent,
            student=student,
            title=f'Teacher Report - {student.name}',
            message=f'Teacher Report: {student.name} has {weekly_absences} absences this week (threshold: {absence_threshold}). {report_message}',
            type='teacher_report'
        )
        print(f"Created teacher report notification: {notification.id}")
        return notification
    except Exception as e:
        print(f"Error creating teacher report notification: {e}")
        return None


@api_view(['GET'])
@permission_classes([permissions.AllowAny])
def parent_detailed_reports(request, parent_id):
    """
    Get teacher reports for a parent's children
    Only shows reports that were actually sent by teachers (teacher_report notifications)
    """
    try:
        parent = Parent.objects.get(id=parent_id)
        
        # Get date range from query parameters
        from_date = request.GET.get('from_date')
        to_date = request.GET.get('to_date')
        
        if not from_date or not to_date:
            return Response({
                'error': 'Both from_date and to_date parameters are required'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        try:
            from_date = datetime.strptime(from_date, '%Y-%m-%d').date()
            to_date = datetime.strptime(to_date, '%Y-%m-%d').date()
        except ValueError:
            return Response({
                'error': 'Invalid date format. Use YYYY-MM-DD format'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        # Get teacher report notifications (including legacy 'report' type)
        teacher_report_notifications = Notification.objects.filter(
            parent=parent,
            type__in=['teacher_report', 'report'],  # Include both new and legacy report types
            created_at__date__range=[from_date, to_date]
        ).select_related('student').order_by('-created_at')
        
        absence_reports = []
        
        for notification in teacher_report_notifications:
            if notification.student:
                # Extract information from the notification message
                student_name = notification.student.name
                classroom_name = notification.student.classroom.name if notification.student.classroom else 'Unknown Class'
                
                # Parse the notification message to extract absence count and other details
                message = notification.message
                
                # Extract absence count from message (e.g., "has 2 absences")
                import re
                absence_match = re.search(r'has (\d+) absences', message)
                absent_days = int(absence_match.group(1)) if absence_match else 0
                
                # Extract teacher name from message (e.g., "Reported by: John Smith")
                teacher_match = re.search(r'Reported by: (.+)', message)
                teacher_name = teacher_match.group(1) if teacher_match else 'Unknown Teacher'
                
                # Get absence dates for this student in the date range
                absence_records = Attendance.objects.filter(
                    student=notification.student,
                    is_present=False,
                    timestamp__date__range=[from_date, to_date]
                ).select_related('classroom', 'teacher').order_by('-timestamp')
                
                absence_dates = []
                for record in absence_records:
                    # Use the same timezone logic as other parts of the system
                    local_date = get_local_date_key(record.timestamp)
                    local_time = timezone.localtime(record.timestamp)
                    absence_dates.append({
                        'date': local_date,
                        'teacher': record.teacher.name,
                        'classroom': record.classroom.name,
                        'time': local_time.time().strftime('%H:%M')
                    })
                
                report_data = {
                    'student_id': str(notification.student.id),
                    'student_name': student_name,
                    'classroom_name': classroom_name,
                    'teacher_name': teacher_name,
                    'absent_days': absent_days,
                    'warning_message': message,
                    'absence_dates': absence_dates,
                    'report_sent_at': notification.created_at.isoformat(),
                }
                absence_reports.append(report_data)
        
        # If no teacher reports found, return appropriate message
        if not absence_reports:
            return Response({
                'parent': ParentSerializer(parent).data,
                'date_range': {
                    'from_date': from_date.isoformat(),
                    'to_date': to_date.isoformat(),
                },
                'message': 'No teacher reports found for the selected period. All children are doing well!',
                'absence_reports': [],
            }, status=status.HTTP_200_OK)
        
        return Response({
            'parent': ParentSerializer(parent).data,
            'date_range': {
                'from_date': from_date.isoformat(),
                'to_date': to_date.isoformat(),
            },
            'absence_reports': absence_reports,
            'total_children_with_reports': len(absence_reports),
        }, status=status.HTTP_200_OK)
        
    except Parent.DoesNotExist:
        return api_error('Parent not found', status.HTTP_404_NOT_FOUND, code='parent_not_found')
    except Exception as e:
        return api_error('An error occurred while generating absence reports', status.HTTP_500_INTERNAL_SERVER_ERROR, code='server_error', details=str(e))