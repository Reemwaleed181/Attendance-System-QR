#!/usr/bin/env python3
"""
Script to update Flutter app files with correct student names
"""

import os
import re

def update_flutter_files():
    """Update Flutter files with correct student names"""
    
    print("🔧 UPDATING FLUTTER APP WITH CORRECT NAMES")
    print("=" * 50)
    
    # Define the correct name mappings based on parents.csv
    name_mappings = {
        # From parents.csv children names to what should be in the app
        'Ahmed Ali': 'Ahmed Ali',
        'Aliaa Ali': 'Aliaa Ali', 
        'Reem Omaran': 'Reem Omaran',
        'Amina Omaran': 'Amina Omaran',
        'ALi Mohammed': 'ALi Mohammed',
        'Aisha Mohammed': 'Aisha Mohammed',
        'Khadeja Khalil': 'Khadeja Khalil',
        'Hala Khalil': 'Hala Khalil',
        'Omran Omar': 'Omran Omar',
        'Layla Omar': 'Layla Omar',
        'Zainab Omar': 'Zainab Omar',
        'Nada Omar': 'Nada Omar',
        'Yaser Youssef': 'Yaser Youssef',
        'Tariq Youssef': 'Tariq Youssef',
        'Nouran Adam': 'Nouran Adam',
        'Khalid Adam': 'Khalid Adam',
        'Aser Khalid': 'Aser Khalid',
        'Mahmoud Khalid': 'Mahmoud Khalid',
        'MALk Ibrahim': 'MALk Ibrahim',
        'Sara Ibrahim': 'Sara Ibrahim'
    }
    
    # Files to update (add more as needed)
    flutter_files = [
        'lib/screens/teacher_attendance_history_screen.dart',
        'lib/screens/teacher_classes_screen.dart',
        'lib/screens/teacher_home_screen.dart',
        'lib/screens/parent_home_screen.dart',
        'lib/screens/parent_weekly_stats_screen.dart',
        'lib/screens/qr_scanner_screen.dart',
        'lib/screens/class_attendance_screen.dart'
    ]
    
    updated_files = []
    
    for file_path in flutter_files:
        if os.path.exists(file_path):
            print(f"📝 Checking {file_path}...")
            
            try:
                with open(file_path, 'r', encoding='utf-8') as file:
                    content = file.read()
                
                original_content = content
                
                # Update any hardcoded student names
                for old_name, new_name in name_mappings.items():
                    if old_name != new_name:  # Only update if different
                        # Use word boundaries to avoid partial matches
                        pattern = r'\b' + re.escape(old_name) + r'\b'
                        content = re.sub(pattern, new_name, content)
                
                # Write back if changed
                if content != original_content:
                    with open(file_path, 'w', encoding='utf-8') as file:
                        file.write(content)
                    updated_files.append(file_path)
                    print(f"   ✅ Updated {file_path}")
                else:
                    print(f"   ℹ️  No changes needed in {file_path}")
                    
            except Exception as e:
                print(f"   ❌ Error updating {file_path}: {e}")
        else:
            print(f"   ⚠️  File not found: {file_path}")
    
    print(f"\n📊 SUMMARY:")
    print(f"   Files updated: {len(updated_files)}")
    
    if updated_files:
        print("\n✅ Updated files:")
        for file_path in updated_files:
            print(f"   - {file_path}")
    else:
        print("\nℹ️  No files needed updating")

def create_name_verification_script():
    """Create a script to verify all names are consistent"""
    
    script_content = '''#!/usr/bin/env python3
"""
Script to verify all student names are consistent across the app
"""

import os
import sys
import django

# Add the backend directory to Python path
sys.path.append(os.path.join(os.path.dirname(__file__), 'backend'))

# Set up Django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'school_attendance.settings')
django.setup()

from attendance.models import Student, Parent

def verify_names():
    """Verify all student names are consistent"""
    
    print("🔍 VERIFYING STUDENT NAMES CONSISTENCY")
    print("=" * 50)
    
    # Get all students
    students = Student.objects.all().order_by('name')
    
    print(f"📋 Students in database ({students.count()}):")
    for i, student in enumerate(students, 1):
        parent_count = student.parents.count()
        classroom_name = student.classroom.name if student.classroom else 'No Class'
        print(f"{i:2d}. {student.name} | Class: {classroom_name} | Parents: {parent_count}")
    
    # Check for students without parents
    students_without_parents = students.filter(parents__isnull=True)
    if students_without_parents.exists():
        print(f"\\n⚠️  Students without parents ({students_without_parents.count()}):")
        for student in students_without_parents:
            print(f"   - {student.name}")
    else:
        print("\\n✅ All students have parents!")
    
    # Show parent-child relationships
    print(f"\\n👨‍👩‍👧‍👦 Parent-Child Relationships:")
    parents = Parent.objects.all().order_by('name')
    for parent in parents:
        children = parent.children.all()
        if children.exists():
            children_names = [child.name for child in children]
            print(f"   {parent.name}: {', '.join(children_names)}")

if __name__ == "__main__":
    verify_names()
'''
    
    with open('verify_names.py', 'w', encoding='utf-8') as file:
        file.write(script_content)
    
    print("✅ Created verify_names.py script")

if __name__ == "__main__":
    update_flutter_files()
    create_name_verification_script()
    print("\\n🎉 Flutter update completed!")
