import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:ride_guard/core/fusion/motion_pipeline.dart';
import 'package:ride_guard/core/fusion/mount_orientation.dart';
import 'package:ride_guard/core/math/vec3.dart';
import 'package:ride_guard/data/bike_catalogue.dart';
import 'package:ride_guard/data/local_store.dart';
import 'package:ride_guard/models/bike_choice.dart';
import 'package:ride_guard/models/bike_profile.dart';
import 'package:ride_guard/models/calibration_profile.dart';
import 'package:ride_guard/screens/bike_setup/bike_setup_screen.dart';
import 'package:ride_guard/screens/bike_setup/make_chips.dart';
import 'package:ride_guard/screens/bike_setup/model_change_dialog.dart';
import 'package:ride_guard/screens/bike_setup/model_list.dart';
import 'package:ride_guard/screens/bike_setup/other_bike_form.dart';
import 'package:ride_guard/screens/safety_briefing_screen.dart';
import 'package:ride_guard/services/app_state.dart';
import 'package:ride_guard/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fakes.dart';

Future<AppState> _app() async {
  final stack = offlineFirstStack();
  final app = AppState(
    store: await LocalStore.open(),
    remote: stack.remote,
    catalogue: realCatalogue(),
  );
  await app.load();
  return app;
}

Future<void> _calibrate(AppState app) => app.saveCalibration(
  CalibrationProfile(
    id: 'cal',
    bikeId: app.bike!.id,
    rideId: 'ride',
    calibratedAt: DateTime.utc(2026, 10, 24),
    params: FusionParams(mount: MountOrientation.provisional(Vec3.unitY)),
    forwardFromMotion: true,
    straightOffsetDeg: 0,
    quality: 0.9,
  ),
);

/// First run shows the picker directly; editing opens it from a host page,
/// like Home does.
Future<void> _pump(
  WidgetTester tester,
  AppState app, {
  bool editing = false,
  Size size = const Size(1080, 2400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: app,
      child: MaterialApp(
        theme: buildAppTheme(),
        home: editing ? const _Host() : const BikeSetupScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (editing) await _tap(tester, 'open-edit');
}

class _Host extends StatelessWidget {
  const _Host();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        key: const Key('open-edit'),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const BikeSetupScreen(editing: true),
          ),
        ),
        child: const Text('HOST'),
      ),
    ),
  );
}

Future<void> _tap(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, String key, String text) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.enterText(f, text);
  await tester.pumpAndSettle();
}

/// Taps [make]'s chip, expanding "+ more" when it isn't among the first.
Future<void> _pickMake(WidgetTester tester, String make) async {
  if (find.byKey(Key('make-$make')).evaluate().isEmpty) {
    await _tap(tester, 'more-makes');
  }
  await _tap(tester, 'make-$make');
}

Future<void> _pickModel(WidgetTester tester, CatalogueModel m) async {
  await _pickMake(tester, m.make);
  await _tap(tester, 'model-${m.id}');
}

CatalogueModel _firstWhere(bool Function(CatalogueModel) test) {
  final cat = realCatalogue();
  return [
    for (final make in cat.makes) ...cat.modelsFor(make),
  ].firstWhere(test);
}

bool _makeSelected(WidgetTester tester, String make) =>
    tester.widget<MakeChip>(find.byKey(Key('make-$make'))).selected;

void _legacy(String model) => SharedPreferences.setMockInitialValues({
  'bike':
      '{"id":"legacy","model":"$model","rated_top_speed_kmh":214,'
      '"created_at":"2026-10-01T00:00:00Z"}',
});

bool _selected(WidgetTester tester, String id) =>
    tester.widget<ModelRow>(find.byKey(Key('model-$id'))).selected;

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final cat = realCatalogue();
  final gsx2021 = cat.byId('suzuki-gsx-s1000-2021')!;

  testWidgets('pick Suzuki then GSX-S1000 2021 and continue', (tester) async {
    final app = await _app();
    await _pump(tester, app);
    expect(find.text('SET UP YOUR BIKE'), findsOneWidget);

    await _tap(tester, 'make-Suzuki');
    expect(find.text('GSX-S1000'), findsWidgets);
    expect(find.text(gsx2021.yearsLabel), findsWidgets);
    await _tap(tester, 'model-suzuki-gsx-s1000-2021');
    expect(_selected(tester, 'suzuki-gsx-s1000-2021'), isTrue);

    // The catalogue has no sourced top speed for the owner's bike, so the
    // rider is asked for it.
    expect(gsx2021.topSpeedKmh, isNull);
    await _enter(tester, 'top-speed-field', '250');
    await _tap(tester, 'save-bike');

    final bike = app.bike!;
    expect(bike.catalogueModelId, 'suzuki-gsx-s1000-2021');
    expect(bike.topSpeedSource, TopSpeedSource.rider);
    expect(bike.ratedTopSpeedKmh, 250);
    expect(find.byType(SafetyBriefingScreen), findsOneWidget);
  });

  testWidgets('a model with a catalogue top speed asks nothing more', (
    tester,
  ) async {
    final app = await _app();
    final m = cat.byId('suzuki-gsx-s1000-2015')!;
    expect(m.topSpeedKmh, isNotNull);
    await _pump(tester, app);
    await _pickModel(tester, m);

    expect(find.byKey(const Key('top-speed-field')), findsNothing);
    // Nothing spec-derived is shown for a known model.
    expect(find.textContaining('km/h'), findsNothing);
    await _tap(tester, 'save-bike');

    expect(app.bike!.catalogueModelId, m.id);
    expect(app.bike!.topSpeedSource, TopSpeedSource.catalogue);
    expect(app.bike!.ratedTopSpeedKmh, m.topSpeedKmh!.value);
    expect(find.byType(SafetyBriefingScreen), findsOneWidget);
  });

  testWidgets('model without top speed asks for it', (tester) async {
    final app = await _app();
    final m = _firstWhere((m) => m.topSpeedKmh == null);
    await _pump(tester, app);
    await _pickModel(tester, m);

    expect(find.byKey(const Key('top-speed-field')), findsOneWidget);
    expect(find.text('Fastest possible speed'), findsOneWidget);
    await _tap(tester, 'save-bike');
    expect(find.text('Enter a speed in km/h'), findsOneWidget);
    expect(app.bike, isNull);

    await _enter(tester, 'top-speed-field', '900');
    await _tap(tester, 'save-bike');
    expect(find.text('Between 40 and 420 km/h'), findsOneWidget);
    expect(app.bike, isNull);
  });

  testWidgets('continue without a model asks for one', (tester) async {
    final app = await _app();
    await _pump(tester, app);
    await _tap(tester, 'save-bike');
    expect(find.text('Choose your make'), findsOneWidget);

    await _tap(tester, 'make-Honda');
    expect(find.text('Choose your make'), findsNothing);
    await _tap(tester, 'save-bike');
    expect(find.text('Choose your model'), findsOneWidget);
    expect(app.bike, isNull);
  });

  testWidgets('+ more shows every make', (tester) async {
    final app = await _app();
    await _pump(tester, app);
    expect(find.byType(MakeChip), findsNWidgets(8));
    expect(find.byKey(const Key('make-Harley-Davidson')), findsNothing);

    await _tap(tester, 'more-makes');
    expect(find.byType(MakeChip), findsNWidgets(cat.makes.length));
    expect(find.byKey(const Key('more-makes')), findsNothing);
    await _tap(tester, 'make-Harley-Davidson');
    expect(
      tester
          .widget<MakeChip>(find.byKey(const Key('make-Harley-Davidson')))
          .selected,
      isTrue,
    );
    for (final m in cat.modelsFor('Harley-Davidson')) {
      expect(find.byKey(Key('model-${m.id}')), findsOneWidget);
    }
  });

  testWidgets('other bike form saves the typed bike', (tester) async {
    final app = await _app();
    await _pump(tester, app);
    await _tap(tester, 'other-bike');
    expect(find.text('OTHER BIKE'), findsOneWidget);

    await _enter(tester, 'other-make', 'CFMoto');
    await _enter(tester, 'other-model', '450NK');
    await _enter(tester, 'other-year', '2024');
    await _enter(tester, 'top-speed-field', '160');
    await _tap(tester, 'save-bike');

    final bike = app.bike!;
    expect(bike.isOther, isTrue);
    expect(bike.otherMake, 'CFMoto');
    expect(bike.otherModel, '450NK');
    expect(bike.otherYear, 2024);
    expect(bike.ratedTopSpeedKmh, 160);
    expect(bike.topSpeedSource, TopSpeedSource.rider);
    expect(find.byType(SafetyBriefingScreen), findsOneWidget);
  });

  testWidgets('other form validates inline; back returns to the picker', (
    tester,
  ) async {
    final app = await _app();
    await _pump(tester, app);
    await _tap(tester, 'other-bike');

    await _tap(tester, 'save-bike');
    expect(find.text('Enter the make'), findsOneWidget);
    expect(find.text('Enter the model'), findsOneWidget);
    expect(find.text('Enter a speed in km/h'), findsOneWidget);

    await _enter(tester, 'other-year', '1900');
    await _tap(tester, 'save-bike');
    expect(find.text('A year between 1950 and 2030'), findsOneWidget);

    await _enter(tester, 'other-make', 'A' * 40);
    await _enter(tester, 'other-model', 'B' * 60);
    await _tap(tester, 'save-bike');
    expect(
      find.text('Make and model together: up to 79 characters'),
      findsOneWidget,
    );
    expect(app.bike, isNull);

    // System back leaves the form, not the setup page.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('make-Honda')), findsOneWidget);
    expect(find.byKey(const Key('other-make')), findsNothing);

    // So does the app bar's back arrow.
    await _tap(tester, 'other-bike');
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('make-Honda')), findsOneWidget);
  });

  testWidgets('changing the model asks fixing or different bike', (
    tester,
  ) async {
    final app = await _app();
    final gsx2015 = cat.byId('suzuki-gsx-s1000-2015')!;
    final hayabusa = cat.byId('suzuki-hayabusa-2021')!;
    await app.saveBike(CatalogueChoice(model: gsx2015));
    await _calibrate(app);
    final firstId = app.bike!.id;

    await _pump(tester, app, editing: true);
    expect(_selected(tester, gsx2015.id), isTrue);
    await _tap(tester, 'model-${hayabusa.id}');
    await _tap(tester, 'save-bike');
    expect(find.text('Fixing the model, or a different bike?'), findsOneWidget);

    await _tap(tester, 'fix-model');
    expect(app.bike!.catalogueModelId, hayabusa.id);
    expect(app.bike!.id, firstId);
    expect(app.calibration, isNotNull);
    expect(find.text('HOST'), findsOneWidget);

    // Again, this time a different bike.
    await _tap(tester, 'open-edit');
    expect(_selected(tester, hayabusa.id), isTrue);
    await _tap(tester, 'model-suzuki-gsx-s1000-2021');
    await _enter(tester, 'top-speed-field', '250');
    await _tap(tester, 'save-bike');
    await _tap(tester, 'different-bike');

    expect(app.calibration, isNull);
    expect(app.bike!.id, isNot(firstId));
    expect(app.bike!.catalogueModelId, 'suzuki-gsx-s1000-2021');
    expect(find.byType(SafetyBriefingScreen), findsOneWidget);
    // The new bike must do its init ride: nothing to go back to.
    expect(find.text('HOST'), findsNothing);
    expect(
      Navigator.of(tester.element(find.byType(SafetyBriefingScreen))).canPop(),
      isFalse,
    );
  });

  testWidgets('dismissing the dialog saves nothing', (tester) async {
    final app = await _app();
    await app.saveBike(
      CatalogueChoice(model: cat.byId('suzuki-gsx-s1000-2015')!),
    );
    await _calibrate(app);
    await _pump(tester, app, editing: true);
    await _tap(tester, 'model-suzuki-hayabusa-2021');
    await _tap(tester, 'save-bike');
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(find.text('Fixing the model, or a different bike?'), findsNothing);
    expect(app.bike!.catalogueModelId, 'suzuki-gsx-s1000-2015');
    expect(find.byType(BikeSetupScreen), findsOneWidget);
  });

  testWidgets('saving the same model again asks nothing', (tester) async {
    final app = await _app();
    await app.saveBike(CatalogueChoice(model: gsx2021, riderTopSpeedKmh: 250));
    await _calibrate(app);
    final id = app.bike!.id;

    await _pump(tester, app, editing: true);
    expect(_selected(tester, gsx2021.id), isTrue);
    // The rider's own speed is prefilled.
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('top-speed-field')))
          .controller!
          .text,
      '250',
    );
    await _enter(tester, 'top-speed-field', '255');
    await _tap(tester, 'save-bike');

    expect(find.text('Fixing the model, or a different bike?'), findsNothing);
    expect(app.bike!.id, id);
    expect(app.bike!.ratedTopSpeedKmh, 255);
    expect(app.calibration, isNotNull);
    expect(find.text('HOST'), findsOneWidget);
  });

  testWidgets('editing an Other bike of a known make opens the picker', (
    tester,
  ) async {
    final app = await _app();
    await app.saveBike(
      const OtherChoice(
        make: 'ducati',
        model: 'Monster',
        year: 2019,
        topSpeedKmh: 230,
      ),
    );
    await _calibrate(app);

    await _pump(tester, app, editing: true);
    expect(_makeSelected(tester, 'Ducati'), isTrue);
    expect(find.byKey(const Key('current-other')), findsOneWidget);

    // Other is one tap away, prefilled.
    await _tap(tester, 'other-bike');
    String text(String key) =>
        tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text;
    expect(text('other-make'), 'ducati');
    expect(text('other-model'), 'Monster');
    expect(text('other-year'), '2019');
    expect(text('top-speed-field'), '230');

    // Case and spacing are a correction, not another model.
    await _enter(tester, 'other-model', ' monster ');
    await _tap(tester, 'save-bike');
    expect(find.text('Fixing the model, or a different bike?'), findsNothing);
    expect(app.calibration, isNotNull);
    expect(find.text('HOST'), findsOneWidget);

    // Picking from the catalogue is a change.
    await _tap(tester, 'open-edit');
    await _pickModel(tester, cat.byId('suzuki-hayabusa-2021')!);
    await _tap(tester, 'save-bike');
    expect(find.text('Fixing the model, or a different bike?'), findsOneWidget);
  });

  testWidgets('a legacy bike "Yamaha MT-07" opens the picker on Yamaha', (
    tester,
  ) async {
    _legacy('Yamaha MT-07');
    final app = await _app();
    await _calibrate(app);
    await _pump(tester, app, editing: true);
    expect(_makeSelected(tester, 'Yamaha'), isTrue);
    expect(find.byKey(const Key('other-make')), findsNothing);

    // Keeping it as Other: the form has the text split into make and model.
    await _tap(tester, 'other-bike');
    String text(String key) =>
        tester.widget<TextFormField>(find.byKey(Key(key))).controller!.text;
    expect(text('other-make'), 'Yamaha');
    expect(text('other-model'), 'MT-07');
    expect(text('top-speed-field'), '214');

    await _tap(tester, 'save-bike');
    expect(find.text('Fixing the model, or a different bike?'), findsNothing);
    expect(app.bike!.otherMake, 'Yamaha');
    expect(app.bike!.otherModel, 'MT-07');
    expect(app.bike!.model, 'Yamaha MT-07');
    expect(app.calibration, isNotNull);
  });

  testWidgets('a legacy bike of an unknown make can pick from the list', (
    tester,
  ) async {
    _legacy('Aprilia RS 660');
    final app = await _app();
    await _pump(tester, app, editing: true);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('other-model')))
          .controller!
          .text,
      'Aprilia RS 660',
    );

    await _tap(tester, 'pick-from-list');
    expect(find.byKey(const Key('make-Honda')), findsOneWidget);
    expect(find.byKey(const Key('other-make')), findsNothing);

    final m = cat.byId('suzuki-gsx-s1000-2015')!;
    await _pickModel(tester, m);
    await _tap(tester, 'save-bike');
    expect(app.bike!.catalogueModelId, m.id);
    expect(app.bike!.isOther, isFalse);
    expect(app.bike!.topSpeedSource, TopSpeedSource.catalogue);
    expect(find.text('HOST'), findsOneWidget);
  });

  testWidgets('back from Other when editing leaves the page in one step', (
    tester,
  ) async {
    _legacy('Aprilia RS 660');
    final app = await _app();
    await _pump(tester, app, editing: true);
    expect(find.byKey(const Key('other-make')), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('HOST'), findsOneWidget);

    // Also when the form was opened from the picker.
    await _tap(tester, 'open-edit');
    await _tap(tester, 'pick-from-list');
    await _tap(tester, 'other-bike');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('HOST'), findsOneWidget);
    expect(app.bike!.model, 'Aprilia RS 660');
  });

  testWidgets('no dialog without a calibration', (tester) async {
    final app = await _app();
    await app.saveBike(
      CatalogueChoice(model: cat.byId('suzuki-gsx-s1000-2015')!),
    );
    await _pump(tester, app, editing: true);
    await _tap(tester, 'model-suzuki-hayabusa-2021');
    await _tap(tester, 'save-bike');
    expect(find.text('Fixing the model, or a different bike?'), findsNothing);
    expect(app.bike!.catalogueModelId, 'suzuki-hayabusa-2021');
  });

  testWidgets('fits a 360×640 screen, keyboard up', (tester) async {
    final app = await _app();
    await _pump(tester, app, size: const Size(1080, 1920));
    await _pickModel(tester, _firstWhere((m) => m.topSpeedKmh == null));
    expect(tester.takeException(), isNull);

    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    await tester.pumpAndSettle();
    await _enter(tester, 'top-speed-field', '1');
    final save = tester.getRect(find.byKey(const Key('save-bike')));
    expect(save.bottom, lessThanOrEqualTo(640 - 300));
    expect(tester.takeException(), isNull);

    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    await _tap(tester, 'other-bike');
    expect(tester.takeException(), isNull);
    tester.view.viewInsets = const FakeViewPadding(bottom: 900);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const Key('save-bike'))).bottom,
      lessThanOrEqualTo(640 - 300),
    );
    expect(tester.takeException(), isNull);
  });

  group('modelChanged', () {
    BikeProfile other(String make, String model, {int? year}) => BikeProfile(
      id: 'b',
      model: '$make $model',
      ratedTopSpeedKmh: 200,
      createdAt: DateTime.utc(2026),
      otherMake: make,
      otherModel: model,
      otherYear: year,
    );
    final catBike = BikeProfile(
      id: 'b',
      model: gsx2021.displayName,
      ratedTopSpeedKmh: 250,
      createdAt: DateTime.utc(2026),
      catalogueModelId: gsx2021.id,
    );

    test('same catalogue id is no change', () {
      expect(
        modelChanged(
          catBike,
          CatalogueChoice(model: gsx2021, riderTopSpeedKmh: 260),
        ),
        isFalse,
      );
    });

    test('another catalogue id or Other is a change', () {
      expect(
        modelChanged(
          catBike,
          CatalogueChoice(model: cat.byId('suzuki-hayabusa-2021')!),
        ),
        isTrue,
      );
      expect(
        modelChanged(
          catBike,
          const OtherChoice(
            make: 'Suzuki',
            model: 'GSX-S1000',
            topSpeedKmh: 250,
          ),
        ),
        isTrue,
      );
    });

    test('Other text compares without case or spacing', () {
      final b = other('CFMoto', '450 NK', year: 2024);
      expect(
        modelChanged(
          b,
          const OtherChoice(make: ' cfmoto', model: '450  nk ', topSpeedKmh: 1),
        ),
        isFalse,
      );
      expect(
        modelChanged(
          b,
          const OtherChoice(
            make: 'CFMoto',
            model: '450 NK',
            year: 2023,
            topSpeedKmh: 160,
          ),
        ),
        isFalse,
      );
      expect(
        modelChanged(
          b,
          const OtherChoice(make: 'CFMoto', model: '450SR', topSpeedKmh: 160),
        ),
        isTrue,
      );
      expect(
        modelChanged(b, CatalogueChoice(model: gsx2021, riderTopSpeedKmh: 1)),
        isTrue,
      );
    });

    test('a legacy bike compares its text as the model', () {
      final legacy = BikeProfile(
        id: 'b',
        model: 'Yamaha MT-07',
        ratedTopSpeedKmh: 214,
        createdAt: DateTime.utc(2026),
        otherModel: 'Yamaha MT-07',
      );
      expect(
        modelChanged(
          legacy,
          const OtherChoice(make: 'Yamaha', model: 'mt-07', topSpeedKmh: 214),
        ),
        isFalse,
      );
    });
  });

  test('top speed must be a real number in range', () {
    for (final bad in ['NaN', 'nan', 'Infinity', '-Infinity', '1e999', '']) {
      expect(TopSpeedField.validate(bad), isNotNull, reason: bad);
      expect(BikeSetupScreen.validateTopSpeed(bad), isNotNull, reason: bad);
    }
    expect(TopSpeedField.validate('39'), isNotNull);
    expect(TopSpeedField.validate('421'), isNotNull);
    expect(TopSpeedField.validate('40'), isNull);
    expect(TopSpeedField.validate('214.5'), isNull);
    expect(TopSpeedField.validate('420'), isNull);
  });
}
