class DevDefaults {
  // Set once for your LAN; used by all targets (web, USB phone, Wi‑Fi phone)
  // Example: 'http://192.168.10.7:8000/api'
  static const String apiBaseUrl = 'http://192.168.10.7:8000/api';

  // Optional: candidates the app will probe at startup to auto-detect server
  static const List<String> apiCandidates = <String>[
    'http://192.168.10.7:8000/api',
    // Common local development loopbacks
    'http://10.0.2.2:8000/api', // Android emulator
    'http://127.0.0.1:8000/api', // USB + adb reverse
    'http://localhost:8000/api', // desktop/web
  ];
}


