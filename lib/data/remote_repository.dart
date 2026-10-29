import 'package:flutter/foundation.dart';

import '../core/safety/motion_clip.dart';
import '../models/bike_profile.dart';
import '../models/calibration_profile.dart';
import '../models/incident.dart';
import '../models/model_check.dart';
import '../models/ride_sample.dart';
import '../models/ride_summary.dart';
import '../models/text_clip.dart';
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
        'phone_model': clipText(phone.model, 80),
        'os_version': clipText(phone.osVersion, 40),
      });

  /// Links the Google account the rider signed in with; the backend
  /// verifies [idToken] with Google.
  Future<void> linkGoogle(String riderId, String idToken) =>
      _sync.enqueue('PUT', '/v1/riders/$riderId/google', {'id_token': idToken});

  /// The name the rider chose. A PUT keyed by rider id, so the outbox can
  /// resend it from any network address and the last one wins.
  Future<void> setRiderName(String riderId, String name) =>
      _sync.enqueue('PUT', '/v1/riders/$riderId/name', {'name': name});

  /// Backend caps other_make/other_model (clipped); the full text stays in
  /// `model`.
  Future<void> upsertBike(String riderId, BikeProfile bike) =>
      _sync.enqueue('PUT', '/v1/bikes/${bike.id}', {
        'rider_id': riderId,
        'model': bike.model,
        'rated_top_speed_kmh': bike.ratedTopSpeedKmh,
        'catalogue_model_id': bike.catalogueModelId,
        'catalogue_version': bike.catalogueVersion,
        'other_make': bike.isOther ? clipText(bike.otherMake, 40) : null,
        'other_model': bike.isOther
            ? clipText(bike.otherModel ?? bike.model, 60)
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

  /// Raw motion around an incident; the incident must already be queued.
  Future<void> saveIncidentClip(
    String rideId,
    String incidentId,
    MotionClip clip,
  ) => _sync.enqueue(
    'PUT',
    '/v1/rides/$rideId/incidents/$incidentId/clip',
    clip.toApiJson(),
  );

  /// Upsert by id; the calibration and init ride must already be queued.
  Future<void> saveModelCheck(ModelCheck c) => _sync.enqueue(
    'PUT',
    '/v1/bikes/${c.bikeId}/model-checks/${c.id}',
    c.toApiJson(),
  );
}
