import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ride_guard/core/analysis/performance_meter.dart';
import 'package:ride_guard/core/fusion/motion_pipeline.dart';
import 'package:ride_guard/core/fusion/mount_orientation.dart';
import 'package:ride_guard/core/math/vec3.dart';
import 'package:ride_guard/core/safety/safety_baseline.dart';
import 'package:ride_guard/data/bike_catalogue.dart';
import 'package:ride_guard/data/local_store.dart';
import 'package:ride_guard/data/remote_repository.dart';
import 'package:ride_guard/data/sync_service.dart';
import 'package:ride_guard/models/bike_choice.dart';
import 'package:ride_guard/models/bike_profile.dart';
import 'package:ride_guard/models/calibration_profile.dart';
import 'package:ride_guard/models/model_check.dart';
import 'package:ride_guard/services/app_state.dart';
import 'package:ride_guard/services/phone_info.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';

/// Two models with known top speeds, so results don't depend on the data.
final _catalogue = BikeCatalogue.parse(_catalogueJson);

const _catalogueJson = '''
{
  "version": "test.1",
  "make_order": ["Testa"],
  "models": [
    {"id": "testa-250-2020", "make": "Testa", "model": "Two-Fifty",
     "year_from": 2020, "year_to": null, "markets": ["tr"],
     "category": "sport", "abs": "yes",
     "displacement_cc": {"value": 1000, "source": "https://t.example", "quality": "official"},
     "power_kw": null, "weight_kg": null,
     "top_speed_kmh": {"value": 250, "source": "https://t.example", "quality": "official"},
     "zero_to_100_s": null},
    {"id": "testa-310-2020", "make": "Testa", "model": "Three-Ten",
     "year_from": 2020, "year_to": null, "markets": ["tr"],
     "category": "sport", "abs": "yes",
     "displacement_cc": {"value": 1400, "source": "https://t.example", "quality": "official"},
     "power_kw": null, "weight_kg": null,
     "top_speed_kmh": {"value": 310, "source": "https://t.example", "quality": "official"},
     "zero_to_100_s": null}
  ]
}
''';

CalibrationProfile _calibrationFor(BikeProfile bike) => CalibrationProfile(
  id: 'a0000000-0000-4000-8000-000000000001',
  bikeId: bike.id,
  rideId: 'a0000000-0000-4000-8000-000000000002',
  calibratedAt: DateTime.utc(2026, 10, 24),
  params: FusionParams(mount: MountOrientation.provisional(Vec3.unitY)),
  forwardFromMotion: true,
  straightOffsetDeg: 0,
  quality: 0.9,
);

InitReadings _readings(CalibrationProfile cal, {double top = 300}) =>
    InitReadings(
      calibrationId: cal.id,
      rideId: cal.rideId,
      readings: PerformanceReadings(
        sustainedTopSpeedKmh: top,
        peakAccelMps2: 3,
        peakDecelMps2: 4,
      ),
      imuHz: 100,
    );

void main() {
  late ({SyncService sync, RemoteRepository remote, RecordingBackend backend})
  stack;
  late AppState app;

  Future<AppState> open({BikeCatalogue? catalogue}) async {
    final a = AppState(
      store: await LocalStore.open(),
      remote: stack.remote,
      catalogue: catalogue ?? _catalogue,
      phoneInfo: () async =>
          const PhoneInfo(model: 'Pixel 9', osVersion: 'Android 16'),
    );
    await a.load();
    return a;
  }

  List<Map<String, dynamic>> checks(String bikeId) =>
      stack.backend.bodiesFor('PUT', '/v1/bikes/$bikeId/model-checks/');

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    stack = offlineFirstStack();
    app = await open();
  });

  Future<CalibrationProfile> initRide(double top) async {
    final cal = _calibrationFor(app.bike!);
    await app.saveCalibration(cal);
    await app.saveSafetyBaseline(SafetyBaseline(calibrationId: cal.id));
    await app.recordInitRide(cal, _readings(cal, top: top));
    await stack.sync.flush();
    return cal;
  }

  test('rider upload carries the phone model', () async {
    await app.saveBike(
      const OtherChoice(make: 'Vespa', model: 'GTS 300', topSpeedKmh: 90),
    );
    await stack.sync.flush();

    final bodies = stack.backend.bodiesFor('PUT', '/v1/riders/');
    expect(bodies, isNotEmpty);
    expect(bodies.last['phone_model'], 'Pixel 9');
    expect(bodies.last['os_version'], 'Android 16');
  });

  test('a failing reader falls back to unknown', () async {
    final a = AppState(
      store: await LocalStore.open(),
      remote: stack.remote,
      catalogue: _catalogue,
      phoneInfo: () async => throw StateError('no plugin'),
    );
    await a.load();
    expect(a.phone.model, isNull);
  });

  test(
    'a catalogue bike takes its top speed and name from the catalogue',
    () async {
      final bike = await app.saveBike(
        CatalogueChoice(model: _catalogue.byId('testa-250-2020')!),
      );
      expect(bike.model, 'Testa Two-Fifty (2020–)');
      expect(bike.ratedTopSpeedKmh, 250);
      expect(bike.topSpeedSource, TopSpeedSource.catalogue);
      expect(bike.catalogueVersion, 'test.1');
      expect(bike.otherModel, isNull);
      expect(app.startupStep, StartupStep.calibration);
    },
  );

  test('impossible measured top speed takes priority', () async {
    final bike = await app.saveBike(
      CatalogueChoice(model: _catalogue.byId('testa-250-2020')!),
    );
    await initRide(300);

    final check = checks(bike.id).single;
    expect(check['reason'], 'init_ride');
    expect(check['results']['top_speed'], 'mismatch');
    expect(check['mismatch'], isTrue);
    expect(check['expected']['top_speed_kmh'], 250);
    expect(check['measured']['sustained_top_speed_kmh'], 300);
    expect(check['phone_model'], 'Pixel 9');
    expect(check['imu_hz'], 100);
    expect(app.bike!.id, bike.id);
    expect(app.bike!.ratedTopSpeedKmh, 300);
    expect(app.bike!.topSpeedSource, TopSpeedSource.measured);
    // The bike is re-uploaded with the measured top speed.
    final bikes = stack.backend.bodiesFor(
      'PUT',
      RegExp('/v1/bikes/${bike.id}\$'),
    );
    expect(bikes.last['rated_top_speed_kmh'], 300);
    expect(bikes.last['top_speed_source'], 'measured');
    // Survives a restart.
    final reloaded = await open();
    expect(reloaded.bike!.ratedTopSpeedKmh, 300);
    expect(reloaded.initReadings!.readings.sustainedTopSpeedKmh, 300);
  });

  test('other bike init ride saves readings with no envelope', () async {
    final bike = await app.saveBike(
      const OtherChoice(
        make: 'CFMoto',
        model: '450NK',
        year: 2024,
        topSpeedKmh: 160,
      ),
    );
    expect(bike.isOther, isTrue);
    expect(bike.model, 'CFMoto 450NK');
    await initRide(300);

    final check = checks(bike.id).single;
    expect(check['expected'], isNull);
    expect(check['other_make'], 'CFMoto');
    expect(check['other_model'], '450NK');
    expect(check['other_year'], 2024);
    expect(check['catalogue_model_id'], isNull);
    expect(check['results'], {
      'top_speed': 'not_tested',
      'acceleration': 'not_tested',
      'braking': 'not_tested',
    });
    expect(check['mismatch'], isFalse);
    // Nothing to compare against: the rider's value stands.
    expect(app.bike!.ratedTopSpeedKmh, 160);
    expect(app.bike!.topSpeedSource, TopSpeedSource.rider);
    final reloaded = await open();
    expect(reloaded.initReadings!.readings.sustainedTopSpeedKmh, 300);
  });

  test('fixing the model re-checks without a new init ride', () async {
    final bike = await app.saveBike(
      CatalogueChoice(model: _catalogue.byId('testa-250-2020')!),
    );
    final cal = await initRide(300);
    expect(app.bike!.topSpeedSource, TopSpeedSource.measured);

    final fixed = await app.saveBike(
      CatalogueChoice(model: _catalogue.byId('testa-310-2020')!),
    );
    await stack.sync.flush();

    expect(fixed.id, bike.id);
    expect(app.calibration!.id, cal.id);
    expect(app.safetyBaseline, isNotNull);
    expect(app.startupStep, StartupStep.ready);
    final all = checks(bike.id);
    expect(all, hasLength(2));
    final second = all.last;
    expect(second['reason'], 'model_corrected');
    expect(second['calibration_id'], cal.id);
    expect(second['ride_id'], cal.rideId);
    expect(second['catalogue_model_id'], 'testa-310-2020');
    expect(second['results']['top_speed'], 'match');
    expect(second['mismatch'], isFalse);
    expect(app.bike!.ratedTopSpeedKmh, 310);
    expect(app.bike!.topSpeedSource, TopSpeedSource.catalogue);
  });

  test('saving the same model again keeps the measured top speed', () async {
    await app.saveBike(
      CatalogueChoice(model: _catalogue.byId('testa-250-2020')!),
    );
    await initRide(300);
    await app.saveBike(
      CatalogueChoice(model: _catalogue.byId('testa-250-2020')!),
    );
    await stack.sync.flush();
    expect(checks(app.bike!.id), hasLength(1));
    expect(app.bike!.ratedTopSpeedKmh, 300);
    expect(app.bike!.topSpeedSource, TopSpeedSource.measured);
  });

  test(
    'switching Other to a catalogue model clears the Other fields',
    () async {
      await app.saveBike(
        const OtherChoice(make: 'Testa', model: '250', topSpeedKmh: 240),
      );
      final bike = await app.saveBike(
        CatalogueChoice(model: _catalogue.byId('testa-250-2020')!),
      );
      expect(bike.otherMake, isNull);
      expect(bike.otherModel, isNull);
      expect(bike.otherYear, isNull);
      final back = await app.saveBike(
        const OtherChoice(make: 'Testa', model: '250', topSpeedKmh: 240),
      );
      expect(back.catalogueModelId, isNull);
      expect(back.catalogueVersion, isNull);
      expect(back.topSpeedSource, TopSpeedSource.rider);
    },
  );

  test('different bike starts over', () async {
    final old = await app.saveBike(
      CatalogueChoice(model: _catalogue.byId('testa-250-2020')!),
    );
    await initRide(300);

    final bike = await app.saveBike(
      const OtherChoice(make: 'CFMoto', model: '450NK', topSpeedKmh: 160),
      differentBike: true,
    );
    await stack.sync.flush();

    expect(bike.id, isNot(old.id));
    expect(app.bike!.id, bike.id);
    expect(app.calibration, isNull);
    expect(app.safetyBaseline, isNull);
    expect(app.initReadings, isNull);
    expect(app.startupStep, StartupStep.calibration);
    expect(checks(bike.id), isEmpty);
    expect(checks(old.id), hasLength(1));
    final reloaded = await open();
    expect(reloaded.bike!.id, bike.id);
    expect(reloaded.calibration, isNull);
    expect(reloaded.initReadings, isNull);
    expect(reloaded.startupStep, StartupStep.calibration);
  });

  test(
    'the check carries the catalogue version its envelope came from',
    () async {
      final bike = await app.saveBike(
        CatalogueChoice(model: _catalogue.byId('testa-250-2020')!),
      );
      expect(bike.catalogueVersion, 'test.1');
      // An app update ships a newer catalogue before the init ride.
      app = await open(
        catalogue: BikeCatalogue.parse(
          _catalogueJson.replaceFirst('"test.1"', '"test.2"'),
        ),
      );
      await initRide(200);
      expect(checks(bike.id).single['catalogue_version'], 'test.2');
    },
  );

  test('an existing rider sends the phone and the legacy bike once', () async {
    // Stored by the app before the catalogue: no phone was ever sent and
    // the bike is free text.
    final legacy = BikeProfile(
      id: 'b0000000-0000-4000-8000-000000000001',
      model: 'Honda CBR 650R',
      ratedTopSpeedKmh: 220,
      createdAt: DateTime.utc(2026, 1, 2),
    );
    SharedPreferences.setMockInitialValues({
      'rider_id': 'r0000000-0000-4000-8000-000000000001',
      'bike': jsonEncode({
        'id': legacy.id,
        'model': legacy.model,
        'rated_top_speed_kmh': 220,
        'created_at': '2026-01-02T00:00:00.000Z',
      }),
      'calibration': jsonEncode(_calibrationFor(legacy).toJson()),
    });
    stack = offlineFirstStack();
    app = await open();
    await stack.sync.flush();

    expect(app.bike!.isOther, isTrue);
    expect(app.startupStep, StartupStep.ready);
    final bikes = stack.backend.bodiesFor('PUT', '/v1/bikes/${legacy.id}');
    expect(bikes, hasLength(1));
    expect(bikes.single['other_model'], 'Honda CBR 650R');
    expect(bikes.single['catalogue_model_id'], isNull);
    expect(bikes.single['top_speed_source'], 'rider');
    final riders = stack.backend.bodiesFor(
      'PUT',
      '/v1/riders/r0000000-0000-4000-8000-000000000001',
    );
    expect(riders, hasLength(1));
    expect(riders.single['phone_model'], 'Pixel 9');
    expect(riders.single['os_version'], 'Android 16');

    // Next start, same phone: nothing new to send.
    app = await open();
    await stack.sync.flush();
    expect(stack.backend.bodiesFor('PUT', '/v1/riders/'), hasLength(1));
    expect(stack.backend.bodiesFor('PUT', '/v1/bikes/'), hasLength(1));
    expect(app.calibration, isNotNull);

    // A new phone (or OS update) is sent once.
    final updated = AppState(
      store: await LocalStore.open(),
      remote: stack.remote,
      catalogue: _catalogue,
      phoneInfo: () async =>
          const PhoneInfo(model: 'Pixel 10', osVersion: 'Android 17'),
    );
    await updated.load();
    await stack.sync.flush();
    final after = stack.backend.bodiesFor('PUT', '/v1/riders/');
    expect(after, hasLength(2));
    expect(after.last['phone_model'], 'Pixel 10');
  });

  test('saving a bike records the phone as sent', () async {
    await app.saveBike(
      const OtherChoice(make: 'Vespa', model: 'GTS 300', topSpeedKmh: 90),
    );
    app = await open();
    await stack.sync.flush();
    expect(stack.backend.bodiesFor('PUT', '/v1/riders/'), hasLength(1));
  });
}
