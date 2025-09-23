import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';
import '../../models/student.dart';
import '../../constants/app_colors.dart';
import '../../utils/responsive.dart';

class ParentWeeklyStatsScreen extends StatefulWidget {
  const ParentWeeklyStatsScreen({super.key});

  @override
  State<ParentWeeklyStatsScreen> createState() => _ParentWeeklyStatsScreenState();
}

class _ParentWeeklyStatsScreenState extends State<ParentWeeklyStatsScreen>
    with TickerProviderStateMixin {
  String? _parentId;
  List<Student> _children = [];
  Map<String, Map<String, dynamic>> _weeklyStats = {};
  bool _isLoading = true;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));

    _animationController.forward();
    _loadParentId();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Refresh data when screen becomes visible to catch new absence reports
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_parentId != null) {
        _loadChildrenData();
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadParentId() async {
    final prefs = await SharedPreferences.getInstance();
    _parentId = prefs.getString('parent_id');
    if (_parentId != null) {
      await _loadChildrenData();
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadChildrenData() async {
    if (_parentId == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      // Load parent children data
      final parentData = await ApiService.getParentChildren(_parentId!);
      final childrenData = parentData['children'] as List<dynamic>? ?? [];
      
      final children = childrenData.map((json) {
        // The backend returns children in a nested structure: {'student': {...}, 'attendance_today': [...]}
        final studentData = json['student'] as Map<String, dynamic>? ?? json;
        return Student.fromJson(studentData);
      }).toList();
      
      // Load comprehensive weekly statistics for each child
      final Map<String, Map<String, dynamic>> weeklyStats = {};
      for (final child in children) {
        try {
          // Get current week's date range (Sunday to Thursday)
          // Use the same timezone logic as backend: get_local_date_key function
          final now = DateTime.now();
          final deviceTimezoneOffset = now.timeZoneOffset.inMinutes;
          // Convert to backend timezone like the backend does
          final backendTime = now.toUtc().add(Duration(minutes: deviceTimezoneOffset));
          // Calculate start of week (Sunday)
          // weekday returns 1=Monday, 2=Tuesday, ..., 7=Sunday
          // We need to go back to the previous Sunday
          final daysSinceSunday = (backendTime.weekday % 7); // 0=Sunday, 1=Monday, ..., 6=Saturday
          final startOfWeek = backendTime.subtract(Duration(days: daysSinceSunday));
          // End of week is Thursday (4 days after Sunday)
          final endOfWeek = startOfWeek.add(const Duration(days: 4));
          
          final fromDateStr = '${startOfWeek.year}-${startOfWeek.month.toString().padLeft(2, '0')}-${startOfWeek.day.toString().padLeft(2, '0')}';
          final toDateStr = '${endOfWeek.year}-${endOfWeek.month.toString().padLeft(2, '0')}-${endOfWeek.day.toString().padLeft(2, '0')}';
          
          // Get detailed reports for comprehensive stats
          final reports = await ApiService.getParentDetailedReports(
            _parentId!,
            fromDate: fromDateStr,
            toDate: toDateStr,
          );
          
          // Process the data to extract comprehensive statistics
          final stats = _processWeeklyStats(reports, child.id);
          weeklyStats[child.id] = stats;
        } catch (e) {
          print('Error loading stats for ${child.name}: $e');
          // If stats not available, create default structure
          weeklyStats[child.id] = {
            'total_days': 5,
            'present_days': 0,
            'absent_days': 0,
            'late_days': 0,
            'time_absences': 0,
            'attendance_rate': 0.0,
            'reports_sent': 0,
            'weekly_data': [],
          };
        }
      }
      
      setState(() {
        _children = children;
        _weeklyStats = weeklyStats;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  Map<String, dynamic> _processWeeklyStats(Map<String, dynamic> reports, String childId) {
    final absenceReports = reports['absence_reports'] as List<dynamic>? ?? [];
    
    // Find reports for this specific child
    final childReports = absenceReports.where((report) => 
      report['student_id'] == childId
    ).toList();
    
    int presentDays = 0;
    int absentDays = 0;
    int lateDays = 0;
    int timeAbsences = 0;
    int reportsSent = childReports.length;
    
    // Process each day of the week (Sunday to Thursday)
    // Use the same timezone logic as backend: get_local_date_key function
    final now = DateTime.now();
    final deviceTimezoneOffset = now.timeZoneOffset.inMinutes;
    // Convert to backend timezone like the backend does
    final backendTime = now.toUtc().add(Duration(minutes: deviceTimezoneOffset));
    // Calculate start of week (Sunday)
    // weekday returns 1=Monday, 2=Tuesday, ..., 7=Sunday
    // We need to go back to the previous Sunday
    final daysSinceSunday = (backendTime.weekday % 7); // 0=Sunday, 1=Monday, ..., 6=Saturday
    final startOfWeek = backendTime.subtract(Duration(days: daysSinceSunday));
    final List<Map<String, dynamic>> weeklyData = [];
    
    for (int i = 0; i < 5; i++) { // Sunday to Thursday
      final day = startOfWeek.add(Duration(days: i));
      final dayStr = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
      
      // Check if there's an absence report for this day
      final dayReport = childReports.where((report) {
        final absenceDates = report['absence_dates'] as List<dynamic>? ?? [];
        return absenceDates.any((absence) => absence['date'] == dayStr);
      }).toList();
      
      if (dayReport.isNotEmpty) {
        // Any reported absence counts as absent for the day.
        final hasTimeAbsence = dayReport.any((report) {
          final absenceDates = report['absence_dates'] as List<dynamic>? ?? [];
          return absenceDates.any((absence) => absence['date'] == dayStr && (absence['time'] != null && absence['time'] != ''));
        });
        if (hasTimeAbsence) {
          timeAbsences++;
        }
        absentDays++;
        weeklyData.add({
          'day': dayStr,
          'is_present': false,
          'is_late': false,
          'has_time_absence': hasTimeAbsence,
        });
      } else {
        // No absence report - fully present
        presentDays++;
        weeklyData.add({
          'day': dayStr,
          'is_present': true,
          'is_late': false,
          'has_time_absence': false,
        });
      }
    }
    
    final totalDays = presentDays + absentDays;
    final attendanceRate = totalDays > 0 ? presentDays / totalDays : 0.0;
    
    return {
      'total_days': totalDays,
      'present_days': presentDays,
      'absent_days': absentDays,
      'late_days': lateDays,
      'time_absences': timeAbsences,
      'attendance_rate': attendanceRate,
      'reports_sent': reportsSent,
      'weekly_data': weeklyData,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFFF8FAFC),
              Color(0xFFE2E8F0),
              Color(0xFFCBD5E1),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom App Bar
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.secondary, AppColors.secondaryDark],
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(32),
                    bottomRight: Radius.circular(32),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.secondary.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.arrow_back,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Weekly Statistics',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                          Opacity(
                            opacity: 0.9,
                            child: Text(
                              'Track your children\'s weekly attendance',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _showMonthlyCalendar,
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.calendar_month,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              // Main Content
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.secondary,
                        ),
                      )
                    : FadeTransition(
                        opacity: _fadeAnimation,
                        child: SlideTransition(
                          position: _slideAnimation,
                          child: RefreshIndicator(
                            onRefresh: _loadChildrenData,
                            color: AppColors.secondary,
                            child: SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: Responsive.pagePadding(context),
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: Responsive.maxContentWidth(context),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                  if (_children.isEmpty)
                                    Container(
                                      padding: const EdgeInsets.all(32),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(24),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.05),
                                            blurRadius: 20,
                                            offset: const Offset(0, 8),
                                          ),
                                        ],
                                      ),
                                      child: Column(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(20),
                                            decoration: BoxDecoration(
                                              color: AppColors.secondary.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: const Icon(
                                              Icons.people_outline,
                                              size: 48,
                                              color: AppColors.secondary,
                                            ),
                                          ),
                                          const SizedBox(height: 20),
                                          const Text(
                                            'No Children Found',
                                            style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF1F2937),
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                          const SizedBox(height: 12),
                                          const Text(
                                            'No children are registered under your account',
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: Color(0xFF6B7280),
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    )
                                  else
                                    Column(
                                      children: [
                                        // Children Stats Cards
                                        ..._children.map((child) => _buildChildStatsCard(child)),
                                      ],
                                    ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChildStatsCard(Student child) {
    final stats = _weeklyStats[child.id] ?? {};
    final presentDays = stats['present_days'] ?? 0;
    final absentDays = stats['absent_days'] ?? 0;
    final lateDays = stats['late_days'] ?? 0;
    final attendanceRate = stats['attendance_rate'] ?? 0.0;
    final reportsSent = stats['reports_sent'] ?? 0;
    final weeklyData = stats['weekly_data'] as List<dynamic>? ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Child Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.secondary, AppColors.secondaryDark],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.secondary.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      child.name.isNotEmpty ? child.name : 'Unknown Student',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    Text(
                      'Class: ${child.classroomName.isNotEmpty ? child.classroomName : 'Not Assigned'}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
              // Attendance Rate Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: attendanceRate >= 0.8 
                        ? [AppColors.secondary, AppColors.secondaryDark]
                        : attendanceRate >= 0.6
                            ? [const Color(0xFFF59E0B), const Color(0xFFD97706)]
                            : [const Color(0xFFEF4444), const Color(0xFFDC2626)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${(attendanceRate * 100).toInt()}%',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          // Weekly Chart
          if (weeklyData.isNotEmpty) ...[
            const Text(
              'Weekly Attendance Breakdown',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 140,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: _buildEnhancedWeeklyChart(weeklyData),
              ),
            ),
          ],
          
          const SizedBox(height: 20),
          
          // Summary Info
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFF8FAFC),
                  Color(0xFFE2E8F0),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFE2E8F0),
                width: 1,
              ),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.info_outline_rounded,
                      color: Color(0xFF6B7280),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Weekly Summary',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildSummaryItem('Present', presentDays, AppColors.secondary),
                    _buildSummaryItem('Absent', absentDays, const Color(0xFFEF4444)),
                    _buildSummaryItem('Late', lateDays, const Color(0xFFF59E0B)),
                    _buildSummaryItem('Reports', reportsSent, const Color(0xFF3B82F6)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildSummaryItem(String label, int value, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            value.toString(),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: Color(0xFF6B7280),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildEnhancedWeeklyChart(List<dynamic> weeklyData) {
    final days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu'];
    final List<Widget> chartBars = [];
    
    for (int i = 0; i < days.length && i < weeklyData.length; i++) {
      final dayData = weeklyData[i] as Map<String, dynamic>? ?? {};
      final isPresent = dayData['is_present'] ?? false;
      final isLate = dayData['is_late'] ?? false;
      
      Color color;
      double height;
      String status;
      
      if (isPresent && !isLate) {
        color = AppColors.secondary;
        height = 80.0;
        status = 'Present';
      } else if (isPresent && isLate) {
        color = const Color(0xFFF59E0B);
        height = 50.0;
        status = 'Late';
      } else {
        color = const Color(0xFFEF4444);
        height = 30.0;
        status = 'Absent';
      }
      
      chartBars.add(
        Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Container(
              width: 35,
              height: height,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    color,
                    color.withValues(alpha: 0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(6),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6), // Reduced from 8
            Text(
              days[i],
              style: const TextStyle(
                fontSize: 11, // Reduced from 12
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280),
              ),
            ),
            const SizedBox(height: 3), // Reduced from 4
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1), // Reduced padding
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                status,
                style: TextStyle(
                  fontSize: 7, // Reduced from 8
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      );
    }
    
    return chartBars;
  }
  
  void _showMonthlyCalendar() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      backgroundColor: Colors.white,
      builder: (context) {
        final now = DateTime.now();
        final deviceTimezoneOffset = now.timeZoneOffset.inMinutes;
        final backendTime = now.toUtc().add(Duration(minutes: deviceTimezoneOffset));
        DateTime selectedMonth = DateTime(backendTime.year, backendTime.month);
        Map<String, Set<String>> childIdToAbsentDates = {};

        Future<void> loadMonthData(DateTime month) async {
          if (_parentId == null) return;
          final firstDay = DateTime(month.year, month.month, 1);
          final lastDay = DateTime(month.year, month.month + 1, 0);
          final fromDate = '${firstDay.year}-${firstDay.month.toString().padLeft(2, '0')}-${firstDay.day.toString().padLeft(2, '0')}';
          final toDate = '${lastDay.year}-${lastDay.month.toString().padLeft(2, '0')}-${lastDay.day.toString().padLeft(2, '0')}';
          final reports = await ApiService.getParentDetailedReports(_parentId!, fromDate: fromDate, toDate: toDate);
          final absenceReports = reports['absence_reports'] as List<dynamic>? ?? [];
          final Map<String, Set<String>> map = {};
          for (final child in _children) {
            final childReports = absenceReports.where((r) => r['student_id'] == child.id);
            final dates = <String>{};
            for (final rep in childReports) {
              final list = rep['absence_dates'] as List<dynamic>? ?? [];
              for (final a in list) {
                final d = a['date']?.toString();
                if (d != null && d.isNotEmpty) dates.add(d);
              }
            }
            map[child.id] = dates;
          }
          childIdToAbsentDates = map;
        }

        return StatefulBuilder(
          builder: (context, setModalState) {
            return FutureBuilder<void>(
              future: loadMonthData(selectedMonth),
              builder: (context, snapshot) {
                final media = MediaQuery.of(context);
                return SafeArea(
                  child: Container(
                    constraints: BoxConstraints(maxHeight: media.size.height * 0.5),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.calendar_month, color: AppColors.secondary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${_monthName(selectedMonth)} ${selectedMonth.year}',
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF1F2937), letterSpacing: -0.3),
                              ),
                            ),
                            _headerIconButton(Icons.chevron_left, () async {
                              selectedMonth = DateTime(selectedMonth.year, selectedMonth.month - 1);
                              await loadMonthData(selectedMonth);
                              setModalState(() {});
                            }),
                            const SizedBox(width: 8),
                            _headerIconButton(Icons.chevron_right, () async {
                              selectedMonth = DateTime(selectedMonth.year, selectedMonth.month + 1);
                              await loadMonthData(selectedMonth);
                              setModalState(() {});
                            }),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              _LegendDot(color: AppColors.secondary, label: 'Present'),
                              SizedBox(width: 18),
                              _LegendDot(color: Color(0xFFEF4444), label: 'Absent'),
                              SizedBox(width: 18),
                              _LegendDot(color: Color(0xFFF59E0B), label: 'Holiday'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: snapshot.connectionState == ConnectionState.waiting
                              ? const Center(child: CircularProgressIndicator(color: AppColors.secondary))
                              : SingleChildScrollView(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (_children.isEmpty)
                                        const Padding(
                                          padding: EdgeInsets.all(8.0),
                                          child: Text('No children found.', style: TextStyle(color: Color(0xFF6B7280))),
                                        )
                                      else
                                        ..._children.map((child) {
                                          final absentDates = childIdToAbsentDates[child.id] ?? <String>{};
                                          // Using the month cell grid below; keep days via _monthCells
                                          return Container(
                                            margin: const EdgeInsets.only(bottom: 16.0),
                                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius: BorderRadius.circular(16),
                                              boxShadow: [
                                                BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4)),
                                              ],
                                            ),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  child.name.isNotEmpty ? child.name : 'Unknown Student',
                                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF1F2937), letterSpacing: -0.2),
                                                ),
                                                const SizedBox(height: 10),
                                                _WeekdayHeaders(),
                                                const SizedBox(height: 8),
                                                LayoutBuilder(
                                                  builder: (context, constraints) {
                                                    final cells = _calendarCells(selectedMonth);
                                                    return GridView.count(
                                                      crossAxisCount: 7,
                                                      mainAxisSpacing: 10,
                                                      crossAxisSpacing: 10,
                                                      childAspectRatio: 1.0, // Ensure square cells to prevent overflow
                                                      shrinkWrap: true,
                                                      physics: const NeverScrollableScrollPhysics(),
                                                      children: cells.map((CalendarCellDate cell) {
                                                        final d = cell.date;
                                                        final inMonth = cell.isCurrentMonth;
                                                        final dateStr = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
                                                        final isWeekend = _isWeekend(d);
                                                        final now = DateTime.now();
                                                        final deviceTimezoneOffset = now.timeZoneOffset.inMinutes;
                                                        final backendTime = now.toUtc().add(Duration(minutes: deviceTimezoneOffset));
                                                        final isToday = _isSameDay(d, backendTime);
                                                        CalendarStatus? status;
                                                        if (!inMonth) {
                                                          status = null; // no dot
                                                        } else if (isWeekend) {
                                                          status = CalendarStatus.holiday;
                                                        } else if (d.isAfter(backendTime)) {
                                                          status = null; // no dot for future days
                                                        } else if (absentDates.contains(dateStr)) {
                                                          status = CalendarStatus.absent;
                                                        } else {
                                                          status = CalendarStatus.present;
                                                        }
                                                        return _CalendarCell(
                                                          day: d.day,
                                                          inCurrentMonth: inMonth,
                                                          isToday: isToday,
                                                          status: status,
                                                        );
                                                      }).toList(),
                                                    );
                                                  },
                                                ),
                                              ],
                                            ),
                                          );
                                        }).toList(),
                                    ],
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // helper reserved for future use (intentionally unused)
  // ignore: unused_element
  List<DateTime> _allDaysOfMonth(DateTime month) { final last = DateTime(month.year, month.month + 1, 0); return List.generate(last.day, (i) => DateTime(month.year, month.month, i + 1)); }
  
  // Build a 7xN grid (previous month leading days + current + next) to align under headers
  List<CalendarCellDate> _calendarCells(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final last = DateTime(month.year, month.month + 1, 0);
    final startIndex = first.weekday % 7; // 0=Sun .. 6=Sat
    final totalDays = last.day;
    final List<CalendarCellDate> cells = [];
    // Leading days from previous month
    if (startIndex > 0) {
      final prevLast = DateTime(month.year, month.month, 0).day;
      for (int i = startIndex - 1; i >= 0; i--) {
        final day = prevLast - i;
        final d = DateTime(month.year, month.month - 1, day);
        cells.add(CalendarCellDate(d, false));
      }
    }
    // Current month days
    for (int d = 1; d <= totalDays; d++) {
      cells.add(CalendarCellDate(DateTime(month.year, month.month, d), true));
    }
    // Trailing days to complete the last week
    final remainder = cells.length % 7;
    if (remainder != 0) {
      final needed = 7 - remainder;
      for (int i = 1; i <= needed; i++) {
        cells.add(CalendarCellDate(DateTime(month.year, month.month + 1, i), false));
      }
    }
    return cells;
  }

  String _monthName(DateTime m) {
    const names = ['January','February','March','April','May','June','July','August','September','October','November','December'];
    return names[m.month - 1];
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  // ignore: unused_element
  bool _isSchoolDay(DateTime date) { final weekday = date.weekday % 7; return weekday >= 0 && weekday <= 4; }

  bool _isWeekend(DateTime date) {
    final weekday = date.weekday % 7;
    return weekday == 5 || weekday == 6; // Fri or Sat
  }

  Widget _headerIconButton(IconData icon, VoidCallback onPressed) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        icon: Icon(icon, color: AppColors.secondaryDark),
        onPressed: onPressed,
      ),
    );
  }

}

class _WeekdayHeaders extends StatelessWidget {
  const _WeekdayHeaders();

  @override
  Widget build(BuildContext context) {
    const days = ['SUN','MON','TUE','WED','THU','FRI','SAT'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: days.map((e) {
        final bool isWeekend = e == 'Fri' || e == 'Sat';
        return Expanded(
          child: Center(
            child: Text(
              e,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isWeekend ? const Color(0xFF94A3B8) : const Color(0xFF6B7280),
                letterSpacing: 0.2,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

enum CalendarStatus { present, absent, holiday }

class _CalendarCell extends StatelessWidget {
  final int day;
  final bool inCurrentMonth;
  final bool isToday;
  final CalendarStatus? status;
  const _CalendarCell({required this.day, required this.inCurrentMonth, required this.isToday, required this.status});

  @override
  Widget build(BuildContext context) {
    final Color numberColor = inCurrentMonth ? const Color(0xFF374151) : const Color(0xFFCBD5E1);
    final Color dotColor = switch (status) {
      CalendarStatus.present => AppColors.secondary,
      CalendarStatus.absent => const Color(0xFFEF4444),
      CalendarStatus.holiday => const Color(0xFFF59E0B),
      null => Colors.transparent,
    };

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 32, // Reduced from 34 to 32
          height: 32, // Reduced from 34 to 32
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isToday && status != null ? dotColor.withValues(alpha: 0.18) : Colors.transparent,
            border: isToday && status == null ? Border.all(color: const Color(0xFFF59E0B), width: 2) : null,
          ),
          child: Text(
            day.toString(),
            style: TextStyle(
              fontSize: 13, // Reduced from 14 to 13
              fontWeight: FontWeight.w700,
              color: isToday && status != null ? dotColor : numberColor,
            ),
          ),
        ),
        const SizedBox(height: 2), // Reduced from 4 to 2
        if (status != null)
          Container(
            width: 4, // Reduced from 6 to 4
            height: 4, // Reduced from 6 to 4
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
      ],
    );
  }
}

class CalendarCellDate {
  final DateTime date;
  final bool isCurrentMonth;
  CalendarCellDate(this.date, this.isCurrentMonth);
}

// Removed unused _WeeklyRowCalendar widget (replaced by monthly calendar)

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280), fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

