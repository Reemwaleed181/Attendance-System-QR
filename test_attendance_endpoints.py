#!/usr/bin/env python3
"""
Test script to verify attendance report and summary endpoints are working correctly.
Run this from the backend directory: python test_attendance_endpoints.py
"""

import os
import sys
import django
from datetime import datetime, date, timedelta

# Add the backend directory to Python path
backend_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'backend')
sys.path.append(backend_dir)

# Setup Django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'school_attendance.settings')
django.setup()

from attendance.models import ClassRoom, Student, Parent, Teacher, Attendance, User
from django.contrib.auth.models import User as AuthUser
from django.utils import timezone

def create_test_data():
    """Create test data for attendance reports"""
    print("Creating test data...")
    
    # Create test user and teacher
    user, created = AuthUser.objects.get_or_create(
        username='test_teacher',
        defaults={'email': 'teacher@test.com'}
    )
    if created:
        user.set_password('testpass123')
        user.save()
    
    teacher, created = Teacher.objects.get_or_create(
        user=user,
        defaults={'name': 'Test Teacher'}
    )
    
    # Create test classroom
    classroom, created = ClassRoom.objects.get_or_create(
        name='Test Class 1',
        defaults={'qr_code': 'CLASS_001'}
    )
    
    # Create test students
    students = []
    for i in range(5):
        student, created = Student.objects.get_or_create(
            name=f'Test Student {i+1}',
            defaults={
                'qr_code': f'STUDENT_{i+1:03d}',
                'classroom': classroom
            }
        )
        students.append(student)
    
    # Create test parent
    parent, created = Parent.objects.get_or_create(
        name='Test Parent',
        defaults={'email': 'parent@test.com', 'phone': '1234567890'}
    )
    parent.children.set(students[:3])  # First 3 students belong to this parent
    
    # Create attendance records for the past week
    today = timezone.now().date()
    for i in range(7):  # Past 7 days
        record_date = today - timedelta(days=i)
        
        # Skip weekends
        if record_date.weekday() >= 5:
            continue
            
        for j, student in enumerate(students):
            # Create attendance record (some present, some absent)
            is_present = (i + j) % 3 != 0  # Vary attendance pattern
            
            Attendance.objects.get_or_create(
                student=student,
                classroom=classroom,
                teacher=teacher,
                timestamp=timezone.make_aware(datetime.combine(record_date, datetime.min.time())),
                defaults={'is_present': is_present}
            )
    
    print(f"✅ Created test data:")
    print(f"   - Teacher: {teacher.name}")
    print(f"   - Classroom: {classroom.name}")
    print(f"   - Students: {len(students)}")
    print(f"   - Parent: {parent.name}")
    print(f"   - Attendance records: {Attendance.objects.count()}")
    
    return {
        'teacher': teacher,
        'classroom': classroom,
        'students': students,
        'parent': parent
    }

def test_endpoints():
    """Test the attendance endpoints"""
    print("\n" + "="*50)
    print("TESTING ATTENDANCE ENDPOINTS")
    print("="*50)
    
    # Test data
    test_data = create_test_data()
    teacher = test_data['teacher']
    parent = test_data['parent']
    students = test_data['students']
    
    print(f"\n1. Testing Teacher Reports Endpoint...")
    print(f"   URL: /api/teacher/reports/?from_date=2024-01-01&to_date=2024-12-31")
    print(f"   Teacher: {teacher.name}")
    
    # Test teacher reports
    from attendance.views import teacher_reports
    from django.test import RequestFactory
    from django.contrib.auth import get_user_model
    
    factory = RequestFactory()
    # Use current date range for testing
    today = timezone.now().date()
    from_date = (today - timedelta(days=7)).strftime('%Y-%m-%d')
    to_date = today.strftime('%Y-%m-%d')
    request = factory.get(f'/api/teacher/reports/?from_date={from_date}&to_date={to_date}')
    request.user = teacher.user
    
    try:
        response = teacher_reports(request)
        print(f"   Status: {response.status_code}")
        if response.status_code == 200:
            data = response.data
            stats = data.get('statistics', {})
            print(f"   ✅ Total Records: {stats.get('total_attendance', 0)}")
            print(f"   ✅ Present: {stats.get('present_count', 0)}")
            print(f"   ✅ Absent: {stats.get('absent_count', 0)}")
            print(f"   ✅ Attendance Rate: {stats.get('attendance_rate', 0)}%")
        else:
            print(f"   ❌ Error: {response.data}")
    except Exception as e:
        print(f"   ❌ Exception: {e}")
    
    print(f"\n2. Testing Teacher Attendance History Endpoint...")
    print(f"   URL: /api/teacher/attendance/history/")
    
    try:
        from attendance.views import teacher_attendance_history
        request = factory.get('/api/teacher/attendance/history/')
        request.user = teacher.user
        
        response = teacher_attendance_history(request)
        print(f"   Status: {response.status_code}")
        if response.status_code == 200:
            data = response.data
            print(f"   ✅ Total Records: {data.get('total_records', 0)}")
            print(f"   ✅ Days with Records: {len(data.get('attendance_by_date', {}))}")
        else:
            print(f"   ❌ Error: {response.data}")
    except Exception as e:
        print(f"   ❌ Exception: {e}")
    
    print(f"\n3. Testing Student Weekly Stats Endpoint...")
    print(f"   URL: /api/student/{students[0].id}/weekly-stats/")
    
    try:
        from attendance.views import student_weekly_stats
        request = factory.get(f'/api/student/{students[0].id}/weekly-stats/')
        
        response = student_weekly_stats(request, str(students[0].id))
        print(f"   Status: {response.status_code}")
        if response.status_code == 200:
            data = response.data
            print(f"   ✅ Student: {data.get('student', {}).get('name', 'Unknown')}")
            print(f"   ✅ Present Days: {data.get('present_days', 0)}")
            print(f"   ✅ Absent Days: {data.get('absent_days', 0)}")
            print(f"   ✅ Attendance Rate: {data.get('attendance_rate', 0)}%")
            print(f"   ✅ Weekly Data Points: {len(data.get('weekly_data', []))}")
        else:
            print(f"   ❌ Error: {response.data}")
    except Exception as e:
        print(f"   ❌ Exception: {e}")
    
    print(f"\n4. Testing Parent Children Endpoint...")
    print(f"   URL: /api/parent/{parent.id}/children/")
    
    try:
        from attendance.views import parent_children_attendance
        request = factory.get(f'/api/parent/{parent.id}/children/')
        
        response = parent_children_attendance(request, str(parent.id))
        print(f"   Status: {response.status_code}")
        if response.status_code == 200:
            data = response.data
            children = data.get('children', [])
            print(f"   ✅ Parent: {data.get('parent', {}).get('name', 'Unknown')}")
            print(f"   ✅ Children: {len(children)}")
            for child in children:
                student_data = child.get('student', {})
                print(f"      - {student_data.get('name', 'Unknown')}: Present Today: {child.get('is_present_today', False)}")
        else:
            print(f"   ❌ Error: {response.data}")
    except Exception as e:
        print(f"   ❌ Exception: {e}")
    
    print(f"\n" + "="*50)
    print("TEST COMPLETED")
    print("="*50)

if __name__ == '__main__':
    test_endpoints()
