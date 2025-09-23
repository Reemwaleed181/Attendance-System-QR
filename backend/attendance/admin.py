from django.contrib import admin
from django.utils import timezone
from django.utils.html import format_html
from .models import ClassRoom, Student, Parent, Teacher, Attendance


@admin.register(ClassRoom)
class ClassRoomAdmin(admin.ModelAdmin):
    list_display = ['name', 'qr_code', 'created_at']
    search_fields = ['name', 'qr_code']
    readonly_fields = ['id', 'created_at', 'updated_at']


@admin.register(Student)
class StudentAdmin(admin.ModelAdmin):
    list_display = ['name', 'classroom', 'qr_code', 'created_at']
    list_filter = ['classroom', 'created_at']
    search_fields = ['name', 'qr_code']
    readonly_fields = ['id', 'created_at', 'updated_at']


@admin.register(Parent)
class ParentAdmin(admin.ModelAdmin):
    list_display = ['name', 'email', 'phone', 'created_at']
    search_fields = ['name', 'email', 'phone']
    filter_horizontal = ['children']
    readonly_fields = ['id', 'created_at', 'updated_at']


@admin.register(Teacher)
class TeacherAdmin(admin.ModelAdmin):
    list_display = ['name', 'user', 'created_at']
    search_fields = ['name', 'user__username']
    readonly_fields = ['id', 'created_at', 'updated_at']


@admin.register(Attendance)
class AttendanceAdmin(admin.ModelAdmin):
    list_display = ['student', 'classroom', 'teacher', 'local_timestamp', 'is_present']
    list_filter = ['classroom', 'teacher', 'timestamp', 'is_present']
    search_fields = ['student__name', 'classroom__name', 'teacher__name']
    readonly_fields = ['id', 'timestamp', 'local_timestamp']
    date_hierarchy = 'timestamp'
    
    def local_timestamp(self, obj):
        """Display timestamp in local timezone"""
        # Convert UTC to local timezone (UTC+3 for your region)
        from datetime import timedelta
        local_time = obj.timestamp + timedelta(hours=3)  # UTC+3
        
        # Get current local date (UTC+3) for comparison
        current_utc = timezone.now()
        current_local = current_utc + timedelta(hours=3)
        current_local_date = current_local.date()
        
        # Color code based on date
        if local_time.date() == current_local_date:
            color = 'green'  # Today
        elif local_time.date() == (current_local_date - timedelta(days=1)):
            color = 'orange'  # Yesterday
        else:
            color = 'black'  # Other days
            
        return format_html(
            '<span style="color: {};">{}</span>',
            color,
            local_time.strftime('%b. %d, %Y, %I:%M %p')
        )
    local_timestamp.short_description = 'Local Time (UTC+3)'
    local_timestamp.admin_order_field = 'timestamp'
