# SDD ledger — plan: docs/superpowers/plans/2026-10-24-bike-catalogue.md
Spec: docs/superpowers/specs/2026-10-24-bike-catalogue-design.md
Branch: feature/bike-catalogue (from main 4ec0264). Scratch Postgres on 127.0.0.1:54329 left running for backend tests.

## Pre-flight scan
| Tasks | Produces → consumes | Found |
|---|---|---|
| 3→4 | bikes.json format, CATALOGUE_PATH → sync_catalogue | consistent |
| 3→7 | bikes.json snake_case fields, make_order → Dart CatalogueModel/BikeCatalogue | consistent |
| 4,5,13 | all append migration 004 | allowed by plan note (004 new on branch) |
| 2→4,5,13 | schemas package modules | consistent |
| 6→14,15 | ride/calibration screens move into lib/screens/ride/, lib/screens/calibration/ | 14 uses the moved paths; consistent |
| 7→11→15 | BikeProfile fields → BikeChoice/saveBike → picker | consistent; 11 changes saveBike signature (7 keeps old) |
| 8→9,11,13 | PerformanceReadings.toApiJson keys = model-check `measured` = PerformanceIn | consistent |
| 9→5 | envelope/results API keys and values | consistent |
| 10→5,11 | phone model | CONFLICT: spec lists phone model in model-check record; plan's model_checks omits it |
| 12→13 | MotionClip rows [t,x,y,z], bands histograms {min,max,counts} | consistent |
| 13→14 | rider_label/labelled_at replaces false_alarm | app keeps sending false_alarm between 13 and 14; only live test affected (fixed in 16) |
| 11→15 | AppState needs BikeCatalogue loaded in main.dart | 11 must wire it |
| self T1 | branch+commit | setup, controller does it |
| self T7 | test "makes.first == Honda (or…)" | ambiguous; resolve: assert makes == file make_order |
| other tasks self | tests vs code vs files | consistent |

Ruling: phone model stored on each model check too (column phone_model text ≤80 in model_checks; ModelCheck.phoneModel sent as phone_model) — spec lists it in the record and rider's phone can change later — cost if wrong: one redundant column.
Ruling: Task 1 (branch + baseline commit) done by controller as setup, not dispatched — it is git setup, no code — cost if wrong: none.
Ruling: Task 7 make-order test asserts BikeCatalogue.makes equals the file's make_order — plan text was ambiguous — cost if wrong: trivial.
Ruling: between Task 13 and 14 the app still sends false_alarm; accepted, live test is skipped by default and Task 16 re-runs it — cost if wrong: a temporarily failing optional live test.

Task 1: complete (commits 4ec0264..4efb9a9, baseline: flutter 66 pass/2 skip, backend 36 pass)
Task 2: minor (deferred): redundant single-section divider comments in schemas modules; multi-line import lists in schemas/__init__.py
Task 2: complete (commits 4efb9a9..452f0a9, review clean; controller verified backend 36 passed)
Task 3: Ruling: aggregator top speeds and manufacturer claims (incl. low scooter claims like Mondial/PCX) must be included, tagged aggregator/official; only lower-bound values ("200+", "over 200") excluded — owner decision "allowed but tagged so the owner can filter" binds; a too-low claim only yields a filterable mismatch record and a measured top speed for the gauge — cost if wrong: some false scooter mismatches in the DB.
Task 3: Ruling: SA market flags must be backed by KSA/GCC distributor or brand-site lineups; unverifiable → no "sa" flag; if verified SA count < 60, lower the test threshold to the verified count (min 30) and say so in the report — markets drive no app behaviour, so accuracy beats count — cost if wrong: fewer SA-tagged models.
Task 3: minor (deferred): some ids/year_from conflate generations with current-year source values (ZX-10R 2021 vs 2026 page, Low Rider S 2022 vs 2025 data, GSX-S1000 2015 source 2015-17)
Task 3: minor (deferred): catalogue_schema not pydantic-strict (bool/str coerced to float); codebase "Strict" = extra=forbid only
Task 3: minor (deferred): Hayabusa top speed tagged official via iol.co.za; thin TR scooter coverage (Activa 125, Dio)
Task 3: fix round 1/5 (2 addressed, 0 open; commits deaee90..4831ec3)
Task 3: minor (deferred): bmw-s-1000-xr-2024 top speed tagged official but sourced to motorradonline (third party); hayabusa official via news site; some aggregator values from a different model-year page
Task 3: Ruling: SA coverage ends at 44 verified models (no Yamaha/Suzuki/Kawasaki/Triumph/Benelli/Vespa; the owner's GSX-S1000 is TR-only) — markets drive no app behaviour, all models stay pickable — cost if wrong: SA tagging is incomplete for later filtering.
Task 3: complete (commits 452f0a9..4831ec3, review clean after 1 fix round)
Task 4: minor (deferred): long get_rider SELECT line; split typing imports in schemas/riders.py; rider/bike PUT replaces (nulls) omitted new fields like platform; no direct sync_catalogue idempotency/deletion test
Task 4: complete (commits 4831ec3..8dabe6a, review clean)
Task 5: minor (deferred): model_checks lacks catalogue-xor-other CHECK/validator; GET checks on unknown bike → 200 []; ride not checked to be the calibration's ride; thin gaps/mismatch view tests, CLI untested; missing DATABASE_URL → KeyError
Task 5: complete (commits 8dabe6a..4769029, review clean; controller verified backend 51 passed)
Task 6: minor (deferred): ResultViewState made public unnecessarily
Task 6: complete (commits 4769029..01ae626, review clean; controller verified analyze clean, flutter 66 pass/2 skip)
Task 7: minor (deferred): BikeProfile.copyWith can't clear catalogueModelId/otherMake/otherYear (Task 11 must handle catalogue↔Other switches); old saveBike leaves otherModel set on catalogue bikes until Task 11; modelsFor re-sorts each call
Task 7: fix round 1/5 (1 addressed, 0 open; commits 589946d..caeebca)
Task 7: minor (deferred): _clip substring may split a UTF-16 surrogate pair at the cut
Task 7: complete (commits 01ae626..caeebca, review clean after 1 fix round)
Task 8: minor (deferred): sustained-speed window doesn't treat a >0.5 s gap between reliable samples as a break; no tests for unreliable-sample window break or <5 km/h accel gating; accel/decel not gated on speedReliable
Task 8: complete (commits caeebca..7c50e96, review clean; controller verified full flutter suite)
Task 9: minor (deferred): no boundary/null-path tests (GSX accel mismatch/match, model without top speed, null accel envelope, sub-limit stop, abs unknown scooter / naked abs no)
Task 9: complete (commits 7c50e96..28460f5, review clean; ⚠ meanDecelMps2 = (startSpeed/3.6)/duration confirmed by controller in brake_event.dart)
Task 10: minor (deferred): no clipping test for phone_model/os_version; readPhoneInfo swallows errors silently; device_info_plus out of alphabetical order in pubspec; unrequested iOS branch returns raw machine id
Task 10: complete (commits 28460f5..34bccef, review clean)
Task 11: Ruling: re-graded reviewer Minor "out-of-range stop/peak in PerformanceReadings.toApiJson → 422 → outbox drops the whole model check" to Important — it silently loses the record the feature exists to collect (crash-like stops in the init ride trigger it) — cost if wrong: one small guard + test.
Task 11: note: 2 skipped tests are the pre-existing live-backend tests (baseline had them)
Task 11: fix round 1/5 (4 addressed, 0 open; commits 5319a1d..229bc18)
Task 11: minor (deferred): no automated backend-contract test for the model-check body (validated by hand against ModelCheckIn); editing a catalogue bike in the old setup screen turns it Other until Task 15
Task 11: complete (commits 34bccef..229bc18, review clean after 1 fix round)
Task 12: Ruling: between Task 12 and 13 ride summaries with bands/performance and clip PUTs are rejected by the old backend schema — accepted transient on the feature branch (no deployment in between) — cost if wrong: none after Task 13.
Task 12: note for Task 13: bands may be an empty list; schema must accept []
Task 12: Ruling: crash clips anchor on the event (impact time on the impact path, down-since on the bike-down path), 5 s before / 5 s after the event, rows relative to the event — spec says "5 s before, 5 s after the event"; the crash label is useless without the impact — cost if wrong: a longer IMU ring buffer (~confirmWithin+5 s).
Task 12: Ruling: re-graded Minor "wobble_hz taken from out-of-band strongest rotation" to Important — bands' wobble_hz must be the frequency of the in-band sample that sets wobble_rms, else the ML signature mislabels; must be fixed before Task 13 freezes the schema — cost if wrong: a few lines.
Task 12: minor (deferred): onClip delivered before detection in addAccel/addGyro (future sync throw would skip detection); abort/dispose path doesn't flush clips or send performance; toApiJson keeps first 50 stops not hardest; band test tolerance widened to 50–65 s; reportClip doesn't check _disposed
Task 12: fix round 1/5 (2 addressed, 0 open; commits c9862fb..b8275a1)
Task 12: minor (deferred): clip body doesn't record its anchor relative to detection time; bike-down anchor (downSince) lags ground hit ~0.6 s due to smoothed tilt
Task 12: complete (commits 229bc18..b8275a1, review clean after 1 fix round)
Task 13: minor (deferred): unlabelled PUT after a label clears it (outbox is FIFO so no stale replay today; consider COALESCE); ClipIn floats accept NaN/Inf (app filters non-finite) → possible 500; no 1500-row boundary / >5 bands tests; BandStatsIn.seconds int-only
Task 13: complete (commits b8275a1..b39a062, review clean; controller confirmed SpeedBand apiNames)
Task 14: Ruling: legacy queued incident jobs carrying false_alarm are fixed on the backend — IncidentIn accepts deprecated optional false_alarm (true → rider_label 'no', labelled_at = resolved_at or detected_at, never on crash; false → ignored); assigned to this fix round — the earlier debug APK may have queued such jobs; backend fix covers every client version — cost if wrong: one deprecated field.
Task 14: Ruling: re-graded Minor "tilt/stamp only on drag, not on YES/NO taps" to Important — owner asked for Tinder-style cards and smooth UX — cost if wrong: a short animation.
Task 14: Ruling: re-graded Minor "init-ride card flow untested" to Important — Review Focus 5 covers both flows — cost if wrong: one widget test with a stub controller.
Task 14: minor (deferred): AppState.labelIncident saves the raised baseline before enqueueing the upload; SafetyController.end() now clears the warning banner (intended)
Task 14: fix round 1/5 (3 addressed, 0 open; commits 1703430..a99f20b)
Task 14: minor (deferred): calibration_controller.dart 276 lines, app_state.dart 343 lines (over ~250 guide); _CalibrationView made public for tests
Task 14: complete (commits b39a062..a99f20b, review clean after 1 fix round)
Task 15: Ruling: brief test "pick GSX-S1000 2021 → topSpeedSource catalogue" is impossible with real data (no catalogue top speed); test enters 250 and expects rider, separate test covers catalogue source with GSX-S1000 2015 — data fact — cost if wrong: none.
Task 15: Ruling: Home header drops "· N km/h" so no catalogue-derived number is shown — spec "rider sees nothing spec-derived" — cost if wrong: rider loses the top-speed hint on Home.
Task 15: Ruling: Other-form copy changes from "We'll add it to the list." to "We'll use it to improve the list." in this fix round — the mockup copy was the controller's own wording, not an owner decision, and it promises curation nothing does — cost if wrong: one string.
Task 15: minor (deferred): bike_setup_screen.dart 439 lines; stale catalogue id + unchanged save shows the model-change dialog; failed saveBike throws out of onPressed with no message
Task 15: fix round 1/5 (2 addressed, 0 open; commits eb9b6f4..18a5753)
Task 15: minor (deferred): bike_setup_screen.dart ~500 lines (cohesive; could extract _Logo/pages); _prefillOther match loop lacks break
Task 15: complete (commits a99f20b..18a5753, review clean after 1 fix round)
Task 16: minor (deferred): README test-command comment placed after a line-continuation backslash; live test doesn't assert the catalogue_gaps view (checked by hand); leftover livemake* rows in the scratch rideguard DB
Task 16: Ruling: fix round 1 (one README line) verified by the controller directly (diff read in full; bikes.json counted: 202 models, 21 makes) instead of dispatching a re-review — a 1-line doc diff fully inspected — cost if wrong: none.
Task 16: fix round 1/5 (1 addressed, 0 open; commits 76ac0a4..fc46e93)
Task 16: complete (commits 18a5753..fc46e93, review clean after 1 fix round)
Final: Ruling: final review covers 4efb9a9..HEAD (this plan's work), not merge-base 4ec0264 — 4efb9a9 is the baseline commit of the earlier crash/wobble/learning work (already tested and security-reviewed in the previous session) — cost if wrong: earlier work gets no second whole-branch review here.
Final: Ruling: "NO on an impact warning raises impactG, which also gates the crash-by-impact path" (reviewer declined to judge) is now a finding — spec/constraint "no label may make crash detection less sensitive" binds; crash impact path uses the noise-learned impact threshold without label raises — cost if wrong: impact warnings and crash impacts use slightly different thresholds.
Final: Ruling: reviewer minors re-graded into the fix wave: aborted init ride with alerts shows the cards (crash labels are the scarcest data); onClip poll after detection (protects crash rule); hardest 50 stops kept; NaN speed input rejected (crashes save); BMW S 1000 XR top-speed quality tag → aggregator — each cheap and user/data-affecting — cost if wrong: small extra diff.
Final: Ruling: old bike's lastRide still shown on Home after "different bike" — left as is, cosmetic and the spec is silent — cost if wrong: a stale summary card.
Final: minor (deferred): two "same model?" checks disagree (year/case edit uploads an extra model_corrected check); dispose paths don't flush clips/performance
Final: Ruling: suzuki-hayabusa-2021 top speed (299, the factory limiter) stays tagged official although sourced via a news article quoting Suzuki — it is a manufacturer claim — cost if wrong: one mis-tagged value.
Final: fixed 10 findings (commits fc46e93..b861246), scoped re-review: all addressed, no new Critical/Important
Final: minor (deferred): after a NO raises impactG above crashImpactG, a ≥impactG jolt within 1 s of a sub-impactG crash candidate emits no impact warning (crash detection unaffected); legacy bike re-saved before its PUT is queued (tiny kill window)
