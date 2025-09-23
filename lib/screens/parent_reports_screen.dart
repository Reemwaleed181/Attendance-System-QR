import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../constants/app_colors.dart';

class ParentReportsScreen extends StatefulWidget {
  const ParentReportsScreen({super.key});

  @override
  State<ParentReportsScreen> createState() => _ParentReportsScreenState();
}

class _ParentReportsScreenState extends State<ParentReportsScreen>
    with TickerProviderStateMixin {
  // State variables
  String? _parentId;
  Map<String, dynamic> _reportsData = {};
  bool _isLoading = true;
  bool _hasError = false;
  String? _errorMessage;
  
  // Animation controllers
  late AnimationController _mainAnimationController;
  late AnimationController _cardAnimationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Constants
  static const Duration _animationDuration = Duration(milliseconds: 1200);
  static const Duration _cardAnimationDuration = Duration(milliseconds: 300);
  static const double _cardSpacing = 24.0;
  static const double _borderRadius = 28.0;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadParentData();
  }

  void _initializeAnimations() {
    _mainAnimationController = AnimationController(
      duration: _animationDuration,
      vsync: this,
    );

    _cardAnimationController = AnimationController(
      duration: _cardAnimationDuration,
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _mainAnimationController, curve: Curves.easeOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3), 
      end: Offset.zero
    ).animate(
      CurvedAnimation(
        parent: _mainAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );


    _mainAnimationController.forward();
  }

  @override
  void dispose() {
    _mainAnimationController.dispose();
    _cardAnimationController.dispose();
    super.dispose();
  }

  Future<void> _loadParentData() async {
    try {
    final prefs = await SharedPreferences.getInstance();
    _parentId = prefs.getString('parent_id');

      if (_parentId == null) {
        _setErrorState('Parent ID not found. Please log in again.');
        return;
      }

          await _loadReportsData();
      } catch (e) {
      _setErrorState('Error loading parent data: $e');
    }
  }

  Future<void> _loadReportsData() async {
    if (_parentId == null) return;
    
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = null;
    });
    
    try {
      final dateRange = _getCurrentWeekDateRange();
      final data = await ApiService.getParentDetailedReports(
        _parentId!,
        fromDate: dateRange['from'],
        toDate: dateRange['to'],
      );
      
      setState(() {
        _reportsData = data;
        _isLoading = false;
      });
      
      _cardAnimationController.forward();
    } catch (e) {
      _setErrorState('Error loading reports: $e');
    }
  }

  void _setErrorState(String message) {
    setState(() {
      _isLoading = false;
      _hasError = true;
      _errorMessage = message;
    });
  }

  Map<String, String> _getCurrentWeekDateRange() {
    final now = DateTime.now();
    // Calculate start of week (Sunday) - consistent with weekly stats
    // weekday returns 1=Monday, 2=Tuesday, ..., 7=Sunday
    // We need to go back to the previous Sunday
    final daysSinceSunday = (now.weekday % 7); // 0=Sunday, 1=Monday, ..., 6=Saturday
    final startOfWeek = now.subtract(Duration(days: daysSinceSunday));
    // End of week is Thursday (4 days after Sunday) - consistent with weekly stats
    final endOfWeek = startOfWeek.add(const Duration(days: 4));
    
    return {
      'from': '${startOfWeek.year}-${startOfWeek.month.toString().padLeft(2, '0')}-${startOfWeek.day.toString().padLeft(2, '0')}',
      'to': '${endOfWeek.year}-${endOfWeek.month.toString().padLeft(2, '0')}-${endOfWeek.day.toString().padLeft(2, '0')}',
    };
  }

  String _formatAbsenceDateTime(Map<String, dynamic> absence) {
    try {
      // Try to parse the date and time from the absence record
      final dateStr = absence['date']?.toString() ?? '';
      final timeStr = absence['time']?.toString() ?? '';
      
      if (dateStr.isNotEmpty && timeStr.isNotEmpty) {
        // Parse the date and time, assuming they're in UTC from the backend
        final dateTimeStr = '${dateStr}T${timeStr}Z'; // Add Z to indicate UTC
        final utcDateTime = DateTime.parse(dateTimeStr);
        final localDateTime = utcDateTime.toLocal();
        
        // Format as "Sep. 23, 2024, 12:57 AM" (matching backend format)
        final months = ['Jan.', 'Feb.', 'Mar.', 'Apr.', 'May', 'Jun.',
                       'Jul.', 'Aug.', 'Sep.', 'Oct.', 'Nov.', 'Dec.'];
        final month = months[localDateTime.month - 1];
        final day = localDateTime.day;
        final year = localDateTime.year;
        final hour = localDateTime.hour;
        final minute = localDateTime.minute;
        
        // Convert to 12-hour format
        final period = hour >= 12 ? 'PM' : 'AM';
        final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
        final displayMinute = minute.toString().padLeft(2, '0');
        
        return '$month $day, $year, $displayHour:$displayMinute $period';
      }
    } catch (e) {
      print('Error formatting absence date/time: $e');
    }
    
    // Fallback to original format if parsing fails
    return '${absence['date']} at ${absence['time']}';
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AppColors.secondaryGradient,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(child: _buildMainContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Column(
                  children: [
                    Row(
                      children: [
              _buildHeaderButton(
                icon: Icons.arrow_back_ios_new_rounded,
                            onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 16),
                        Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                              const Text(
                                'Teacher Reports',
                            style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                              color: Colors.white,
                                  letterSpacing: -0.8,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'Detailed reports sent by teachers',
                              style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
              _buildHeaderButton(
                icon: Icons.refresh_rounded,
                onPressed: _loadReportsData,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Container(
                        decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _buildMainContent() {
    return Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(32),
                      topRight: Radius.circular(32),
                    ),
                  ),
                  child: _isLoading
          ? _buildLoadingState()
          : _hasError
              ? _buildErrorState()
              : _buildReportsContent(),
    );
  }

  Widget _buildLoadingState() {
    return Center(
                                    child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(20),
                                          decoration: BoxDecoration(
                                            color: AppColors.secondary.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                child: const CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.secondary),
                                  strokeWidth: 3,
                                ),
                              ),
                              const SizedBox(height: 16),
                                        const Text(
                                'Loading teacher reports...',
                                          style: TextStyle(
                                            fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                            color: Color(0xFF6B7280),
                                          ),
                                        ),
                                      ],
                                    ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_borderRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
              ),
            ],
          ),
              child: const Icon(
                Icons.error_outline_rounded,
                size: 56,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Something went wrong',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1F2937),
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Unable to load reports',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFDC2626),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage ?? 'An unexpected error occurred',
              style: const TextStyle(
                fontSize: 16,
                color: Color(0xFF6B7280),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadReportsData,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportsContent() {
    if (_reportsData.isEmpty) {
      return _buildEmptyState();
    }

    return _buildReportsData();
  }

  Widget _buildEmptyState() {
    return Center(
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SlideTransition(
          position: _slideAnimation,
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(_borderRadius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
      children: [
        Container(
                  padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: AppColors.secondaryGradient,
                    ),
                    borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppColors.secondary.withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                ),
                child: const Icon(
                    Icons.check_circle_rounded,
                    size: 56,
                  color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                    const Text(
                  'Excellent Attendance!',
                      style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1F2937),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1FAE5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'No teacher reports this week',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF065F46),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'No detailed reports have been sent by teachers this week. All children are doing well!',
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFF6B7280),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReportsData() {
    final absenceReports = _reportsData['absence_reports'] as List<dynamic>? ?? [];
    final message = _reportsData['message'] as String?;
    
    if (absenceReports.isEmpty && message != null) {
      return _buildNoAbsencesMessage(message);
    }
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: absenceReports.asMap().entries.map((entry) {
          final index = entry.key;
          final absenceReport = entry.value;
          return _buildAbsenceReportCard(absenceReport, index);
        }).toList(),
      ),
    );
  }

  Widget _buildAbsenceReportCard(Map<String, dynamic> absenceReport, int index) {
          return TweenAnimationBuilder<double>(
            duration: Duration(milliseconds: 300 + (index * 100)),
            tween: Tween(begin: 0.0, end: 1.0),
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, 20 * (1 - value)),
                child: Opacity(
                  opacity: value,
                  child: Container(
              margin: const EdgeInsets.only(bottom: _cardSpacing),
                    decoration: BoxDecoration(
                      color: Colors.white,
                borderRadius: BorderRadius.circular(_borderRadius),
                      boxShadow: [
                BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        ),
                        BoxShadow(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                  _buildStudentHeader(absenceReport),
                  const SizedBox(height: 20),
                  _buildWarningMessage(absenceReport),
                  const SizedBox(height: 20),
                  if (_hasAbsenceDates(absenceReport)) ...[
                    _buildAbsenceDates(absenceReport),
                    const SizedBox(height: 20),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStudentHeader(Map<String, dynamic> absenceReport) {
    return Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                const Color(0xFFEF4444).withValues(alpha: 0.1),
                                const Color(0xFFFEE2E2).withValues(alpha: 0.8),
                              ],
                            ),
                            borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(_borderRadius),
          topRight: Radius.circular(_borderRadius),
                            ),
                          ),
                          child: Row(
                            children: [
          _buildStudentAvatar(),
                              const SizedBox(width: 20),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      absenceReport['student_name'] ?? 'Unknown Student',
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                    color: Color(0xFF1F2937),
                                        letterSpacing: -0.5,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Text(
                                        'Class: ${absenceReport['classroom_name'] ?? 'Unknown'}',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFFDC2626),
                                        ),
                                      ),
                ),
              ],
            ),
                              ),
          _buildAbsenceCountBadge(absenceReport),
        ],
      ),
    );
  }

  Widget _buildStudentAvatar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEF4444).withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Icon(
        Icons.person_rounded,
        color: Colors.white,
        size: 28,
      ),
    );
  }

  Widget _buildAbsenceCountBadge(Map<String, dynamic> absenceReport) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEF4444).withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            '${absenceReport['absent_days'] ?? 0}',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Absent Days',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningMessage(Map<String, dynamic> absenceReport) {
    return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Color(0xFFFEF3C7),
                                Color(0xFFFDE68A),
            Color(0xFFFCD34D),
                              ],
                            ),
        borderRadius: BorderRadius.circular(24),
                            border: Border.all(
          color:  Colors.transparent,
                              width: 2,
                            ),
            boxShadow: [
              BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          // Header with warning icon and title
              Row(
                children: [
                  Container(
                padding: const EdgeInsets.all(12),
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
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                    ),
                    child: const Icon(
                                      Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                                  const Text(
                                    'Teacher Warning',
                                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                                      color: Color(0xFF92400E),
                        letterSpacing: -0.5,
                                    ),
                                  ),
                    const SizedBox(height: 4),
                              Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                        color: const Color(0xFF92400E).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                      child: const Text(
                        'Attendance Alert',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                                    color: Color(0xFF92400E),
                                  ),
                    ),
                  ),
                ],
                          ),
                        ),
            ],
          ),
                        const SizedBox(height: 20),
                        
          // Warning message content
                        Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                colors: [
                  Colors.white,
                  Color(0xFFFEFBF3),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  absenceReport['warning_message'] ?? 'No warning message available',
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF92400E),
                    height: 1.6,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                
                // Teacher information section - simple format
                Row(
                  children: [
                    Icon(
                      Icons.person_rounded,
                      color: const Color(0xFF92400E).withValues(alpha: 0.7),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Reported by: ',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF92400E).withValues(alpha: 0.8),
                      ),
                    ),
                    Text(
                      absenceReport['teacher_name'] ?? 'Unknown Teacher',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF92400E),
                    ),
                  ),
                ],
                          ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  bool _hasAbsenceDates(Map<String, dynamic> absenceReport) {
    final absenceDates = absenceReport['absence_dates'];
    return absenceDates != null && (absenceDates as List).isNotEmpty;
  }

  Widget _buildAbsenceDates(Map<String, dynamic> absenceReport) {
    return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                                        color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.calendar_today_rounded,
                                        color: Color(0xFFEF4444),
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    const Text(
                                      'Absence Dates',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF1F2937),
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                ...(absenceReport['absence_dates'] as List).asMap().entries.map<Widget>((entry) {
                                  final index = entry.key;
                                  final absence = entry.value;
            return _buildAbsenceDateItem(absence, index);
          }),
        ],
      ),
    );
  }

  Widget _buildAbsenceDateItem(Map<String, dynamic> absence, int index) {
                                  return TweenAnimationBuilder<double>(
                                    duration: Duration(milliseconds: 200 + (index * 50)),
                                    tween: Tween(begin: 0.0, end: 1.0),
                                    builder: (context, value, child) {
                                      return Transform.scale(
                                        scale: 0.8 + (0.2 * value),
                                        child: Opacity(
                                          opacity: value,
                                          child: Container(
                                            margin: const EdgeInsets.only(bottom: 12),
                                            padding: const EdgeInsets.all(16),
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                  colors: [Color(0xFFFEF2F2), Color(0xFFFEE2E2)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                                              border: Border.all(
                                                color: const Color(0xFFFECACA).withValues(alpha: 0.5),
                                                width: 1,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: const Color(0xFFEF4444).withValues(alpha: 0.05),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                ),
                child: Row(
                  children: [
                    Container(
                                                  padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                                                    color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                                                    borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                                                    Icons.event_rounded,
                                                    color: Color(0xFFEF4444),
                                                    size: 18,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                                                      Text(
                                                        _formatAbsenceDateTime(absence),
                                                        style: const TextStyle(
                                                          fontSize: 15,
                                                          color: Color(0xFF991B1B),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                                                      const SizedBox(height: 2),
                          Text(
                                                        'Teacher: ${absence['teacher'] ?? 'Unknown'}',
                            style: const TextStyle(
                                                          fontSize: 13,
                                                          color: Color(0xFF6B7280),
                                                          fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
                                        ),
                                      );
                                    },
    );
  }

  Widget _buildNoAbsencesMessage(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
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
              Icons.check_circle_outline,
              color: AppColors.secondary,
              size: 48,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Great News!',
            style: TextStyle(
              fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F2937),
                      ),
                    ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
                        color: Color(0xFF6B7280),
              height: 1.5,
                    ),
                  ),
                ],
      ),
    );
  }
}