from django.urls import path
from . import views

urlpatterns = [
    # Authentication
    path('login/teacher/', views.teacher_login, name='teacher_login'),
    path('login/parent/', views.parent_login, name='parent_login'),
    
    # Attendance
    path('attendance/mark/', views.mark_attendance, name='mark_attendance'),
    path('attendance/mark-absence/', views.mark_absence, name='mark_absence'),
    
    # Data endpoints
    path('classrooms/', views.ClassRoomListView.as_view(), name='classroom_list'),
    path('students/', views.StudentListView.as_view(), name='student_list'),
    
    # Parent endpoints
    path('parent/<uuid:parent_id>/children/', views.parent_children_attendance, name='parent_children'),
    path('student/<uuid:student_id>/attendance/', views.student_attendance_history, name='student_attendance'),
    path('student/<uuid:student_id>/weekly-stats/', views.student_weekly_stats, name='student_weekly_stats'),
    path('parent/<uuid:parent_id>/detailed-reports/', views.parent_detailed_reports, name='parent_detailed_reports'),
    
    # Teacher endpoints
    path('teacher/attendance/history/', views.teacher_attendance_history, name='teacher_attendance_history'),
    path('teacher/reports/', views.teacher_reports, name='teacher_reports'),
    path('teacher/students-with-absences/', views.teacher_students_with_absences, name='teacher_students_with_absences'),
    path('teacher/send-absence-reports/', views.teacher_send_absence_reports, name='teacher_send_absence_reports'),
    path('teacher/send-daily-absence-notifications/', views.teacher_send_daily_absence_notifications, name='teacher_send_daily_absence_notifications'),
    path('teacher/send-report-notifications/', views.teacher_send_report_notifications, name='teacher_send_report_notifications'),
    
    # Notification endpoints
    path('parent/<uuid:parent_id>/notifications/', views.parent_notifications, name='parent_notifications'),
    path('notifications/<uuid:notification_id>/mark-read/', views.mark_notification_as_read, name='mark_notification_as_read'),
    path('parent/<uuid:parent_id>/notifications/mark-all-read/', views.mark_all_notifications_as_read, name='mark_all_notifications_as_read'),
]
