import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum CallResult {
  /// The call was placed.
  placed,

  /// No call permission (or an emergency number): the dialer was opened
  /// with the number filled in.
  dialerOpened,
  failed,
}

/// Alarm, vibration and phone calls. Abstract so controllers can be tested
/// with a fake.
abstract class EmergencyPlatform {
  /// [urgent]: loud looping alarm with continuous vibration, at full alarm
  /// volume. Otherwise a short alert sound and vibration pattern.
  Future<void> startAlarm({required bool urgent});
  Future<void> stopAlarm();
  Future<CallResult> call(String number);

  /// Asks for permission to place calls without the dialer. Returns true if
  /// granted.
  Future<bool> requestCallPermission();
}

/// Android implementation (MainActivity.kt). Elsewhere, falls back to haptics
/// and the system alert sound, and cannot call.
class DeviceEmergencyPlatform implements EmergencyPlatform {
  const DeviceEmergencyPlatform();

  static const _channel = MethodChannel('rideguard/emergency');

  @override
  Future<void> startAlarm({required bool urgent}) async {
    try {
      await _channel.invokeMethod<void>('startAlarm', {'urgent': urgent});
    } on Object catch (e) {
      debugPrint('Native alarm unavailable: $e');
      await HapticFeedback.vibrate();
      await SystemSound.play(SystemSoundType.alert);
    }
  }

  @override
  Future<void> stopAlarm() async {
    try {
      await _channel.invokeMethod<void>('stopAlarm');
    } on Object catch (e) {
      debugPrint('Native alarm unavailable: $e');
    }
  }

  @override
  Future<CallResult> call(String number) async {
    try {
      final result = await _channel.invokeMethod<String>('call', {
        'number': number,
      });
      return switch (result) {
        'placed' => CallResult.placed,
        'dialer' => CallResult.dialerOpened,
        _ => CallResult.failed,
      };
    } on Object catch (e) {
      debugPrint('Calling failed: $e');
      return CallResult.failed;
    }
  }

  @override
  Future<bool> requestCallPermission() async {
    try {
      return await _channel.invokeMethod<bool>('requestCallPermission') ??
          false;
    } on Object catch (e) {
      debugPrint('Call permission unavailable: $e');
      return false;
    }
  }
}
