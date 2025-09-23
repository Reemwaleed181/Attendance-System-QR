import 'package:flutter/foundation.dart';

void testPlatformDetection() {
  print('Platform Detection Test:');
  print('kIsWeb: $kIsWeb');
  print('Platform is Web: ${kIsWeb}');
  print('Platform is Mobile: ${!kIsWeb}');
  
  if (kIsWeb) {
    print('Running on Web - using localhost');
  } else {
    print('Running on Mobile - using IP address');
  }
}
