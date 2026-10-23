import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Turns "keep the screen on" on or off. Injectable so tests avoid the
/// platform channel.
typedef KeepAwake = Future<void> Function(bool enable);

/// Default [KeepAwake]: the phone sits on a mount while recording and nobody
/// touches it, so the screen must not lock.
Future<void> keepScreenAwake(bool enable) async {
  try {
    await WakelockPlus.toggle(enable: enable);
  } on Object catch (e) {
    debugPrint('Wakelock unavailable: $e');
  }
}
