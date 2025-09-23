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

def check_class_1_students():
    try:
        c1 = ClassRoom.objects.get(name='Class 1')
        students = Student.objects.filter(classroom=c1)
        
        print(f"Class 1 has {students.count()} students:")
        for i, student in enumerate(students, 1):
            print(f"{i}. {student.name} (ID: {student.id})")
            
        return students
    except ClassRoom.DoesNotExist:
        print("Class 1 not found in database")
        return None

if __name__ == "__main__":
    check_class_1_students()
