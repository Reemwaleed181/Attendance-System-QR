import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../widgets/custom_button.dart';
import '../utils/responsive.dart';

class WebQRScannerScreen extends StatefulWidget {
  const WebQRScannerScreen({super.key});

  @override
  State<WebQRScannerScreen> createState() => _WebQRScannerScreenState();
}

class _WebQRScannerScreenState extends State<WebQRScannerScreen>
    with TickerProviderStateMixin {
  MobileScannerController cameraController = MobileScannerController();
  bool _isLoading = false;
  String? _currentClassroom;
  String? _currentStudent;
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
      // Check if it's a classroom QR code (various formats)
      if (qrCode.startsWith('CLASS_') || qrCode.startsWith('CLASS:') || qrCode.contains('CLASS')) {
        setState(() {
          _currentClassroom = qrCode;
          _currentStudent = null;
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Classroom detected: $qrCode'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
      // Check if it's a student QR code (various formats)
      else if (qrCode.startsWith('STUDENT_') || qrCode.startsWith('STUDENT:') || qrCode.contains('STUDENT')) {
        if (_currentClassroom == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Please scan classroom QR code first'),
            backgroundColor: const Color(0xFFF59E0B),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
          return;
        }
        
        // Mark attendance
        if (_teacherToken != null) {
          final response = await ApiService.markAttendance(
            qrCode,
            _currentClassroom!,
            _teacherToken!,
          );
          
          setState(() {
            _currentStudent = qrCode;
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response['message'] ?? 'Attendance marked successfully'),
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Invalid QR code format'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: const Color(0xFFEF4444),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    } finally {
      setState(() => _isLoading = false);
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
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                Container(
                      padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.qr_code_scanner,
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
                            'Web QR Scanner',
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
                               'Use your web camera to scan QR codes',
                               style: const TextStyle(
                        fontSize: 16,
                                 fontWeight: FontWeight.w500,
                                 color: Colors.white,
                      ),
                    ),
                           ),
                        ],
                  ),
                ),
              ],
            ),
          ),
          
              // Main Content
          Expanded(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: SingleChildScrollView(
                      padding: Responsive.pagePadding(context),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: Responsive.maxContentWidth(context),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                          // Current Status Card
                          if (_currentClassroom != null || _currentStudent != null)
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.05),
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
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF6366F1).withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: const Icon(
                                          Icons.info_outline,
                                          color: Color(0xFF6366F1),
                                          size: 24,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      const Text(
                                        'Current Status',
                                        style: TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF1F2937),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 20),
                                  if (_currentClassroom != null)
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10B981).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: const Color(0xFF10B981).withOpacity(0.3),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.class_,
                                            color: Color(0xFF10B981),
                                            size: 24,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  'Classroom',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                    color: Color(0xFF10B981),
                                                  ),
                                                ),
                                                Text(
                                                  _currentClassroom!,
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w700,
                                                    color: Color(0xFF1F2937),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  if (_currentClassroom != null && _currentStudent != null)
                                    const SizedBox(height: 12),
                                  if (_currentStudent != null)
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF3B82F6).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: const Color(0xFF3B82F6).withOpacity(0.3),
                                        ),
                                      ),
                                      child: Row(
                      children: [
                                          const Icon(
                                            Icons.person,
                                            color: Color(0xFF3B82F6),
                                            size: 24,
                                          ),
                                          const SizedBox(width: 12),
                        Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  'Student',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w600,
                                                    color: Color(0xFF3B82F6),
                                                  ),
                                                ),
                                                Text(
                                                  _currentStudent!,
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w700,
                                                    color: Color(0xFF1F2937),
                          ),
                        ),
                      ],
                    ),
                                          ),
                                        ],
                          ),
                        ),
                      ],
                              ),
                            ),
                          if (_currentClassroom != null || _currentStudent != null)
                            const SizedBox(height: 24),
                          
                          // Scanner Instructions
                          Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                              ),
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF6366F1).withOpacity(0.3),
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
                                Text(
                                  'Web Camera Instructions',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                  textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                                Text(
                                  '1. Allow camera access when prompted\n2. First scan a classroom QR code\n3. Then scan student QR codes to mark attendance',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                          
                          const SizedBox(height: 24),
                          
                          // Camera View
                          Container(
                            height: 400,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 20,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: Stack(
                                children: [
                                  MobileScanner(
                                    controller: cameraController,
                                    onDetect: (capture) {
                                      final List<Barcode> barcodes = capture.barcodes;
                                      for (final barcode in barcodes) {
                                        _processQRCode(barcode.rawValue ?? '');
                                      }
                                    },
                                  ),
                                  // Scanner overlay
                                  Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: const Color(0xFF6366F1),
                                        width: 3,
                                      ),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    margin: const EdgeInsets.all(40),
                                  ),
                                  // Corner indicators
                                  Positioned(
                                    top: 40,
                                    left: 40,
                                    child: Container(
                                      width: 20,
                                      height: 20,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF6366F1),
                                        borderRadius: BorderRadius.only(
                                          topLeft: Radius.circular(4),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 40,
                                    right: 40,
                                    child: Container(
                                      width: 20,
                                      height: 20,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF6366F1),
                                        borderRadius: BorderRadius.only(
                                          topRight: Radius.circular(4),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 40,
                                    left: 40,
                                    child: Container(
                                      width: 20,
                                      height: 20,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF6366F1),
                                        borderRadius: BorderRadius.only(
                                          bottomLeft: Radius.circular(4),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 40,
                                    right: 40,
                                    child: Container(
                                      width: 20,
                                      height: 20,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF6366F1),
                                        borderRadius: BorderRadius.only(
                                          bottomRight: Radius.circular(4),
                                        ),
                        ),
                      ),
                    ),
                  ],
                              ),
                            ),
                          ),
                          
                          const SizedBox(height: 24),
                          
                          // Control Buttons
                          Row(
                            children: [
                              Expanded(
                                child: CustomButton(
                                  text: 'Toggle Flash',
                                  icon: Icons.flash_on,
                                  onPressed: () => cameraController.toggleTorch(),
                                  backgroundColor: const Color(0xFF6B7280),
                                  foregroundColor: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: CustomButton(
                                  text: 'Switch Camera',
                                  icon: Icons.flip_camera_ios,
                                  onPressed: () => cameraController.switchCamera(),
                                  backgroundColor: const Color(0xFF6366F1),
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
              ),
            ),
          ),
                ))],
          ),
        ),
      ),
    );
  }
}
