#!/usr/bin/env python3
"""
Test script to verify timezone fix for attendance records
"""

import os
import sys
import django
from datetime import datetime, timezone as tz

# Add the backend directory to Python path
sys.path.append(os.path.join(os.path.dirname(__file__), 'backend'))

# Setup Django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'school_attendance.settings')
django.setup()

from django.utils import timezone
from attendance.models import Attendance
from attendance.views import get_local_date_key

def test_timezone_fix():
    """Test the timezone fix"""
    print("Testing timezone fix...")
    print(f"Current Django timezone: {timezone.get_current_timezone()}")
    print(f"Current local time: {timezone.now()}")
    print(f"Current UTC time: {timezone.now().utcnow()}")
    
    # Get some recent attendance records
    recent_records = Attendance.objects.all().order_by('-timestamp')[:5]
    
    print(f"\nFound {recent_records.count()} recent attendance records:")
    for record in recent_records:
        utc_timestamp = record.timestamp
        local_timestamp = timezone.localtime(record.timestamp)
        date_key = get_local_date_key(record.timestamp)
        
        print(f"  Student: {record.student.name}")
        print(f"    UTC timestamp: {utc_timestamp}")
        print(f"    Local timestamp: {local_timestamp}")
        print(f"    Date key: {date_key}")
        print(f"    UTC date: {utc_timestamp.date()}")
        print(f"    Local date: {local_timestamp.date()}")
        print()

if __name__ == "__main__":
    test_timezone_fix()
