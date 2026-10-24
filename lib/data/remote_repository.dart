import 'package:flutter/foundation.dart';

import '../models/bike_profile.dart';
import '../models/calibration_profile.dart';
import '../models/incident.dart';
import '../models/ride_sample.dart';
import '../models/ride_summary.dart';
import '../services/phone_info.dart';
import 'sync_service.dart';

/// Typed backend API. Every call is queued in the outbox, so callers never
/// wait on the network and nothing is lost offline.
class RemoteRepository {
  RemoteRepository(this._sync);

  final SyncService _sync;

  Future<void> upsertRider(String riderId, PhoneInfo phone) =>
      _sync.enqueue('PUT', '/v1/riders/$riderId', {
        'platform': defaultTargetPlatform.name,
        'phone_model': _clip(phone.model, 80),
        'os_version': _clip(phone.osVersion, 40),
      });

  /// Backend caps other_make/other_model; the full text stays in `model`.
  static String? _clip(String? text, int max) {
    final t = text?.trim();
    if (t == null || t.isEmpty) return null;
    return t.length <= max ? t : t.substring(0, max).trimRight();
  }

  Future<void> upsertBike(String riderId, BikeProfile bike) =>
      _sync.enqueue('PUT', '/v1/bikes/${bike.id}', {
        'rider_id': riderId,
        'model': bike.model,
        'rated_top_speed_kmh': bike.ratedTopSpeedKmh,
        'catalogue_model_id': bike.catalogueModelId,
        'catalogue_version': bike.catalogueVersion,
        'other_make': bike.isOther ? _clip(bike.otherMake, 40) : null,
        'other_model': bike.isOther
            ? _clip(bike.otherModel ?? bike.model, 60)
            : null,
        'other_year': bike.isOther ? bike.otherYear : null,
        'top_speed_source': bike.topSpeedSource.name,
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

  /// Upsert: a crash is sent when detected and again once resolved.
  Future<void> saveIncident(Incident incident) => _sync.enqueue(
    'PUT',
    '/v1/rides/${incident.rideId}/incidents/${incident.id}',
    incident.toApiJson(),
  );
}
