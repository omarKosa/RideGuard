import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/safety/safety_baseline.dart';
import '../models/bike_profile.dart';
import '../models/calibration_profile.dart';
import '../models/emergency_contact.dart';
import '../models/ride_summary.dart';

/// Small on-device key-value persistence for profile and settings.
class LocalStore {
  LocalStore(this._prefs);

  static Future<LocalStore> open() async =>
      LocalStore(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static const _riderId = 'rider_id';
  static const _bike = 'bike';
  static const _calibration = 'calibration';
  static const _lastRide = 'last_ride';
  static const _apiUrl = 'api_url';
  static const _emergencyContact = 'emergency_contact';
  static const _safetyBaseline = 'safety_baseline';

  String? get riderId => _prefs.getString(_riderId);
  Future<void> setRiderId(String id) => _prefs.setString(_riderId, id);

  BikeProfile? get bike => _read(_bike, BikeProfile.fromJson);
  Future<void> setBike(BikeProfile bike) => _write(_bike, bike.toJson());

  CalibrationProfile? get calibration =>
      _read(_calibration, CalibrationProfile.fromJson);
  Future<void> setCalibration(CalibrationProfile? c) => c == null
      ? _prefs.remove(_calibration)
      : _write(_calibration, c.toJson());

  RideSummary? get lastRide => _read(_lastRide, RideSummary.fromJson);
  Future<void> setLastRide(RideSummary s) => _write(_lastRide, s.toJson());

  String? get apiUrl => _prefs.getString(_apiUrl);
  Future<void> setApiUrl(String url) => _prefs.setString(_apiUrl, url);

  EmergencyContact? get emergencyContact =>
      _read(_emergencyContact, EmergencyContact.fromJson);
  Future<void> setEmergencyContact(EmergencyContact? c) => c == null
      ? _prefs.remove(_emergencyContact)
      : _write(_emergencyContact, c.toJson());

  SafetyBaseline? get safetyBaseline =>
      _read(_safetyBaseline, SafetyBaseline.fromJson);
  Future<void> setSafetyBaseline(SafetyBaseline? b) => b == null
      ? _prefs.remove(_safetyBaseline)
      : _write(_safetyBaseline, b.toJson());

  T? _read<T>(String key, T Function(Map<String, dynamic>) fromJson) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      return fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Object {
      // Stored by an incompatible app version; treat as absent.
      return null;
    }
  }

  Future<void> _write(String key, Map<String, dynamic> json) =>
      _prefs.setString(key, jsonEncode(json));
}
