#!/usr/bin/env python3
"""
Script to update Excel files with correct student and parent data
"""

import pandas as pd
import os

def update_excel_files():
    """Update all Excel files with correct data"""
    
    print("📊 UPDATING EXCEL FILES")
    print("=" * 40)
    
    # Update students.xlsx
    print("📝 Updating students.xlsx...")
    students_df = pd.read_csv('excel_data/students.csv')
    students_df.to_excel('excel_data/students.xlsx', index=False)
    print(f"   ✅ Updated students.xlsx with {len(students_df)} students")
    
    # Update parents.xlsx
    print("📝 Updating parents.xlsx...")
    parents_df = pd.read_csv('excel_data/parents.csv')
    parents_df.to_excel('excel_data/parents.xlsx', index=False)
    print(f"   ✅ Updated parents.xlsx with {len(parents_df)} parents")
    
    # Update classes.xlsx
    print("📝 Updating classes.xlsx...")
    classes_df = pd.read_csv('excel_data/classes.csv')
    classes_df.to_excel('excel_data/classes.xlsx', index=False)
    print(f"   ✅ Updated classes.xlsx with {len(classes_df)} classes")
    
    # Create a comprehensive data.xlsx with all data
    print("📝 Creating comprehensive data.xlsx...")
    with pd.ExcelWriter('excel_data/data.xlsx') as writer:
        students_df.to_excel(writer, sheet_name='Students', index=False)
        parents_df.to_excel(writer, sheet_name='Parents', index=False)
        classes_df.to_excel(writer, sheet_name='Classes', index=False)
    
    print("   ✅ Created comprehensive data.xlsx")
    
    print("\n🎉 ALL EXCEL FILES UPDATED!")
    print("=" * 40)
    
    # Show summary
    print(f"📊 SUMMARY:")
    print(f"   Students: {len(students_df)}")
    print(f"   Parents: {len(parents_df)}")
    print(f"   Classes: {len(classes_df)}")
    
    # Show students without parents in CSV
    all_student_names = set(students_df['name'].tolist())
    all_children_names = set()
    for children_str in parents_df['children'].dropna():
        children_names = [name.strip() for name in children_str.split(';')]
        all_children_names.update(children_names)
    
    missing_students = all_student_names - all_children_names
    if missing_students:
        print(f"\n⚠️  Students in CSV but not assigned to parents ({len(missing_students)}):")
        for student in sorted(missing_students):
            print(f"   - {student}")
    else:
        print("\n✅ All students in CSV are assigned to parents!")

if __name__ == "__main__":
    update_excel_files()
