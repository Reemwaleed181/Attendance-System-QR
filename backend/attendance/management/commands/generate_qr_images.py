from django.core.management.base import BaseCommand
from attendance.models import ClassRoom, Student
import os
import qrcode

class Command(BaseCommand):
    help = 'Generate QR code images for classrooms and students'

    def handle(self, *args, **options):
        self.stdout.write('🔍 Generating QR Code Images...')
        
        # Create QR codes directory
        qr_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(__file__)))), 'excel_data', 'qr_codes')
        os.makedirs(qr_dir, exist_ok=True)
        
        # Generate QR codes for classrooms
        self.stdout.write('\n🏫 Generating Classroom QR Codes:')
        classrooms = ClassRoom.objects.all()
        for classroom in classrooms:
            qr_code = classroom.qr_code
            filename = f"classroom_{classroom.name.replace(' ', '_')}.png"
            filepath = os.path.join(qr_dir, filename)
            
            # Create QR code
            qr = qrcode.QRCode(
                version=1,
                error_correction=qrcode.constants.ERROR_CORRECT_L,
                box_size=10,
                border=4,
            )
            qr.add_data(qr_code)
            qr.make(fit=True)
            
            # Create image
            img = qr.make_image(fill_color="black", back_color="white")
            img.save(filepath)
            
            self.stdout.write(
                self.style.SUCCESS(f'✅ {classroom.name}: {qr_code} -> {filename}')
            )
        
        # Generate QR codes for students
        self.stdout.write('\n👦 Generating Student QR Codes:')
        students = Student.objects.all()
        for student in students:
            qr_code = student.qr_code
            filename = f"student_{student.name.replace(' ', '_')}.png"
            filepath = os.path.join(qr_dir, filename)
            
            # Create QR code
            qr = qrcode.QRCode(
                version=1,
                error_correction=qrcode.constants.ERROR_CORRECT_L,
                box_size=10,
                border=4,
            )
            qr.add_data(qr_code)
            qr.make(fit=True)
            
            # Create image
            img = qr.make_image(fill_color="black", back_color="white")
            img.save(filepath)
            
            self.stdout.write(
                self.style.SUCCESS(f'✅ {student.name} ({student.classroom.name}): {qr_code} -> {filename}')
            )
        
        self.stdout.write(f'\n🎉 QR codes generated successfully in: {qr_dir}')
        self.stdout.write(f'📁 Total files created: {len(classrooms) + len(students)}')
        
        # Print summary
        self.stdout.write('\n📋 QR Code Summary:')
        self.stdout.write('=' * 50)
        self.stdout.write('🏫 CLASSROOM QR CODES:')
        for classroom in classrooms:
            self.stdout.write(f'   {classroom.name}: {classroom.qr_code}')
        
        self.stdout.write('\n👦 STUDENT QR CODES:')
        for student in students:
            self.stdout.write(f'   {student.name} ({student.classroom.name}): {student.qr_code}')
        
        self.stdout.write('\n💡 USAGE INSTRUCTIONS:')
        self.stdout.write('1. Print the QR code images')
        self.stdout.write('2. Post classroom QR codes on classroom doors')
        self.stdout.write('3. Give student QR codes to students (ID cards)')
        self.stdout.write('4. Use the Flutter app to scan them for attendance')
