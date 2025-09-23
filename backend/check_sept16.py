#!/usr/bin/env python
import os
import sys
import django
from datetime import datetime, date

# Add the backend directory to the Python path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

# Set up Django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'school_attendance.settings')
django.setup()

from attendance.models import Attendance, Student, ClassRoom, Teacher

def main():
    print("=== September 16th Attendance Check ===")
    
    # Check for September 16th records
    sept16 = date(2025, 9, 16)
    sept16_records = Attendance.objects.filter(timestamp__date=sept16)
    
    print(f"Records for September 16th, 2025: {sept16_records.count()}")
    
    if sept16_records.count() > 0:
        print("\nSeptember 16th records:")
        for attendance in sept16_records:
            print(f"  - {attendance.student.name} in {attendance.classroom.name} on {attendance.timestamp} - Present: {attendance.is_present}")
    else:
        print("No records found for September 16th, 2025")
    
    # Check all dates with records
    print("\nAll dates with attendance records:")
    all_records = Attendance.objects.all().order_by('timestamp')
    current_date = None
    count = 0
    for record in all_records:
        record_date = record.timestamp.date()
        if current_date != record_date:
            if current_date is not None:
                print(f"  - {current_date}: {count} records")
            current_date = record_date
            count = 1
        else:
            count += 1
    if current_date is not None:
        print(f"  - {current_date}: {count} records")

if __name__ == "__main__":
    main()
