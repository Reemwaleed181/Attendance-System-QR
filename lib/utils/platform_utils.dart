import 'package:flutter/foundation.dart';
import 'runtime_config.dart';
import 'dev_defaults.dart';
import 'package:http/http.dart' as http;

class PlatformUtils {
  static bool get isWeb => kIsWeb;
  static bool get isMobile => !kIsWeb;

  // Optional override at build time:
  // flutter run --dart-define=API_BASE_URL=http://<host>:8000/api
  static const String _envBaseUrl = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
    // 0) Runtime override saved in app settings
    final saved = RuntimeConfig.instance.apiBaseUrlOverride;
    if (saved != null && saved.isNotEmpty) return saved;

    // 1) Respect any explicit override first
    if (_envBaseUrl.isNotEmpty) return _envBaseUrl;

    // 2) Standardized dev default: single LAN URL for all targets
    if (DevDefaults.apiBaseUrl.isNotEmpty) return DevDefaults.apiBaseUrl;

    // 3) Fallbacks (rarely used if DevDefaults is set)
    if (kIsWeb) return 'http://localhost:8000/api';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:8000/api';
      case TargetPlatform.iOS:
        return 'http://localhost:8000/api';
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return 'http://localhost:8000/api';
      default:
        return 'http://10.0.2.2:8000/api';
    }
  }

  // Best-effort auto-detect: try candidate URLs until one responds 200 OK at /health or /
  static Future<String> autodetectBaseUrl({Duration timeout = const Duration(seconds: 2)}) async {
    // 0) Respect runtime override or env first
    final saved = RuntimeConfig.instance.apiBaseUrlOverride;
    if (saved != null && saved.isNotEmpty) return saved;
    if (_envBaseUrl.isNotEmpty) return _envBaseUrl;

    final candidates = <String>{};
    candidates.addAll(DevDefaults.apiCandidates);

    for (final base in candidates) {
      try {
        final uri = Uri.parse(base);
        // Try a cheap endpoint first
        final resp = await http.get(Uri.parse('${uri.scheme}://${uri.host}:${uri.port}/api/'),).timeout(timeout);
        if (resp.statusCode >= 200 && resp.statusCode < 500) {
          return base; // treat as reachable
        }
      } catch (_) {
        // ignore and continue
      }
    }

    // Fallback to synchronous default
    return baseUrl;
  }
}
