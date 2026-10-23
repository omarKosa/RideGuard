# Bike Catalogue, Init-Ride Spec Check, Alert Labels & ML-Ready Data — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Riders pick their bike from a researched Turkey/Saudi catalogue; the init ride is checked against the model's physical envelope and the result (or the "Other" bike's readings) is stored; every alert is labelled with Tinder-style cards; rides upload the data a future per-model ML model needs; the codebase is tidied.

**Architecture:** One catalogue JSON file is the single source, bundled as a Flutter asset and loaded by the backend into a table at startup. Measurement (`PerformanceMeter`) and judgement (`SpecCheck`) are pure-Dart core units tested with the ride simulator; controllers wire them into the init ride and rides; everything uploads through the existing ordered outbox. Backend gains new tables via migration 004, new endpoints, SQL views and a Python report command.

**Tech Stack:** Flutter 3.47 / Dart, provider, sensors_plus, shared_preferences, new `device_info_plus`; FastAPI + asyncpg + Pydantic v2 + Postgres 17; pytest.

**Spec:** `docs/superpowers/specs/2026-10-24-bike-catalogue-design.md`

## Global Constraints

- No machine learning anywhere (spec: "No ML model, on device or on the server").
- The rider sees nothing new because a model is known — no spec-derived numbers or alerts on ride screens.
- Spec check runs only at the end of the init ride (and on "fixing the model"); never on regular rides.
- Mismatch only when physically impossible: speed > top × 1.07 + 3 km/h sustained ≥ 3 s; forward accel > expected max × 1.2 averaged over 1 s; decel > braking limit × 1.2 averaged over 0.5 s, or a stop's mean decel > braking limit × 1.2. Gentle riding = "not tested", never mismatch.
- Catalogue values: every non-null spec value has `source` URL and `quality` ∈ {`official`, `road_test`, `aggregator`}; empty beats guessed; ~120 models; Turkish vs Saudi variants that differ are separate entries.
- Crash labels are data only: no label or spec may make crash detection less sensitive.
- NO on a warning (wobble, impact, extreme lean) raises that threshold exactly as today's NOT REAL (wobble ×1.15, impact ×1.1, lean +3, within caps).
- SKIP on the alert cards skips **all** remaining cards. No alerts → no cards.
- Never edit migrations `001`–`003`; add `004_*` and later.
- Existing riders keep bike, calibration, safety baseline and queued outbox jobs after the update; a stored legacy bike becomes "Other" with its text as the model.
- Backend validation mirrors DB CHECK constraints (`Strict` models, `extra="forbid"`), all SQL parameterised.
- Commits: no `Co-Authored-By`/"Generated with" lines.
- Commands: Flutter `flutter test` and `flutter analyze` (must report "No issues found!"). Backend: start Postgres with
  `P=/tmp/claude-1000/-home-omarak-Projects-RideGaurd/4429594a-b65f-4445-9f0b-0b0d67c103a0/scratchpad; $P/pgenv/bin/pg_ctl -D $P/pgdata -o "-k '' -p 54329" -l $P/pg.log start`
  then `cd backend && DATABASE_URL=postgresql://rideguard@127.0.0.1:54329/rideguard $P/pgenv/bin/python -m pytest -q` (stop with `pg_ctl ... stop` at the end). If that env is gone, the user's equivalent is `docker compose --profile test run --rm api-test`.

## Review Focus

1. **A GPS spike during the init ride** (one 400 km/h fix) must not create a speed mismatch — only a 3 s sustained reading counts. Test in Task 9.
2. **Ride ends within 5 s of an alert** (rider stops right after a wobble): the motion clip must still upload (truncated), and the card for it still appears. Test in Task 12.
3. **Catalogue asset newer than the server's catalogue** (or a model id the server doesn't know): bike upload must still succeed — no FK from bikes to catalogue. Test in Task 4.
4. **Legacy stored bike JSON without the new fields** loads as Other and the app opens on Home, not setup. Test in Task 7.
5. **Back button / app kill during the alert cards** leaves the ride saved and the unanswered alerts unlabelled; the summary still opens on back. Test in Task 14.

---

### Task 1: Branch and baseline

**Files:** none changed (git only), plus `.gitignore` already has `.superpowers/`.

- [ ] **Step 1: Create branch** — `git switch -c feature/bike-catalogue`. Expected: "Switched to a new branch".
- [ ] **Step 2: Baseline commit of the existing, tested safety work and the spec/plan** — `git add -A && git commit -m "Crash/wobble detection, safety learning; bike catalogue design and plan"`. Expected: commit created; `git status` clean.
- [ ] **Step 3: Record green baseline** — run `flutter test` (Expected: all pass, 2 skipped live tests) and the backend suite (Expected: 36 passed).

---

### Task 2: Backend tidy — split schemas by area

**Files:**
- Create: `backend/app/schemas/__init__.py` (re-exports everything currently importable from `app.schemas`), `backend/app/schemas/common.py` (`Strict`, `Vec3`, `SpeedKmh`, `LeanMagnitude`), `riders.py` (Rider*, Bike*), `rides.py` (Ride*, Sample*, Stats*, BrakeEvent*, SafetyStatsIn, WindowAnalysisOut), `calibrations.py`, `incidents.py`.
- Delete: `backend/app/schemas.py`.
- Test: existing `backend/tests/*`.

- [ ] **Step 1:** Move classes verbatim into the area modules; `__init__.py` imports and lists them in `__all__` so `from ..schemas import X` keeps working. Resolve the forward reference `BikeStatsOut.latest_calibration: CalibrationOut` by importing `CalibrationOut` into `riders.py`.
- [ ] **Step 2:** Run backend suite. Expected: 36 passed.
- [ ] **Step 3:** Commit `refactor(backend): split schemas by area`.

---

### Task 3: Bike catalogue — research and validated file

**Files:**
- Create: `backend/app/catalogue/bikes.json`, `backend/app/catalogue/__init__.py` (empty), `backend/app/catalogue_schema.py`
- Test: `backend/tests/test_catalogue.py`

**Interfaces:**
- Produces (file format, consumed by Tasks 4 and 6):
```json
{
  "version": "2026.10.1",
  "make_order": ["Honda", "Yamaha", "Suzuki", "..."],
  "models": [{
    "id": "suzuki-gsx-s1000-2021",
    "make": "Suzuki", "model": "GSX-S1000",
    "year_from": 2021, "year_to": null,
    "markets": ["tr", "sa"],
    "category": "naked",
    "abs": "yes",
    "displacement_cc": {"value": 999, "source": "https://...", "quality": "official"},
    "power_kw": {...} | null,
    "weight_kg": {"value": 214, "basis": "wet", "source": "...", "quality": "official"} | null,
    "top_speed_kmh": {...} | null,
    "zero_to_100_s": {...} | null
  }]
}
```
- Produces: `catalogue_schema.py` — Pydantic `Catalogue`, `CatalogueModel`, `SpecValue` (`value: float`, `source: HttpUrl`, `quality: Literal["official","road_test","aggregator"]`), `WeightValue(SpecValue)` + `basis: Literal["wet","kerb","dry"]`; `load_catalogue(path: Path = CATALOGUE_PATH) -> Catalogue`; `CATALOGUE_PATH = Path(__file__).parent / "catalogue" / "bikes.json"`. Enums: `category ∈ {scooter, commuter, naked, sport, touring, adventure, cruiser, off_road}`, `abs ∈ {yes, no, optional, unknown}`, `markets ⊆ {tr, sa}`, non-empty. Ranges: displacement 49–2500, power 1–250, weight 60–450, top speed 40–420, 0–100 2.3–30, year_from 1990–2027, year_to ≥ year_from or null.

- [ ] **Step 1: Write the failing tests** in `test_catalogue.py` (no DB needed):
  - `test_catalogue_file_is_valid`: `load_catalogue()` succeeds; `len(models) >= 120`; ids unique and match `^[a-z0-9-]+$`.
  - `test_target_models_present`: ids `suzuki-gsx-s1000-2015` and `suzuki-gsx-s1000-2021` exist; GSX-S1000 2021 has `displacement_cc.value == 999`.
  - `test_brand_coverage`: every brand in `["Honda","Yamaha","Suzuki","Kawasaki","BMW","KTM","Ducati","Triumph","Harley-Davidson","CFMoto","Bajaj","TVS","Kymco","SYM","Piaggio","Vespa","Benelli","Voge","Mondial","Kuba","RKS"]` has ≥ 1 model; both markets have ≥ 60 models; `make_order` contains every make exactly once.
  - `test_rejects_value_without_source`: a model dict whose `top_speed_kmh` lacks `source` raises `ValidationError`.
- [ ] **Step 2:** Run `pytest tests/test_catalogue.py -q`. Expected: FAIL (module missing).
- [ ] **Step 3:** Implement `catalogue_schema.py`.
- [ ] **Step 4: Research and write `bikes.json`.** For each brand, find the current and recent models sold in Turkey (brand TR sites, e.g. suzuki.com.tr, honda.com.tr, mondial.com.tr, kuba, rks) and Saudi Arabia (brand KSA/GCC sites, dealers). Specs: manufacturer sheet first (`official`), reputable road tests for top speed and 0–100 (`road_test`), spec aggregators (bikez, motorcyclespecs, Wikipedia) only as fallback (`aggregator`). Unverifiable → `null`. Separate entries for performance-different generations/market variants. `make_order` by popularity in the two markets (Honda, Yamaha first; Turkish brands and Bajaj/TVS high).
- [ ] **Step 5:** Run `pytest tests/test_catalogue.py -q`. Expected: 4 passed.
- [ ] **Step 6:** Commit `feat(catalogue): researched TR/SA bike catalogue with sources`.

---

### Task 4: Backend — catalogue table, bike model fields, rider phone fields

**Files:**
- Create: `backend/app/migrations/004_catalogue_checks_labels.sql` with this task's parts; Tasks 5 and 13 append to it (allowed: 004 is new on this branch and the test DB is recreated each session), `backend/app/catalogue_sync.py`
- Modify: `backend/app/main.py` (lifespan: `await sync_catalogue(pool)` after `migrate`), `backend/app/schemas/riders.py`, `backend/app/routers/riders.py`, `backend/tests/conftest.py` (truncate new tables; do **not** truncate `catalogue_models`)
- Test: `backend/tests/test_catalogue.py` (DB part), `backend/tests/test_api.py`

**Migration 004 contents:**
- `catalogue_models(id text PK, catalogue_version text NOT NULL, make text, model text, year_from smallint, year_to smallint, markets text[], category text, abs text, displacement_cc real, power_kw real, weight_kg real, top_speed_kmh real, zero_to_100_s real, spec jsonb NOT NULL, updated_at timestamptz DEFAULT now())`.
- `riders` add `phone_model text CHECK (char_length <= 80)`, `os_version text CHECK (<= 40)`.
- `bikes` add `catalogue_model_id text` (**no FK**), `catalogue_version text`, `other_make text CHECK (1..40)`, `other_model text CHECK (1..60)`, `other_year smallint CHECK (1950..2030)`, `top_speed_source text NOT NULL DEFAULT 'rider' CHECK IN ('catalogue','rider','measured')`; `CHECK (catalogue_model_id IS NULL OR (other_make IS NULL AND other_model IS NULL))`.

**Interfaces:**
- Produces: `async def sync_catalogue(pool, path: Path = CATALOGUE_PATH) -> int` — upserts every model (returns count), deletes rows not in the file.
- Produces API: `PUT /v1/riders/{id}` accepts optional `phone_model`, `os_version`. `PUT /v1/bikes/{id}` accepts optional `catalogue_model_id`, `catalogue_version`, `other_make`, `other_model`, `other_year`, `top_speed_source` (default `"rider"`); `BikeOut` returns them. Validator: catalogue id and other fields mutually exclusive (422).

- [ ] **Step 1: Failing tests:**
  - `test_catalogue_loaded_on_startup` (DB): after `client` fixture, `SELECT count(*) FROM catalogue_models` equals `len(load_catalogue().models)`; GSX-S1000 2021 row `displacement_cc == 999`.
  - `test_bike_with_catalogue_model`: PUT bike with `catalogue_model_id="suzuki-gsx-s1000-2021"`, `catalogue_version`, `top_speed_source="catalogue"` → 200 and echoed.
  - `test_bike_with_unknown_catalogue_id_is_accepted` (Review Focus 3): `catalogue_model_id="brand-new-2027"` → 200.
  - `test_bike_other_fields_and_exclusivity`: Other fields → 200; both catalogue id and `other_model` → 422.
  - `test_rider_phone_fields`: PUT rider with `phone_model="SM-S918B"`, `os_version="Android 15"` → echoed.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement migration (Task 4 parts), `catalogue_sync.py`, schemas, router SQL, lifespan hook, conftest truncation list.
- [ ] **Step 4:** Run backend suite. Expected: all pass.
- [ ] **Step 5:** Commit `feat(backend): catalogue table, bike model and phone fields`.

---

### Task 5: Backend — model checks, gap views and report command

**Files:**
- Modify: `backend/app/migrations/004_catalogue_checks_labels.sql`
- Create: `backend/app/schemas/model_checks.py`, `backend/app/routers/model_checks.py`, `backend/app/reports.py`
- Modify: `backend/app/main.py` (include router)
- Test: `backend/tests/test_model_checks.py`

**Migration additions:**
- `model_checks(id uuid PK, bike_id uuid NOT NULL REFERENCES bikes ON DELETE CASCADE, calibration_id uuid NOT NULL REFERENCES calibrations ON DELETE CASCADE, ride_id uuid NOT NULL REFERENCES rides ON DELETE CASCADE, reason text CHECK IN ('init_ride','model_corrected'), catalogue_model_id text, catalogue_version text, other_make text, other_model text, other_year smallint, imu_hz real, expected jsonb, measured jsonb NOT NULL, results jsonb NOT NULL, mismatch boolean NOT NULL, checked_at timestamptz NOT NULL, created_at timestamptz DEFAULT now())`, index on `(catalogue_model_id)`.
- View `catalogue_gaps`: bikes with `other_model IS NOT NULL`, grouped by `lower(trim(other_make)), lower(trim(other_model))` → `make, model, bikes, years (array_agg distinct other_year), latest_measured (measured of the newest check), max_sustained_speed_kmh, max_accel_mps2, max_decel_mps2` (from `measured` keys).
- View `catalogue_mismatches`: per `catalogue_model_id` → `checks, mismatches, mismatch_items` (array of failing item names), latest measured vs expected.

**Interfaces:**
- Produces API: `PUT /v1/bikes/{bike_id}/model-checks/{check_id}` body `ModelCheckIn`:
```
reason: "init_ride"|"model_corrected"; calibration_id; ride_id; checked_at
catalogue_model_id?, catalogue_version?, other_make?, other_model?, other_year?, imu_hz?
expected: {top_speed_kmh?, max_accel_mps2?, max_decel_mps2?} | null
measured: {sustained_top_speed_kmh?, peak_accel_mps2?, peak_decel_mps2?, stops: [{start_speed_kmh, duration_s, mean_decel_mps2}] (≤ 50)}
results: {top_speed: R, acceleration: R, braking: R}, R ∈ "match"|"mismatch"|"not_tested"
mismatch: bool   # must equal any(result == "mismatch") → else 422
```
  Insert-once: `ON CONFLICT (id) DO NOTHING`; a retry with the same bike returns the stored row (200); same id under another bike → 409. Calibration/ride must belong to the bike (422 otherwise). `GET /v1/bikes/{bike_id}/model-checks` lists newest first.
- Produces: `python -m app.reports gaps|mismatches` (reads `DATABASE_URL`) printing the view as an aligned text table; `async def fetch_report(conn, name: Literal["gaps","mismatches"]) -> list[dict]`.

- [ ] **Step 1: Failing tests** (reuse the calibration-flow helpers in `test_api.py`; move shared helpers to `conftest.py` if needed):
  - `test_model_check_roundtrip_and_retry`: PUT twice → 200 both, one row.
  - `test_model_check_mismatch_flag_must_match_results`: `mismatch=false` with a `"mismatch"` result → 422.
  - `test_model_check_other_bike_shows_in_gaps`: Other bike "CFMoto"/"450NK" + check → `fetch_report(conn,"gaps")` has a row `model == "450nk"` with `max_sustained_speed_kmh` from the check.
  - `test_mismatch_report`: two checks for `suzuki-gsx-s1000-2021`, one mismatch on `top_speed` → row `checks=2, mismatches=1, "top_speed" in mismatch_items`.
  - `test_model_check_wrong_bike_calibration` → 422; `test_model_check_id_reused_by_other_bike` → 409.
- [ ] **Step 2:** Run. Expected: FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run backend suite. Expected: all pass. Also run `python -m app.reports gaps` against the test DB once; Expected: header line printed, no traceback.
- [ ] **Step 5:** Commit `feat(backend): init-ride model checks, catalogue gap reports`.

---

### Task 6: Flutter tidy — split large screens, shared key/value rows

**Files:**
- Create: `lib/widgets/key_value_rows.dart` (`KeyValueRows(rows: List<(String,String)>, {valueSize = 16})` — Expanded key + Flexible end-aligned value, the overflow-safe layout from `SafetyLearningSummary`), `lib/screens/ride/` (`ride_screen.dart` + `ride_gauges_panel.dart`, `hold_to_stop_button.dart` …), `lib/screens/calibration/` (`calibration_screen.dart`, `running_view.dart`, `stopped_view.dart`, `result_view.dart`), `lib/screens/settings/` (`settings_screen.dart`, `emergency_contact_card.dart`, `safety_learning_card.dart`, `server_card.dart`).
- Modify: imports everywhere; `SafetyLearningSummary`, calibration `_kv`, summary rows use `KeyValueRows`.
- Test: existing suite.

- [ ] **Step 1:** Move private widgets to their own files as public-in-library widgets (no behaviour change, keys unchanged). Remove duplicated `_kv` helpers. Keep each file < ~250 lines.
- [ ] **Step 2:** `flutter analyze` → "No issues found!"; `flutter test` → same counts as Task 1 baseline.
- [ ] **Step 3:** Commit `refactor(app): split large screens, shared key/value rows`.

---

### Task 7: Catalogue in the app, bike model fields, legacy migration

**Files:**
- Modify: `pubspec.yaml` (`flutter: assets: [backend/app/catalogue/bikes.json]`), `lib/models/bike_profile.dart`, `lib/data/remote_repository.dart` (`upsertBike` sends new fields)
- Create: `lib/models/catalogue_model.dart`, `lib/data/bike_catalogue.dart`
- Test: `test/data/bike_catalogue_test.dart`, `test/models/bike_profile_test.dart`

**Interfaces:**
- Produces: `class SpecValue { final double value; final String source; final SpecQuality quality; }`, `enum SpecQuality { official, roadTest, aggregator }`; `class CatalogueModel { id, make, model, yearFrom, int? yearTo, Set<String> markets, BikeCategory category, AbsFitment abs, SpecValue displacementCc, SpecValue? powerKw, SpecValue? weightKg, SpecValue? topSpeedKmh, SpecValue? zeroTo100S; String get yearsLabel /* "2021–" or "2015–2020" */; String get displayName /* "Suzuki GSX-S1000 (2021–)" */ }`; `enum BikeCategory { scooter, commuter, naked, sport, touring, adventure, cruiser, offRoad }`; `enum AbsFitment { yes, no, optional, unknown }`.
- Produces: `class BikeCatalogue { final String version; List<String> get makes /* make_order */; List<CatalogueModel> modelsFor(String make) /* sorted by model, then yearFrom desc */; CatalogueModel? byId(String id); static BikeCatalogue parse(String json); static Future<BikeCatalogue> load(AssetBundle bundle) }`.
- Produces: `BikeProfile` adds `String? catalogueModelId, String? catalogueVersion, String? otherMake, String? otherModel, int? otherYear, TopSpeedSource topSpeedSource` (`enum TopSpeedSource { catalogue, rider, measured }`), `bool get isOther => catalogueModelId == null`. `fromJson` of a legacy record (no `top_speed_source` key) → `otherModel = model`, `topSpeedSource = rider`. `copyWith` covers new fields.

- [ ] **Step 1: Failing tests:**
  - `bike_catalogue_test`: parse the real asset (`File('backend/app/catalogue/bikes.json')`): `makes.first == 'Honda'` (or whatever Task 3 put first — assert `makes` equals file `make_order`); `byId('suzuki-gsx-s1000-2021')!.displayName == 'Suzuki GSX-S1000 (2021–)'`; `modelsFor('Suzuki')` non-empty and contains both GSX-S1000 generations, newer first.
  - `bike_profile_test` (Review Focus 4): legacy JSON `{"id":"b","model":"Yamaha MT-07","rated_top_speed_kmh":214,"created_at":"..."}` → `isOther`, `otherModel == 'Yamaha MT-07'`, `topSpeedSource == TopSpeedSource.rider`; round-trip of a catalogue bike keeps all fields. Plus a widget-level check in `test/widget_test.dart`: with a legacy bike and calibration stored, app opens on Home.
- [ ] **Step 2:** `flutter test test/data/bike_catalogue_test.dart test/models/bike_profile_test.dart` → FAIL.
- [ ] **Step 3:** Implement; `RemoteRepository.upsertBike` sends `catalogue_model_id, catalogue_version, other_make, other_model, other_year, top_speed_source` (API names `catalogue|rider|measured`).
- [ ] **Step 4:** Run → PASS; full `flutter test` green.
- [ ] **Step 5:** Commit `feat(app): bundled bike catalogue and bike model fields`.

---

### Task 8: PerformanceMeter (measure what the bike did)

**Files:**
- Create: `lib/core/analysis/performance_meter.dart`
- Test: `test/core/performance_meter_test.dart`

**Interfaces:**
- Produces: `class PerformanceMeter { void add(MotionState s); void addStop(BrakeEvent e); PerformanceReadings get readings; }` and `class PerformanceReadings { final double? sustainedTopSpeedKmh; final double? peakAccelMps2; final double? peakDecelMps2; final List<BrakeEvent> stops; Map<String, dynamic> toApiJson(); /* sustained_top_speed_kmh, peak_accel_mps2, peak_decel_mps2, stops:[{start_speed_kmh,duration_s,mean_decel_mps2}] */ Map<String,dynamic> toJson(); factory fromJson }`.
- Rules: sustained top speed = max over time of the minimum `speedKmh` across any window ≥ 3 s of consecutive `speedReliable` GPS samples (a non-reliable sample breaks the window). Peak accel = max of 1.0 s moving mean of `forwardAccel` while `speedKmh ≥ 5`. Peak decel = max of 0.5 s moving mean of `-forwardAccel` while `speedKmh ≥ 5`. Samples arrive at 10 Hz; use `s.t` for windows.

- [ ] **Step 1: Failing tests** (use `RideSimulator` + `MotionPipeline` like `analysis_test.dart`):
  - `sustained top speed ignores a one-sample GPS spike` (Review Focus 1): cruise 120 km/h, inject one state with 400 km/h reliable → `sustainedTopSpeedKmh` in 115–125.
  - `peak accel of a launch`: accelerate 0→100 in 4 s → `peakAccelMps2` in 6–9; `peak decel of a hard stop` braking at ~8 m/s² → `peakDecelMps2` in 6.5–9.5.
  - `gentle ride gives low readings and json round-trips`.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit `feat(core): performance meter`.

---

### Task 9: SpecCheck (judge readings against the model)

**Files:**
- Create: `lib/core/catalogue/spec_check.dart`
- Test: `test/core/spec_check_test.dart`

**Interfaces:**
- Consumes: `CatalogueModel` (Task 7), `PerformanceReadings` (Task 8).
- Produces: `class ModelEnvelope { final double? topSpeedKmh; final double? maxAccelMps2; final double maxDecelMps2; factory ModelEnvelope.of(CatalogueModel m); Map<String,dynamic> toApiJson() /* top_speed_kmh, max_accel_mps2, max_decel_mps2 */ }`; `enum CheckResult { match, mismatch, notTested }` (API `match|mismatch|not_tested`); `enum SpecItem { topSpeed, acceleration, braking }` (API `top_speed|acceleration|braking`); `class SpecCheck { final ModelEnvelope? envelope; final PerformanceReadings measured; final Map<SpecItem, CheckResult> results; bool get mismatch; static SpecCheck run(CatalogueModel? model, PerformanceReadings measured) }` — `model == null` (Other) → all `notTested`, `envelope == null`.
- Envelope (constants named in the class): `g = 9.81`; `maxAccel` = if 0–100 known: `min(1.1 g, 1.5 × (100/3.6) / t)`; else if power & weight known: `max(2.5, min(1.1 g, 60 × powerKw / (weightKg + 80)))`; else null. `maxDecel` = `0.8 g` for scooter/commuter without ABS (`abs ∈ {no, unknown}`), `1.1 g` for ABS `yes`, else `1.0 g`. `topSpeed` = catalogue value or null.
- Results: top speed — null envelope/reading → notTested; reading > top × 1.07 + 3 → mismatch; reading ≥ 0.9 × top → match; else notTested. Acceleration — > 1.2 × max → mismatch; ≥ 0.8 × max → match; else notTested. Braking — peak decel > 1.2 × max **or** any stop `meanDecel > 1.2 × max` → mismatch; peak ≥ 0.8 × max → match; else notTested.

- [ ] **Step 1: Failing tests** with a GSX-S1000-like model (top 250, 0–100 3.1 s, ABS yes) and a scooter (no 0–100, power 8.5 kW, weight 130, ABS no):
  - `gentle init ride is not tested, never mismatch`: readings 90 km/h, 3 m/s², 4 m/s² → all notTested, `mismatch == false`.
  - `impossible top speed is a mismatch`: 272 km/h → topSpeed mismatch; 270 → match (250×1.07+3 = 270.5).
  - `scooter acceleration envelope from power to weight`: maxAccel ≈ 2.5 (floor); reading 3.5 → mismatch.
  - `braking beyond tyre grip`: GSX peak decel 13.5 (> 1.2×10.79) → mismatch; scooter limit 0.8 g.
  - `other bike has no envelope`.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS.
- [ ] **Step 5:** Commit `feat(core): spec check against the model envelope`.

---

### Task 10: Phone info

**Files:**
- Modify: `pubspec.yaml` (`device_info_plus`, latest stable), `lib/data/remote_repository.dart` (`upsertRider(String riderId, PhoneInfo phone)`), `lib/services/app_state.dart`, `lib/main.dart`, `lib/app.dart`, `test/support/fakes.dart`
- Create: `lib/services/phone_info.dart`
- Test: `test/services/app_state_test.dart`

**Interfaces:**
- Produces: `class PhoneInfo { final String? model; final String? osVersion; static const unknown = PhoneInfo(); }`; `typedef PhoneInfoReader = Future<PhoneInfo> Function();` `Future<PhoneInfo> readPhoneInfo()` (device_info_plus; Android `manufacturer model`, `Android <release>`; failures → `PhoneInfo.unknown`). `AppState({..., PhoneInfoReader? phoneInfo})`; `AppState.phone` getter after `load()`.
- [ ] **Step 1: Failing test** `rider upload carries the phone model`: AppState with fake reader `('Pixel 9', 'Android 16')`, `saveBike(...)` → outbox body of `PUT /v1/riders/...` has `phone_model: 'Pixel 9'`, `os_version: 'Android 16'`.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS; `flutter test` green.
- [ ] **Step 5:** Commit `feat(app): record phone model with the rider`.

---

### Task 11: Init-ride check, effective specs, model change

**Files:**
- Modify: `lib/services/calibration_controller.dart`, `lib/services/app_state.dart`, `lib/data/local_store.dart`, `lib/data/remote_repository.dart`
- Create: `lib/models/model_check.dart`, `lib/models/bike_choice.dart`
- Test: `test/services/controllers_test.dart`, `test/services/app_state_test.dart`

**Interfaces:**
- Consumes: `PerformanceMeter` (8), `SpecCheck` (9), `BikeCatalogue` (7), `PhoneInfo` (10).
- Produces: `sealed class BikeChoice`; `class CatalogueChoice extends BikeChoice { final CatalogueModel model; final double? riderTopSpeedKmh; }` (required when `model.topSpeedKmh == null`); `class OtherChoice extends BikeChoice { final String make, model; final int? year; final double topSpeedKmh; }`.
- Produces: `AppState(..., BikeCatalogue catalogue)`; `Future<BikeProfile> saveBike(BikeChoice choice, {bool differentBike = false})` — new bike when none or `differentBike` (new id; clears calibration, safety baseline, stored init readings → `startupStep == calibration`); otherwise same id, and if the model changed and a calibration exists, re-checks stored init readings with `reason: 'model_corrected'`. Display `model` string = `CatalogueModel.displayName` or `"$make $model"`.
- Produces: `class ModelCheck { id, bikeId, calibrationId, rideId, String reason, DateTime checkedAt, String? catalogueModelId, catalogueVersion, otherMake, otherModel, int? otherYear, double? imuHz, SpecCheck check; Map<String,dynamic> toApiJson() }`; `RemoteRepository.saveModelCheck(ModelCheck c)` → `PUT /v1/bikes/{bikeId}/model-checks/{id}`.
- Produces: `LocalStore.initReadings` / `setInitReadings(InitReadings?)` where `InitReadings { calibrationId, rideId, PerformanceReadings readings, double? imuHz }`.
- Produces: `AppState.recordInitRide(CalibrationProfile cal, InitReadings readings)` — called by `CalibrationController.accept()` after `saveCalibration`: stores readings, runs `SpecCheck.run(catalogue.byId(bike.catalogueModelId), readings)`, uploads `ModelCheck(reason:'init_ride')`, then applies **effective specs**: if `results[topSpeed] == mismatch` → bike `ratedTopSpeedKmh = readings.sustainedTopSpeedKmh`, `topSpeedSource = measured`, re-upload bike.
- CalibrationController: feeds `PerformanceMeter` from `_onTick` and `addStop` from recorder brake events; `imuHz` from `takeNoise().imuHz`.

- [ ] **Step 1: Failing tests:**
  - `init ride with a catalogue bike uploads a model check` (controllers_test, full simulated init ride as the existing e2e does, bike = GSX-S1000 2021 from the real catalogue): after `accept()`, outbox has `PUT /v1/bikes/<id>/model-checks/...` with `reason: 'init_ride'`, `results.top_speed == 'not_tested'` for a 90 km/h ride, `mismatch == false`, and the calibration PUT precedes it.
  - `impossible measured top speed takes priority` (app_state_test, with a fake `InitReadings` of 300 km/h sustained on a 250 km/h model): mismatch uploaded; `app.bike.ratedTopSpeedKmh == 300`, `topSpeedSource == measured`.
  - `other bike init ride saves readings with no envelope`: Other bike → check uploaded with `expected == null`, `other_model` set.
  - `fixing the model re-checks without a new init ride`: change model with `differentBike: false` → second check `reason: 'model_corrected'`, calibration kept.
  - `different bike starts over`: `differentBike: true` → new bike id, `calibration == null`, `startupStep == StartupStep.calibration`, safety baseline null.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement (update existing call sites of `saveBike` and the test helpers in `fakes.dart`). **Step 4:** Run → PASS; `flutter test` green.
- [ ] **Step 5:** Commit `feat(app): init-ride spec check, measured priority, model change`.

---

### Task 12: Ride data for future ML — speed-band vibration, performance, motion clips

**Files:**
- Modify: `lib/core/safety/safety_baseline.dart` (`RideNoise`), `lib/core/safety/safety_monitor.dart`, `lib/services/safety_controller.dart`, `lib/services/ride_controller.dart`, `lib/services/calibration_controller.dart`, `lib/services/ride_recorder.dart` + `lib/models/ride_summary.dart` (`performance` map), `lib/data/remote_repository.dart`
- Create: `lib/core/safety/motion_clip.dart`
- Test: `test/core/safety_monitor_test.dart`, `test/core/safety_learning_test.dart`, `test/services/safety_controller_test.dart`

**Interfaces:**
- Produces: `enum SpeedBand { b20to40, b40to60, b60to90, b90to120, b120plus; String get apiName /* "20-40" … "120+" */; static SpeedBand? of(double kmh) }`; `class BandNoise { Histogram wobbleRms; Histogram wobbleHz /* min 0.5, max 25 */; Histogram peakG; }`; `RideNoise.bands: Map<SpeedBand, BandNoise>` filled per usable second alongside the existing histograms; `RideNoise.toApiJson(tuning)` adds `bands: [{band, seconds, wobble_rms:{min,max,counts}, wobble_hz:{...}, peak_g:{...}}]`. `RideNoise.toJson()` (baseline storage) stays unchanged — bands are upload-only.
- Produces: `class MotionClip { final double rateHz; final double startOffsetS /* -5 or later */; final List<List<double>> accel /* [t, x, y, z], t relative to the hazard */; final List<List<double>> gyro; Map<String,dynamic> toApiJson() }`; `class ClipRecorder { ClipRecorder({double before = 5, double after = 5}); void addAccel(Vec3, double t); void addGyro(Vec3, double t); void capture(Hazard h); List<(Hazard, MotionClip)> poll(double t) /* completed */; List<(Hazard, MotionClip)> flush() /* truncated, at ride end */ }`.
- `SafetyMonitor({..., void Function(Hazard, MotionClip)? onClip})`: owns a `ClipRecorder`, captures on every emitted hazard, delivers via `onClip`; `takeNoise()` flushes pending clips first.
- `SafetyController.reportClip(Hazard hazard, MotionClip clip)` — maps hazard → incident id (identity map filled in `report`), uploads `RemoteRepository.saveIncidentClip(rideId, incidentId, clip)` → `PUT /v1/rides/{rideId}/incidents/{id}/clip`. Clips for hazards that produced no incident (cooldown-suppressed) are dropped.
- `RideSummary.performance` (`Map<String,dynamic>?`, from `PerformanceMeter.readings.toApiJson()`), sent as `performance` in the summary upload; RideController runs a `PerformanceMeter` too.

- [ ] **Step 1: Failing tests:**
  - safety_learning_test `bands split normal riding by speed`: ride 60 s at 50 km/h and 60 s at 100 km/h → `bands[b40to60]` and `bands[b90to120]` each ~ 50–60 s; `toApiJson` has `bands` with `band: "40-60"`.
  - safety_monitor_test `wobble produces a 10 s clip around it`: wobble then 10 s cruise → one clip, `startOffsetS == -5`, accel rows ≈ 500 (±10), first `t ≈ -5`, last `t ≈ +5`.
  - safety_monitor_test `ride ending right after a hazard flushes a truncated clip` (Review Focus 2): wobble, 2 s later `takeNoise()` → clip delivered, last `t ≤ 2.5`.
  - safety_controller_test `clips upload against their incident`: report hazard, then `reportClip` → outbox `PUT .../incidents/<that id>/clip`.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS; `flutter test` green.
- [ ] **Step 5:** Commit `feat: speed-band vibration, ride performance and motion clips`.

---

### Task 13: Backend — rider labels, clips, ride profile

**Files:**
- Modify: `backend/app/migrations/004_catalogue_checks_labels.sql`, `backend/app/schemas/incidents.py`, `backend/app/schemas/rides.py`, `backend/app/routers/incidents.py`, `backend/app/routers/rides.py`
- Test: `backend/tests/test_incidents.py`, `backend/tests/test_api.py`

**Migration additions:** `incidents` add `rider_label text CHECK IN ('yes','no')`, `labelled_at timestamptz`, `CHECK ((rider_label IS NULL) = (labelled_at IS NULL))`; backfill `rider_label='no', labelled_at=updated_at WHERE false_alarm`. `incident_clips(incident_id uuid PK REFERENCES incidents ON DELETE CASCADE, rate_hz real CHECK (0 < rate_hz <= 1000), start_offset_s real CHECK (-10 <= start_offset_s <= 0), accel jsonb NOT NULL, gyro jsonb NOT NULL, created_at timestamptz DEFAULT now())`. `rides` add `performance jsonb`.

**Interfaces:**
- `IncidentIn`: replace `false_alarm` with `rider_label: Literal["yes","no"] | None = None`, `labelled_at: AwareDatetime | None = None` (both or neither; `labelled_at ≥ detected_at`). Router writes `false_alarm = (rider_label = 'no' AND kind <> 'crash')`; a crash labelled `no` is allowed (data only). Label may change on later PUTs (same outcome rule as today). `IncidentOut` returns `rider_label`, `labelled_at`, `false_alarm`.
- `PUT /v1/rides/{ride_id}/incidents/{incident_id}/clip` body `ClipIn {rate_hz, start_offset_s, accel: list[Annotated[list[float], len 4]] (≤ 1500), gyro: same}`; 404 if incident not in that ride; upsert (replace).
- `SafetyStatsIn` adds optional `bands: list[BandStatsIn] (≤ 5)` with `band: Literal["20-40","40-60","60-90","90-120","120+"]`, `seconds ≥ 0`, histograms `{min>0, max>min, counts: list[int ≥ 0] (≤ 100)}`. `RideSummaryIn.performance: PerformanceIn | None` (same keys as the model-check `measured`). `RideOut.performance`.

- [ ] **Step 1: Failing tests:** `test_rider_label_yes_and_no` (no on a wobble → `false_alarm` true; yes → false); `test_crash_can_be_labelled_no_without_false_alarm`; `test_label_requires_labelled_at`; `test_clip_upload_and_replace`; `test_clip_rejects_bad_rows` (3-element row → 422); `test_summary_with_bands_and_performance` (round-trip via `GET /v1/rides/{id}`). Update existing false-alarm tests to the label API.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Backend suite → all pass.
- [ ] **Step 5:** Commit `feat(backend): rider labels, motion clips, ride performance`.

---

### Task 14: Labels in the app and the Tinder-style alert cards

**Files:**
- Modify: `lib/models/incident.dart`, `lib/core/safety/safety_baseline.dart`, `lib/services/app_state.dart`, `lib/services/calibration_controller.dart`, `lib/screens/ride/ride_screen.dart`, `lib/screens/calibration/calibration_screen.dart` (+ result view), `lib/screens/ride_summary_screen.dart`
- Create: `lib/widgets/alert_review.dart`, `lib/screens/alert_review_screen.dart`
- Test: `test/widgets/alert_review_test.dart`, `test/widgets/safety_ui_test.dart`, `test/core/safety_learning_test.dart`

**Interfaces:**
- `enum RiderLabel { yes, no }`; `Incident.riderLabel`, `Incident.labelledAt`, `Incident labelled(RiderLabel l, DateTime at)` (allowed on crashes); remove `falseAlarm`/`markedFalseAlarm`; `toApiJson` sends `rider_label`, `labelled_at`.
- `SafetyBaseline withLabel(Incident i)` — `no` on wobble (with rms) / impact (with g) / extreme lean → existing `withFalse*`; anything else returns `this`.
- `AppState.labelIncident(Incident i, RiderLabel l) -> Future<Incident>` (replaces `markFalseAlarm`); `CalibrationController.labelIncident(...)` applies `withLabel` to its pending `_safetyBaseline` and uploads.
- `AlertReview({required List<Incident> incidents, required Future<Incident> Function(Incident, RiderLabel) onLabel, required ValueChanged<List<Incident>> onDone})` — one card at a time; `Dismissible` horizontal (right = YES, left = NO) plus buttons; keys `alert-card`, `alert-yes`, `alert-no`, `alert-skip`; header `ALERT n OF m` + dots; copy: warnings "Did this really happen?", crash "Was this a real crash or fall?"; card title/subtitle reuse `describeWarning` data (kind, Hz/g/°, speed, time). SKIP → `onDone` with current list (rest unlabelled).
- `AlertReviewScreen(incidents, onLabel)` pops with the labelled list; system back = SKIP.
- Ride flow: `_stop` → if incidents non-empty push `AlertReviewScreen`, then `pushReplacement` summary with the returned list. Init ride: `_CalibrationView` shows `AlertReview` when `phase == finished && incidents non-empty && !reviewed`, then the result view.
- Summary `_IncidentsCard`: NOT REAL buttons removed; each row shows `You said: it happened` / `You said: not real` / `No answer`.

- [ ] **Step 1: Failing tests:**
  - alert_review_test `answers every alert then finishes`: 3 incidents; tap `alert-yes`, drag card left (`tester.drag(find.byKey(Key('alert-card')), Offset(-500, 0))`), tap `alert-no` → `onDone` with labels `[yes, no, no]`; `ALERT 2 OF 3` shown after the first.
  - `skip leaves the rest unlabelled`: label first, tap `alert-skip` → labels `[yes, null, null]`.
  - `crash card asks about a real crash`: text `Was this a real crash or fall?`.
  - safety_learning_test `no on a crash never loosens anything` / `no on a wobble raises the wobble threshold ×1.15`.
  - safety_ui_test: ride with incidents → cards appear before summary; system back on the cards opens the summary with alerts unlabelled (Review Focus 5); ride with no incidents → summary directly. Replace the NOT REAL test with a summary-shows-answers test.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS; `flutter test` green; `flutter analyze` clean.
- [ ] **Step 5:** Commit `feat(app): swipe cards to label every alert`.

---

### Task 15: Bike picker UI (make → model → Other), model-change dialog

**Files:**
- Modify: `lib/screens/bike_setup_screen.dart` (split into `lib/screens/bike_setup/` : `bike_setup_screen.dart`, `make_chips.dart`, `model_list.dart`, `other_bike_form.dart`), `lib/screens/home_screen.dart` (shows `bike.model`, unchanged otherwise)
- Test: `test/widgets/bike_setup_test.dart`, `test/widget_test.dart`

**Behaviour:**
- MAKE chips: first 8 of `catalogue.makes`, then `+ more` expanding all (keys `make-<Make>`, `more-makes`). Selecting a make shows MODEL rows `model · yearsLabel` (keys `model-<id>`), then the link `My bike isn't listed → Other` (key `other-bike`).
- Chosen model without top speed → field `Fastest possible speed` (key `top-speed-field`, same validator as today) appears before CONTINUE (key `save-bike`).
- Other form: Make (`other-make`, 1–40 chars), Model (`other-model`, 1–60), Year optional (`other-year`, 1950–2030), Fastest possible speed (`top-speed-field`).
- Editing an existing bike: preselects its make/model (or opens Other prefilled for legacy/Other bikes). If the model changed and a calibration exists → dialog `Fixing the model, or a different bike?` with buttons `FIXING THE MODEL` (key `fix-model`) and `DIFFERENT BIKE` (key `different-bike`); different bike → after save, navigate to the init ride briefing.

- [ ] **Step 1: Failing tests:**
  - `pick Suzuki then GSX-S1000 2021 and continue`: tap `make-Suzuki`, `model-suzuki-gsx-s1000-2021`, `save-bike` → `app.bike.catalogueModelId == 'suzuki-gsx-s1000-2021'`, `topSpeedSource == catalogue`, safety briefing shown.
  - `model without top speed asks for it`: pick a catalogue model whose `topSpeedKmh == null` (find one in the real file in the test) → `top-speed-field` visible; CONTINUE without it → validation error.
  - `other bike form saves the typed bike`: `other-bike` → fill CFMoto / 450NK / 2024 / 160 → `bike.isOther`, `otherModel == '450NK'`.
  - `changing the model asks fixing or different bike`: with a calibration, edit → choose another model → dialog; `fix-model` keeps calibration; `different-bike` → `app.calibration == null`.
- [ ] **Step 2:** Run → FAIL. **Step 3:** Implement. **Step 4:** Run → PASS; full `flutter test` green.
- [ ] **Step 5:** Commit `feat(app): make → model bike picker with Other and model-change choice`.

---

### Task 16: End-to-end verification, live test, docs

**Files:**
- Modify: `test/integration/live_backend_test.dart`, `README.md`, `test/services/controllers_test.dart`

- [ ] **Step 1:** Extend the live backend test: rider with phone fields → catalogue bike → init ride → model check → ride with an incident, label and clip → `GET` endpoints return them; Other bike → `catalogue_gaps` row via `python -m app.reports gaps`.
- [ ] **Step 2:** Run the API on the scratch Postgres (`uvicorn app.main:create_app --factory --port 18000`) and `flutter test test/integration/live_backend_test.dart --dart-define=LIVE_API=http://127.0.0.1:18000` (use the define the file already reads). Expected: all live tests pass. Stop the API and Postgres.
- [ ] **Step 3:** Full `flutter test`, `flutter analyze` ("No issues found!"), backend suite, `flutter build apk --debug` (Expected: "Built build/app/outputs/flutter-apk/app-debug.apk").
- [ ] **Step 4:** README: catalogue (where the file is, how to add a model, sourcing rules), init-ride check rules, alert cards, ML data collected, `python -m app.reports gaps|mismatches`, new endpoints; note `docker compose up -d --build` applies migrations 002–004.
- [ ] **Step 5:** Commit `test+docs: end-to-end catalogue flow, README`.
