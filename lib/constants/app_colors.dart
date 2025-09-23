import 'package:flutter/material.dart';

/// School Attendance App Color Palette
/// Professional, trustworthy, and educational color scheme
class AppColors {
  // Primary brand colors (Indigo 600 palette)
  // Primary Color (AppBar/Navigation): #3949AB
  static const Color primary = Color(0xFF3949AB);
  // Helpful complements around the primary tone
  static const Color primaryLight = Color(0xFF5C6BC0); // Indigo 400/500
  static const Color primaryDark = Color(0xFF303F9F);  // Indigo 700

  // Secondary/Success colors (kept for status usage)
  static const Color secondary = Color(0xFF26A69A); // Teal 400 (also parent button/highlight)
  static const Color secondaryLight = Color(0xFF80CBC4);
  static const Color secondaryDark = Color(0xFF00897B);

  // Accent Colors
  // Teacher Interface Accent: #5E35B1 (Deep Purple 600)
  static const Color accent = Color(0xFF5E35B1);
  static const Color accentLight = Color(0xFF7E57C2); // Teacher button/highlight (Purple 400)
  static const Color accentDark = Color(0xFF4527A0);

  // Status Colors
  static const Color success = Color(0xFF10B981); // Present/Success
  static const Color warning = Color(0xFFF59E0B); // Warning/Attention
  static const Color error = Color(0xFFEF4444); // Absent/Error
  static const Color info = Color(0xFF3B82F6); // Information

  // Neutral / Surfaces
  // Background: #FAFAFA
  static const Color background = Color(0xFFFAFAFA);
  static const Color surface = Color(0xFFFFFFFF); // Card/Container background
  static const Color surfaceVariant = Color(0xFFF3F4F6); // Subtle grey surface

  // Text Colors
  // Primary Text: #212121, Secondary Text: #616161
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF616161);
  static const Color textTertiary = Color(0xFF9E9E9E);
  static const Color textOnPrimary = Color(
    0xFFFFFFFF,
  ); // Text on primary colors
  static const Color textOnSecondary = Color(
    0xFFFFFFFF,
  ); // Text on secondary colors

  // Border Colors
  static const Color border = Color(0xFFE2E8F0); // Default borders
  static const Color borderLight = Color(0xFFF1F5F9); // Light borders
  static const Color borderDark = Color(0xFFCBD5E1); // Dark borders

  // Shadow Colors
  static const Color shadow = Color(0x1A000000); // Default shadow
  static const Color shadowLight = Color(0x0D000000); // Light shadow
  static const Color shadowDark = Color(0x33000000); // Dark shadow

  // Gradient Colors
  static const List<Color> primaryGradient = [
    Color(0xFF3949AB),
    Color(0xFF5C6BC0),
  ];

  static const List<Color> secondaryGradient = [
    Color(0xFF00838F), // Parent accent (Teal 700)
    Color(0xFF26A69A), // Parent button/highlight (Teal 400)
  ];

  static const List<Color> accentGradient = [
    Color(0xFF5E35B1),
    Color(0xFF7E57C2),
  ];

  static const List<Color> backgroundGradient = [
    Color(0xFFFAFAFA),
    Color(0xFFF3F4F6),
    Color(0xFFE0E0E0),
  ];

  // Role-specific primary accents
  static const Color teacherPrimary = Color(0xFF5E35B1); // Teacher accent (Deep Purple 600)
  static const Color teacherButton = Color(0xFF7E57C2); // Teacher highlight (Purple 400)
  static const Color parentPrimary = Color(0xFF00838F); // Parent accent (Teal 700)
  static const Color parentButton = Color(0xFF26A69A); // Parent highlight (Teal 400)
  static const Color adminPrimary = Color(0xFF5E35B1);

  // Attendance status colors
  static const Color present = Color(0xFF10B981); // Green for present
  static const Color absent = Color(0xFFEF4444); // Red for absent
  static const Color late = Color(0xFFF59E0B); // Orange for late
  static const Color excused = Color(0xFF6B7280); // Gray for excused
}
