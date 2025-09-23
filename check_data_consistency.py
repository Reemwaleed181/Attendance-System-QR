#!/usr/bin/env python3
"""
Script to check for data inconsistencies in the school QR attendance system:
- Duplicate student names
- Duplicate QR codes
- Missing students in UI vs database
- Duplicate class names
- QR code uniqueness
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
import json

def check_duplicate_students():
    """Check for duplicate student names"""
    print("=== CHECKING FOR DUPLICATE STUDENT NAMES ===")
    
    students = Student.objects.all()
    student_names = [student.name for student in students]
    name_counts = Counter(student_names)
    
    duplicates = {name: count for name, count in name_counts.items() if count > 1}
    
    if duplicates:
        print(f"❌ Found {len(duplicates)} duplicate student names:")
        for name, count in duplicates.items():
            print(f"  - '{name}': {count} times")
            # Show details for each duplicate
            duplicate_students = Student.objects.filter(name=name)
            for student in duplicate_students:
                print(f"    ID: {student.id}, QR: {student.qr_code}, Class: {student.classroom.name if student.classroom else 'None'}")
    else:
        print("✅ No duplicate student names found")
    
    return len(duplicates)

def check_duplicate_qr_codes():
    """Check for duplicate QR codes"""
    print("\n=== CHECKING FOR DUPLICATE QR CODES ===")
    
    # Check student QR codes
    students = Student.objects.all()
    student_qr_codes = [student.qr_code for student in students if student.qr_code]
    student_qr_counts = Counter(student_qr_codes)
    
    # Check classroom QR codes
    classrooms = ClassRoom.objects.all()
    classroom_qr_codes = [classroom.qr_code for classroom in classrooms if classroom.qr_code]
    classroom_qr_counts = Counter(classroom_qr_codes)
    
    # Check for duplicates within students
    student_duplicates = {qr: count for qr, count in student_qr_counts.items() if count > 1}
    
    # Check for duplicates within classrooms
    classroom_duplicates = {qr: count for qr, count in classroom_qr_counts.items() if count > 1}
    
    # Check for cross-duplicates (student QR same as classroom QR)
    all_student_qrs = set(student_qr_codes)
    all_classroom_qrs = set(classroom_qr_codes)
    cross_duplicates = all_student_qrs.intersection(all_classroom_qrs)
    
    total_issues = 0
    
    if student_duplicates:
        print(f"❌ Found {len(student_duplicates)} duplicate student QR codes:")
        for qr, count in student_duplicates.items():
            print(f"  - '{qr}': {count} times")
            duplicate_students = Student.objects.filter(qr_code=qr)
            for student in duplicate_students:
                print(f"    Student: {student.name} (ID: {student.id})")
        total_issues += len(student_duplicates)
    else:
        print("✅ No duplicate student QR codes found")
    
    if classroom_duplicates:
        print(f"❌ Found {len(classroom_duplicates)} duplicate classroom QR codes:")
        for qr, count in classroom_duplicates.items():
            print(f"  - '{qr}': {count} times")
            duplicate_classrooms = ClassRoom.objects.filter(qr_code=qr)
            for classroom in duplicate_classrooms:
                print(f"    Classroom: {classroom.name} (ID: {classroom.id})")
        total_issues += len(classroom_duplicates)
    else:
        print("✅ No duplicate classroom QR codes found")
    
    if cross_duplicates:
        print(f"❌ Found {len(cross_duplicates)} QR codes shared between students and classrooms:")
        for qr in cross_duplicates:
            print(f"  - '{qr}'")
            students_with_qr = Student.objects.filter(qr_code=qr)
            classrooms_with_qr = ClassRoom.objects.filter(qr_code=qr)
            for student in students_with_qr:
                print(f"    Student: {student.name} (ID: {student.id})")
            for classroom in classrooms_with_qr:
                print(f"    Classroom: {classroom.name} (ID: {classroom.id})")
        total_issues += len(cross_duplicates)
    else:
        print("✅ No QR codes shared between students and classrooms")
    
    return total_issues

def check_duplicate_class_names():
    """Check for duplicate class names"""
    print("\n=== CHECKING FOR DUPLICATE CLASS NAMES ===")
    
    classrooms = ClassRoom.objects.all()
    class_names = [classroom.name for classroom in classrooms]
    name_counts = Counter(class_names)
    
    duplicates = {name: count for name, count in name_counts.items() if count > 1}
    
    if duplicates:
        print(f"❌ Found {len(duplicates)} duplicate class names:")
        for name, count in duplicates.items():
            print(f"  - '{name}': {count} times")
            duplicate_classrooms = ClassRoom.objects.filter(name=name)
            for classroom in duplicate_classrooms:
                print(f"    ID: {classroom.id}, QR: {classroom.qr_code}")
    else:
        print("✅ No duplicate class names found")
    
    return len(duplicates)

def check_missing_students():
    """Check for students that might be missing from UI"""
    print("\n=== CHECKING FOR MISSING STUDENTS ===")
    
    students = Student.objects.all()
    print(f"Total students in database: {students.count()}")
    
    # Check for students without QR codes
    students_without_qr = students.filter(qr_code__isnull=True) | students.filter(qr_code='')
    if students_without_qr.exists():
        print(f"❌ Found {students_without_qr.count()} students without QR codes:")
        for student in students_without_qr:
            print(f"  - {student.name} (ID: {student.id})")
    else:
        print("✅ All students have QR codes")
    
    # Check for students without classrooms
    students_without_class = students.filter(classroom__isnull=True)
    if students_without_class.exists():
        print(f"❌ Found {students_without_class.count()} students without classrooms:")
        for student in students_without_class:
            print(f"  - {student.name} (ID: {student.id})")
    else:
        print("✅ All students have classrooms assigned")
    
    # Check for students without parents
    students_without_parents = students.filter(parents__isnull=True)
    if students_without_parents.exists():
        print(f"❌ Found {students_without_parents.count()} students without parents:")
        for student in students_without_parents:
            print(f"  - {student.name} (ID: {student.id})")
    else:
        print("✅ All students have parents assigned")
    
    return students_without_qr.count() + students_without_class.count() + students_without_parents.count()

def check_qr_code_format():
    """Check QR code format and validity"""
    print("\n=== CHECKING QR CODE FORMATS ===")
    
    students = Student.objects.all()
    classrooms = ClassRoom.objects.all()
    
    invalid_student_qrs = []
    invalid_classroom_qrs = []
    
    for student in students:
        if student.qr_code and not student.qr_code.startswith('STUDENT_'):
            invalid_student_qrs.append(student)
    
    for classroom in classrooms:
        if classroom.qr_code and not classroom.qr_code.startswith('CLASS_'):
            invalid_classroom_qrs.append(classroom)
    
    if invalid_student_qrs:
        print(f"❌ Found {len(invalid_student_qrs)} students with invalid QR code format:")
        for student in invalid_student_qrs:
            print(f"  - {student.name}: '{student.qr_code}' (should start with 'STUDENT_')")
    else:
        print("✅ All student QR codes have correct format")
    
    if invalid_classroom_qrs:
        print(f"❌ Found {len(invalid_classroom_qrs)} classrooms with invalid QR code format:")
        for classroom in invalid_classroom_qrs:
            print(f"  - {classroom.name}: '{classroom.qr_code}' (should start with 'CLASS_')")
    else:
        print("✅ All classroom QR codes have correct format")
    
    return len(invalid_student_qrs) + len(invalid_classroom_qrs)

def generate_summary_report():
    """Generate a summary report"""
    print("\n=== SUMMARY REPORT ===")
    
    students = Student.objects.all()
    classrooms = ClassRoom.objects.all()
    parents = Parent.objects.all()
    teachers = Teacher.objects.all()
    attendance_records = Attendance.objects.all()
    
    print(f"📊 Database Statistics:")
    print(f"  - Students: {students.count()}")
    print(f"  - Classrooms: {classrooms.count()}")
    print(f"  - Parents: {parents.count()}")
    print(f"  - Teachers: {teachers.count()}")
    print(f"  - Attendance Records: {attendance_records.count()}")
    
    # Check for recent attendance
    from django.utils import timezone
    from datetime import timedelta
    
    today = timezone.now().date()
    week_ago = today - timedelta(days=7)
    
    recent_attendance = attendance_records.filter(timestamp__date__gte=week_ago)
    print(f"  - Recent Attendance (last 7 days): {recent_attendance.count()}")

def main():
    """Main function to run all checks"""
    print("🔍 Starting data consistency check...")
    print("=" * 60)
    
    total_issues = 0
    
    # Run all checks
    total_issues += check_duplicate_students()
    total_issues += check_duplicate_qr_codes()
    total_issues += check_duplicate_class_names()
    total_issues += check_missing_students()
    total_issues += check_qr_code_format()
    
    # Generate summary
    generate_summary_report()
    
    print("\n" + "=" * 60)
    if total_issues == 0:
        print("🎉 All checks passed! No data inconsistencies found.")
    else:
        print(f"⚠️  Found {total_issues} total issues that need attention.")
    
    return total_issues

if __name__ == "__main__":
    main()
