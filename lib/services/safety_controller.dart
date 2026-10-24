import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../core/safety/motion_clip.dart';
import '../core/safety/safety_monitor.dart';
import '../models/emergency_contact.dart';
import '../models/incident.dart';
import 'app_state.dart';
import 'emergency_platform.dart';

enum SafetyPhase {
  /// Nothing critical going on (a warning may still be shown).
  idle,

  /// Crash detected: alarm sounding, counting down to the call.
  countdown,

  /// The countdown ran out but nobody could be called: alarm keeps going.
  alarming,

  /// The emergency contact was called (or the dialer opened).
  called,
}

/// Turns hazards into the rider-facing response.
///
/// * Warnings (wobble, impact, extreme lean): short alert sound and
///   vibration plus an on-screen banner.
/// * Crash: looping alarm and a [countdown] the rider can cancel; when it
///   runs out the emergency contact is called.
///
/// Every incident is uploaded through the offline outbox, followed by the
/// raw motion around it ([reportClip]).
class SafetyController extends ChangeNotifier {
  SafetyController({
    required AppState app,
    required EmergencyPlatform platform,
    DateTime Function()? clock,
    this.countdown = AppConfig.crashCountdown,
    this.alertDuration = const Duration(seconds: 3),
    this.bannerDuration = const Duration(seconds: 20),
  }) : _app = app,
       _platform = platform,
       _clock = clock ?? DateTime.now;

  final Duration countdown;

  /// How long a warning sounds.
  final Duration alertDuration;

  /// How long a warning stays on screen.
  final Duration bannerDuration;

  final AppState _app;
  final EmergencyPlatform _platform;
  final DateTime Function() _clock;
  static const _uuid = Uuid();

  String? _rideId;
  SafetyPhase _phase = SafetyPhase.idle;
  Incident? _crash;
  Incident? _warning;
  int _secondsLeft = 0;
  Timer? _countdownTimer;
  Timer? _alertTimer;
  Timer? _bannerTimer;
  final List<Incident> _incidents = [];

  /// Where each reported hazard's clip goes. Keeps the ride too: clips cut
  /// short at the end of the ride arrive after [end].
  final Map<Hazard, ({String rideId, String incidentId})> _clipTargets =
      Map.identity();
  bool _disposed = false;

  SafetyPhase get phase => _phase;

  /// The crash being handled, if any.
  Incident? get crash => _crash;

  /// The latest warning, while its banner is up.
  Incident? get warning => _warning;
  int get secondsLeft => _secondsLeft;
  List<Incident> get incidents => List.unmodifiable(_incidents);
  EmergencyContact? get contact => _app.emergencyContact;

  /// Starts attributing hazards to [rideId].
  void begin(String rideId) {
    _rideId = rideId;
    _clipTargets.clear();
  }

  /// Handles a hazard from the [SafetyMonitor].
  void report(Hazard hazard) {
    final rideId = _rideId;
    if (rideId == null || _disposed) return;
    final incident = Incident.fromHazard(
      id: _uuid.v4(),
      rideId: rideId,
      hazard: hazard,
      detectedAt: _clock(),
    );
    if (hazard.kind.critical) {
      // One crash at a time; the first one owns the alarm.
      if (_phase != SafetyPhase.idle) return;
      _startCountdown(incident);
    } else {
      _warn(incident);
    }
    _clipTargets[hazard] = (rideId: rideId, incidentId: incident.id);
  }

  /// Uploads the raw motion around [hazard] (the very object passed to
  /// [report]) against its incident. Queued after the incident, so the
  /// backend has it first. A hazard that made no incident has nowhere to
  /// go and its clip is dropped; each incident gets one clip.
  void reportClip(Hazard hazard, MotionClip clip) {
    final target = _clipTargets.remove(hazard);
    if (target == null) return;
    unawaited(
      _app.remote.saveIncidentClip(target.rideId, target.incidentId, clip),
    );
  }

  void _warn(Incident incident) {
    _record(incident);
    _warning = incident;
    _bannerTimer?.cancel();
    _bannerTimer = Timer(bannerDuration, () {
      _warning = null;
      _notify();
    });
    // Never talk over a crash alarm.
    if (_phase == SafetyPhase.idle) {
      unawaited(_platform.startAlarm(urgent: false));
      _alertTimer?.cancel();
      _alertTimer = Timer(alertDuration, () {
        if (_phase == SafetyPhase.idle) unawaited(_platform.stopAlarm());
      });
    }
    _notify();
  }

  void _startCountdown(Incident incident) {
    _alertTimer?.cancel();
    _crash = incident;
    _record(incident);
    _phase = SafetyPhase.countdown;
    _secondsLeft = countdown.inSeconds;
    unawaited(_platform.startAlarm(urgent: true));
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _secondsLeft--;
      if (_secondsLeft <= 0) {
        timer.cancel();
        unawaited(_escalate());
      }
      _notify();
    });
    _notify();
  }

  Future<void> _escalate() async {
    final crash = _crash;
    if (crash == null || _phase != SafetyPhase.countdown) return;
    final contact = _app.emergencyContact;
    if (contact == null) {
      // The alarm keeps sounding so people nearby notice.
      _phase = SafetyPhase.alarming;
      _resolve(IncidentOutcome.noContact);
      return;
    }
    // Silence the alarm so the call can be heard.
    await _platform.stopAlarm();
    final result = await _platform.call(contact.phone);
    if (_crash != crash) return; // Dismissed meanwhile.
    switch (result) {
      case CallResult.placed:
        _phase = SafetyPhase.called;
        _resolve(IncidentOutcome.called);
      case CallResult.dialerOpened:
        _phase = SafetyPhase.called;
        _resolve(IncidentOutcome.dialerOpened);
      case CallResult.failed:
        _phase = SafetyPhase.alarming;
        unawaited(_platform.startAlarm(urgent: true));
        _resolve(IncidentOutcome.callFailed);
    }
  }

  /// "I'm OK": cancels the countdown, or silences the alarm afterwards.
  void dismiss() {
    if (_phase == SafetyPhase.idle) return;
    _countdownTimer?.cancel();
    if (_phase == SafetyPhase.countdown) _resolve(IncidentOutcome.cancelled);
    _phase = SafetyPhase.idle;
    _crash = null;
    unawaited(_platform.stopAlarm());
    _notify();
  }

  /// The ride is over. Stopping the ride proves the rider is OK. The
  /// warning banner goes too: it would cover what comes next.
  void end() {
    dismiss();
    _alertTimer?.cancel();
    _bannerTimer?.cancel();
    if (_warning != null) {
      unawaited(_platform.stopAlarm());
      _warning = null;
      _notify();
    }
    _rideId = null;
  }

  void _resolve(IncidentOutcome outcome) {
    final crash = _crash;
    if (crash == null) return;
    final resolved = crash.resolve(outcome, _clock());
    _crash = resolved;
    _record(resolved);
    _notify();
  }

  void _record(Incident incident) {
    final i = _incidents.indexWhere((x) => x.id == incident.id);
    if (i >= 0) {
      _incidents[i] = incident;
    } else {
      _incidents.add(incident);
    }
    unawaited(_app.remote.saveIncident(incident));
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    end();
    _disposed = true;
    _countdownTimer?.cancel();
    _alertTimer?.cancel();
    _bannerTimer?.cancel();
    super.dispose();
  }
}
