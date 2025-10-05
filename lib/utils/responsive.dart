import 'package:flutter/material.dart';

class Breakpoints {
  static const double mobile = 600;
  static const double tablet = 1024;
  static const double desktop = 1440;
}

class Responsive {
  static bool isMobile(BuildContext context) => MediaQuery.of(context).size.width < Breakpoints.mobile;
  static bool isTablet(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return w >= Breakpoints.mobile && w < Breakpoints.tablet;
  }
  static bool isDesktop(BuildContext context) => MediaQuery.of(context).size.width >= Breakpoints.tablet;

  static double maxContentWidth(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w >= Breakpoints.desktop) return 1100;
    if (w >= Breakpoints.tablet) return 900;
    return w; // full width on mobile
  }

  static EdgeInsets pagePadding(BuildContext context) {
    if (isDesktop(context)) return const EdgeInsets.all(32);
    if (isTablet(context)) return const EdgeInsets.all(24);
    return const EdgeInsets.all(16);
  }
}


