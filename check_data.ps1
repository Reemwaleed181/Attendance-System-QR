# PowerShell script to check data consistency
Write-Host "🔍 Starting data consistency check..." -ForegroundColor Green
Write-Host "=" * 60 -ForegroundColor Yellow

# Change to backend directory and run Django shell commands
cd backend

Write-Host "`n=== CHECKING FOR DUPLICATE STUDENT NAMES ===" -ForegroundColor Cyan
python manage.py shell -c "
from attendance.models import Student, ClassRoom
from collections import Counter

# Check duplicate student names
students = Student.objects.all()
student_names = [student.name for student in students]
name_counts = Counter(student_names)
duplicates = {name: count for name, count in name_counts.items() if count > 1}

if duplicates:
    print(f'❌ Found {len(duplicates)} duplicate student names:')
    for name, count in duplicates.items():
        print(f'  - \"{name}\": {count} times')
        duplicate_students = Student.objects.filter(name=name)
        for student in duplicate_students:
            print(f'    ID: {student.id}, QR: {student.qr_code}, Class: {student.classroom.name if student.classroom else \"None\"}')
else:
    print('✅ No duplicate student names found')
"

Write-Host "`n=== CHECKING FOR DUPLICATE QR CODES ===" -ForegroundColor Cyan
python manage.py shell -c "
from attendance.models import Student, ClassRoom
from collections import Counter

# Check student QR codes
students = Student.objects.all()
student_qr_codes = [student.qr_code for student in students if student.qr_code]
student_qr_counts = Counter(student_qr_codes)

# Check classroom QR codes
classrooms = ClassRoom.objects.all()
classroom_qr_codes = [classroom.qr_code for classroom in classrooms if classroom.qr_code]
classroom_qr_counts = Counter(classroom_qr_codes)

# Check for duplicates within students
student_duplicates = {qr: count for qr, count in student_qr_counts.items() if count > 1}

# Check for duplicates within classrooms
classroom_duplicates = {qr: count for qr, count in classroom_qr_counts.items() if count > 1}

# Check for cross-duplicates
all_student_qrs = set(student_qr_codes)
all_classroom_qrs = set(classroom_qr_codes)
cross_duplicates = all_student_qrs.intersection(all_classroom_qrs)

if student_duplicates:
    print(f'❌ Found {len(student_duplicates)} duplicate student QR codes:')
    for qr, count in student_duplicates.items():
        print(f'  - \"{qr}\": {count} times')
        duplicate_students = Student.objects.filter(qr_code=qr)
        for student in duplicate_students:
            print(f'    Student: {student.name} (ID: {student.id})')
else:
    print('✅ No duplicate student QR codes found')

if classroom_duplicates:
    print(f'❌ Found {len(classroom_duplicates)} duplicate classroom QR codes:')
    for qr, count in classroom_duplicates.items():
        print(f'  - \"{qr}\": {count} times')
        duplicate_classrooms = ClassRoom.objects.filter(qr_code=qr)
        for classroom in duplicate_classrooms:
            print(f'    Classroom: {classroom.name} (ID: {classroom.id})')
else:
    print('✅ No duplicate classroom QR codes found')

if cross_duplicates:
    print(f'❌ Found {len(cross_duplicates)} QR codes shared between students and classrooms:')
    for qr in cross_duplicates:
        print(f'  - \"{qr}\"')
        students_with_qr = Student.objects.filter(qr_code=qr)
        classrooms_with_qr = ClassRoom.objects.filter(qr_code=qr)
        for student in students_with_qr:
            print(f'    Student: {student.name} (ID: {student.id})')
        for classroom in classrooms_with_qr:
            print(f'    Classroom: {classroom.name} (ID: {classroom.id})')
else:
    print('✅ No QR codes shared between students and classrooms')
"

Write-Host "`n=== CHECKING FOR DUPLICATE CLASS NAMES ===" -ForegroundColor Cyan
python manage.py shell -c "
from attendance.models import ClassRoom
from collections import Counter

classrooms = ClassRoom.objects.all()
class_names = [classroom.name for classroom in classrooms]
name_counts = Counter(class_names)
duplicates = {name: count for name, count in name_counts.items() if count > 1}

if duplicates:
    print(f'❌ Found {len(duplicates)} duplicate class names:')
    for name, count in duplicates.items():
        print(f'  - \"{name}\": {count} times')
        duplicate_classrooms = ClassRoom.objects.filter(name=name)
        for classroom in duplicate_classrooms:
            print(f'    ID: {classroom.id}, QR: {classroom.qr_code}')
else:
    print('✅ No duplicate class names found')
"

Write-Host "`n=== CHECKING FOR MISSING STUDENTS ===" -ForegroundColor Cyan
python manage.py shell -c "
from attendance.models import Student

students = Student.objects.all()
print(f'Total students in database: {students.count()}')

# Check for students without QR codes
students_without_qr = students.filter(qr_code__isnull=True) | students.filter(qr_code='')
if students_without_qr.exists():
    print(f'❌ Found {students_without_qr.count()} students without QR codes:')
    for student in students_without_qr:
        print(f'  - {student.name} (ID: {student.id})')
else:
    print('✅ All students have QR codes')

# Check for students without classrooms
students_without_class = students.filter(classroom__isnull=True)
if students_without_class.exists():
    print(f'❌ Found {students_without_class.count()} students without classrooms:')
    for student in students_without_class:
        print(f'  - {student.name} (ID: {student.id})')
else:
    print('✅ All students have classrooms assigned')

# Check for students without parents
students_without_parents = students.filter(parents__isnull=True)
if students_without_parents.exists():
    print(f'❌ Found {students_without_parents.count()} students without parents:')
    for student in students_without_parents:
        print(f'  - {student.name} (ID: {student.id})')
else:
    print('✅ All students have parents assigned')
"

Write-Host "`n=== CHECKING QR CODE FORMATS ===" -ForegroundColor Cyan
python manage.py shell -c "
from attendance.models import Student, ClassRoom

students = Student.objects.all()
classrooms = ClassRoom.objects.all()

invalid_student_qrs = []
invalid_classroom_qrs = []

for student in students:
    if student.qr_code and not student.qr_code.startswith('STUDENT_'):
        invalid_student_qrs.append(student)

for classroom in classrooms:
    if classroom.qr_code and not classroom.qr_code.startswith('CLASS_'):
        invalid_classroom_qrs.append(classroom)

if invalid_student_qrs:
    print(f'❌ Found {len(invalid_student_qrs)} students with invalid QR code format:')
    for student in invalid_student_qrs:
        print(f'  - {student.name}: \"{student.qr_code}\" (should start with \"STUDENT_\")')
else:
    print('✅ All student QR codes have correct format')

if invalid_classroom_qrs:
    print(f'❌ Found {len(invalid_classroom_qrs)} classrooms with invalid QR code format:')
    for classroom in invalid_classroom_qrs:
        print(f'  - {classroom.name}: \"{classroom.qr_code}\" (should start with \"CLASS_\")')
else:
    print('✅ All classroom QR codes have correct format')
"

Write-Host "`n=== DATABASE STATISTICS ===" -ForegroundColor Cyan
python manage.py shell -c "
from attendance.models import Student, ClassRoom, Parent, Teacher, Attendance
from django.utils import timezone
from datetime import timedelta

students = Student.objects.all()
classrooms = ClassRoom.objects.all()
parents = Parent.objects.all()
teachers = Teacher.objects.all()
attendance_records = Attendance.objects.all()

print(f'📊 Database Statistics:')
print(f'  - Students: {students.count()}')
print(f'  - Classrooms: {classrooms.count()}')
print(f'  - Parents: {parents.count()}')
print(f'  - Teachers: {teachers.count()}')
print(f'  - Attendance Records: {attendance_records.count()}')

# Check for recent attendance
today = timezone.now().date()
week_ago = today - timedelta(days=7)
recent_attendance = attendance_records.filter(timestamp__date__gte=week_ago)
print(f'  - Recent Attendance (last 7 days): {recent_attendance.count()}')
"

Write-Host "`n=== LISTING ALL STUDENTS ===" -ForegroundColor Cyan
python manage.py shell -c "
from attendance.models import Student

print('All students in database:')
students = Student.objects.all().order_by('name')
for i, student in enumerate(students, 1):
    classroom_name = student.classroom.name if student.classroom else 'No Class'
    parent_count = student.parents.count()
    print(f'{i:2d}. {student.name} | QR: {student.qr_code} | Class: {classroom_name} | Parents: {parent_count}')
"

Write-Host "`n=== LISTING ALL CLASSROOMS ===" -ForegroundColor Cyan
python manage.py shell -c "
from attendance.models import ClassRoom

print('All classrooms in database:')
classrooms = ClassRoom.objects.all().order_by('name')
for i, classroom in enumerate(classrooms, 1):
    student_count = classroom.student_set.count()
    print(f'{i:2d}. {classroom.name} | QR: {classroom.qr_code} | Students: {student_count}')
"

Write-Host "`n" + "=" * 60 -ForegroundColor Yellow
Write-Host "✅ Data consistency check completed!" -ForegroundColor Green
