import 'package:flutter/foundation.dart';

import '../models/bike_profile.dart';
import '../models/calibration_profile.dart';
import '../models/ride_sample.dart';
import '../models/ride_summary.dart';
import 'sync_service.dart';

/// Typed backend API. Every call is queued in the outbox, so callers never
/// wait on the network and nothing is lost offline.
class RemoteRepository {
  RemoteRepository(this._sync);

  final SyncService _sync;

  Future<void> upsertRider(String riderId) => _sync.enqueue(
    'PUT',
    '/v1/riders/$riderId',
    {'platform': defaultTargetPlatform.name},
  );

  Future<void> upsertBike(String riderId, BikeProfile bike) =>
      _sync.enqueue('PUT', '/v1/bikes/${bike.id}', {
        'rider_id': riderId,
        'model': bike.model,
        'rated_top_speed_kmh': bike.ratedTopSpeedKmh,
      });

  Future<void> startRide({
    required String rideId,
    required String bikeId,
    required RideKind kind,
    required DateTime startedAt,
    required int windowMinutes,
    String? calibrationId,
  }) => _sync.enqueue('PUT', '/v1/rides/$rideId', {
    'bike_id': bikeId,
    'kind': kind.name,
    'started_at': startedAt.toUtc().toIso8601String(),
    'analysis_window_min': windowMinutes,
    'calibration_id': calibrationId,
  });

  Future<void> addSamples(String rideId, List<RideSample> samples) =>
      _sync.enqueue('POST', '/v1/rides/$rideId/samples', {
        'samples': [for (final s in samples) s.toJson()],
      });

  Future<void> finishRide(RideSummary summary) => _sync.enqueue(
    'PUT',
    '/v1/rides/${summary.rideId}/summary',
    summary.toApiJson(),
  );

  Future<void> saveCalibration(CalibrationProfile profile) => _sync.enqueue(
    'PUT',
    '/v1/calibrations/${profile.id}',
    profile.toApiJson(),
  );
}
