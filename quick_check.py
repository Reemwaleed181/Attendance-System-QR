#!/usr/bin/env python3
"""
Quick data consistency check for school QR attendance system
Run this from the project root directory
"""

import os
import sys
import django

# Add the backend directory to Python path
sys.path.append(os.path.join(os.path.dirname(__file__), 'backend'))

# Set up Django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'school_attendance.settings')
django.setup()

from attendance.models import ClassRoom, Student, Parent, Teacher, Attendance
from collections import Counter

def main():
    print("🔍 QUICK DATA CONSISTENCY CHECK")
    print("=" * 50)
    
    # Get all data
    students = Student.objects.all()
    classrooms = ClassRoom.objects.all()
    parents = Parent.objects.all()
    teachers = Teacher.objects.all()
    attendance_records = Attendance.objects.all()
    
    print(f"\n📊 DATABASE STATISTICS:")
    print(f"  Students: {students.count()}")
    print(f"  Classrooms: {classrooms.count()}")
    print(f"  Parents: {parents.count()}")
    print(f"  Teachers: {teachers.count()}")
    print(f"  Attendance Records: {attendance_records.count()}")
    
    # Check duplicate student names
    print(f"\n🔍 CHECKING DUPLICATE STUDENT NAMES:")
    student_names = [s.name for s in students]
    name_counts = Counter(student_names)
    duplicates = {name: count for name, count in name_counts.items() if count > 1}
    
    if duplicates:
        print(f"❌ Found {len(duplicates)} duplicate names:")
        for name, count in duplicates.items():
            print(f"  - '{name}': {count} times")
    else:
        print("✅ No duplicate student names")
    
    # Check duplicate QR codes
    print(f"\n🔍 CHECKING DUPLICATE QR CODES:")
    student_qrs = [s.qr_code for s in students if s.qr_code]
    classroom_qrs = [c.qr_code for c in classrooms if c.qr_code]
    
    student_qr_duplicates = {qr: count for qr, count in Counter(student_qrs).items() if count > 1}
    classroom_qr_duplicates = {qr: count for qr, count in Counter(classroom_qrs).items() if count > 1}
    cross_duplicates = set(student_qrs).intersection(set(classroom_qrs))
    
    total_qr_issues = len(student_qr_duplicates) + len(classroom_qr_duplicates) + len(cross_duplicates)
    
    if student_qr_duplicates:
        print(f"❌ Duplicate student QR codes: {len(student_qr_duplicates)}")
        for qr, count in student_qr_duplicates.items():
            print(f"  - '{qr}': {count} times")
    
    if classroom_qr_duplicates:
        print(f"❌ Duplicate classroom QR codes: {len(classroom_qr_duplicates)}")
        for qr, count in classroom_qr_duplicates.items():
            print(f"  - '{qr}': {count} times")
    
    if cross_duplicates:
        print(f"❌ QR codes shared between students and classrooms: {len(cross_duplicates)}")
        for qr in cross_duplicates:
            print(f"  - '{qr}'")
    
    if total_qr_issues == 0:
        print("✅ No duplicate QR codes")
    
    # Check missing data
    print(f"\n🔍 CHECKING MISSING DATA:")
    students_without_qr = students.filter(qr_code__isnull=True) | students.filter(qr_code='')
    students_without_class = students.filter(classroom__isnull=True)
    students_without_parents = students.filter(parents__isnull=True)
    
    missing_issues = 0
    if students_without_qr.exists():
        print(f"❌ Students without QR codes: {students_without_qr.count()}")
        missing_issues += students_without_qr.count()
    
    if students_without_class.exists():
        print(f"❌ Students without classrooms: {students_without_class.count()}")
        missing_issues += students_without_class.count()
    
    if students_without_parents.exists():
        print(f"❌ Students without parents: {students_without_parents.count()}")
        missing_issues += students_without_parents.count()
    
    if missing_issues == 0:
        print("✅ No missing data issues")
    
    # List all students
    print(f"\n📋 ALL STUDENTS:")
    for i, student in enumerate(students.order_by('name'), 1):
        classroom_name = student.classroom.name if student.classroom else 'No Class'
        parent_count = student.parents.count()
        print(f"{i:2d}. {student.name} | QR: {student.qr_code} | Class: {classroom_name} | Parents: {parent_count}")
    
    # List all classrooms
    print(f"\n🏫 ALL CLASSROOMS:")
    for i, classroom in enumerate(classrooms.order_by('name'), 1):
        student_count = classroom.student_set.count()
        print(f"{i:2d}. {classroom.name} | QR: {classroom.qr_code} | Students: {student_count}")
    
    print(f"\n" + "=" * 50)
    total_issues = len(duplicates) + total_qr_issues + missing_issues
    if total_issues == 0:
        print("🎉 All checks passed! No issues found.")
    else:
        print(f"⚠️  Found {total_issues} total issues that need attention.")

if __name__ == "__main__":
    main()
