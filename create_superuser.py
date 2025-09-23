#!/usr/bin/env python
import os
import sys
import django

# Add the backend directory to Python path
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

# Set Django settings
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'school_attendance.settings')
django.setup()

from django.contrib.auth.models import User
from attendance.models import Teacher

# Create superuser
username = 'admin'
email = 'admin@school.com'
password = 'admin123'

if User.objects.filter(username=username).exists():
    print(f"User {username} already exists!")
else:
    user = User.objects.create_superuser(username, email, password)
    print(f"Superuser {username} created successfully!")
    
    # Create teacher profile
    teacher, created = Teacher.objects.get_or_create(
        user=user,
        defaults={'name': 'Admin Teacher'}
    )
    if created:
        print("Teacher profile created successfully!")
    else:
        print("Teacher profile already exists!")

print("Setup completed!")
