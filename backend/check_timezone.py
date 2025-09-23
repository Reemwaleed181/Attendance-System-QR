#!/usr/bin/env python
import os
import sys
import django
from datetime import datetime
from django.utils import timezone

# Add the backend directory to the Python path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

# Set up Django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'school_attendance.settings')
django.setup()

def main():
    print("=== Timezone and Time Check ===")
    
    # Current system time
    now_system = datetime.now()
    print(f"System time: {now_system}")
    
    # Django timezone time
    now_django = timezone.now()
    print(f"Django timezone time: {now_django}")
    
    # Today's date in Django timezone
    today_django = timezone.now().date()
    print(f"Today's date (Django): {today_django}")
    
    # Check if there are any records for today
    from attendance.models import Attendance
    today_records = Attendance.objects.filter(timestamp__date=today_django)
    print(f"Records for today ({today_django}): {today_records.count()}")
    
    if today_records.count() > 0:
        print("Today's records:")
        for record in today_records:
            print(f"  - {record.student.name} in {record.classroom.name} at {record.timestamp}")

if __name__ == "__main__":
    main()
