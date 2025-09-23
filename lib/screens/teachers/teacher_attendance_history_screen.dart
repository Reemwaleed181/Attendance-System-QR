import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../services/api_service.dart';
import '../../constants/app_colors.dart';

class TeacherAttendanceHistoryScreen extends StatefulWidget {
  const TeacherAttendanceHistoryScreen({super.key});

  @override
  State<TeacherAttendanceHistoryScreen> createState() => _TeacherAttendanceHistoryScreenState();
}

class _TeacherAttendanceHistoryScreenState extends State<TeacherAttendanceHistoryScreen>
    with TickerProviderStateMixin {
  String? _teacherToken;
  Map<String, dynamic>? _attendanceData;
  bool _isLoading = true;
  // Holds total student count per classroom (keyed by classroomId)
  Map<String, int> _classroomStudentCounts = {};
  // Maps classroomId -> classroomName for display
  Map<String, String> _classroomIdToName = {};
  // Holds total student count per classroom name (for records that only provide names)
  Map<String, int> _classroomNameCounts = {};
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  DateTime _currentDate = DateTime.now();

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
    _loadTeacherToken();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  // Helper to format date consistently for API communication
  String _formatDateForApi(DateTime date) {
    return date.toIso8601String().split('T')[0];
  }
  
  // Helper to get device timezone info
  String _getDeviceTimezoneInfo() {
    final now = DateTime.now();
    final offset = now.timeZoneOffset;
    final offsetHours = offset.inHours;
    final offsetMinutes = offset.inMinutes % 60;
    final sign = offsetHours >= 0 ? '+' : '-';
    return 'Local Time: ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} (UTC${sign}${offsetHours.abs().toString().padLeft(2, '0')}:${offsetMinutes.toString().padLeft(2, '0')})';
  }

  // Helpers to normalize/extract ids, names and timestamps safely
  String _extractClassroomId(Map<String, dynamic> record) {
    try {
      if (record['classroom_id'] != null) return record['classroom_id'].toString();
      if (record['classroom'] is String) return record['classroom'];
      if (record['classroom'] is Map) return (record['classroom']['id'] ?? 'Unknown').toString();
      if (record['classroom'] != null) return record['classroom'].toString();
    } catch (_) {}
    return 'Unknown';
  }

  String _extractClassroomName(Map<String, dynamic> record) {
    try {
      if (record['classroom_name'] != null) return record['classroom_name'].toString();
      if (record['classroom'] is Map) return (record['classroom']['name'] ?? 'Unknown').toString();
      if (record['classroom'] is String) return record['classroom'];
    } catch (_) {}
    return 'Unknown';
  }

  String _extractStudentId(Map<String, dynamic> record) {
    try {
      if (record['student_id'] != null) return record['student_id'].toString();
      if (record['student'] is String) return record['student'];
      if (record['student'] is Map) return (record['student']['id'] ?? '').toString();
      if (record['student_id'] == null && record['student'] != null) return record['student'].toString();
    } catch (_) {}
    return 'unknown';
  }

  DateTime _parseTimestamp(Map<String, dynamic> record) {
    try {
      if (record['timestamp'] is String) {
        // Parse the timestamp and ensure it's in local timezone
        final parsed = DateTime.parse(record['timestamp']);
        // Always convert to local timezone for display
        return parsed.toLocal();
      }
      if (record['timestamp'] is Map) {
        final m = record['timestamp'] as Map<String, dynamic>;
        final v = (m['date'] ?? m['timestamp'] ?? '') as String;
        if (v.isNotEmpty) {
          final parsed = DateTime.parse(v);
          return parsed.toLocal();
        }
      }
    } catch (e) {
      print('Error parsing timestamp: $e');
    }
    return DateTime.now();
  }

  int _computeClassSize(String classroomId, Map<String, Map<String, dynamic>> latestByStudent) {
    // Prefer authoritative count from students list if available
    final int? knownCount = _classroomStudentCounts[classroomId];
    if (knownCount != null && knownCount > 0) return knownCount;

    // Fallback: number of unique students we saw today by name (handles dup IDs)
    final Set<String> uniqueNames = {};
    for (final rec in latestByStudent.values) {
      try {
        String name = 'unknown';
        if (rec['student_name'] != null) name = rec['student_name'].toString();
        else if (rec['student'] is Map) name = (rec['student']['name'] ?? 'unknown').toString();
        else if (rec['student'] is String) name = rec['student'];
        uniqueNames.add(name.trim().toLowerCase());
      } catch (_) {}
    }
    return uniqueNames.isNotEmpty ? uniqueNames.length : latestByStudent.length;
  }

  int _computeDisplayClassSize(String classroomId, String classroomName, Map<String, Map<String, dynamic>> latestByStudent) {
    // Try by ID first
    final int? byId = _classroomStudentCounts[classroomId];
    if (byId != null && byId > 0) return byId;
    // Then by name (for data sources keyed by name only)
    final int? byName = _classroomNameCounts[classroomName];
    if (byName != null && byName > 0) return byName;
    // Fallback to deduped count from today's records
    return _computeClassSize(classroomId, latestByStudent);
  }

  Future<void> _loadTeacherToken() async {
    final prefs = await SharedPreferences.getInstance();
    _teacherToken = prefs.getString('teacher_token');
    if (_teacherToken != null) {
      // Load attendance and classroom counts in parallel
      _loadClassroomCounts();
      await _loadAttendanceHistory();
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadAttendanceHistory() async {
    if (_teacherToken == null) return;
    
    setState(() => _isLoading = true);
    
    try {
      final data = await ApiService.getTeacherAttendanceHistory(_teacherToken!);
      setState(() {
        _attendanceData = data;
        _isLoading = false;
        
        // Always set current date to today regardless of attendance data
        _currentDate = DateTime.now();
      });
    } catch (e) {
      print('Error loading attendance history: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading attendance history: $e'),
            backgroundColor: Colors.red.shade400,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  Future<void> _loadClassroomCounts() async {
    if (_teacherToken == null) return;
    try {
      final students = await ApiService.getStudents(_teacherToken!);
      final Map<String, int> counts = {};
      final Map<String, String> idToName = {};
      final Map<String, int> nameCounts = {};
      for (final student in students) {
        try {
          final String classroomId = (student as dynamic).classroomId?.toString() ?? 'Unknown';
          final String classroomName = ((student as dynamic).classroomName as String?) ?? 'Unknown';
          counts[classroomId] = (counts[classroomId] ?? 0) + 1;
          if (!idToName.containsKey(classroomId) && classroomName.isNotEmpty) {
            idToName[classroomId] = classroomName;
          }
          if (classroomName.isNotEmpty) {
            nameCounts[classroomName] = (nameCounts[classroomName] ?? 0) + 1;
          }
        } catch (_) {
          counts['Unknown'] = (counts['Unknown'] ?? 0) + 1;
        }
      }
      if (mounted) {
        setState(() {
          _classroomStudentCounts = counts;
          _classroomIdToName = idToName;
          _classroomNameCounts = nameCounts;
        });
      }
    } catch (e) {
      // Non-blocking: just log
      print('Error loading classroom counts: $e');
    }
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
              Color(0xFFE0E7FF),
              Color(0xFFDDD6FE),
              Color(0xFFC4B5FD),
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
                    colors: AppColors.accentGradient,
                  ),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(32),
                    bottomRight: Radius.circular(32),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.3),
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
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.history,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                          Text(
                            'Attendance History',
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
                              'View your attendance records',
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
                      onPressed: _loadAttendanceHistory,
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.refresh,
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
                          color: AppColors.accent,
                        ),
                      )
                    : FadeTransition(
                        opacity: _fadeAnimation,
                        child: SlideTransition(
                          position: _slideAnimation,
                          child: RefreshIndicator(
                            onRefresh: _loadAttendanceHistory,
                            color: AppColors.accent,
                            child: SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(24.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (_attendanceData == null)
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
                                              color: AppColors.accent.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: const Icon(
                                              Icons.history_outlined,
                                              size: 48,
                                              color: AppColors.accent,
                                            ),
                                          ),
                                          const SizedBox(height: 20),
                        const Text(
                                            'No Attendance Data',
                          style: TextStyle(
                            fontSize: 20,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF1F2937),
                          ),
                                            textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                                          Text(
                                            'No attendance records found for your account',
                                  style: TextStyle(
                                    fontSize: 16,
                                              fontWeight: FontWeight.w500,
                                              color: const Color(0xFF6B7280),
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    )
                                  else ...[
                                    // Summary card
                                    Container(
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
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(12),
                                                decoration: BoxDecoration(
                                                  gradient: const LinearGradient(
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                    colors: [
                                                      AppColors.accent,
                                                      Color(0xFF8B5CF6),
                                                    ],
                                                  ),
                                                  borderRadius: BorderRadius.circular(16),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: AppColors.accent.withValues(alpha: 0.3),
                                                      blurRadius: 10,
                                                      offset: const Offset(0, 4),
                                                    ),
                                                  ],
                                                ),
                                                child: const Icon(
                                                  Icons.assessment,
                                                  color: Colors.white,
                                                  size: 28,
                                                ),
                                              ),
                                              const SizedBox(width: 20),
                                              const Text(
                                                'Summary',
                                                style: TextStyle(
                                                  fontSize: 24,
                                                  fontWeight: FontWeight.w800,
                                                  color: Color(0xFF1F2937),
                                                  letterSpacing: -0.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 20),
                                          // Summary content
                                          _buildSummaryContent(),
                      ],
                    ),
                  ),
                                    
                                    const SizedBox(height: 24),
                                    
                                    // Attendance records
                                    Container(
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
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(12),
                                                decoration: BoxDecoration(
                                                  gradient: const LinearGradient(
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                    colors: [
                                                      Color(0xFF10B981),
                                                      Color(0xFF059669),
                                                    ],
                                                  ),
                                                  borderRadius: BorderRadius.circular(16),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: const Color(0xFF10B981).withValues(alpha: 0.3),
                                                      blurRadius: 10,
                                                      offset: const Offset(0, 4),
                                                    ),
                                                  ],
                                                ),
                                                child: const Icon(
                                                  Icons.list_alt,
                                                  color: Colors.white,
                                                  size: 28,
                                                ),
                                              ),
                                              const SizedBox(width: 20),
                                              Text(
                                                '${_currentDate.day}/${_currentDate.month}/${_currentDate.year} Records',
                                                style: const TextStyle(
                                                  fontSize: 24,
                                                  fontWeight: FontWeight.w800,
                                                  color: Color(0xFF1F2937),
                                                  letterSpacing: -0.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 20),
                                          // Attendance records
                                          _buildAttendanceRecords(),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
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
  
  Widget _buildSummaryContent() {
    if (_attendanceData == null) return const SizedBox.shrink();
    
    // Calculate attendance for the selected day (use local date)
    final selectedDateKey = _formatDateForApi(_currentDate);
    
    double attendanceRate = 0.0;
    double absenceRate = 0.0;
    
    try {
      final attendanceByDate = _attendanceData!['attendance_by_date'] as Map<String, dynamic>? ?? {};
      
      if (attendanceByDate.containsKey(selectedDateKey)) {
        final records = attendanceByDate[selectedDateKey] as List<dynamic>;
        if (records.isNotEmpty) {
          int presentCount = 0;
          int totalCount = records.length;
          
          for (final record in records) {
            if (record is Map<String, dynamic>) {
              final isPresent = record['is_present'] ?? false;
              if (isPresent) {
                presentCount++;
              }
            }
          }
          
          attendanceRate = totalCount > 0 ? (presentCount / totalCount * 100) : 0.0;
          absenceRate = totalCount > 0 ? ((totalCount - presentCount) / totalCount * 100) : 0.0;
        }
      }
      
      // For both current and historical dates, show data for the selected day only
      // The percentages are already calculated above for the selected date
    } catch (e) {
      print('Error calculating daily attendance: $e');
    }
    
    return Column(
      children: [
        // Date and Weekly Status Card
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
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
              // Date Display
              GestureDetector(
                onTap: _showDatePicker,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          '${_currentDate.day}',
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF6B46C1),
                            letterSpacing: -1,
                          ),
                        ),
                        Text(
                          _getOrdinalSuffix(_currentDate.day),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6B46C1),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _getDayName(_currentDate.weekday),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6B46C1),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getMonthYear(_currentDate),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
              
              // This week status
              const Text(
                'This week status',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF374151),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Weekly status indicators
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: _buildWeeklyStatusIndicators(),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 20),
        
        // Summary Metrics Card
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildCircularProgressIndicator(
                'Attendance',
                '${attendanceRate.toStringAsFixed(1)}%',
                attendanceRate / 100.0,
                const Color(0xFF10B981),
              ),
              _buildCircularProgressIndicator(
                'Absence',
                '${absenceRate.toStringAsFixed(1)}%',
                absenceRate / 100.0,
                const Color(0xFFEF4444),
              ),
            ],
          ),
        ),
        
      ],
    );
  }
  
  Widget _buildWeekDayIndicator(String day, bool? isPresent, DateTime dayDate) {
    Color backgroundColor;
    bool isSelected = isSameDay(_currentDate, dayDate);
    
    if (isSelected) {
      // Selected day - purple background
      backgroundColor = const Color(0xFF6B46C1);
    } else {
      // All other days - light gray background
      backgroundColor = const Color(0xFFE5E7EB);
    }
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _currentDate = dayDate;
        });
      },
      child: Column(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: backgroundColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: backgroundColor.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
              border: isSelected 
                  ? Border.all(
                      color: Colors.white,
                      width: 3,
                    )
                  : null,
            ),
            child: Center(
              child: Text(
                day,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isSelected 
                      ? Colors.white
                      : const Color(0xFF374151),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            day,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isSelected 
                  ? const Color(0xFF6B46C1)
                  : const Color(0xFF374151),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildCircularProgressIndicator(String label, String value, double progress, Color color) {
    return Column(
      children: [
        SizedBox(
          width: 80,
          height: 80,
          child: Stack(
            children: [
              // Background circle
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withValues(alpha: 0.1),
                ),
              ),
              // Progress circle
              SizedBox(
                width: 80,
                height: 80,
                child: CircularProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  strokeWidth: 8,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
              // Center text
              Center(
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF374151),
          ),
        ),
      ],
    );
  }
  
  String _getDayName(int weekday) {
    switch (weekday) {
      case 1: return 'Monday';
      case 2: return 'Tuesday';
      case 3: return 'Wednesday';
      case 4: return 'Thursday';
      case 5: return 'Friday';
      case 6: return 'Saturday';
      case 7: return 'Sunday';
      default: return 'Unknown';
    }
  }
  
  String _getMonthYear(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[date.month - 1]} ${date.year}';
  }
  
  
  Widget _buildAttendanceRecords() {
    if (_attendanceData == null) return const SizedBox.shrink();
    
    // Safely extract attendance data
    Map<String, dynamic> attendanceByDate = {};
    try {
      final data = _attendanceData!['attendance_by_date'];
      if (data is Map<String, dynamic>) {
        attendanceByDate = data;
      }
    } catch (e) {
      print('Error extracting attendance data: $e');
    }
    
    if (attendanceByDate.isEmpty) {
      return const Text(
        'No attendance records found',
        style: TextStyle(
          fontSize: 16,
          color: Color(0xFF6B7280),
        ),
        textAlign: TextAlign.center,
      );
    }
    
    // Get records for the selected date (use local date)
    final selectedDateKey = _formatDateForApi(_currentDate);
    final recordsToShow = attendanceByDate[selectedDateKey] as List<dynamic>? ?? [];
    
    if (recordsToShow.isEmpty) {
      return const Text(
        'No attendance records for this date',
        style: TextStyle(
          fontSize: 16,
          color: Color(0xFF6B7280),
        ),
        textAlign: TextAlign.center,
      );
    }
    
    // Group records by classroomId for better organization
    Map<String, List<Map<String, dynamic>>> recordsByClassroomId = {};
    for (final record in recordsToShow) {
      if (record is Map<String, dynamic>) {
        final String classroomId = _extractClassroomId(record);
        (recordsByClassroomId[classroomId] ??= []).add(record);
      }
    }
    
    return Column(
      children: [
        // Records Section (Today's or Historical)
        ...recordsByClassroomId.entries.map((classroomEntry) {
          final classroomId = classroomEntry.key;
          final records = classroomEntry.value;
          // Determine display name
          final String classroomName = _classroomIdToName[classroomId] 
              ?? (records.isNotEmpty ? _extractClassroomName(records.first) : 'Unknown');
        
        // Deduplicate by student using the latest record timestamp
        final Map<String, Map<String, dynamic>> latestByStudent = {};
        for (final rec in records) {
          final String studentId = _extractStudentId(rec);
          final DateTime ts = _parseTimestamp(rec);
          final existing = latestByStudent[studentId];
          if (existing == null || ts.isAfter(_parseTimestamp(existing))) {
            latestByStudent[studentId] = rec;
          }
        }

        // Separate students by status for this classroom using relative arrival time
        List<Map<String, dynamic>> presentStudents = [];
        List<Map<String, dynamic>> absentStudents = [];
        List<Map<String, dynamic>> lateStudents = [];

        // Compute earliest present timestamp among present students
        DateTime? earliestPresent;
        for (final rec in latestByStudent.values) {
          final bool isPresent = rec['is_present'] ?? false;
          if (isPresent) {
            final ts = _parseTimestamp(rec).toLocal();
            if (earliestPresent == null || ts.isBefore(earliestPresent)) {
              earliestPresent = ts;
            }
          }
        }

        // Consider a student late if they arrive more than 5 minutes after the earliest student
        // or after 8:00 AM (assuming school starts at 8:00 AM)
        const lateSkew = Duration(minutes: 5);
        final schoolStartTime = DateTime(earliestPresent?.year ?? DateTime.now().year, 
                                       earliestPresent?.month ?? DateTime.now().month, 
                                       earliestPresent?.day ?? DateTime.now().day, 8, 0);
        for (final rec in latestByStudent.values) {
          final bool isPresent = rec['is_present'] ?? false;
          if (isPresent) {
            final ts = _parseTimestamp(rec).toLocal();
            // Check if student is late based on either:
            // 1. More than 5 minutes after the earliest student, OR
            // 2. After 8:00 AM school start time
            bool isLate = false;
            if (earliestPresent != null && ts.isAfter(earliestPresent.add(lateSkew))) {
              isLate = true;
            } else if (ts.isAfter(schoolStartTime)) {
              isLate = true;
            }
            
            if (isLate) {
              lateStudents.add(rec);
            } else {
              presentStudents.add(rec);
            }
          } else {
            absentStudents.add(rec);
          }
        }
        
        return Container(
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFF8FAFC),
                Color(0xFFF1F5F9),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFE2E8F0),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.05),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Enhanced Classroom Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.accent,
                      Color(0xFF8B5CF6),
                    ],
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.class_,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            classroomName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Text(
                            '${_currentDate.day}/${_currentDate.month}/${_currentDate.year} Summary - ${presentStudents.length} on time, ${lateStudents.length} late, ${absentStudents.length} absent',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withValues(alpha: 0.9),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _getDeviceTimezoneInfo(),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.7),
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.list_alt,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${_computeDisplayClassSize(classroomId, classroomName, latestByStudent)} students',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              // All Present Summary
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF10B981),
                      Color(0xFF059669),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                      spreadRadius: 0,
                    ),
                    BoxShadow(
                      color: const Color(0xFF10B981).withValues(alpha: 0.1),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.check_circle_rounded,
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
                            'All Present!',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${presentStudents.length} students were on time',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${presentStudents.length}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Absent Students Section
              if (absentStudents.isNotEmpty) ...[
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFEF4444),
                        Color(0xFFDC2626),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                        spreadRadius: 0,
                      ),
                      BoxShadow(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.cancel_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Absent Students',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${absentStudents.length}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: absentStudents.map((record) {
                          String studentName = 'Unknown';
                          try {
                            if (record['student_name'] != null) {
                              studentName = record['student_name'].toString();
                            } else if (record['student'] is Map) {
                              studentName = record['student']['name'] ?? 'Unknown';
                            } else if (record['student'] is String) {
                              studentName = record['student'];
                            }
                          } catch (e) {
                            print('Error extracting student name: $e');
                          }
                          
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(25),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.person_rounded,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  studentName,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              // Late Students Section
              if (lateStudents.isNotEmpty) ...[
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFF59E0B),
                        Color(0xFFD97706),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                        spreadRadius: 0,
                      ),
                      BoxShadow(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.schedule_rounded,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Late Students',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '${lateStudents.length}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      ...lateStudents.map((record) {
                        String studentName = 'Unknown';
                        String arrivalTime = '';
                        try {
                          if (record['student_name'] != null) {
                            studentName = record['student_name'].toString();
                          } else if (record['student'] is Map) {
                            studentName = record['student']['name'] ?? 'Unknown';
                          } else if (record['student'] is String) {
                            studentName = record['student'];
                          }
                          
                          if (record['timestamp'] is String) {
                            final timestamp = DateTime.parse(record['timestamp']).toLocal();
                            arrivalTime = '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')} Local';
                          }
                        } catch (e) {
                          print('Error extracting student data: $e');
                        }
                        
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.person_rounded,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      studentName,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Arrived at $arrivalTime',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white.withValues(alpha: 0.8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  arrivalTime.split(' ')[0], // Just the time part
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ],
          ),
        );
      }).toList(),
      
      // No previous days section - just show selected day records
    ] 
    );
  }
  
  
  
  String _getOrdinalSuffix(int day) {
    if (day >= 11 && day <= 13) {
      return 'th';
    }
    switch (day % 10) {
      case 1: return 'st';
      case 2: return 'nd';
      case 3: return 'rd';
      default: return 'th';
    }
  }
  
  
  void _showDatePicker() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 600),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                // Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF6B46C1),
                            Color(0xFF8B5CF6),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.calendar_month,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        'Select Date',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.close,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Calendar
                SizedBox(
                  height: 350,
                  child: TableCalendar<String>(
                    firstDay: DateTime.utc(2020, 1, 1),
                    lastDay: DateTime.utc(2030, 12, 31),
                    focusedDay: _currentDate,
                    calendarFormat: CalendarFormat.month,
                    eventLoader: _getEventsForDay,
                    startingDayOfWeek: StartingDayOfWeek.sunday,
                    calendarStyle: CalendarStyle(
                      outsideDaysVisible: false,
                      weekendTextStyle: const TextStyle(
                        color: Color(0xFF6B46C1),
                        fontWeight: FontWeight.w600,
                      ),
                      defaultTextStyle: const TextStyle(
                        color: Color(0xFF374151),
                        fontWeight: FontWeight.w600,
                      ),
                      selectedTextStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                      todayTextStyle: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                      selectedDecoration: BoxDecoration(
                        color: const Color(0xFF6B46C1),
                        shape: BoxShape.circle,
                      ),
                      todayDecoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6),
                        shape: BoxShape.circle,
                      ),
                      markerDecoration: BoxDecoration(
                        color: const Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                      markersMaxCount: 1,
                      markerSize: 6,
                    ),
                    headerStyle: const HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                      titleTextStyle: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F2937),
                      ),
                      leftChevronIcon: Icon(
                        Icons.chevron_left,
                        color: Color(0xFF6B46C1),
                        size: 24,
                      ),
                      rightChevronIcon: Icon(
                        Icons.chevron_right,
                        color: Color(0xFF6B46C1),
                        size: 24,
                      ),
                    ),
                    onDaySelected: (selectedDay, focusedDay) {
                      setState(() {
                        _currentDate = selectedDay;
                      });
                      Navigator.of(context).pop();
                    },
                    selectedDayPredicate: (day) {
                      return isSameDay(_currentDate, day);
                    },
                  ),
                ),
                const SizedBox(height: 16),
                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: Color(0xFFE5E7EB)),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6B46C1),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Select',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
  
  List<Widget> _buildWeeklyStatusIndicators() {
    // Get the current week's Sunday (weekday 7 in Dart) - not based on selected date
    final now = DateTime.now();
    final currentWeekStart = now.subtract(Duration(days: now.weekday == 7 ? 0 : now.weekday));
    
    // Get attendance data for this week
    Map<String, dynamic> attendanceByDate = {};
    if (_attendanceData != null) {
      try {
        final data = _attendanceData!['attendance_by_date'];
        if (data is Map<String, dynamic>) {
          attendanceByDate = data;
        }
      } catch (e) {
        print('Error extracting attendance data: $e');
      }
    }
    
    List<Widget> indicators = [];
    List<String> dayNames = ['Su', 'M', 'T', 'W', 'Th'];
    
    for (int i = 0; i < 5; i++) {
      final dayDate = currentWeekStart.add(Duration(days: i));
      final dateKey = _formatDateForApi(dayDate);
      
      bool? dayStatus;
      
      if (attendanceByDate.containsKey(dateKey)) {
        final records = attendanceByDate[dateKey] as List<dynamic>;
        if (records.isNotEmpty) {
          // Calculate attendance percentage for this day
          int presentCount = 0;
          int totalCount = records.length;
          
          for (final record in records) {
            if (record is Map<String, dynamic>) {
              final isPresent = record['is_present'] ?? false;
              if (isPresent) {
                presentCount++;
              }
            }
          }
          
          // Determine status based on attendance percentage
          if (totalCount > 0) {
            double attendanceRate = presentCount / totalCount;
            if (attendanceRate >= 0.5) {
              dayStatus = true; // More than 50% present
            } else {
              dayStatus = false; // Less than 50% present
            }
          }
        }
      } else {
        // No records for this day
        if (dayDate.isBefore(DateTime.now().subtract(const Duration(days: 1)))) {
          // Past day with no records - consider absent
          dayStatus = false;
        } else if (dayDate.isAfter(DateTime.now())) {
          // Future day - show as pending
          dayStatus = null;
        } else {
          // Today with no records - show as pending
          dayStatus = null;
        }
      }
      
      indicators.add(_buildWeekDayIndicator(dayNames[i], dayStatus, dayDate));
    }
    
    return indicators;
  }
  
  
  List<String> _getEventsForDay(DateTime day) {
    if (_attendanceData == null) return [];
    
    Map<String, dynamic> attendanceByDate = {};
    try {
      final data = _attendanceData!['attendance_by_date'];
      if (data is Map<String, dynamic>) {
        attendanceByDate = data;
      }
    } catch (e) {
      return [];
    }
    
    final dateKey = _formatDateForApi(day);
    if (attendanceByDate.containsKey(dateKey)) {
      final records = attendanceByDate[dateKey] as List<dynamic>;
      if (records.isNotEmpty) {
        return ['attendance'];
      }
    }
    
    return [];
  }
  
}
