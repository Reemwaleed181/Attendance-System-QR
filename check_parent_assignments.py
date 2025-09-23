#!/usr/bin/env python3
"""
Script to check if all students are assigned to parents
"""

import csv

def check_parent_assignments():
    """Check if all students are assigned to parents"""
    
    print("🔍 CHECKING PARENT-STUDENT ASSIGNMENTS")
    print("=" * 50)
    
    # Read students from CSV
    students = []
    with open('excel_data/students.csv', 'r', encoding='utf-8') as file:
        reader = csv.DictReader(file)
        for row in reader:
            if row['name'].strip():  # Skip empty names
                students.append(row['name'].strip())
    
    print(f"📋 Students in students.csv: {len(students)}")
    
    # Read parents and their children from CSV
    all_children = []
    parents_data = []
    
    with open('excel_data/parents.csv', 'r', encoding='utf-8') as file:
        reader = csv.DictReader(file)
        for row in reader:
            if row['name'].strip():  # Skip empty rows
                parent_name = row['name'].strip()
                children_str = row['children'].strip()
                if children_str:
                    children = [name.strip() for name in children_str.split(';') if name.strip()]
                    all_children.extend(children)
                    parents_data.append({
                        'parent': parent_name,
                        'children': children
                    })
                    print(f"👨‍👩‍👧‍👦 {parent_name}: {', '.join(children)}")
    
    print(f"\n📊 SUMMARY:")
    print(f"   Total students in students.csv: {len(students)}")
    print(f"   Total children assigned to parents: {len(all_children)}")
    print(f"   Total parents: {len(parents_data)}")
    
    # Check for students not assigned to parents
    students_set = set(students)
    children_set = set(all_children)
    
    missing_from_parents = students_set - children_set
    extra_in_parents = children_set - students_set
    
    if missing_from_parents:
        print(f"\n❌ STUDENTS NOT ASSIGNED TO PARENTS ({len(missing_from_parents)}):")
        for student in sorted(missing_from_parents):
            print(f"   - {student}")
    else:
        print(f"\n✅ ALL STUDENTS ARE ASSIGNED TO PARENTS!")
    
    if extra_in_parents:
        print(f"\n⚠️  CHILDREN IN PARENTS.CSV BUT NOT IN STUDENTS.CSV ({len(extra_in_parents)}):")
        for child in sorted(extra_in_parents):
            print(f"   - {child}")
    
    # Check for duplicates in parent assignments
    from collections import Counter
    children_counts = Counter(all_children)
    duplicates = {child: count for child, count in children_counts.items() if count > 1}
    
    if duplicates:
        print(f"\n⚠️  DUPLICATE CHILDREN IN PARENT ASSIGNMENTS:")
        for child, count in duplicates.items():
            print(f"   - {child}: assigned to {count} parents")
    else:
        print(f"\n✅ NO DUPLICATE CHILDREN IN PARENT ASSIGNMENTS")
    
    return len(missing_from_parents) == 0

if __name__ == "__main__":
    check_parent_assignments()
