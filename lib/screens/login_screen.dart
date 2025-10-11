import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:school_qr/screens/parents/parent_home_screen.dart';
import 'package:school_qr/screens/teachers/teacher_classes_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../widgets/custom_text_field.dart';
import '../widgets/custom_button.dart';
import '../constants/app_colors.dart';
import '../utils/responsive.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  bool _isTeacher = true; // when false, currently Parent; we'll add Student tab
  bool _isStudent = false;
  bool _isLoading = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Teacher fields
  final _teacherUsernameController = TextEditingController();
  final _teacherPasswordController = TextEditingController();

  // Parent fields
  final _parentNameController = TextEditingController();
  final _parentEmailController = TextEditingController();
  final _parentPhoneController = TextEditingController();

  // Student fields
  final _studentUsernameController = TextEditingController();
  final _studentPasswordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: Curves.easeOutCubic,
          ),
        );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _teacherUsernameController.dispose();
    _teacherPasswordController.dispose();
    _parentNameController.dispose();
    _parentEmailController.dispose();
    _parentPhoneController.dispose();
    _studentUsernameController.dispose();
    _studentPasswordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      Map<String, dynamic> response;

      if (_isTeacher) {
        response = await ApiService.teacherLogin(
          _teacherUsernameController.text,
          _teacherPasswordController.text,
        );

        // Save teacher token
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('teacher_token', response['token']);
        await prefs.setString('user_type', 'teacher');

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => const TeacherClassesScreen(),
            ),
          );
        }
      } else if (_isStudent) {
        response = await ApiService.studentLogin(
          _studentUsernameController.text,
          _studentPasswordController.text,
        );

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('student_token', response['token']);
        await prefs.setString('student_id', response['student']['id']);
        await prefs.setString('student_class_id', response['classroom']['id']);
        await prefs.setString(
          'student_name',
          response['student']['name'] ?? '',
        );
        await prefs.setString(
          'student_class_name',
          response['classroom']['name'] ?? '',
        );
        await prefs.setString(
          'student_qr',
          response['student']['qr_code'] ?? '',
        );
        await prefs.setString(
          'student_class_qr',
          response['classroom']['qr_code'] ?? '',
        );
        await prefs.setString('user_type', 'student');

        if (mounted) {
          Navigator.pushReplacementNamed(
            context,
            '/student/request-attendance',
          );
        }
      } else {
        response = await ApiService.parentLogin(
          _parentNameController.text,
          _parentEmailController.text,
          _parentPhoneController.text,
        );

        // Save parent data
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('parent_id', response['parent']['id']);
        await prefs.setString('user_type', 'parent');

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const ParentHomeScreen()),
          );
        }
      }
    } catch (e) {
      String message = 'Login failed. Please try again.';
      if (e is ApiException) {
        // Friendly messages based on error code/status
        switch (e.code) {
          case 'missing_credentials':
            message = 'Please enter your username and password.';
            break;
          case 'invalid_username':
            message = 'Incorrect username. Please check and try again.';
            break;
          case 'invalid_password':
            message = 'Incorrect password. Please try again.';
            break;
          case 'not_teacher':
            message = 'This account is not registered as a teacher.';
            break;
          case 'invalid_input':
            // Keep it simple: show the first specific field error if provided
            if (e.fields is Map) {
              final f = e.fields as Map;
              String? firstErr(String key) {
                final v = f[key];
                if (v is List && v.isNotEmpty) return v.first.toString();
                return null;
              }

              final fieldOrder = [
                ['username', 'Username'],
                ['password', 'Password'],
                ['name', 'Full Name'],
                ['email', 'Email'],
                ['phone', 'Phone'],
              ];
              String? picked;
              String label = '';
              for (final pair in fieldOrder) {
                final err = firstErr(pair[0]);
                if (err != null && err.isNotEmpty) {
                  picked = err;
                  label = pair[1];
                  break;
                }
              }
              message = picked != null ? '$label: $picked' : 'Invalid input.';
            } else {
              message = 'Invalid input.';
            }
            break;
          default:
            if (e.statusCode >= 500) {
              message = 'Server error. Please try again later.';
            } else if (e.statusCode == 0) {
              message = 'Network error. Check your connection.';
            }
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red.shade400,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login'), actions: const []),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: AppColors.backgroundGradient,
          ),
        ),
        child: SafeArea(
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
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 40),

                        // Header
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: AppColors.primaryGradient,
                            ),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Icon(
                                  Icons.qr_code_outlined,
                                  size: 48,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                'Welcome Back!',
                                style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  letterSpacing: -0.5,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Sign in to your account',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white.withValues(alpha: 0.9),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 32),

                        Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // User type selector: Teacher, Parent, Student
                              Container(
                                padding: const EdgeInsets.all(4),
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
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () => setState(() {
                                          _isTeacher = true;
                                          _isStudent = false;
                                        }),
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 300,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 16,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _isTeacher
                                                ? AppColors.primary
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Text(
                                            'Teacher',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: _isTeacher
                                                  ? AppColors.textOnPrimary
                                                  : AppColors.textSecondary,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () => setState(() {
                                          _isTeacher = false;
                                          _isStudent = false;
                                        }),
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 300,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 16,
                                          ),
                                          decoration: BoxDecoration(
                                            color: (!_isTeacher && !_isStudent)
                                                ? AppColors.primary
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Text(
                                            'Parent',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color:
                                                  (!_isTeacher && !_isStudent)
                                                  ? AppColors.textOnPrimary
                                                  : AppColors.textSecondary,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: GestureDetector(
                                        onTap: () => setState(() {
                                          _isTeacher = false;
                                          _isStudent = true;
                                        }),
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 300,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 16,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _isStudent
                                                ? AppColors.primary
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Text(
                                            'Student',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: _isStudent
                                                  ? AppColors.textOnPrimary
                                                  : AppColors.textSecondary,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 32),

                              // Login form
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppColors.shadowLight,
                                      blurRadius: 20,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    // Error banner removed: errors are shown via SnackBar only
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withValues(
                                              alpha: 0.1,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          child: Icon(
                                            _isTeacher
                                                ? Icons.person
                                                : _isStudent
                                                ? Icons.school
                                                : Icons.family_restroom,
                                            color: AppColors.primary,
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Text(
                                          _isTeacher
                                              ? 'Teacher Login'
                                              : _isStudent
                                              ? 'Student Login'
                                              : 'Parent Login',
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 24),

                                    if (_isTeacher) ...[
                                      CustomTextField(
                                        controller: _teacherUsernameController,
                                        label: 'Username',
                                        prefixIcon: Icons.person_outline,
                                        validator: (value) {
                                          if (value == null || value.isEmpty) {
                                            return 'Please enter username';
                                          }
                                          return null;
                                        },
                                      ),
                                      const SizedBox(height: 20),
                                      CustomTextField(
                                        controller: _teacherPasswordController,
                                        label: 'Password',
                                        prefixIcon: Icons.lock_outline,
                                        obscureText: true,
                                        validator: (value) {
                                          if (value == null || value.isEmpty) {
                                            return 'Please enter password';
                                          }
                                          return null;
                                        },
                                      ),
                                    ] else if (!_isTeacher && !_isStudent) ...[
                                      CustomTextField(
                                        controller: _parentNameController,
                                        label: 'Full Name',
                                        prefixIcon: Icons.person_outline,
                                        textCapitalization:
                                            TextCapitalization.words,
                                        inputFormatters: [
                                          // Allow letters and single spaces, collapse multiple spaces
                                          FilteringTextInputFormatter.allow(
                                            RegExp(r"[A-Za-z\s]"),
                                          ),
                                          _TwoWordNameFormatter(),
                                        ],
                                        validator: (value) {
                                          if (value == null || value.isEmpty) {
                                            return 'Please enter your full name';
                                          }
                                          final parts = value.trim().split(
                                            RegExp(r"\s+"),
                                          );
                                          if (parts.length < 2) {
                                            return 'Please enter first and last name';
                                          }
                                          if (!RegExp(
                                                r"^[A-Z][a-zA-Z]*",
                                              ).hasMatch(parts[0]) ||
                                              !RegExp(
                                                r"^[A-Z][a-zA-Z]*",
                                              ).hasMatch(parts[1])) {
                                            return 'Capitalize first letters (e.g., John Doe)';
                                          }
                                          return null;
                                        },
                                      ),
                                      const SizedBox(height: 20),
                                      CustomTextField(
                                        controller: _parentEmailController,
                                        label: 'Email Address',
                                        prefixIcon: Icons.email_outlined,
                                        keyboardType:
                                            TextInputType.emailAddress,
                                        validator: (value) {
                                          if (value == null || value.isEmpty) {
                                            return 'Please enter your email';
                                          }
                                          if (!value.contains('@')) {
                                            return 'Please enter a valid email';
                                          }
                                          return null;
                                        },
                                      ),
                                      const SizedBox(height: 20),
                                      CustomTextField(
                                        controller: _parentPhoneController,
                                        label: 'Phone Number',
                                        prefixIcon: Icons.phone_outlined,
                                        keyboardType: TextInputType.phone,
                                        validator: (value) {
                                          if (value == null || value.isEmpty) {
                                            return 'Please enter your phone number';
                                          }
                                          return null;
                                        },
                                      ),
                                    ] else ...[
                                      CustomTextField(
                                        controller: _studentUsernameController,
                                        label: 'Username',
                                        prefixIcon: Icons.person_outline,
                                        validator: (value) {
                                          if (value == null || value.isEmpty) {
                                            return 'Please enter username';
                                          }
                                          return null;
                                        },
                                      ),
                                      const SizedBox(height: 20),
                                      CustomTextField(
                                        controller: _studentPasswordController,
                                        label: 'Password',
                                        prefixIcon: Icons.lock_outline,
                                        obscureText: true,
                                        validator: (value) {
                                          if (value == null || value.isEmpty) {
                                            return 'Please enter password';
                                          }
                                          return null;
                                        },
                                      ),
                                    ],

                                    const SizedBox(height: 32),

                                    CustomButton(
                                      text: _isTeacher
                                          ? 'Sign In'
                                          : (_isStudent
                                                ? 'Sign In'
                                                : 'Register'),
                                      icon: Icons.login,
                                      onPressed: _isLoading ? null : _login,
                                      isLoading: _isLoading,
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: AppColors.textOnPrimary,
                                      isGradient: true,
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
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TwoWordNameFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    String text = newValue.text;

    // Collapse multiple spaces to single
    text = text.replaceAll(RegExp(r"\s+"), ' ');

    // Limit to two words max
    final parts = text.trimLeft().split(' ');
    if (parts.length > 2) {
      text = parts.take(2).join(' ');
    }

    // Title-case first two words
    List<String> tokens = text.split(' ');
    for (int i = 0; i < tokens.length && i < 2; i++) {
      final t = tokens[i];
      if (t.isEmpty) continue;
      if (t.length == 1) {
        tokens[i] = t.toUpperCase();
      } else {
        tokens[i] = t[0].toUpperCase() + t.substring(1).toLowerCase();
      }
    }
    text = tokens.join(' ');

    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
      composing: TextRange.empty,
    );
  }
}
