import 'package:shared_preferences/shared_preferences.dart';

class RuntimeConfig {
  RuntimeConfig._internal();
  static final RuntimeConfig instance = RuntimeConfig._internal();

  static const String _keyApiBaseUrl = 'runtime_api_base_url';

  String? _apiBaseUrlOverride;

  String? get apiBaseUrlOverride => _apiBaseUrlOverride;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _apiBaseUrlOverride = prefs.getString(_keyApiBaseUrl);
  }

  Future<void> setApiBaseUrlOverride(String? url) async {
    _apiBaseUrlOverride = (url != null && url.trim().isNotEmpty) ? url.trim() : null;
    final prefs = await SharedPreferences.getInstance();
    if (_apiBaseUrlOverride == null) {
      await prefs.remove(_keyApiBaseUrl);
    } else {
      await prefs.setString(_keyApiBaseUrl, _apiBaseUrlOverride!);
    }
  }
}


