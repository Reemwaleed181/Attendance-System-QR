#!/usr/bin/env python
import os
import sys
import django

# Add the backend directory to the Python path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

# Set up Django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'school_attendance.settings')
django.setup()

from attendance.models import Attendance, Student, ClassRoom, Teacher

def main():
    print("=== Attendance Database Check ===")
    
    # Check total attendance records
    total_records = Attendance.objects.count()
    print(f"Total attendance records: {total_records}")
    
    if total_records > 0:
        print("\nRecent attendance records:")
        for attendance in Attendance.objects.all()[:10]:
            print(f"  - {attendance.student.name} in {attendance.classroom.name} on {attendance.timestamp} - Present: {attendance.is_present}")
    else:
        print("No attendance records found in database!")
    
    # Check students and classrooms
    print(f"\nTotal students: {Student.objects.count()}")
    print(f"Total classrooms: {ClassRoom.objects.count()}")
    print(f"Total teachers: {Teacher.objects.count()}")
    
    # Check Class 1 specifically
    try:
        class1 = ClassRoom.objects.get(name='Class 1')
        class1_students = Student.objects.filter(classroom=class1)
        print(f"\nClass 1 students: {class1_students.count()}")
        for student in class1_students:
            print(f"  - {student.name} (QR: {student.qr_code})")
    except ClassRoom.DoesNotExist:
        print("\nClass 1 not found!")

if __name__ == "__main__":
    main()
