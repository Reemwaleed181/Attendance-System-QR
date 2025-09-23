from django.core.management.base import BaseCommand
from attendance.models import Student, ClassRoom

class Command(BaseCommand):
    help = 'Check students in Class 1'

    def handle(self, *args, **options):
        try:
            c1 = ClassRoom.objects.get(name='Class 1')
            students = Student.objects.filter(classroom=c1)
            
            self.stdout.write(f'Class 1 has {students.count()} students:')
            for i, student in enumerate(students, 1):
                self.stdout.write(f'{i}. {student.name} (ID: {student.id})')
                
        except ClassRoom.DoesNotExist:
            self.stdout.write(self.style.ERROR('Class 1 not found in database'))
