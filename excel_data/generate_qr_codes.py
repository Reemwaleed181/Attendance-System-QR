import pandas as pd
import qrcode
import os

# IMPORTANT: This is the SINGLE source for QR codes in the project
# All QR codes are generated in: excel_data/qr_codes/
# Do not create QR codes in other locations to avoid confusion

def generate_qr_codes():
    print("🔍 Generating QR Code Images for Updated Students...")
    print("📍 QR codes will be generated in: excel_data/qr_codes/")
    
    # Read the updated students data
    students_df = pd.read_csv('students.csv')
    
    # Create QR codes directory (single location)
    qr_dir = 'qr_codes'
    os.makedirs(qr_dir, exist_ok=True)
    
    # Clear existing QR codes to ensure consistency
    for file in os.listdir(qr_dir):
        if file.startswith('student_') and file.endswith('.png'):
            os.remove(os.path.join(qr_dir, file))
            print(f"🗑️  Removed old QR code: {file}")
    
    # Generate QR codes for each student
    print(f"\n👦 Generating Student QR Codes for {len(students_df)} students:")
    
    for index, row in students_df.iterrows():
        student_name = row['name']
        student_class = row['class']
        
        # Create QR code data (student name + class) - match database format
        qr_data = f"STUDENT_{student_name.replace(' ', '_').lower()}"
        
        # Create filename
        filename = f"student_{student_name.replace(' ', '_')}.png"
        filepath = os.path.join(qr_dir, filename)
        
        # Create QR code
        qr = qrcode.QRCode(
            version=1,
            error_correction=qrcode.constants.ERROR_CORRECT_L,
            box_size=10,
            border=4,
        )
        qr.add_data(qr_data)
        qr.make(fit=True)
        
        # Create image
        img = qr.make_image(fill_color="black", back_color="white")
        img.save(filepath)
        
        print(f"✅ {student_name} ({student_class}): {qr_data} -> {filename}")
    
    # Generate QR codes for classes
    print(f"\n🏫 Generating Classroom QR Codes:")
    classes_df = pd.read_csv('classes.csv')
    
    for index, row in classes_df.iterrows():
        class_name = row['name']
        teacher = row['teacher']
        capacity = row['capacity']
        
        # Create QR code data (class info) - match database format
        qr_data = f"CLASS_{class_name.replace(' ', '_').upper()}"
        
        # Create filename
        filename = f"classroom_{class_name.replace(' ', '_')}.png"
        filepath = os.path.join(qr_dir, filename)
        
        # Create QR code
        qr = qrcode.QRCode(
            version=1,
            error_correction=qrcode.constants.ERROR_CORRECT_L,
            box_size=10,
            border=4,
        )
        qr.add_data(qr_data)
        qr.make(fit=True)
        
        # Create image
        img = qr.make_image(fill_color="black", back_color="white")
        img.save(filepath)
        
        print(f"✅ {class_name} ({teacher}): {qr_data} -> {filename}")
    
    print(f"\n🎉 QR codes generated successfully in: {qr_dir}")
    print(f"📁 Total files created: {len(students_df) + len(classes_df)}")
    print(f"📍 Single source location: {os.path.abspath(qr_dir)}")
    
    # Print summary
    print('\n📋 QR Code Summary:')
    print('=' * 50)
    print('🏫 CLASSROOM QR CODES:')
    for index, row in classes_df.iterrows():
        print(f"   {row['name']}: {row['teacher']}")
    
    print('\n👦 STUDENT QR CODES:')
    for index, row in students_df.iterrows():
        print(f"   {row['name']} ({row['class']})")
    
    print('\n💡 USAGE INSTRUCTIONS:')
    print('1. Print the QR code images')
    print('2. Post classroom QR codes on classroom doors')
    print('3. Give student QR codes to students (ID cards)')
    print('4. Use the Flutter app to scan them for attendance')
    print(f'5. All QR codes are stored in: {os.path.abspath(qr_dir)}')

if __name__ == "__main__":
    try:
        generate_qr_codes()
    except Exception as e:
        print(f"❌ Error generating QR codes: {e}")
        print("Make sure you have the required packages installed:")
        print("pip install pandas qrcode pillow")
