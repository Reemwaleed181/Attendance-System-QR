import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../constants/app_colors.dart';
import '../../utils/location_service.dart';
import '../../utils/responsive.dart';
import '../../services/api_service.dart';

class StudentAttendanceRequestScreen extends StatefulWidget {
  const StudentAttendanceRequestScreen({super.key});

  @override
  State<StudentAttendanceRequestScreen> createState() =>
      _StudentAttendanceRequestScreenState();
}

class _StudentAttendanceRequestScreenState
    extends State<StudentAttendanceRequestScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  // method selection removed; GPS used automatically

  final _studentQrController = TextEditingController();
  final _classQrController = TextEditingController();
  final MobileScannerController _scannerController = MobileScannerController();
  String? _studentName;
  String? _className;
  double? _lat;
  double? _lng;
  bool _attendanceEnabled = false;
  DateTime? _windowExpiresAt;
  bool _submitted = false;
  Timer? _statusTimer;

  @override
  void dispose() {
    _statusTimer?.cancel();
    _studentQrController.dispose();
    _classQrController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadStudentData();
    _loadLocation();
    _startStatusPolling();
  }

  Future<void> _loadStudentData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _studentName = prefs.getString('student_name');
      _className = prefs.getString('student_class_name');
      _studentQrController.text = prefs.getString('student_qr') ?? '';
      _classQrController.text = prefs.getString('student_class_qr') ?? '';
    });
  }

  Future<void> _loadLocation() async {
    final pos = await LocationService.getCurrentPosition();
    if (!mounted) return;
    setState(() {
      _lat = pos?.latitude;
      _lng = pos?.longitude;
    });
  }

  void _startStatusPolling() {
    _statusTimer?.cancel();
    // Poll less frequently and stop once enabled
    _statusTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final studentToken = prefs.getString('student_token') ?? '';
        final classQr = _classQrController.text.trim().isNotEmpty
            ? _classQrController.text.trim()
            : (prefs.getString('student_class_qr') ?? '');
        if (studentToken.isEmpty || classQr.isEmpty) return;
        final resp = await ApiService.getSelfAttendanceStatus(
          studentToken: studentToken,
          classQr: classQr,
        );
        final enabled = (resp['enabled'] == true);
        final expires = resp['expires_at'] is String
            ? DateTime.tryParse(resp['expires_at'])
            : null;
        if (!mounted) return;
        setState(() {
          _attendanceEnabled = enabled;
          _windowExpiresAt = expires;
        });
        // Stop polling once the teacher enables the window; student can refresh manually later
        if (enabled) {
          _statusTimer?.cancel();
          _statusTimer = null;
        }
      } catch (_) {
        // ignore transient polling errors
      }
    });
  }

  Future<void> _checkStatusOnce() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final studentToken = prefs.getString('student_token') ?? '';
      final classQr = _classQrController.text.trim().isNotEmpty
          ? _classQrController.text.trim()
          : (prefs.getString('student_class_qr') ?? '');
      if (studentToken.isEmpty || classQr.isEmpty) return;
      final resp = await ApiService.getSelfAttendanceStatus(
        studentToken: studentToken,
        classQr: classQr,
      );
      final enabled = (resp['enabled'] == true);
      final expires = resp['expires_at'] is String
          ? DateTime.tryParse(resp['expires_at'])
          : null;
      if (!mounted) return;
      setState(() {
        _attendanceEnabled = enabled;
        _windowExpiresAt = expires;
      });
    } catch (_) {
      // ignore single-shot errors
    }
  }

  Future<void> _refresh() async {
    await _loadStudentData();
    await _loadLocation();
    await _checkStatusOnce();
  }

  String? _remainingText() {
    if (!_attendanceEnabled || _windowExpiresAt == null) return null;
    final now = DateTime.now();
    final diff = _windowExpiresAt!.difference(now);
    if (diff.isNegative) return 'Expired';
    final minutes = diff.inMinutes;
    final seconds = diff.inSeconds % 60;
    if (minutes <= 0) {
      return 'Ends in ${seconds}s';
    }
    return 'Ends in ${minutes}m ${seconds}s';
  }

  Future<void> _enableLocation() async {
    setState(() => _isLoading = true);
    try {
      final ok = await LocationService.requestPermissionsAndService();
      if (!mounted) return;
      if (!ok) {
        // Location permission not granted
      }
      await _loadLocation();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatTime12(DateTime dt) {
    final local = dt.toLocal();
    final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final min = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour < 12 ? 'AM' : 'PM';
    return '$hour12:$min $ampm';
  }

  Future<void> _saveClassQrAndRefresh(String qr) async {
    _classQrController.text = qr;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('student_class_qr', qr);
    await _checkStatusOnce();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Class QR set to: $qr')));
  }

  bool _looksLikeClassQr(String value) {
    final v = value.trim();
    return v.startsWith('CLASS_') ||
        v.startsWith('CLASS:') ||
        v.contains('CLASS');
  }

  bool _looksLikeStudentQr(String value) {
    final v = value.trim();
    return v.startsWith('STUDENT_') ||
        v.startsWith('STUDENT:') ||
        v.contains('STUDENT');
  }

  Future<void> _handleScannedValue(String raw) async {
    final prefs = await SharedPreferences.getInstance();
    final expectedStudentQr = prefs.getString('student_qr') ?? '';
    final expectedClassQr = prefs.getString('student_class_qr') ?? '';

    final value = raw.trim();
    if (_looksLikeClassQr(value)) {
      // Only accept if it matches student's assigned class QR
      if (expectedClassQr.isNotEmpty && value != expectedClassQr) {
        await _showInfoDialog(
          title: 'Wrong Class',
          message:
              'This QR belongs to a different class. Please scan your class QR only.',
        );
        return;
      }
      await _saveClassQrAndRefresh(value);
      return;
    }

    if (_looksLikeStudentQr(value)) {
      if (expectedStudentQr.isEmpty || value != expectedStudentQr) {
        await _showInfoDialog(
          title: 'Wrong Student',
          message:
              'This QR belongs to another student. Please use your own account.',
        );
        return;
      }
      await _showInfoDialog(
        title: 'Student QR Detected',
        message:
            'This page requires the class QR. Please scan your classroom QR instead.',
      );
      return;
    }

    await _showInfoDialog(
      title: 'Unrecognized QR',
      message: 'The scanned code is not a valid classroom or student QR.',
    );
  }

  Future<void> _scanClassQrFromCamera() async {
    if (_isLoading) return;
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        String? detected;
        return SafeArea(
          child: Stack(
            children: [
              MobileScanner(
                controller: _scannerController,
                onDetect: (capture) {
                  for (final barcode in capture.barcodes) {
                    final raw = barcode.rawValue ?? '';
                    // Pass any value; we'll validate outside
                    detected = raw;
                    Navigator.of(ctx).pop(detected);
                    break;
                  }
                },
              ),
              Positioned(
                top: 12,
                left: 12,
                child: IconButton(
                  color: Colors.white,
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ),
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Scan classroom QR',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (result != null && result.isNotEmpty) {
      await _handleScannedValue(result);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No valid class QR detected')),
      );
    }
  }

  Future<void> _pickImageAndScan() async {
    if (_isLoading) return;
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;
      final path = image.path;
      if (!File(path).existsSync()) return;
      final capture = await _scannerController.analyzeImage(path);
      if (capture == null || capture.barcodes.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No QR found in image')));
        return;
      }
      for (final barcode in capture.barcodes) {
        final raw = barcode.rawValue ?? '';
        await _handleScannedValue(raw);
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image does not contain classroom QR')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to read image: $e')));
    }
  }

  Future<void> _requestAttendance() async {
    if (_submitted) return;
    if (!_attendanceEnabled) {
      await _showInfoDialog(
        title: 'Recording Not Enabled',
        message:
            'Your teacher hasn\'t enabled attendance yet. Please wait and try again.',
      );
      return;
    }
    setState(() {
      _isLoading = true;
    });

    try {
      double? lat = _lat;
      double? lng = _lng;

      final prefs = await SharedPreferences.getInstance();
      final studentToken = prefs.getString('student_token') ?? '';
      final classQr = _classQrController.text.trim().isNotEmpty
          ? _classQrController.text.trim()
          : (prefs.getString('student_class_qr') ?? '');

      if (classQr.isEmpty) {
        return;
      }

      if (studentToken.isEmpty) {
        return;
      }

      if (lat == null || lng == null) {
        return;
      }

      await ApiService.studentSelfMark(
        studentToken: studentToken,
        classQr: classQr,
        lat: lat,
        lng: lng,
      );
      if (!mounted) return;
      setState(() {
        _submitted = true;
      });
      await _showInfoDialog(
        title: 'Attendance Recorded',
        message: 'Thank you. Please focus on the lesson.',
      );
      await Future.delayed(const Duration(milliseconds: 200));
      SystemNavigator.pop();
    } catch (e) {
      String errorMessage = 'Failed to submit request';

      if (e.toString().contains('no_active_window')) {
        errorMessage =
            'Self-attendance is not currently enabled by your teacher.';
        if (mounted) {
          await _showInfoDialog(
            title: 'Recording Not Enabled',
            message:
                'Your teacher has not enabled student self-attendance for this class yet. Please wait until your teacher enables it and try again.',
          );
        }
      } else if (e.toString().contains('outside_geofence')) {
        errorMessage =
            'You are not in the classroom location. Attendance cannot be recorded.';
      } else if (e.toString().contains('invalid_token')) {
        errorMessage = 'Session expired. Please log in again.';
      } else if (e.toString().contains('wrong_class')) {
        errorMessage = 'You are not enrolled in this classroom.';
      } else if (e.toString().contains('network') ||
          e.toString().contains('SocketException')) {
        errorMessage = 'Network error. Please check connection and try again.';
      }

      if (!mounted) return;
      await _showRetryDialog(message: errorMessage);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _remainingText();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Request Attendance'),
        actions: [
          _attendanceEnabled
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 6,
                  ),
                  child: Chip(
                    label: Text(
                      remaining == null ? 'Enabled' : 'Enabled • $remaining',
                      style: const TextStyle(color: Colors.white),
                    ),
                    backgroundColor: const Color(0xFF10B981),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                )
              : const SizedBox.shrink(),
          IconButton(
            onPressed: _isLoading ? null : () => _refresh(),
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AppColors.backgroundGradient,
          ),
        ),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _refresh,
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
                      if (!_attendanceEnabled) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.amber.withOpacity(0.4),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.info,
                                color: Colors.amber,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  "Your teacher hasn't enabled attendance yet.",
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ] else if (_attendanceEnabled &&
                          (_lat == null || _lng == null)) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.orange.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.gps_off,
                                color: Colors.orange,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Location not available. Enable GPS and permissions to proceed.',
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _isLoading ? null : _enableLocation,
                                icon: const Icon(Icons.my_location),
                                label: const Text('Enable'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (_studentName != null || _className != null) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.shadowLight,
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF6366F1,
                                  ).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.person,
                                  color: Color(0xFF6366F1),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _studentName ?? '-',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.class_,
                                          size: 14,
                                          color: AppColors.textSecondary,
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            _className ?? '-',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: AppColors.textSecondary,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (_attendanceEnabled &&
                                        _lat != null &&
                                        _lng != null) ...[
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.location_on,
                                            size: 14,
                                            color: Color(0xFF10B981),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              '${_lat!.toStringAsFixed(6)}, ${_lng!.toStringAsFixed(6)}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: Color(0xFF10B981),
                                                fontWeight: FontWeight.w600,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    if (_attendanceEnabled &&
                                        _windowExpiresAt != null) ...[
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.timer,
                                            size: 14,
                                            color: Color(0xFF10B981),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Enabled until: ${_formatTime12(_windowExpiresAt!)}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Color(0xFF10B981),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.shadowLight,
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Your QR codes',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _studentQrController,
                              readOnly: true,
                              decoration: const InputDecoration(
                                labelText: 'Student QR Code',
                              ),
                            ),
                            const SizedBox(height: 8),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _classQrController,
                              readOnly: true,
                              decoration: const InputDecoration(
                                labelText: 'Class QR Code',
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Scan or load your class QR code:',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.25),
                                          blurRadius: 12,
                                          offset: const Offset(0, 6),
                                        ),
                                      ],
                                    ),
                                    child: ElevatedButton.icon(
                                      onPressed: _isLoading
                                          ? null
                                          : _scanClassQrFromCamera,
                                      icon: const Icon(
                                        Icons.qr_code_scanner,
                                        size: 20,
                                        color: AppColors.textPrimary,
                                      ),
                                      label: const Text(
                                        'Scan QR',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        shadowColor: Colors.transparent,
                                        elevation: 0,
                                        minimumSize: const Size.fromHeight(52),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.25),
                                          blurRadius: 12,
                                          offset: const Offset(0, 6),
                                        ),
                                      ],
                                    ),
                                    child: ElevatedButton.icon(
                                      onPressed: _isLoading
                                          ? null
                                          : _pickImageAndScan,
                                      icon: const Icon(
                                        Icons.photo_library_outlined,
                                        size: 20,
                                        color: AppColors.textPrimary,
                                      ),
                                      label: const Text(
                                        'Load from Gallery',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.transparent,
                                        shadowColor: Colors.transparent,
                                        elevation: 0,
                                        minimumSize: const Size.fromHeight(52),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const SizedBox(height: 16),
                            const SizedBox(height: 24),
                            ElevatedButton.icon(
                              onPressed: (_isLoading || _submitted)
                                  ? null
                                  : _requestAttendance,
                              icon: const Icon(Icons.how_to_reg),
                              label: Text(
                                _submitted
                                    ? 'Recorded'
                                    : (_isLoading
                                          ? 'Submitting...'
                                          : 'Record Attendance'),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                minimumSize: const Size.fromHeight(48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showInfoDialog({
    required String title,
    required String message,
  }) async {
    await _showThemedDialog(
      title: title,
      message: message,
      icon: Icons.info_outline,
      color: const Color(0xFF6366F1),
      primaryActionText: 'OK',
    );
  }

  Future<void> _showRetryDialog({required String message}) async {
    await _showThemedDialog(
      title: 'Attendance',
      message: message,
      icon: Icons.warning_amber_rounded,
      color: const Color(0xFFF59E0B),
      secondaryActionText: 'Cancel',
      primaryActionText: 'Retry',
      onPrimaryTap: () {
        Navigator.of(context).pop();
        _requestAttendance();
      },
    );
  }

  Future<void> _showThemedDialog({
    required String title,
    required String message,
    required IconData icon,
    required Color color,
    String? primaryActionText,
    String? secondaryActionText,
    VoidCallback? onPrimaryTap,
  }) async {
    await showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: color, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(message, style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (secondaryActionText != null)
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(secondaryActionText),
                      ),
                    if (primaryActionText != null)
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: color),
                        onPressed:
                            onPrimaryTap ?? () => Navigator.of(context).pop(),
                        child: Text(primaryActionText),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
