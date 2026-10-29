import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../config/app_config.dart';
import '../core/fusion/motion_pipeline.dart';
import '../core/math/vec3.dart';
import '../core/safety/safety_monitor.dart';

class ImuEvent {
  const ImuEvent(this.value, this.timestamp);
  final Vec3 value;
  final DateTime timestamp;
}

class LocationEvent {
  const LocationEvent({
    required this.speedMps,
    required this.latitude,
    required this.longitude,
    required this.accuracyM,
    required this.speedAccuracyMps,
  });
  final double speedMps;
  final double latitude;
  final double longitude;
  final double accuracyM;
  final double speedAccuracyMps;
}

enum LocationAccess { granted, denied, serviceDisabled }

/// Platform sensors. Abstract so controllers can be driven by fakes.
abstract class SensorSource {
  Future<LocationAccess> requestLocation();
  Stream<ImuEvent> accelerometer();
  Stream<ImuEvent> userAccelerometer();
  Stream<ImuEvent> gyroscope();
  Stream<LocationEvent> location();
}

class DeviceSensorSource implements SensorSource {
  @override
  Future<LocationAccess> requestLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return LocationAccess.serviceDisabled;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      return permission == LocationPermission.always ||
              permission == LocationPermission.whileInUse
          ? LocationAccess.granted
          : LocationAccess.denied;
    } on Object catch (e) {
      debugPrint('Location permission check failed: $e');
      return LocationAccess.denied;
    }
  }

  @override
  Stream<ImuEvent> accelerometer() => accelerometerEventStream(
    samplingPeriod: AppConfig.imuSamplingPeriod,
  ).map((e) => ImuEvent(Vec3(e.x, e.y, e.z), e.timestamp));

  @override
  Stream<ImuEvent> userAccelerometer() => userAccelerometerEventStream(
    samplingPeriod: AppConfig.imuSamplingPeriod,
  ).map((e) => ImuEvent(Vec3(e.x, e.y, e.z), e.timestamp));

  @override
  Stream<ImuEvent> gyroscope() => gyroscopeEventStream(
    samplingPeriod: AppConfig.imuSamplingPeriod,
  ).map((e) => ImuEvent(Vec3(e.x, e.y, e.z), e.timestamp));

  @override
  Stream<LocationEvent> location() {
    final LocationSettings settings =
        defaultTargetPlatform == TargetPlatform.android
        ? AndroidSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 0,
            intervalDuration: const Duration(seconds: 1),
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 0,
          );
    return Geolocator.getPositionStream(locationSettings: settings)
        // Fixes without a Doppler speed would read as "stopped".
        .where((p) => p.hasSpeed && p.speed >= 0)
        .map(
          (p) => LocationEvent(
            speedMps: p.speed,
            latitude: p.latitude,
            longitude: p.longitude,
            accuracyM: p.accuracy,
            speedAccuracyMps: p.speedAccuracy,
          ),
        );
  }
}

/// Wires a [SensorSource] into a [MotionPipeline] and emits a processed
/// [MotionState] at [AppConfig.sampleHz]. A [SafetyMonitor] gets the raw IMU
/// readings at full rate (crash impacts and wobbles are too fast for 10 Hz).
class SensorFeed {
  /// [clock] returns monotonic seconds; defaults to a stopwatch started with
  /// the feed. Injectable so recorded/simulated data can be replayed.
  SensorFeed(this._source, {double Function()? clock}) : _customClock = clock;

  final SensorSource _source;
  final double Function()? _customClock;
  final List<StreamSubscription<Object>> _subs = [];
  final Stopwatch _clock = Stopwatch();
  Timer? _ticker;
  DateTime? _lastGyroTs;
  double _lastGyroT = 0;

  bool gpsAvailable = false;

  /// Sensors whose stream failed (usually: the phone has none).
  final Set<String> missingSensors = {};

  /// One short line for the rider, or null. Linear acceleration alone is
  /// not worth a warning (only speed between GPS fixes uses it).
  String? get sensorError {
    if (missingSensors.contains('accelerometer')) {
      return 'Your device has no motion sensor';
    }
    if (missingSensors.contains('gyroscope')) {
      return 'Your device has no gyroscope sensor';
    }
    return null;
  }

  bool get isRunning => _ticker != null;

  double get _now => _customClock?.call() ?? _clock.elapsedMicroseconds / 1e6;

  Future<void> start(
    MotionPipeline pipeline,
    void Function(MotionState state) onTick, {
    SafetyMonitor? safety,
  }) async {
    await stop();
    missingSensors.clear();
    gpsAvailable = await _source.requestLocation() == LocationAccess.granted;
    _clock
      ..reset()
      ..start();
    _lastGyroTs = null;

    void Function(Object) onError(String sensor) => (Object e) {
      missingSensors.add(sensor);
      debugPrint('$sensor unavailable: $e');
    };

    _subs
      ..add(
        _source.accelerometer().listen((e) {
          final t = _now;
          pipeline.addAccel(e.value, t);
          safety?.addAccel(e.value, t);
        }, onError: onError('accelerometer')),
      )
      ..add(
        _source.userAccelerometer().listen(
          (e) => pipeline.addLinearAccel(e.value, _now),
          onError: onError('linear'),
        ),
      )
      ..add(
        _source.gyroscope().listen((e) {
          final t = _now;
          final dt = _gyroDt(e.timestamp, t);
          pipeline.addGyro(e.value, t, dt);
          safety?.addGyro(e.value, t, dt);
        }, onError: onError('gyroscope')),
      );

    if (gpsAvailable) {
      _subs.add(
        _source.location().listen(
          (e) => pipeline.addGps(
            GpsFix(
              t: _now,
              speedMps: e.speedMps,
              latitude: e.latitude,
              longitude: e.longitude,
              accuracyM: e.accuracyM,
              speedAccuracyMps: e.speedAccuracyMps,
            ),
          ),
          onError: (Object e) {
            debugPrint('Location error: $e');
            gpsAvailable = false;
          },
        ),
      );
    }

    _ticker = Timer.periodic(
      Duration(microseconds: 1000000 ~/ AppConfig.sampleHz),
      (_) {
        final state = pipeline.snapshot();
        safety?.update(state, pipeline.mount);
        onTick(state);
      },
    );
  }

  /// Integration step from sensor timestamps (accurate even when events
  /// arrive in bursts), falling back to arrival time.
  double _gyroDt(DateTime ts, double t) {
    final prevTs = _lastGyroTs;
    final prevT = _lastGyroT;
    _lastGyroTs = ts;
    _lastGyroT = t;
    if (prevTs == null) return 0.02;
    final fromTs = ts.difference(prevTs).inMicroseconds / 1e6;
    if (fromTs > 0 && fromTs < 0.2) return fromTs;
    return (t - prevT).clamp(0.001, 0.1).toDouble();
  }

  Future<void> stop() async {
    _ticker?.cancel();
    _ticker = null;
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    _clock.stop();
  }
}
