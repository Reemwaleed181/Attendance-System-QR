#!/usr/bin/env python
import os
import sys
import django

# Add the backend directory to the Python path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

# Set up Django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'school_qr.settings')
django.setup()

from attendance.models import Student, ClassRoom

def main():
    print("=== Database Verification ===")
    
    # Check all classrooms
    print("\nAll Classrooms:")
    for classroom in ClassRoom.objects.all():
        print(f"- {classroom.name} (ID: {classroom.id})")
    
    # Check Class 1 specifically
    print("\nClass 1 Students:")
    try:
        c1 = ClassRoom.objects.get(name='Class 1')
        students = Student.objects.filter(classroom=c1)
        print(f"Found {students.count()} students in Class 1:")
        for student in students:
            print(f"  - {student.name} (ID: {student.id})")
    except ClassRoom.DoesNotExist:
        print("Class 1 not found!")
    
    # Check all students
    print(f"\nAll Students ({Student.objects.count()} total):")
    for student in Student.objects.all():
        print(f"  - {student.name} in {student.classroom.name}")

if __name__ == "__main__":
    main()
