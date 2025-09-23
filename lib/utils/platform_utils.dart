import 'package:flutter/foundation.dart';

class PlatformUtils {
  static bool get isWeb => kIsWeb;
  static bool get isMobile => !kIsWeb;
  
  static String get baseUrl {
    if (isWeb) {
      return 'http://localhost:8000/api';
    } else {
      // For mobile devices, use the IP address
      return 'http://192.168.10.17:8000/api';
    }
  }
}
