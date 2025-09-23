from rest_framework import status, generics, permissions
from rest_framework.decorators import api_view, permission_classes
from rest_framework.response import Response
from rest_framework.authtoken.models import Token
from django.contrib.auth import authenticate
from django.contrib.auth.models import User
from django.utils import timezone
from datetime import datetime, date, timedelta
from .models import ClassRoom, Student, Parent, Teacher, Attendance, Notification
from .serializers import (
    ClassRoomSerializer, StudentSerializer, ParentSerializer, 
    TeacherSerializer, AttendanceSerializer, AttendanceMarkSerializer,
    ParentLoginSerializer, NotificationSerializer
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
            return Response({'error': 'Student not found'}, status=status.HTTP_404_NOT_FOUND)
        except ClassRoom.DoesNotExist:
            return Response({'error': 'Classroom not found'}, status=status.HTTP_404_NOT_FOUND)
        except Teacher.DoesNotExist:
            return Response({'error': 'Teacher profile not found'}, status=status.HTTP_404_NOT_FOUND)
    
    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


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
            return Response({'error': 'Student not found'}, status=status.HTTP_404_NOT_FOUND)
        except ClassRoom.DoesNotExist:
            return Response({'error': 'Classroom not found'}, status=status.HTTP_404_NOT_FOUND)
        except Teacher.DoesNotExist:
            return Response({'error': 'Teacher profile not found'}, status=status.HTTP_404_NOT_FOUND)
    
    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


@api_view(['POST'])
@permission_classes([permissions.AllowAny])
def teacher_login(request):
    """
    Teacher login endpoint
    """
    username = request.data.get('username')
    password = request.data.get('password')
    
    if not username or not password:
        return Response({'error': 'Username and password required'}, status=status.HTTP_400_BAD_REQUEST)
    
    user = authenticate(username=username, password=password)
    if user and hasattr(user, 'teacher'):
        token, created = Token.objects.get_or_create(user=user)
        return Response({
            'token': token.key,
            'teacher': TeacherSerializer(user.teacher).data
        }, status=status.HTTP_200_OK)
    
    return Response({'error': 'Invalid credentials'}, status=status.HTTP_401_UNAUTHORIZED)


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
    
    return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)


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
        return Response({'error': 'Parent not found'}, status=status.HTTP_404_NOT_FOUND)


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
        return Response({'error': 'Student not found'}, status=status.HTTP_404_NOT_FOUND)


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
        return Response({'error': 'Teacher not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({
            'error': 'An error occurred while fetching attendance history',
            'details': str(e)
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


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
        return Response({'error': 'Teacher not found'}, status=status.HTTP_404_NOT_FOUND)


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
        return Response({'error': 'Teacher not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({
            'error': 'An error occurred while fetching students with absences',
            'details': str(e)
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


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
        
        if not student_ids:
            return Response({
                'error': 'No student IDs provided'
            }, status=status.HTTP_400_BAD_REQUEST)
        
        # Get students and their parents
        students = Student.objects.filter(id__in=student_ids)
        reports_sent = []
        
        for student in students:
            # Get parents of this student
            parents = student.parents.all()
            
            # Count absences for this student in the current week (Sunday to Thursday)
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
                    'warning_message': f"Dear Parent, {student.name} was absent {weekly_absences} time(s) this week. Please ensure regular attendance for better academic performance.",
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
            'reports_sent': reports_sent,
            'total_reports': len(reports_sent)
        }, status=status.HTTP_200_OK)
        
    except Teacher.DoesNotExist:
        return Response({'error': 'Teacher not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({
            'error': 'An error occurred while sending reports',
            'details': str(e)
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


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
        return Response({'error': 'Teacher profile not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({
            'error': 'An error occurred while sending daily absence notifications',
            'details': str(e)
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


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
        return Response({'error': 'Teacher profile not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({
            'error': 'An error occurred while sending teacher report notifications',
            'details': str(e)
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


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
        return Response({'error': 'Parent not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({
            'error': 'An error occurred while fetching notifications',
            'details': str(e)
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


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
        return Response({'error': 'Notification not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({
            'error': 'An error occurred while marking notification as read',
            'details': str(e)
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


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
        return Response({'error': 'Parent not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({
            'error': 'An error occurred while marking notifications as read',
            'details': str(e)
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)


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
        return Response({'error': 'Parent not found'}, status=status.HTTP_404_NOT_FOUND)
    except Exception as e:
        return Response({
            'error': 'An error occurred while generating absence reports',
            'details': str(e)
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)