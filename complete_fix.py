#!/usr/bin/env python3
"""
Complete fix script for student names and parent relationships
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

def main():
    """Main function to fix all issues"""
    
    print("🔧 COMPLETE FIX FOR STUDENT NAMES AND PARENT RELATIONSHIPS")
    print("=" * 70)
    
    # Step 1: Read parents.csv
    print("\n📋 STEP 1: Reading parents.csv...")
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
    
    print(f"   Found {len(parents_data)} parents in CSV")
    
    # Step 2: Get all students from database
    print("\n📋 STEP 2: Getting students from database...")
    students = Student.objects.all()
    print(f"   Found {students.count()} students in database")
    
    # Step 3: Create parent-student relationships
    print("\n🔗 STEP 3: Creating parent-student relationships...")
    
    student_map = {student.name: student for student in students}
    name_changes = []
    parent_assignments = []
    
    for parent_data in parents_data:
        parent_name = parent_data['name']
        parent_email = parent_data['email']
        parent_phone = parent_data['phone']
        children_names = parent_data['children']
        
        print(f"\n   👨‍👩‍👧‍👦 Processing parent: {parent_name}")
        
        # Find or create parent
        parent, created = Parent.objects.get_or_create(
            email=parent_email,
            defaults={
                'name': parent_name,
                'phone': parent_phone
            }
        )
        
        if created:
            print(f"      ✅ Created new parent")
        else:
            print(f"      ℹ️  Found existing parent")
        
        # Process each child
        for child_name in children_names:
            if child_name in student_map:
                student = student_map[child_name]
                print(f"      ✅ Found child: {child_name}")
            else:
                # Try to find similar names
                similar_students = []
                for db_name, student in student_map.items():
                    if (child_name.lower() in db_name.lower() or 
                        db_name.lower() in child_name.lower() or
                        child_name.split()[0] == db_name.split()[0]):
                        similar_students.append((db_name, student))
                
                if similar_students:
                    db_name, student = similar_students[0]
                    print(f"      🔄 Found similar: {db_name} -> {child_name}")
                    
                    # Update student name
                    old_name = student.name
                    student.name = child_name
                    student.save()
                    name_changes.append((old_name, child_name))
                    print(f"      ✅ Updated name: {old_name} -> {child_name}")
                else:
                    print(f"      ❌ Child not found: {child_name}")
                    continue
            
            # Assign parent to child
            if not student.parents.filter(id=parent.id).exists():
                student.parents.add(parent)
                parent_assignments.append((student.name, parent.name))
                print(f"      ✅ Assigned parent")
            else:
                print(f"      ℹ️  Parent already assigned")
    
    # Step 4: Summary
    print("\n📊 STEP 4: Summary of changes...")
    print(f"   Name changes: {len(name_changes)}")
    print(f"   Parent assignments: {len(parent_assignments)}")
    
    if name_changes:
        print("\n   🔄 Name changes:")
        for old_name, new_name in name_changes:
            print(f"      {old_name} -> {new_name}")
    
    # Step 5: Final verification
    print("\n🔍 STEP 5: Final verification...")
    students_without_parents = Student.objects.filter(parents__isnull=True)
    print(f"   Students without parents: {students_without_parents.count()}")
    
    if students_without_parents.exists():
        print("   ⚠️  Students still without parents:")
        for student in students_without_parents:
            print(f"      - {student.name}")
    else:
        print("   ✅ All students now have parents!")
    
    # Step 6: Show final student list
    print("\n📋 STEP 6: Final student list...")
    students = Student.objects.all().order_by('name')
    for i, student in enumerate(students, 1):
        parent_count = student.parents.count()
        classroom_name = student.classroom.name if student.classroom else 'No Class'
        print(f"{i:2d}. {student.name} | Class: {classroom_name} | Parents: {parent_count}")
    
    print("\n🎉 COMPLETE FIX FINISHED!")
    print("=" * 70)

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"❌ Error: {e}")
        import traceback
        traceback.print_exc()
