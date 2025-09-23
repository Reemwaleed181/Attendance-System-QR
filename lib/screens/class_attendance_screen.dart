import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/student.dart';
import '../models/classroom.dart';
import '../services/api_service.dart';
import '../widgets/custom_button.dart';

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
  Map<String, bool> _attendanceStatus = {};
  String? _teacherToken;
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
    _loadTeacherToken();
  }

  @override
  void dispose() {
    _animationController.dispose();
    cameraController.dispose();
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
            _attendanceStatus[student.id] = true;
          }
        });

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

  void _toggleStudentAttendance(String studentId) {
    setState(() {
      _attendanceStatus[studentId] = !(_attendanceStatus[studentId] ?? false);
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
        final isPresent = _attendanceStatus[student.id] ?? false;
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
    });
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
                  padding: const EdgeInsets.all(24),
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: SlideTransition(
                      position: _slideAnimation,
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
                  text: 'Mark All Present',
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
                  text: 'Mark All Absent',
                  icon: Icons.cancel,
                  onPressed: _markAllAbsent,
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  height: 50,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStudentsListSection() {
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
                '${_attendanceStatus.values.where((present) => present).length}/${_studentsInClass.length} Present',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildStudentScanner(),
          const SizedBox(height: 16),
          ...(_studentsInClass.map((student) => _buildStudentItem(student))),
        ],
      ),
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
                    fontSize: 14,
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
    final isPresent = _attendanceStatus[student.id] ?? false;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isPresent ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPresent ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isPresent ? const Color(0xFF10B981) : const Color(0xFFEF4444),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isPresent ? Icons.check : Icons.close,
              color: Colors.white,
              size: 16,
            ),
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
                    color: isPresent ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                  ),
                ),
                Text(
                  'ID: ${student.id}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: isPresent,
            onChanged: (value) => _toggleStudentAttendance(student.id),
            activeColor: const Color(0xFF10B981),
            inactiveThumbColor: const Color(0xFFEF4444),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitSection() {
    final presentCount = _attendanceStatus.values.where((present) => present).length;
    final totalCount = _studentsInClass.length;
    final absentCount = totalCount - presentCount;
    final attendanceRate = totalCount > 0 ? (presentCount / totalCount * 100).round() : 0;
    
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
                presentCount / totalCount,
                const Color(0xFF10B981),
              ),
              _buildCircularProgressIndicator(
                'Absent',
                absentCount.toString(),
                absentCount / totalCount,
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
