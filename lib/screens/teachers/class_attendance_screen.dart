import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../utils/responsive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/student.dart';
import '../../models/classroom.dart';
import '../../services/api_service.dart';
import '../../widgets/custom_button.dart';
import 'dart:async';

class ClassAttendanceScreen extends StatefulWidget {
  const ClassAttendanceScreen({super.key});

  @override
  State<ClassAttendanceScreen> createState() => _ClassAttendanceScreenState();
}

class _ClassAttendanceScreenState extends State<ClassAttendanceScreen>
    with TickerProviderStateMixin {
  MobileScannerController cameraController = MobileScannerController();
  bool _isLoading = false;
  bool _isScanning = false;
  String? _currentClassroom;
  String? _currentClassroomName;
  List<Student> _studentsInClass = [];
  Map<String, bool?> _attendanceStatus = {};
  String? _teacherToken;
  DateTime? _selfAttendanceExpiresAt;
  bool _studentSelfAttendanceEnabled = false;
  String _searchQuery = '';
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  Timer? _livePollTimer;
  final Map<String, DateTime> _highlightUntil = {};
  final Map<String, DateTime> _lastSeenStudentRecord = {};
  final Map<String, DateTime> _presentAt = {};

  String _formatTime12(DateTime dt) {
    final local = dt.toLocal();
    final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final min = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour < 12 ? 'AM' : 'PM';
    return '$hour12:$min $ampm';
  }

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
    cameraController.dispose();
    _livePollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadTeacherToken() async {
    final prefs = await SharedPreferences.getInstance();
    _teacherToken = prefs.getString('teacher_token');
  }

  Future<void> _processQRCode(String qrCode) async {
    if (_isLoading) return;
    
    setState(() => _isLoading = true);
    
    try {
      // Debug: Show the actual QR code being scanned
      print('DEBUG: Scanned QR code: "$qrCode"');
      
      // Check for classroom QR codes (various formats)
      if (qrCode.startsWith('CLASS_') || qrCode.startsWith('CLASS:')) {
        await _handleClassroomQR(qrCode);
      } 
      // Check for student QR codes (various formats)
      else if (qrCode.startsWith('STUDENT_') || qrCode.startsWith('STUDENT:')) {
        await _handleStudentQR(qrCode);
      } 
      // Try to handle legacy formats or other patterns
      else if (qrCode.contains('CLASS') || qrCode.contains('STUDENT')) {
        if (qrCode.contains('CLASS')) {
          await _handleClassroomQR(qrCode);
        } else if (qrCode.contains('STUDENT')) {
          await _handleStudentQR(qrCode);
        }
      } else {
        _showSnackBar('Invalid QR code format: $qrCode', isError: true);
      }
    } catch (e) {
      _showSnackBar('Error: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleClassroomQR(String qrCode) async {
    setState(() {
      _currentClassroom = qrCode;
      _isScanning = false;
    });

    if (_teacherToken != null) {
      try {
        String className;
        
        // Parse different QR code formats
        if (qrCode.startsWith('CLASS:')) {
          // Format: CLASS:Class 1|TEACHER:Ms. Sarah Johnson|CAPACITY:25
          final parts = qrCode.split('|');
          className = parts[0].replaceFirst('CLASS:', '');
        } else if (qrCode.startsWith('CLASS_')) {
          // Format: CLASS_001 or CLASS_TEST_CLASS_1
          className = qrCode.replaceFirst('CLASS_', '');
        } else {
          // Fallback: try to extract class name from any format
          className = qrCode;
        }
        
        setState(() {
          _currentClassroomName = className;
        });
        
        // Get all classrooms and try multiple matching strategies
        final classrooms = await ApiService.getClassrooms(_teacherToken!);
        // Exclude the test class from matching
        final filteredClassrooms = classrooms.where((c) => c.name.toLowerCase() != 'test class 1').toList();

        Classroom matchingClassroom = filteredClassrooms.firstWhere(
          (c) => c.qrCode == qrCode,
          orElse: () => Classroom(id: '', name: 'Unknown', qrCode: '', createdAt: DateTime.now(), updatedAt: DateTime.now()),
        );

        if (matchingClassroom.name == 'Unknown') {
          // Normalize common formats: CLASS_3 -> Class 3, case-insensitive compare
          String normalized = className
              .replaceAll('_', ' ')
              .replaceAll('-', ' ')
              .trim();
          // Also try Title Case for common pattern
          final titleNormalized = normalized.isEmpty
              ? normalized
              : normalized[0].toUpperCase() + normalized.substring(1).toLowerCase();

          matchingClassroom = filteredClassrooms.firstWhere(
            (c) => c.name.toLowerCase() == className.toLowerCase()
                || c.name.toLowerCase() == normalized.toLowerCase()
                || c.name.toLowerCase() == titleNormalized.toLowerCase(),
            orElse: () => Classroom(id: '', name: 'Unknown', qrCode: '', createdAt: DateTime.now(), updatedAt: DateTime.now()),
          );
        }
        
        if (matchingClassroom.name == 'Unknown') {
          _showSnackBar('Classroom not found: $className', isError: true);
          return;
        }
        
        // Update _currentClassroom to use the actual classroom QR code from database
        setState(() {
          _currentClassroom = matchingClassroom.qrCode;
          _currentClassroomName = matchingClassroom.name; // ensure display uses canonical name
        });
        
        // Get students and filter by classroom ID instead of name for robustness
        final students = await ApiService.getStudents(_teacherToken!);
        final studentsInClass = students.where((s) => s.classroomId == matchingClassroom.id).toList();
        
        setState(() {
          _studentsInClass = studentsInClass;
          _attendanceStatus.clear();
          for (var student in studentsInClass) {
            _attendanceStatus[student.id] = null; // neutral at start
          }
        });
        // Do not start polling until teacher enables self-attendance

        _showSnackBar('Classroom detected: $className (${studentsInClass.length} students)');
      } catch (e) {
        _showSnackBar('Error fetching students: $e', isError: true);
      }
    }
  }

  Future<void> _handleStudentQR(String qrCode) async {
    if (_currentClassroom == null) {
      _showSnackBar('Please scan classroom QR code first', isError: false, isWarning: true);
      return;
    }

    String studentName;
    
    // Parse different student QR code formats
    if (qrCode.startsWith('STUDENT:')) {
      // Format: STUDENT:John Doe|CLASS:Class 1
      final parts = qrCode.split('|');
      studentName = parts[0].replaceFirst('STUDENT:', '');
    } else if (qrCode.startsWith('STUDENT_')) {
      // Format: STUDENT_ahmed_ali or STUDENT_FATIMA_HASSAN_ce4d7da5
      studentName = qrCode.replaceFirst('STUDENT_', '').split('_').take(2).join(' ');
    } else {
      // Fallback
      studentName = qrCode;
    }
    
    // Try to find the student in the current class
    final student = _studentsInClass.firstWhere(
      (s) => s.name.toLowerCase() == studentName.toLowerCase(),
      orElse: () => Student(
        id: '',
        name: studentName,
        qrCode: qrCode,
        classroomId: '',
        classroomName: _currentClassroomName ?? '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    if (student.id.isNotEmpty) {
      setState(() {
        _attendanceStatus[student.id] = true;
        _isScanning = false; // Stop scanning after successful scan
      });
      _showSnackBar('$studentName marked as present (late arrival)');
    } else {
      _showSnackBar('Student $studentName not found in current class', isError: true);
    }
  }

  void _markPresent(String studentId) {
    setState(() {
      _attendanceStatus[studentId] = true;
      _presentAt[studentId] = DateTime.now();
    });
  }

  void _markAbsent(String studentId) {
    setState(() {
      _attendanceStatus[studentId] = false;
    });
  }

  void _markNeutral(String studentId) {
    setState(() {
      _attendanceStatus[studentId] = null;
    });
  }

  void _markAllPresent() {
    setState(() {
      for (var student in _studentsInClass) {
        _attendanceStatus[student.id] = true;
      }
    });
  }

  void _markAllAbsent() {
    setState(() {
      for (var student in _studentsInClass) {
        _attendanceStatus[student.id] = false;
      }
    });
  }

  Future<void> _submitAttendance() async {
    if (_teacherToken == null || _currentClassroom == null) return;

    setState(() => _isLoading = true);

    try {
      int presentCount = 0;
      int absentCount = 0;
      List<String> absentStudentIds = [];
      
      for (var student in _studentsInClass) {
        final isPresent = _attendanceStatus[student.id] == true;
        await ApiService.markAttendance(
          student.qrCode,
          _currentClassroom!,
          _teacherToken!,
          isPresent: isPresent,
        );
        if (isPresent) {
          presentCount++;
        } else {
          absentCount++;
          absentStudentIds.add(student.id);
        }
      }

      // Send daily absence notifications to parents (not reports)
      if (absentStudentIds.isNotEmpty) {
        try {
          await ApiService.sendDailyAbsenceNotifications(
            _teacherToken!,
            absentStudentIds: absentStudentIds,
            classroomName: _currentClassroomName ?? 'Unknown Class',
            date: DateTime.now().toIso8601String().split('T')[0], // YYYY-MM-DD format
          );
        } catch (e) {
          print('Error sending daily absence notifications: $e');
          // Don't fail the entire attendance submission if notifications fail
        }
      }

      _showSnackBar('Attendance submitted successfully! Present: $presentCount, Absent: $absentCount. Parents will be notified of absences.');
      
      // Navigate to teacher home page after successful submission
      await Future.delayed(const Duration(seconds: 1)); // Small delay to show success message
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/teacher',
          (route) => false,
        );
      }
    } catch (e) {
      _showSnackBar('Error submitting attendance: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _resetForNextClass() {
    setState(() {
      _currentClassroom = null;
      _currentClassroomName = null;
      _studentsInClass.clear();
      _attendanceStatus.clear();
      _studentSelfAttendanceEnabled = false;
      _selfAttendanceExpiresAt = null;
      _searchQuery = '';
    });
  }

  List<Student> get _filteredStudents {
    if (_searchQuery.isEmpty) return _studentsInClass;
    return _studentsInClass.where((student) =>
        student.name.toLowerCase().contains(_searchQuery.toLowerCase())
    ).toList();
  }

  Future<void> _toggleStudentSelfAttendance() async {
    if (_teacherToken == null || _currentClassroom == null) return;

    try {
      setState(() => _isLoading = true);
      
      if (!_studentSelfAttendanceEnabled) {
        // Enable student self-attendance
        final resp = await ApiService.openSelfAttendanceWindow(
          classQr: _currentClassroom!,
          token: _teacherToken!,
          minutes: 10,
        );
        final expiresIso = resp['expires_at'] as String?;
        if (expiresIso != null) {
          setState(() {
            _selfAttendanceExpiresAt = DateTime.tryParse(expiresIso);
            _studentSelfAttendanceEnabled = true;
          });
        }
        _showSnackBar('Students can now record attendance for 10 minutes');
        _startLivePolling();
      } else {
        // Disable student self-attendance: close the window via backend
        await ApiService.closeSelfAttendanceWindow(
          classQr: _currentClassroom!,
          token: _teacherToken!,
        );
        setState(() {
          _studentSelfAttendanceEnabled = false;
          _selfAttendanceExpiresAt = null;
        });
        _showSnackBar('Student self-attendance disabled');
        _livePollTimer?.cancel();
      }
    } catch (e) {
      _showSnackBar('Failed to toggle student recording: $e', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _startLivePolling() {
    _livePollTimer?.cancel();
    if (_teacherToken == null || _currentClassroom == null) return;
    // Do an immediate fetch so UI updates right after a student records
    _fetchLiveOnce();
    _livePollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      _fetchLiveOnce();
    });
  }

  Future<void> _fetchLiveOnce() async {
    try {
      if (_teacherToken == null || _currentClassroom == null) return;
      final data = await ApiService.getLiveClassAttendance(token: _teacherToken!, classQr: _currentClassroom!);
      final List<dynamic> records = (data['records'] as List?) ?? [];
      final now = DateTime.now();
      if (!mounted) return;
      setState(() {
        for (final rec in records) {
          final studentId = rec['student_id']?.toString() ?? '';
          if (studentId.isEmpty) continue;
          final tsStr = rec['timestamp']?.toString();
          final recTs = tsStr != null ? DateTime.tryParse(tsStr) : null;
          final lastTs = _lastSeenStudentRecord[studentId];
          // Only apply if new (prevents repeat highlighting/updates)
          if (recTs == null || lastTs == null || recTs.isAfter(lastTs)) {
            _attendanceStatus[studentId] = true;
            _highlightUntil[studentId] = now.add(const Duration(seconds: 8));
            if (recTs != null) {
              _presentAt[studentId] = recTs.toLocal();
            } else {
              _presentAt[studentId] = now;
            }
            if (recTs != null) {
              _lastSeenStudentRecord[studentId] = recTs;
            }
          }
        }
      });
    } catch (_) {
      // ignore
    }
  }

  Future<void> _manualRefresh() async {
    if (_isLoading) return;
    await _fetchLiveOnce();
    _showSnackBar('Refreshed');
  }

  bool _isRecentlyUpdated(String studentId) {
    final until = _highlightUntil[studentId];
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  void _showSnackBar(String message, {bool isError = false, bool isWarning = false}) {
    Color backgroundColor;
    if (isError) {
      backgroundColor = const Color(0xFFEF4444);
    } else if (isWarning) {
      backgroundColor = const Color(0xFFF59E0B);
    } else {
      backgroundColor = const Color(0xFF10B981);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
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
              _buildAppBar(),
              Expanded(
                child: SingleChildScrollView(
                  padding: Responsive.pagePadding(context),
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: Responsive.maxContentWidth(context),
                          ),
                          child: Column(
                            children: [
                          if (_currentClassroom == null) ...[
                            _buildQRScannerSection(),
                          ] else ...[
                            _buildClassInfoSection(),
                            const SizedBox(height: 24),
                            _buildBulkActionsSection(),
                            const SizedBox(height: 24),
                            _buildStudentsListSection(),
                            const SizedBox(height: 24),
                            _buildSubmitSection(),
                          ],
                            ],
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

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(32),
          bottomRight: Radius.circular(32),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withOpacity(0.3),
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
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.arrow_back,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Class Attendance',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Text(
                  _currentClassroomName ?? 'Scan classroom QR code to start',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Refresh',
            child: IconButton(
              onPressed: (_currentClassroom == null) ? null : _manualRefresh,
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.refresh,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQRScannerSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF8B5CF6), Color(0xFFA855F7)],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8B5CF6).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 2,
              ),
            ),
            child: const Icon(
              Icons.qr_code_scanner,
              size: 48,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Scan Classroom QR Code',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Start by scanning the classroom QR code to see all students',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: Colors.white.withOpacity(0.9),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          Container(
            height: 300,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: MobileScanner(
                controller: cameraController,
                fit: BoxFit.contain,
                onDetect: (capture) {
                  final List<Barcode> barcodes = capture.barcodes;
                  for (final barcode in barcodes) {
                    _processQRCode(barcode.rawValue ?? '');
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClassInfoSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.class_,
              color: Color(0xFF6366F1),
              size: 32,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentClassroomName ?? '',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 8),
                if (_currentClassroom != null) ...[
                  Text(
                    'QR: ${_currentClassroom!}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  '${_studentsInClass.length} students',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _resetForNextClass,
            icon: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.close,
                color: Colors.red,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBulkActionsSection() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'Bulk Actions',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: CustomButton(
                  text: 'Present',
                  icon: Icons.check_circle,
                  onPressed: _markAllPresent,
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  height: 50,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CustomButton(
                  text: 'Absent',
                  icon: Icons.cancel,
                  onPressed: _markAllAbsent,
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  height: 50,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              children: [
                const Icon(Icons.how_to_reg, color: Color(0xFF6366F1)),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Allow student self-attendance',
                    style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1F2937)),
                  ),
                ),
                Switch.adaptive(
                  value: _studentSelfAttendanceEnabled,
                  onChanged: (_currentClassroom == null || _isLoading)
                      ? null
                      : (_) => _toggleStudentSelfAttendance(),
                  activeColor: const Color(0xFF10B981),
                ),
              ],
            ),
          ),
          if (_studentSelfAttendanceEnabled && _selfAttendanceExpiresAt != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF10B981).withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Students can record attendance until: ${_formatTime12(_selfAttendanceExpiresAt!)}',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF10B981), fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStudentsListSection() {
    final filteredStudents = _filteredStudents;
    final presentCount = _attendanceStatus.values.where((v) => v == true).length;
    final totalCount = _studentsInClass.length;
    // Compute late students based on current session arrivals
    final List<MapEntry<String, DateTime>> presentEntries = _presentAt.entries.where((e) => _attendanceStatus[e.key] == true).toList();
    presentEntries.sort((a,b) => a.value.compareTo(b.value));
    DateTime? earliest = presentEntries.isNotEmpty ? presentEntries.first.value : null;
    final lateIds = <String>{};
    if (earliest != null) {
      for (final e in presentEntries) {
        if (e.value.isAfter(earliest.add(const Duration(minutes: 5)))) {
          lateIds.add(e.key);
        }
      }
    }
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.people,
                color: Color(0xFF6366F1),
                size: 24,
              ),
              const SizedBox(width: 12),
              const Text(
                'Students',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2937),
                ),
              ),
              const Spacer(),
              Text(
                '$presentCount/$totalCount Present',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (lateIds.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.schedule, color: Color(0xFFF59E0B), size: 16),
                    const SizedBox(width: 8),
                    Text('Late: ${lateIds.length}', style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _studentsInClass.where((s) => lateIds.contains(s.id)).map((s) {
                final t = _presentAt[s.id];
                final timeStr = t != null ? _formatTime12(t) : '';
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFF59E0B).withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.person, size: 14, color: Color(0xFFF59E0B)),
                      const SizedBox(width: 6),
                      Text(s.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF92400E))),
                      if (timeStr.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(timeStr, style: const TextStyle(fontSize: 12, color: Color(0xFF92400E), fontWeight: FontWeight.w600)),
                      ]
                    ],
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
          // Search Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: TextField(
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: const InputDecoration(
                hintText: 'Search students by name...',
                border: InputBorder.none,
                prefixIcon: Icon(Icons.search, color: Color(0xFF6366F1)),
                contentPadding: EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildStudentScanner(),
          const SizedBox(height: 16),
          // Student Status Legend
          Row(
            children: [
              _buildStatusLegend('Not Marked', const Color(0xFF9CA3AF), Icons.radio_button_unchecked),
              const SizedBox(width: 16),
              _buildStatusLegend('Present', const Color(0xFF10B981), Icons.check_circle),
              const SizedBox(width: 16),
              _buildStatusLegend('Absent', const Color(0xFFEF4444), Icons.cancel),
            ],
          ),
          const SizedBox(height: 16),
          // Students List
          ...(filteredStudents.map((student) => _buildStudentItem(student))),
          if (filteredStudents.isEmpty && _searchQuery.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(
              'No students found matching "$_searchQuery"',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusLegend(String label, Color color, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }


  Widget _buildStudentScanner() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.qr_code_scanner,
                color: Color(0xFF6366F1),
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Scan individual student QR codes to mark late arrivals',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ),
              CustomButton(
                text: _isScanning ? 'Stop' : 'Start',
                icon: _isScanning ? Icons.stop : Icons.play_arrow,
                onPressed: () {
                  setState(() {
                    _isScanning = !_isScanning;
                  });
                },
                backgroundColor: _isScanning ? Colors.red : const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                height: 36,
              ),
            ],
          ),
        ),
        if (_isScanning) ...[
          const SizedBox(height: 16),
          Container(
            height: 200,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF6366F1), width: 2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: MobileScanner(
                controller: cameraController,
                fit: BoxFit.contain,
                onDetect: (capture) {
                  final List<Barcode> barcodes = capture.barcodes;
                  for (final barcode in barcodes) {
                    _processQRCode(barcode.rawValue ?? '');
                  }
                },
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStudentItem(Student student) {
    final attendanceStatus = _attendanceStatus[student.id];
    final isPresent = attendanceStatus == true;
    final isAbsent = attendanceStatus == false;
    final recent = _isRecentlyUpdated(student.id);
    
    Color backgroundColor;
    Color borderColor;
    Color iconColor;
    Color textColor;
    IconData icon;
    
    if (isPresent) {
      backgroundColor = const Color(0xFFF0FDF4);
      borderColor = const Color(0xFF10B981);
      iconColor = const Color(0xFF10B981);
      textColor = const Color(0xFF10B981);
      icon = Icons.check_circle;
    } else if (isAbsent) {
      backgroundColor = const Color(0xFFFEF2F2);
      borderColor = const Color(0xFFEF4444);
      iconColor = const Color(0xFFEF4444);
      textColor = const Color(0xFFEF4444);
      icon = Icons.cancel;
    } else {
      // Neutral state (not yet marked)
      backgroundColor = const Color(0xFFF9FAFB);
      borderColor = const Color(0xFF9CA3AF);
      iconColor = const Color(0xFF9CA3AF);
      textColor = const Color(0xFF6B7280);
      icon = Icons.radio_button_unchecked;
    }
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: recent ? const Color(0xFF22C55E) : borderColor, width: recent ? 2 : 1),
        boxShadow: recent
            ? [
                BoxShadow(
                  color: const Color(0xFF22C55E).withOpacity(0.25),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                )
              ]
            : [],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                if (isPresent) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Present',
                    style: TextStyle(
                      fontSize: 12,
                      color: textColor.withOpacity(0.7),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ] else if (isAbsent) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Absent',
                    style: TextStyle(
                      fontSize: 12,
                      color: textColor.withOpacity(0.7),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 2),
                  Text(
                    'Not marked',
                    style: TextStyle(
                      fontSize: 12,
                      color: textColor.withOpacity(0.7),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Attendance control as sliding segmented (Absent / Not marked / Present)
          SizedBox(
            width: 180,
            child: CupertinoSlidingSegmentedControl<int>(
              padding: const EdgeInsets.all(2),
              groupValue: isPresent ? 1 : (isAbsent ? -1 : 0),
              children: {
                -1: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.close, size: 16, color: Color(0xFFEF4444)),
                    ],
                  ),
                ),
                0: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.radio_button_unchecked, size: 16, color: Color(0xFF9CA3AF)),
                    ],
                  ),
                ),
                1: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.check, size: 16, color: Color(0xFF10B981)),
                    ],
                  ),
                ),
              },
              onValueChanged: (int? value) {
                if (value == null) return;
                if (value == 1) {
                  _markPresent(student.id);
                } else if (value == -1) {
                  _markAbsent(student.id);
                } else {
                  _markNeutral(student.id);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitSection() {
    final presentCount = _attendanceStatus.values.where((v) => v == true).length;
    final absentCount = _attendanceStatus.values.where((v) => v == false).length;
    final markedCount = presentCount + absentCount;
    final attendanceRate = markedCount > 0 ? ((presentCount / markedCount) * 100).round() : 0;
    
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Summary Metrics Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildCircularProgressIndicator(
                'Present',
                presentCount.toString(),
                markedCount > 0 ? (presentCount / markedCount) : 0.0,
                const Color(0xFF10B981),
              ),
              _buildCircularProgressIndicator(
                'Absent',
                absentCount.toString(),
                markedCount > 0 ? (absentCount / markedCount) : 0.0,
                const Color(0xFFEF4444),
              ),
              _buildCircularProgressIndicator(
                'Rate',
                '$attendanceRate%',
                attendanceRate / 100.0,
                const Color(0xFF6B46C1),
              ),
            ],
          ),
          const SizedBox(height: 24),
          CustomButton(
            text: 'Submit Attendance',
            icon: Icons.send,
            onPressed: _isLoading ? null : _submitAttendance,
            backgroundColor: const Color(0xFF6B46C1),
            foregroundColor: Colors.white,
            height: 56,
          ),
        ],
      ),
    );
  }
  
  Widget _buildCircularProgressIndicator(String label, String value, double progress, Color color) {
    return Column(
      children: [
        SizedBox(
          width: 60,
          height: 60,
          child: Stack(
            children: [
              // Background circle
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withOpacity(0.1),
                ),
              ),
              // Progress circle
              SizedBox(
                width: 60,
                height: 60,
                child: CircularProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  strokeWidth: 6,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
              // Center text
              Center(
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF374151),
          ),
        ),
      ],
    );
  }
}
