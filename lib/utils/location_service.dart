// Minimal location utility for requesting permissions and getting current GPS location
import 'package:geolocator/geolocator.dart';

class LocationService {
  static Future<bool> ensureLocationPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      // Open app settings so user can grant permission
      await Geolocator.openAppSettings();
      return false;
    }
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Prompt user to enable location services
      await Geolocator.openLocationSettings();
      return await Geolocator.isLocationServiceEnabled();
    }
    return true;
  }

  static Future<Position?> getCurrentPosition() async {
    try {
      final hasPermission = await ensureLocationPermission();
      if (!hasPermission) return null;
      // First try high accuracy with a timeout
      try {
        return await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 8),
        );
      } catch (_) {
        // Fallback to last known position if available
        return await Geolocator.getLastKnownPosition();
      }
    } catch (_) {
      return null;
    }
  }

  static Future<bool> requestPermissionsAndService() async {
    try {
      final ok = await ensureLocationPermission();
      if (!ok) return false;
      return await Geolocator.isLocationServiceEnabled();
    } catch (_) {
      return false;
    }
  }
}
