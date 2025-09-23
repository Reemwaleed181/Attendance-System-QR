#!/usr/bin/env python3
"""
Setup script for School Attendance System
This script helps set up the Django backend and prepare the environment.
"""

import os
import sys
import subprocess
import pandas as pd

def run_command(command, cwd=None):
    """Run a command and return the result"""
    try:
        result = subprocess.run(command, shell=True, cwd=cwd, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"Error running command: {command}")
            print(f"Error: {result.stderr}")
            return False
        return True
    except Exception as e:
        print(f"Exception running command: {command}")
        print(f"Exception: {e}")
        return False

def create_sample_excel_files():
    """Create sample Excel files for testing"""
    print("Creating sample Excel files...")
    
    # Create sample classes data
    classes_data = {
        'name': [
            'Class 1', 'Class 2', 'Class 3', 'Class 4', 'Class 5',
            'Class 6', 'Class 7', 'Class 8', 'Class 9', 'Class 10'
        ]
    }
    
    # Create sample students data
    students_data = {
        'name': [
            'Ahmed Ali', 'Aliaa Ali', 'Reem Omaran', 'Amina Omaran', 'ALi Mohammed', 'Aisha Mohammed',
            'Khadeja Khalil', 'Hala Khalil', 'Omran Omar', 'Layla Omar', 'Zainab Omar', 'Nada Omar',
            'Yaser Youssef', 'Tariq Youssef', 'Nouran Adam', 'Khalid Adam', 'Aser Khalid', 'Mahmoud Khalid',
            'MALk Ibrahim', 'Sara Ibrahim'
        ],
        'class': [
            'Class 1', 'Class 1', 'Class 1', 'Class 1', 'Class 2', 'Class 2',
            'Class 2', 'Class 2', 'Class 3', 'Class 3', 'Class 3', 'Class 3',
            'Class 4', 'Class 4', 'Class 4', 'Class 4', 'Class 5', 'Class 5',
            'Class 5', 'Class 5'
        ]
    }
    
    # Create sample parents data
    parents_data = {
        'name': [
            'Ali Hassan', 'Fatima Omar', 'Mohammed Ibrahim', 'Aisha khalid', 'Omar Ahmed',
            'Youssef Hassan', 'Noura Ali', 'Khalid Omar', 'Mariam Ibrahim'
        ],
        'email': [
            'ali.hassan@email.com', 'fatima.omar@email.com', 'mohammed.ibrahim@email.com',
            'aisha.khalid@email.com', 'omar.ahmed@email.com', 'youssef.hassan@email.com',
            'noura.ali@email.com', 'khalid.omar@email.com', 'mariam.ibrahim@email.com'
        ],
        'phone': [
            '+1234567890', '+1234567891', '+1234567892', '+1234567893', '+1234567894',
            '+1234567896', '+1234567897', '+1234567898', '+1234567899'
        ],
        'children': [
            'Ahmed Ali;Aliaa Ali', 'Reem Omaran;Amina Omaran', 'ALi Mohammed;Aisha Mohammed',
            'Khadeja Khalil;Hala Khalil', 'Omran Omar;Layla Omar;Zainab Omar;Nada Omar',
            'Yaser Youssef;Tariq Youssef', 'Nouran Adam;Khalid Adam', 'Aser Khalid;Mahmoud Khalid',
            'MALk Ibrahim;Sara Ibrahim'
        ]
    }
    
    # Create DataFrames and save to Excel
    try:
        classes_df = pd.DataFrame(classes_data)
        students_df = pd.DataFrame(students_data)
        parents_df = pd.DataFrame(parents_data)
        
        # Save to Excel files
        classes_df.to_excel('excel_data/classes.xlsx', index=False)
        students_df.to_excel('excel_data/students.xlsx', index=False)
        parents_df.to_excel('excel_data/parents.xlsx', index=False)
        
        print("✅ Sample Excel files created successfully!")
        return True
    except Exception as e:
        print(f"❌ Error creating Excel files: {e}")
        return False

def setup_django_backend():
    """Set up Django backend"""
    print("Setting up Django backend...")
    
    # Check if we're in the right directory
    if not os.path.exists('backend'):
        print("❌ Backend directory not found. Please run this script from the project root.")
        return False
    
    # Install Python dependencies
    print("Installing Python dependencies...")
    if not run_command("pip install -r requirements.txt", cwd="backend"):
        print("❌ Failed to install Python dependencies")
        return False
    
    # Run Django migrations
    print("Running Django migrations...")
    if not run_command("python manage.py migrate", cwd="backend"):
        print("❌ Failed to run Django migrations")
        return False
    
    # Import sample data
    print("Importing sample data...")
    if not run_command("python manage.py import_data", cwd="backend"):
        print("❌ Failed to import sample data")
        return False
    
    print("✅ Django backend setup completed!")
    return True

def setup_flutter_frontend():
    """Set up Flutter frontend"""
    print("Setting up Flutter frontend...")
    
    # Install Flutter dependencies
    print("Installing Flutter dependencies...")
    if not run_command("flutter pub get"):
        print("❌ Failed to install Flutter dependencies")
        return False
    
    print("✅ Flutter frontend setup completed!")
    return True

def main():
    """Main setup function"""
    print("🏫 School Attendance System Setup")
    print("=" * 40)
    
    # Check if required directories exist
    if not os.path.exists('excel_data'):
        os.makedirs('excel_data')
        print("Created excel_data directory")
    
    if not os.path.exists('excel_data/qr_codes'):
        os.makedirs('excel_data/qr_codes')
        print("Created qr_codes directory")
    
    # Create sample Excel files
    if not create_sample_excel_files():
        return
    
    # Setup Django backend
    if not setup_django_backend():
        return
    
    # Setup Flutter frontend
    if not setup_flutter_frontend():
        return
    
    print("\n🎉 Setup completed successfully!")
    print("\nNext steps:")
    print("1. Start Django backend: cd backend && python manage.py runserver")
    print("2. Start Flutter app: flutter run -d chrome")
    print("3. Access Django admin: http://localhost:8000/admin/")
    print("\nDefault teacher credentials:")
    print("Username: admin")
    print("Password: (set during superuser creation)")

if __name__ == "__main__":
    main()
