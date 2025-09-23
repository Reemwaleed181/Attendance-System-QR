#!/usr/bin/env python3
"""
Script to fix student names and parent relationships based on parents.csv
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
import csv

def fix_student_names_and_parents():
    """Fix student names and create parent relationships based on parents.csv"""
    
    print("🔧 FIXING STUDENT NAMES AND PARENT RELATIONSHIPS")
    print("=" * 60)
    
    # Read parents.csv
    parents_data = []
    with open('excel_data/parents.csv', 'r', encoding='utf-8') as file:
        reader = csv.DictReader(file)
        for row in reader:
            if row['name']:  # Skip empty rows
                children_names = [name.strip() for name in row['children'].split(';') if name.strip()]
                parents_data.append({
                    'name': row['name'],
                    'email': row['email'],
                    'phone': row['phone'],
                    'children': children_names
                })
    
    print(f"📋 Found {len(parents_data)} parents in CSV file")
    
    # Get all students from database
    students = Student.objects.all()
    print(f"📋 Found {students.count()} students in database")
    
    # Create a mapping of current student names to Student objects
    student_map = {student.name: student for student in students}
    
    # Track changes
    name_changes = []
    parent_assignments = []
    
    print("\n🔍 ANALYZING MISMATCHES:")
    
    # Process each parent and their children
    for parent_data in parents_data:
        parent_name = parent_data['name']
        parent_email = parent_data['email']
        parent_phone = parent_data['phone']
        children_names = parent_data['children']
        
        print(f"\n👨‍👩‍👧‍👦 Parent: {parent_name}")
        print(f"   Email: {parent_email}")
        print(f"   Phone: {parent_phone}")
        print(f"   Children: {', '.join(children_names)}")
        
        # Find or create parent
        parent, created = Parent.objects.get_or_create(
            email=parent_email,
            defaults={
                'name': parent_name,
                'phone': parent_phone
            }
        )
        
        if created:
            print(f"   ✅ Created new parent: {parent_name}")
        else:
            print(f"   ℹ️  Found existing parent: {parent_name}")
        
        # Process each child
        for child_name in children_names:
            # Check if child exists with exact name
            if child_name in student_map:
                student = student_map[child_name]
                print(f"   ✅ Found child: {child_name}")
            else:
                # Try to find similar names (fuzzy matching)
                similar_students = []
                for db_name, student in student_map.items():
                    if (child_name.lower() in db_name.lower() or 
                        db_name.lower() in child_name.lower() or
                        child_name.split()[0] == db_name.split()[0]):
                        similar_students.append((db_name, student))
                
                if similar_students:
                    # Use the first similar match
                    db_name, student = similar_students[0]
                    print(f"   🔄 Found similar child: {db_name} -> {child_name}")
                    
                    # Update student name
                    old_name = student.name
                    student.name = child_name
                    student.save()
                    name_changes.append((old_name, child_name))
                    print(f"   ✅ Updated name: {old_name} -> {child_name}")
                else:
                    print(f"   ❌ Child not found: {child_name}")
                    continue
            
            # Assign parent to child
            if not student.parents.filter(id=parent.id).exists():
                student.parents.add(parent)
                parent_assignments.append((student.name, parent.name))
                print(f"   ✅ Assigned parent {parent.name} to child {student.name}")
            else:
                print(f"   ℹ️  Parent already assigned to {student.name}")
    
    print("\n" + "=" * 60)
    print("📊 SUMMARY OF CHANGES:")
    print(f"   Name changes: {len(name_changes)}")
    print(f"   Parent assignments: {len(parent_assignments)}")
    
    if name_changes:
        print("\n🔄 NAME CHANGES:")
        for old_name, new_name in name_changes:
            print(f"   {old_name} -> {new_name}")
    
    if parent_assignments:
        print("\n👨‍👩‍👧‍👦 PARENT ASSIGNMENTS:")
        for student_name, parent_name in parent_assignments:
            print(f"   {student_name} -> {parent_name}")
    
    # Check for students still without parents
    students_without_parents = Student.objects.filter(parents__isnull=True)
    if students_without_parents.exists():
        print(f"\n⚠️  STUDENTS STILL WITHOUT PARENTS ({students_without_parents.count()}):")
        for student in students_without_parents:
            print(f"   - {student.name}")
    else:
        print("\n✅ ALL STUDENTS NOW HAVE PARENTS!")
    
    print("\n🎉 FIX COMPLETED!")

def verify_fix():
    """Verify that the fix worked correctly"""
    print("\n🔍 VERIFYING FIX:")
    print("=" * 40)
    
    students = Student.objects.all()
    print(f"Total students: {students.count()}")
    
    students_with_parents = students.filter(parents__isnull=False)
    print(f"Students with parents: {students_with_parents.count()}")
    
    students_without_parents = students.filter(parents__isnull=True)
    print(f"Students without parents: {students_without_parents.count()}")
    
    if students_without_parents.exists():
        print("\nStudents still without parents:")
        for student in students_without_parents:
            print(f"  - {student.name}")
    
    # Show parent-child relationships
    print(f"\n👨‍👩‍👧‍👦 PARENT-CHILD RELATIONSHIPS:")
    parents = Parent.objects.all()
    for parent in parents:
        children = parent.children.all()
        if children.exists():
            children_names = [child.name for child in children]
            print(f"  {parent.name}: {', '.join(children_names)}")

if __name__ == "__main__":
    try:
        fix_student_names_and_parents()
        verify_fix()
    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
