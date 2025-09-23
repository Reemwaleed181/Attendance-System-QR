import os
import pandas as pd
import qrcode
from django.core.management.base import BaseCommand
from django.conf import settings
from attendance.models import ClassRoom, Student, Parent
import uuid


class Command(BaseCommand):
    help = 'Import data from Excel files and generate QR codes'

    def add_arguments(self, parser):
        parser.add_argument(
            '--excel-dir',
            type=str,
            default='../excel_data',
            help='Directory containing Excel files'
        )
        parser.add_argument(
            '--qr-dir',
            type=str,
            default='../excel_data/qr_codes',
            help='Directory to save QR code images'
        )

    def handle(self, *args, **options):
        excel_dir = options['excel_dir']
        qr_dir = options['qr_dir']
        
        # Create QR codes directory if it doesn't exist
        os.makedirs(qr_dir, exist_ok=True)
        
        self.stdout.write('Starting data import...')
        
        # Import classrooms
        self.import_classrooms(excel_dir, qr_dir)
        
        # Import students
        self.import_students(excel_dir, qr_dir)
        
        # Import parents
        self.import_parents(excel_dir)
        
        self.stdout.write(
            self.style.SUCCESS('Data import completed successfully!')
        )

    def import_classrooms(self, excel_dir, qr_dir):
        """Import classrooms from Excel or CSV file"""
        excel_file = os.path.join(excel_dir, 'classes.xlsx')
        csv_file = os.path.join(excel_dir, 'classes.csv')
        
        file_path = excel_file if os.path.exists(excel_file) else csv_file
        
        if not os.path.exists(file_path):
            self.stdout.write(
                self.style.WARNING(f'Classes file not found: {excel_file} or {csv_file}')
            )
            return
        
        try:
            if file_path.endswith('.csv'):
                df = pd.read_csv(file_path)
            else:
                df = pd.read_excel(file_path)
            self.stdout.write(f'Importing {len(df)} classrooms...')
            
            for _, row in df.iterrows():
                class_name = str(row.get('name', '')).strip()
                if not class_name:
                    continue
                
                # Generate QR code
                qr_code = f"CLASS_{class_name.replace(' ', '_').upper()}_{uuid.uuid4().hex[:8]}"
                
                # Create or update classroom
                classroom, created = ClassRoom.objects.get_or_create(
                    name=class_name,
                    defaults={'qr_code': qr_code}
                )
                
                if created:
                    self.generate_qr_image(qr_code, os.path.join(qr_dir, f'class_{class_name}.png'))
                    self.stdout.write(f'Created classroom: {class_name}')
                else:
                    self.stdout.write(f'Classroom already exists: {class_name}')
                    
        except Exception as e:
            self.stdout.write(
                self.style.ERROR(f'Error importing classrooms: {str(e)}')
            )

    def import_students(self, excel_dir, qr_dir):
        """Import students from Excel or CSV file"""
        excel_file = os.path.join(excel_dir, 'students.xlsx')
        csv_file = os.path.join(excel_dir, 'students.csv')
        
        file_path = excel_file if os.path.exists(excel_file) else csv_file
        
        if not os.path.exists(file_path):
            self.stdout.write(
                self.style.WARNING(f'Students file not found: {excel_file} or {csv_file}')
            )
            return
        
        try:
            if file_path.endswith('.csv'):
                df = pd.read_csv(file_path)
            else:
                df = pd.read_excel(file_path)
            self.stdout.write(f'Importing {len(df)} students...')
            
            for _, row in df.iterrows():
                student_name = str(row.get('name', '')).strip()
                class_name = str(row.get('class', '')).strip()
                
                if not student_name or not class_name:
                    continue
                
                try:
                    classroom = ClassRoom.objects.get(name=class_name)
                except ClassRoom.DoesNotExist:
                    self.stdout.write(
                        self.style.WARNING(f'Classroom not found: {class_name}')
                    )
                    continue
                
                # Generate QR code
                qr_code = f"STUDENT_{student_name.replace(' ', '_').upper()}_{uuid.uuid4().hex[:8]}"
                
                # Create or update student
                student, created = Student.objects.get_or_create(
                    name=student_name,
                    classroom=classroom,
                    defaults={'qr_code': qr_code}
                )
                
                if created:
                    self.generate_qr_image(qr_code, os.path.join(qr_dir, f'student_{student_name}.png'))
                    self.stdout.write(f'Created student: {student_name} in {class_name}')
                else:
                    self.stdout.write(f'Student already exists: {student_name}')
                    
        except Exception as e:
            self.stdout.write(
                self.style.ERROR(f'Error importing students: {str(e)}')
            )

    def import_parents(self, excel_dir):
        """Import parents from Excel or CSV file"""
        excel_file = os.path.join(excel_dir, 'parents.xlsx')
        csv_file = os.path.join(excel_dir, 'parents.csv')
        
        file_path = excel_file if os.path.exists(excel_file) else csv_file
        
        if not os.path.exists(file_path):
            self.stdout.write(
                self.style.WARNING(f'Parents file not found: {excel_file} or {csv_file}')
            )
            return
        
        try:
            if file_path.endswith('.csv'):
                df = pd.read_csv(file_path)
            else:
                df = pd.read_excel(file_path)
            self.stdout.write(f'Importing {len(df)} parents...')
            
            for _, row in df.iterrows():
                parent_name = str(row.get('name', '')).strip()
                email = str(row.get('email', '')).strip()
                phone = str(row.get('phone', '')).strip()
                children_names = str(row.get('children', '')).strip()
                
                if not parent_name or not email:
                    continue
                
                # Create or update parent
                parent, created = Parent.objects.get_or_create(
                    email=email,
                    defaults={
                        'name': parent_name,
                        'phone': phone
                    }
                )
                
                if created:
                    self.stdout.write(f'Created parent: {parent_name}')
                else:
                    self.stdout.write(f'Parent already exists: {parent_name}')
                
                # Link children if specified
                if children_names:
                    children_list = [name.strip() for name in children_names.split(';')]
                    for child_name in children_list:
                        try:
                            student = Student.objects.get(name=child_name)
                            parent.children.add(student)
                            self.stdout.write(f'Linked {parent_name} to {child_name}')
                        except Student.DoesNotExist:
                            self.stdout.write(
                                self.style.WARNING(f'Student not found: {child_name}')
                            )
                    
        except Exception as e:
            self.stdout.write(
                self.style.ERROR(f'Error importing parents: {str(e)}')
            )

    def generate_qr_image(self, qr_code, file_path):
        """Generate QR code image"""
        try:
            qr = qrcode.QRCode(
                version=1,
                error_correction=qrcode.constants.ERROR_CORRECT_L,
                box_size=10,
                border=4,
            )
            qr.add_data(qr_code)
            qr.make(fit=True)
            
            img = qr.make_image(fill_color="black", back_color="white")
            img.save(file_path)
            
        except Exception as e:
            self.stdout.write(
                self.style.WARNING(f'Error generating QR code for {qr_code}: {str(e)}')
            )
