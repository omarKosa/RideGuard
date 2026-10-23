# Bike catalogue, init-ride spec check, alert labels and ML-ready data

Date: 2026-10-24 · Status: draft for approval

## Why

RideGuard learns each rider's bike and phone mount from riding (init ride,
then every ride). Today the bike is a free-text name and a top speed the
rider types in. The owner wants three things out of this round:

1. **Know which bike it is.** Riders pick their model from a catalogue of
   bikes sold in **Turkey (Istanbul) and Saudi Arabia (Riyadh)**, the
   owner's two target markets. The owner rides a Suzuki GSX-S1000.
2. **Know whether the app's readings can be trusted for that model.** The
   init ride's measurements are compared with the model's specs. Readings
   the bike physically can't produce (much faster than its top speed,
   unrealistic acceleration, stopping harder than it can brake) are a
   *mismatch*: something is wrong with the readings, the catalogue, or the
   rider's choice of model. Mismatches are saved so the owner can improve
   the catalogue and the readings. Gentle riding is never a mismatch.
3. **Collect the data a future per-model machine-learning model would
   need**, including rider-confirmed labels for every alert.

Plus: **tidy the whole codebase** (existing and new code), and make sure
everything works smoothly, in code and in UX.

## Decisions already made (by the owner)

- **No machine learning now.** The current per-bike statistical learning
  (learned noise floor, false-alarm labels) already is an anomaly detector;
  there are no labelled crash/wobble data to train on, and no reliable
  public dataset. Instead, collect the data that would make per-model ML
  possible later (section "Data for future ML").
- **The rider sees nothing different when a model is known.** No new
  numbers or alerts on screen because of the specs.
- **Bike picker: make, then model** (mockup option B). Brand chips, then a
  model list, then "My bike isn't listed → Other".
- **"Other"**: the rider types make, model, optional year and fastest
  possible speed. This, plus the init ride's key readings, is saved in the
  database so the owner can see which models are missing.
- **The spec check runs only on the init ride.** Later rides are not
  checked (tuning later would make the data ambiguous). Later rides keep
  uploading what they already upload.
- **Mismatch = physically impossible for that model**, not "below spec".
- **When the readings mismatch, the measured readings take priority** over
  the catalogue for that bike (see "Effective specs").
- **Alert labels, Tinder style.** When a ride (or the init ride) ends with
  alerts, one full-screen card per alert asks "Did this really happen?"
  (crash: "Was this a real crash or fall?"). Swipe right / YES, swipe
  left / NO; the next card slides in; progress "ALERT 2 OF 3" with dots;
  a small **SKIP** at the top skips **all** remaining alerts. After the
  last card or SKIP, the ride summary (or init-ride result) opens. No
  alerts → no cards. Mockup: `.superpowers/brainstorm/.../alert-cards.html`.
- **What a label does:** YES on anything → saved as confirmed. NO on a
  warning (wobble, impact, extreme lean) → saved and that threshold
  becomes slightly less sensitive (today's NOT REAL behaviour). Any answer
  on a crash → saved as data only; crash detection never loosens.
  Unanswered alerts stay unlabelled.
- **Tidy-up scope: the whole codebase**, together with the new code.

## Goals

- A bundled bike catalogue covering the bikes realistically ridden in
  Turkey and Saudi Arabia, scooters and 125s through litre bikes.
- Every spec value has a source; values that can't be verified are left
  empty, never guessed.
- Init ride compares measured readings with the chosen model's envelope;
  result (match or mismatch, expected vs measured) saved to the database.
- "Other" bikes saved with the rider's text and init-ride readings; the
  owner can list missing models in one query or one command.
- Labels for every alert, plus a raw motion clip around each alert.
- Per-ride vibration signature by speed band, uploaded.
- Codebase tidied; all tests green; the app flows smoothly end to end.

## Non-goals

- No ML model, on device or on the server.
- No spec check on regular rides.
- No catalogue editing in the app; the owner adds models by editing the
  catalogue file.
- No new rider-facing statistics derived from specs.
- No change of state management, framework, or backend stack.

## Anti-goals (would make this a failure even if it "works")

- Guessed or made-up spec numbers in the catalogue.
- A gentle or slow init ride flagged as a mismatch.
- A GPS glitch or pothole creating a mismatch.
- Crash detection becoming less sensitive because of any label or spec.
- Existing riders losing their bike, calibration, learned safety
  baseline, or queued uploads after the update.
- The label cards getting in the way: they must be fast to clear, and
  never appear when there is nothing to answer.

## The catalogue

**One source file** in the repo (e.g. `catalogue/bikes.json`, with a
`version`), bundled into the app as an asset and loaded by the backend
into a table so the database can join on it. Python validates the file
(schema, ranges, every non-empty spec has a source) as part of the
backend tests.

**Coverage.** Research the models sold in Turkey and Saudi Arabia,
roughly the current and recent generations. Brands to cover at least:
Honda, Yamaha, Suzuki, Kawasaki, BMW, KTM, Ducati, Triumph,
Harley-Davidson, CFMoto, Bajaj, TVS, Kymco, SYM, Piaggio/Vespa, Benelli,
Voge, and Turkish brands such as Mondial, Kuba and RKS. Generations that
differ in performance are separate entries (e.g. GSX-S1000 2015–2020 vs
2021–). Aim for breadth over depth; the owner will add more later.

**Fields per model:** stable id, make, model, year range (from, to or
open), category (scooter, naked, sport, touring, adventure, cruiser,
off-road, commuter), displacement cc, power kW, wet or kerb weight kg,
top speed km/h, 0–100 km/h s, ABS (yes/no/optional), and for each
performance number its source (URL) and whether it is official or a road
test. Top speed and 0–100 are often missing from official sheets: use
reputable road tests; otherwise leave empty.

**Sourcing rules.** Prefer manufacturer spec sheets for cc, power and
weight; reputable magazine road tests for top speed and 0–100.
Manufacturer-claimed figures count as official. Spec-aggregator sites
(bikez, motorcyclespecs, Wikipedia…) are allowed, but each value is
tagged with its source quality (official, road test, aggregator) so the
owner can filter them out. Record the source per value. Empty is better
than a guess. *(Builder's call, accepted by the owner.)*

**Market variants.** When the Turkish and Saudi versions of a model
differ in performance, they are separate entries labelled by market.
*(Builder's call, accepted.)* **Size:** about 120 models to start.

**Missing top speed.** When a catalogue model has no sourced top speed,
the setup page asks the rider one extra field, "Fastest possible speed"
(the same field as Other), for that model only. The answer is stored as
rider-entered, never written into catalogue data, and the init ride's
top-speed check is recorded as "not tested". *(Owner decision.)*

## Init-ride spec check

Runs once, at the end of each init ride, when the rider accepts the
calibration. The init ride already measures top speed and a stop.

**Expected envelope for the chosen model:**

- **Top speed**: the catalogue top speed.
- **Acceleration**: the hardest forward acceleration the model can
  sustain for about one second, derived from its 0–100 time, or from
  power-to-weight when that is missing, and never above about 1.1 g.
- **Braking**: the hardest sustained deceleration a bike of that class can
  achieve (around 1.1 g for ABS road bikes, lower for scooters), which
  also gives a minimum stopping time from a given speed.

**Mismatch** only when a reading is clearly beyond the envelope and
sustained, so a single glitch can't trigger it. Starting defaults (builder
may tune them against the ride simulator):

- speed above top speed × 1.07 + 3 km/h for at least 3 s of GPS speed;
- forward acceleration above the expected maximum × 1.2 averaged over 1 s;
- a stop shorter than the minimum stopping time from its start speed, or
  deceleration above the braking limit × 1.2 averaged over 0.5 s.

Readings that never reach the envelope (gentle riding) are "not tested",
not a mismatch. Each check records **expected, measured, and result**
(match, mismatch, not tested). For "Other" bikes there is nothing to
compare against; the readings are saved as the bike's data.

**Effective specs.** What the app uses as the bike's specs (top speed for
the speedometer scale and init-ride progress, the envelope): the
catalogue's values; for "Other", the rider's value; and where the init
ride produced a mismatch, the measured readings take priority (e.g. the
higher measured top speed).

**Changing the model later** (Edit bike). When the model changes, the app
asks: "Fixing the model, or a different bike?" *(Owner decision.)*

- **Fixing the model**: calibration and learned safety data are kept; the
  stored init-ride readings are re-checked against the newly chosen model
  and a new check record is saved, without another init ride.
- **Different bike**: a new bike record is created; the rider does a new
  init ride and learning starts fresh. The old bike's calibration,
  baseline, rides and checks stay attached to the old bike.

## Database (new or changed)

- **Bikes**: add the catalogue model id and catalogue version, or "Other"
  with make, model, year text. Keep the existing display name and top
  speed.
- **Catalogue table** loaded from the catalogue file.
- **Model checks**, one per init ride (and per model change): bike,
  calibration, init ride, catalogue model or Other text, phone model, the
  expected envelope, the measured readings, each check's result, overall
  mismatch yes/no.
- **Missing models**: a view (and a small Python report command) listing
  "Other" bikes grouped by make/model with their readings, and catalogue
  models with mismatches.
- **Incidents**: rider label (yes, no, none) replacing the false-alarm
  flag's role, and the motion clip.
- **Rides**: vibration signature by speed band (below).
- Never edit a migration that may already have run on someone's database;
  add new ones.

## Data for future ML (per model)

1. **Bike and setup**: catalogue model and version (or Other text), phone
   model and OS, motion sensor rate, mount orientation (already in the
   calibration).
2. **Vibration signature by speed band** for every ride: for bands such as
   20–40, 40–60, 60–90, 90–120, 120+ km/h, the distribution of wobble-band
   shake and its dominant frequency, plus peak g. Today only one p99
   number per ride is uploaded; upload the full histograms per band.
3. **Performance per ride**: top speed, hardest 1 s acceleration, hardest
   braking, max lean (mostly already uploaded).
4. **Motion clip per alert**: about 10 s of raw 50 Hz accelerometer and
   gyroscope (5 s before, 5 s after the event), uploaded with the
   incident. A few tens of kilobytes at most.
5. **Labels**: the YES/NO answers from the cards.

## UX

- **Setup page** (first run and Edit bike): title and intro as today;
  MAKE chips (top brands first, "+ more"), MODEL list with year ranges for
  the chosen make, "My bike isn't listed → Other" link, CONTINUE. Other
  opens a short form: make, model, year (optional), fastest possible
  speed. Works offline (catalogue is bundled).
- **Existing riders after the update**: their free-text bike is kept and
  treated as Other; Edit bike lets them pick from the catalogue. Their
  calibration and learned safety baseline are kept.
- **Alert cards** as described above, after both rides and the init ride.
- **Summary**: the per-alert NOT REAL buttons are replaced by the cards;
  the summary shows each alert's answer.
- Check every flow end to end: first run, init ride, ride with and
  without alerts, crash alarm, edit bike, Other, offline then sync.

## Tidy-up

Whole codebase, existing and new code: split the largest screens
(ride, calibration, settings) into focused widgets; split the backend
schemas by area; remove duplication and dead code; keep naming and
patterns consistent. Behaviour stays the same; the existing tests must
keep passing and are the safety net. No architecture or stack changes.

## Constraints

- Flutter app (provider/ChangeNotifier), pure-Dart core tested with the
  ride simulator; FastAPI + asyncpg + Postgres backend; Docker compose.
- Offline-first: everything uploads through the existing outbox.
- Strict input validation on the backend, mirrored by database checks,
  as today.
- New app dependency allowed for the phone model (device info).

## Left to the builder

- Exact catalogue file format and table layout.
- Exact tolerances and envelope formulas (within the rules above),
  validated with the simulator.
- How the motion clip is encoded.
- Speed band edges and histogram layout.
- Which brands show first on the MAKE chips (by popularity in the two
  markets).
- How the tidy-up is sequenced.
