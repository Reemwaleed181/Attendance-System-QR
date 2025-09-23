import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';
import '../../models/classroom.dart';
import '../../models/student.dart';
import '../../constants/app_colors.dart';
import 'teacher_home_screen.dart';
import '../../utils/responsive.dart';

class TeacherClassesScreen extends StatefulWidget {
  const TeacherClassesScreen({super.key});

  @override
  State<TeacherClassesScreen> createState() => _TeacherClassesScreenState();
}

class _TeacherClassesScreenState extends State<TeacherClassesScreen>
    with TickerProviderStateMixin {
  String? _teacherToken;
  List<Classroom> _allClassrooms = [];
  List<Student> _allStudents = [];
  List<Classroom> _selectedClassrooms = [];
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isLoading = true;
  String? _errorMessage;
  late AnimationController _animationController;
  late AnimationController _buttonAnimationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _buttonGlowAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _buttonAnimationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );

    _buttonGlowAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _buttonAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    _animationController.forward();
    _loadTeacherToken();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _buttonAnimationController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadTeacherToken() async {
    final prefs = await SharedPreferences.getInstance();
    _teacherToken = prefs.getString('teacher_token');
    if (_teacherToken != null) {
      await _loadData();
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadData() async {
    if (_teacherToken == null) return;

    setState(() => _isLoading = true);

    try {
      final classrooms = await ApiService.getClassrooms(_teacherToken!);
      final students = await ApiService.getStudents(_teacherToken!);

      setState(() {
        _allClassrooms = classrooms
            .where((c) => c.name.toLowerCase() != 'test class 1')
            .toList();
        _allStudents = students;
        _isLoading = false;
        _errorMessage = null;
      });

      // Load previously selected classes
      await _loadSelectedClasses();
    } catch (e) {
      String message = 'Failed to load data. Pull to retry.';
      if (e is ApiException) {
        if (e.statusCode == 401) {
          message = 'Session expired. Please sign in again.';
        } else if (e.statusCode >= 500) {
          message = 'Server error. Please try again later.';
        } else {
          message = e.message;
        }
      }
      setState(() {
        _isLoading = false;
        _errorMessage = message;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
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

  void _toggleClassroomSelection(Classroom classroom) {
    setState(() {
      if (_selectedClassrooms.contains(classroom)) {
        _selectedClassrooms.remove(classroom);
      } else {
        _selectedClassrooms.add(classroom);
      }
    });
    _saveSelectedClasses();
    
    // Start button animation when classes are selected
    if (_selectedClassrooms.isNotEmpty) {
      _buttonAnimationController.repeat(reverse: true);
    } else {
      _buttonAnimationController.stop();
    }
  }

  Future<void> _saveSelectedClasses() async {
    final prefs = await SharedPreferences.getInstance();
    final classNames = _selectedClassrooms.map((c) => c.name).toList();
    await prefs.setStringList('teacher_selected_classes', classNames);
  }

  Future<void> _loadSelectedClasses() async {
    final prefs = await SharedPreferences.getInstance();
    final savedClassNames =
        prefs.getStringList('teacher_selected_classes') ?? [];

    setState(() {
      _selectedClassrooms = _allClassrooms
          .where((classroom) => savedClassNames.contains(classroom.name))
          .toList();
    });
    
    // Start button animation if classes are already selected
    if (_selectedClassrooms.isNotEmpty) {
      _buttonAnimationController.repeat(reverse: true);
    }
  }

  List<Student> _getStudentsForClassroom(Classroom classroom) {
    final students = _allStudents
        .where((student) => student.classroomName == classroom.name)
        .toList();
    if (_searchQuery.isEmpty) return students;
    final q = _searchQuery.toLowerCase();
    return students.where((s) =>
      s.name.toLowerCase().contains(q) ||
      s.qrCode.toLowerCase().contains(q)
    ).toList();
  }

  List<Classroom> _filteredClassrooms() {
    if (_searchQuery.isEmpty) return _allClassrooms;
    final q = _searchQuery.toLowerCase();
    return _allClassrooms.where((c) =>
      c.name.toLowerCase().contains(q) ||
      c.qrCode.toLowerCase().contains(q)
    ).toList();
  }

  List<Student> _searchStudents() {
    if (_searchQuery.isEmpty) return const [];
    final q = _searchQuery.toLowerCase();
    return _allStudents.where((s) =>
      s.name.toLowerCase().contains(q) ||
      s.qrCode.toLowerCase().contains(q) ||
      s.classroomName.toLowerCase().contains(q)
    ).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF8FAFC), Color(0xFFE2E8F0), Color(0xFFCBD5E1)],
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
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'My Classes',
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
                              'Select your classes and view QR codes',
                              style: TextStyle(
                                fontSize: 14,
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
                            onRefresh: _loadData,
                            color: AppColors.accent,
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
                                  if (_errorMessage != null) ...[
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 16),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFF1F2),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: const Color(0xFFFCA5A5)),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.error_outline, color: Color(0xFFDC2626)),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              _errorMessage!,
                                              style: const TextStyle(color: Color(0xFFB91C1C), fontWeight: FontWeight.w600),
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: _loadData,
                                            child: const Text('Retry'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                  // Search bar
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 16),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.05),
                                          blurRadius: 16,
                                          offset: const Offset(0, 8),
                                        ),
                                      ],
                                      border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.search, color: Color(0xFF6B7280), size: 20),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: TextField(
                                            controller: _searchController,
                                            decoration: const InputDecoration(
                                              hintText: 'Student or Classroom',
                                              border: InputBorder.none,
                                            ),
                                            onChanged: (value) {
                                              setState(() => _searchQuery = value.trim());
                                            },
                                          ),
                                        ),
                                        if (_searchQuery.isNotEmpty)
                                          IconButton(
                                            icon: const Icon(Icons.clear, size: 18, color: Color(0xFF6B7280)),
                                            onPressed: () {
                                              _searchController.clear();
                                              setState(() => _searchQuery = '');
                                            },
                                          ),
                                      ],
                                    ),
                                  ),
                                  // If searching, show only search results
                                  if (_searchQuery.isNotEmpty) ...[
                                    _buildSearchResults(),
                                  ]
                                  // Otherwise, show normal content
                                  else if (_selectedClassrooms.isNotEmpty)
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 24),
                                      child: AnimatedBuilder(
                                        animation: _buttonGlowAnimation,
                                        builder: (context, child) {
                                          return Stack(
                                            children: [
                                              // Animated background glow
                                              Container(
                                                height: 65,
                                                decoration: BoxDecoration(
                                                  gradient: const LinearGradient(
                                                    colors: [
                                                      Color(0xFF10B981),
                                                      Color(0xFF059669),
                                                      Color(0xFF047857),
                                                    ],
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                  ),
                                                  borderRadius: BorderRadius.circular(28),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: const Color(0xFF10B981).withValues(alpha: 0.4 * _buttonGlowAnimation.value),
                                                      blurRadius: 25 * _buttonGlowAnimation.value,
                                                      offset: const Offset(0, 8),
                                                      spreadRadius: 2 * _buttonGlowAnimation.value,
                                                    ),
                                                    BoxShadow(
                                                      color: const Color(0xFF10B981).withValues(alpha: 0.2 * _buttonGlowAnimation.value),
                                                      blurRadius: 40 * _buttonGlowAnimation.value,
                                                      offset: const Offset(0, 15),
                                                      spreadRadius: 5 * _buttonGlowAnimation.value,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          // Main button content
                                          Container(
                                            height: 80,
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                colors: [
                                                  Color(0xFF10B981),
                                                  Color(0xFF059669),
                                                ],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                              borderRadius: BorderRadius.circular(28),
                                              border: Border.all(
                                                color: Colors.white.withValues(alpha: 0.3),
                                                width: 2,
                                              ),
                                            ),
                                            child: Material(
                                              color: Colors.transparent,
                                              child: InkWell(
                                                onTap: () {
                                                  Navigator.pushReplacement(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (context) =>
                                                          const TeacherHomeScreen(),
                                                    ),
                                                  );
                                                },
                                                borderRadius: BorderRadius.circular(28),
                                                child: Padding(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 20,
                                                    vertical: 10,
                                                  ),
                                                  child: Row(
                                                    children: [
                                                      // Animated icon container
                                                      Container(
                                                        width: 40,
                                                        height: 40,
                                                        decoration: BoxDecoration(
                                                          color: Colors.white.withValues(alpha: 0.2),
                                                          borderRadius: BorderRadius.circular(16),
                                                          border: Border.all(
                                                            color: Colors.white.withValues(alpha: 0.4),
                                                            width: 2,
                                                          ),
                                                        ),
                                                        child: const Icon(
                                                          Icons.dashboard_rounded,
                                                          color: Colors.white,
                                                          size: 22,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 20),
                                                      // Text content
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          mainAxisAlignment: MainAxisAlignment.center,
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            const Text(
                                                              'Ready to Start!',
                                                              style: TextStyle(
                                                                fontSize: 18,
                                                                fontWeight: FontWeight.w800,
                                                                color: Colors.white,
                                                                letterSpacing: -0.5,
                                                              ),
                                                              maxLines: 1,
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                            const SizedBox(height: 2),
                                                            Text(
                                                              '${_selectedClassrooms.length} class${_selectedClassrooms.length == 1 ? '' : 'es'} selected',
                                                              style: TextStyle(
                                                                fontSize: 12,
                                                                fontWeight: FontWeight.w500,
                                                                color: Colors.white.withValues(alpha: 0.9),
                                                              ),
                                                              maxLines: 1,
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                      // Arrow icon
                                                      Container(
                                                        width: 32,
                                                        height: 32,
                                                        decoration: BoxDecoration(
                                                          color: Colors.white.withValues(alpha: 0.2),
                                                          borderRadius: BorderRadius.circular(12),
                                                        ),
                                                        child: const Icon(
                                                          Icons.arrow_forward_ios_rounded,
                                                          color: Colors.white,
                                                          size: 16,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                            ],
                                          );
                                        },
                                      ),
                                    ),
                                  if (_searchQuery.isEmpty)
                                  // Class Selection Section
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: AppColors.accent.withValues(alpha: 0.1),
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: const Icon(
                                                Icons.checklist,
                                                color: AppColors.accent,
                                                size: 24,
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            const Text(
                                              'Select Your Classes',
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF1F2937),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 20),
                                        if (_allClassrooms.isEmpty)
                                          const Center(
                                            child: Text(
                                              'No classrooms found',
                                              style: TextStyle(
                                                fontSize: 16,
                                                color: Color(0xFF6B7280),
                                              ),
                                            ),
                                          )
                                        else
                                          Wrap(
                                            spacing: 12,
                                            runSpacing: 12,
                                            children: _filteredClassrooms().map((
                                              classroom,
                                            ) {
                                              final isSelected =
                                                  _selectedClassrooms.contains(
                                                    classroom,
                                                  );
                                              return GestureDetector(
                                                onTap: () =>
                                                    _toggleClassroomSelection(
                                                      classroom,
                                                    ),
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 16,
                                                        vertical: 12,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: isSelected
                                                        ? AppColors.accent
                                                        : const Color(
                                                            0xFFF3F4F6,
                                                          ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          20,
                                                        ),
                                                    border: Border.all(
                                                      color: isSelected
                                                          ? AppColors.accent
                                                          : const Color(
                                                              0xFFE5E7EB,
                                                            ),
                                                      width: 2,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        isSelected
                                                            ? Icons.check_circle
                                                            : Icons
                                                                  .radio_button_unchecked,
                                                        color: isSelected
                                                            ? Colors.white
                                                            : const Color(
                                                                0xFF6B7280,
                                                              ),
                                                        size: 20,
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        classroom.name,
                                                        style: TextStyle(
                                                          fontSize: 14,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color: isSelected
                                                              ? Colors.white
                                                              : const Color(
                                                                  0xFF1F2937,
                                                                ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              );
                                            }).toList(),
                                          ),
                                      ],
                                    ),
                                  ),

                                  if (_searchQuery.isEmpty && _selectedClassrooms.isNotEmpty) ...[
                                    const SizedBox(height: 24),

                                    // Selected Classes QR Codes
                                    ..._selectedClassrooms.map((classroom) {
                                      final students = _getStudentsForClassroom(
                                        classroom,
                                      );
                                      return Container(
                                        margin: const EdgeInsets.only(
                                          bottom: 24,
                                        ),
                                        padding: const EdgeInsets.all(24),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            24,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: 
                                                0.05,
                                              ),
                                              blurRadius: 20,
                                              offset: const Offset(0, 8),
                                            ),
                                          ],
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            // Class Header
                                            Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.all(
                                                    8,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.accent.withValues(alpha: 0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                  ),
                                                  child: const Icon(
                                                    Icons.class_,
                                                    color: AppColors.accent,
                                                    size: 24,
                                                  ),
                                                ),
                                                const SizedBox(width: 16),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(
                                                        classroom.name,
                                                        style: const TextStyle(
                                                          fontSize: 20,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: Color(
                                                            0xFF1F2937,
                                                          ),
                                                        ),
                                                      ),
                                                      Text(
                                                        '${students.length} students',
                                                        style: const TextStyle(
                                                          fontSize: 14,
                                                          color: Color(
                                                            0xFF6B7280,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),

                                            const SizedBox(height: 20),

                                            // Class QR Code
                                            Center(
                                                child: Column(
                                                  children: [
                                                    const Text(
                                                      'Class QR Code',
                                                      style: TextStyle(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      color: Color(0xFF1F2937),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 12),
                                                  Container(
                                                    padding: const EdgeInsets.all(8),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFFF8FAFC),
                                                      borderRadius: BorderRadius.circular(12),
                                                      border: Border.all(
                                                        color: const Color(0xFFE5E7EB),
                                                        width: 1,
                                                      ),
                                                    ),
                                                    child: SizedBox(
                                                      width: 150,
                                                      height: 150,
                                                      child: QrImageView(
                                                      data: classroom.qrCode,
                                                      version: QrVersions.auto,
                                                        backgroundColor: Colors.white,
                                                      ),
                                                    ),
                                                  ),
                                                  // QR name removed per request
                                                ],
                                              ),
                                            ),

                                            if (students.isNotEmpty)
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                              const SizedBox(height: 24),
                                              const Text(
                                                'Students',
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFF1F2937),
                                                ),
                                              ),
                                              const SizedBox(height: 16),
                                              GridView.builder(
                                                shrinkWrap: true,
                                                physics: const NeverScrollableScrollPhysics(),
                                                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                                  maxCrossAxisExtent: 220,
                                                      crossAxisSpacing: 12,
                                                      mainAxisSpacing: 12,
                                                  childAspectRatio: 0.9,
                                                    ),
                                                itemCount: students.length,
                                                itemBuilder: (context, index) {
                                                      final student = students[index];
                                                      return _buildStudentQRCard(student);
                                                },
                                              ),
                                            ],
                                              ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ],

                                  if (_searchQuery.isEmpty && _selectedClassrooms.isEmpty) ...[
                                    const SizedBox(height: 24),
                                    Container(
                                      padding: const EdgeInsets.all(32),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(24),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 
                                              0.05,
                                            ),
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
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: const Icon(
                                              Icons.class_,
                                              size: 48,
                                              color: AppColors.accent,
                                            ),
                                          ),
                                          const SizedBox(height: 20),
                                          const Text(
                                            'Select Your Classes',
                                            style: TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF1F2937),
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                          const SizedBox(height: 12),
                                          const Text(
                                            'Choose the classes you teach to view their QR codes and students',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w500,
                                              color: Color(0xFF6B7280),
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
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
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStudentQRCard(Student student) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Estimate available space for QR after header/text/paddings
        final availableWidth = constraints.maxWidth;
        final availableHeight = constraints.maxHeight;
        // Reserve ~70px for icon + name + spacing + caption
        final qrMaxByHeight = (availableHeight - 84).clamp(60.0, 180.0);
        final qrMaxByWidth = (availableWidth - 24).clamp(60.0, 180.0);
        final double qrSize = qrMaxByHeight < qrMaxByWidth ? qrMaxByHeight : qrMaxByWidth;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
      ),
      child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.person, color: Color(0xFF10B981), size: 16),
          ),
              const SizedBox(height: 6),
          Text(
            student.name,
            style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
              color: Color(0xFF1F2937),
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
              Flexible(
                fit: FlexFit.loose,
                child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
                ),
                  child: SizedBox(
                    width: qrSize,
                    height: qrSize,
            child: QrImageView(
              data: student.qrCode,
              version: QrVersions.auto,
              backgroundColor: Colors.white,
            ),
          ),
                ),
              ),
              // QR name removed per request
            ],
          ),
        );
      },
    );
  }

  Widget _buildSearchResults() {
    final classResults = _filteredClassrooms();
    // If a class matches exactly (name or QR), show its students too
    Classroom? exactClass;
    if (_searchQuery.isNotEmpty) {
      final lower = _searchQuery.toLowerCase();
      final match = _allClassrooms.where((c) => c.name.toLowerCase() == lower || c.qrCode.toLowerCase() == lower);
      if (match.isNotEmpty) {
        exactClass = match.first;
      }
    }
    final studentResults = exactClass != null
        ? _allStudents.where((s) => s.classroomName == exactClass!.name).toList()
        : _searchStudents();
    final noResults = classResults.isEmpty && studentResults.isEmpty;

    return Container(
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
      child: noResults
          ? const Center(
              child: Text(
                'No results',
                style: TextStyle(fontSize: 16, color: Color(0xFF6B7280)),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (classResults.isNotEmpty) ...[
                  const Text(
                    'Classes',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Column(
                    children: classResults.map((classroom) {
                      final isSelected = _selectedClassrooms.contains(classroom);
                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected ? const Color(0xFF8B5CF6) : const Color(0xFFE5E7EB),
                            width: 2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            // Class header with selection
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: () => _toggleClassroomSelection(classroom),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: isSelected ? const Color(0xFF8B5CF6) : const Color(0xFFF3F4F6),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isSelected ? const Color(0xFF8B5CF6) : const Color(0xFFE5E7EB),
                                        width: 2,
                                      ),
                                    ),
                                    child: Icon(
                                      isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                                      color: isSelected ? Colors.white : const Color(0xFF6B7280),
                                      size: 20,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        classroom.name,
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                          color: isSelected ? const Color(0xFF8B5CF6) : const Color(0xFF1F2937),
                                        ),
                                      ),
                                      Text(
                                        'QR: ${classroom.qrCode}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            // QR Code display
                            Center(
                              child: Column(
                                children: [
                                  const Text(
                                    'Class QR Code',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF1F2937),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(0xFFE5E7EB),
                                        width: 1,
                                      ),
                                    ),
                                    child: SizedBox(
                                      width: 120,
                                      height: 120,
                                      child: QrImageView(
                                        data: classroom.qrCode,
                                        version: QrVersions.auto,
                                        backgroundColor: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
                ],
                if (studentResults.isNotEmpty) ...[
                  const Text(
                    'Students',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 12),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 220,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 0.9,
                    ),
                    itemCount: studentResults.length,
                    itemBuilder: (context, index) {
                      return _buildStudentQRCard(studentResults[index]);
                    },
                  ),
                ],
        ],
      ),
    );
  }
}
