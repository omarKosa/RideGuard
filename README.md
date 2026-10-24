# RideGuard

Motorcycle ride analytics on a phone: calibrated **lean angle**, **top speed**
and **braking / stop time**, analysed over a rolling window of the last
15 minutes and stored in Postgres through a small API. It also watches for
**crashes, speed wobbles and other anomalies**, and after a crash calls an
emergency contact unless the rider cancels.

```
lib/            Flutter app
  core/         Pure Dart: sensor fusion, rolling buffer, analysis, calibration,
                crash / wobble detection (core/safety)
  data/         Backend client, offline outbox, local storage
  services/     Sensor binding and the ride / calibration controllers
  screens/      UI
backend/        FastAPI + asyncpg service, SQL migrations, tests
docker-compose.yml   Postgres + API (+ test runner)
```

## How it works

### 1. Setup → init ride
The app starts on **bike setup**: pick the make, then the model (see
section 8), and the fastest possible speed. It then
shows a **safety briefing** that must be acknowledged, and runs the **init
ride**. The ride advances by itself (vibrating at each step), so the rider
never touches the phone:

| Task | What it calibrates |
|---|---|
| Hold still (bike upright) | Mount "up" axis, gyro bias, accelerometer bias |
| Ride straight, 20+ km/h | What "upright" really reads like (fixes side-stand/tilted calibration) |
| Top speed run | The rider's achieved top speed vs. the bike's rated top speed |
| Brake to a stop | Stop time, stop distance, deceleration (used for stop-time estimates) |
| Lean test (left + right) | Gyro scale and lean direction, verified against physics |

All but the first task can be skipped; the calibration quality score and
warnings reflect what was skipped.

### 2. Any phone orientation
Every reading is rotated from the phone's frame into the bike's frame
(`core/fusion/mount_orientation.dart`):

* **up**: gravity while standing still;
* **forward**: learned from acceleration and braking (the gravity-free
  acceleration vector multiplied by the sign of the GPS speed change);
* **right** = forward × up.

Portrait, landscape, flat on the tank, upside down or crooked: tests cover
all of these.

### 3. Lean angle
A complementary filter (`core/fusion/motion_pipeline.dart`):

* The **gyro roll rate** (bias learned whenever parked) is integrated for a
  fast response.
* At speed it is pulled towards the **coordinated-turn lean**,
  `atan(v·ω/g)`, which never drifts.
* At low speed it is pulled towards the **gravity tilt** instead, except
  while pulling away or braking.

**Normalization** (`StraightLineNormalizer`): a bike riding straight at a
steady speed is upright, so the gravity reading at those moments *is* the
true "0°". The app keeps re-learning it. That corrects a side-stand
calibration and a tilted holder. If the phone slips in its mount mid-ride,
the app detects it, re-aligns, and counts it.

### 4. Rolling-window analysis ("buffer load")
Processed samples (10 Hz) go into a fixed 15-minute time-windowed buffer
(`AppConfig.analysisWindowMinutes`). Max speed, max lean left/right, max stop time and best
deceleration are computed over that window, with whole-ride totals tracked
separately. Lean below 10 km/h and speed from stale GPS fixes are ignored.

### 5. Getting data to the database safely
Every request goes into a file-backed **outbox**, delivered in order with
retry/backoff, so offline rides upload later. Ids are generated on the
phone, and samples are keyed by `(ride_id, seq)`, so retries never
duplicate rows. The API validates every field (Pydantic), and Postgres
enforces the same ranges with CHECK constraints.
`GET /v1/rides/{id}/analysis` recomputes the window metrics from the raw
samples as an independent check of what the phone reported.

### 6. Crashes, wobbles and anomalies
`core/safety/safety_monitor.dart` reads the **raw 50 Hz IMU**. The 10 Hz
processed stream is too slow for a 4-10 Hz wobble or a 50 ms impact. It runs
during rides and during the init ride.

| Hazard | Detected when | Response |
|---|---|---|
| **Crash** | A ≥ 4 g impact while riding, then stopped for 5 s; **or** the bike lies on its side (gravity ≥ 60° from the bike's up axis) for 3 s within a minute of riding | Loud looping alarm at full alarm volume + vibration, 30 s countdown, then **calls the emergency contact** |
| **Speed wobble** | Rotation ≥ 0.5 rad/s RMS reversing 3-12 times a second for 0.6 s, above 30 km/h | Short alert sound + vibration + on-screen warning |
| **Impact** | A ≥ 4 g jolt that the rider rides through (pothole, kerb) | Same as wobble |
| **Extreme lean** | ≥ 55° for 0.5 s above 20 km/h | Same as wobble |

* Turns, swerves, slaloms (≤ 1.5 Hz), emergency stops (a 9 m/s² stop tilts
  the gravity reading only to ~42°) and the side stand never trigger, and
  the tests check this for odd mounts too.
* Crash detection only arms after the bike has moved at 15+ km/h, and
  disarms after firing until it moves again. A bike knocked over in the
  garage, or one still lying where it fell, doesn't set it off.
* The rider cancels with a **long press** on "I'M OK", because rain or
  debris on the screen of a fallen phone can register as taps. Stopping
  the ride also cancels. Back is ignored while the alert is up.
* The emergency contact is set in **Settings**. It stays on the phone and
  is never uploaded. Saving it asks for the Android "Phone" permission up
  front. Without that permission, the app opens the dialer with the number
  instead of calling. If there's no contact, or the call fails, the alarm
  keeps sounding so people nearby notice.
* Every incident is uploaded through the outbox. A crash is uploaded when
  detected (`pending`) and again when resolved (`cancelled`, `called`,
  `dialer_opened`, `call_failed` or `no_contact`).

The thresholds in the table are defaults. Each bike and mount learns its
own (next section).

### 7. Learning to avoid false alarms
Every ride, starting with the init ride, teaches the app what *normal*
riding looks like on this phone, bike and mount
(`core/safety/safety_baseline.dart`):

* **What's measured:** for each second of steady riding (20+ km/h), the
  strongest wobble-band oscillation and the biggest jolt. Seconds within 5 s
  of any detected hazard are left out, so a real wobble never becomes
  "normal". The phone's actual sensor rate is measured too.
* **Memory:** the most recent rides covering about 3 hours of riding.
  Older rides are dropped, so after you fix a rattling mount, sensitivity
  comes back by itself.
* **Thresholds** sit well above the 99th percentile of normal riding, so
  one pothole doesn't move them: wobble = 3× the normal oscillation and
  impact = 1.25× the normal peak. They only ever **rise from the defaults,
  never past a cap** (wobble 1.0 rad/s, impact 6 g, lean 65°), so learning
  can't switch detection off. At least 60 s of riding is needed before
  anything changes.
* **Rider feedback:** the ride summary lists each alert, and a warning can
  be marked **NOT REAL**. That threshold then moves just above the event
  (wobble +15%, impact +10%, lean +3°), still within its cap.
* **Crashes never loosen.** A crash cancelled with "I'M OK" may still have
  been a real crash, so cancellations are only counted.
* **Setup warnings:** the init ride result and Settings → Safety learning
  say when the mount vibrates so much that alerts sit at their least
  sensitive, or when the phone's sensor rate is too slow for fast wobbles
  (it needs about 4 samples per oscillation).
* Redoing the init ride (possibly a new mount) starts learning over, and
  Settings can reset it manually.
* Each ride uploads its statistics and the thresholds it used
  (`safety_stats`, including per-speed-band figures in `bands`), and
  incidents carry the rider's `rider_label` (`yes` / `no`). The server keeps
  the evidence needed to tune the defaults across riders.

### 8. Bike catalogue and the init-ride check
**Catalogue.** `backend/app/catalogue/bikes.json` (about 120 models, mostly
what is sold in Turkey and Saudi Arabia) ships with both the backend and the
app. The API loads it into the `catalogue_models` table at startup. Setup
asks for the make, then the model; **Other** takes a free-text make, model
and year. A model the rider picks is stored as `catalogue_model_id` plus the
catalogue `catalogue_version`; the rider sees nothing new on ride screens
because a model is known.

*Add a model:* append an entry to `models` in `bikes.json` (and the make to
`make_order` if it is new), then run `python -m pytest tests/test_catalogue.py`
in `backend/`. The file is validated on load. Sourcing rules:

* Every non-null spec (displacement, power, weight, top speed, 0-100 km/h)
  has a `source` URL and a `quality`: `official` (maker or distributor),
  `road_test` or `aggregator`.
* A value nobody could verify is `null`. Empty beats guessed.
* Versions of a bike that differ between markets (TR vs SA) are separate
  entries.
* Bump `version` when the file changes.

**Init-ride check.** Only at the end of the init ride (and when the rider
fixes the model afterwards, using the readings already kept), the readings
are judged against what the model can physically do. It is never run on
regular rides.

| Item | Mismatch only when |
|---|---|
| Top speed | sustained >= 3 s above top speed x 1.07 + 3 km/h |
| Acceleration | forward acceleration averaged over 1 s above 1.2 x the expected maximum |
| Braking | deceleration averaged over 0.5 s, or a stop's mean, above 1.2 x the braking limit |

Gentle riding is **not tested**, never a mismatch. On a top speed mismatch
the bike's top speed becomes the measured one. Each check is uploaded as a
model check and an "Other" bike is saved the same way, with everything
"not tested", so the catalogue's gaps show up in the reports below.

**Reports.** From `backend/` with `DATABASE_URL` set:

```bash
python -m app.reports gaps         # Other bikes: what the catalogue is missing
python -m app.reports mismatches   # models whose specs the riders contradict
```

(Docker: `docker compose exec api python -m app.reports gaps`.)

### 9. Alert cards
After a ride (and the init ride), each alert gets a card: swipe right or tap
**YES** if it really happened, swipe left or **NO** if not. **SKIP** (or
back) ends the review and leaves the remaining alerts unanswered. No alerts,
no cards. A **NO** on a
warning raises that threshold like NOT REAL did (wobble x1.15, impact x1.1,
lean +3 degrees, within the caps). Crash labels are data only: no label makes
crash detection less sensitive. Older clients that send `false_alarm` are
still accepted.

### 10. Data collected for later tuning
No machine learning runs anywhere; the server just keeps clean data for
tuning the defaults by hand:

* Per ride: `safety_stats` (normal-riding statistics, thresholds used, IMU
  rate, `bands`), and `performance` (sustained top speed, peak acceleration
  and braking, stops) on init rides.
* Per incident: kind, speed, lean, peak acceleration, wobble figures, the
  outcome, the rider's label and when it was given, and a raw motion
  **clip** (about 5 s either side at the IMU rate, accelerometer and gyro
  in the phone frame).
* Per bike: the catalogue model and version, or the Other text, plus the
  phone model and OS version on the rider.
* Per model check: expected envelope, measured readings, per-item results.

## Run the backend

```bash
cp .env.example .env              # optional: change the password/ports
docker compose up -d --build      # Postgres 17 + API on :8000
curl localhost:8000/health        # {"status":"ok","database":"ok"}
open http://localhost:8000/docs   # interactive API docs
```

Postgres is published on `127.0.0.1:5432` only. The API listens on all
interfaces so a phone on the same Wi-Fi can reach it. Migrations run
automatically at API start. An existing install needs
`docker compose up -d --build` to rebuild the API image so migrations
002-004 (labels, clips, catalogue, model checks) are applied.

> If `docker` says *permission denied*, either prefix commands with `sudo`
> or add yourself to the group: `sudo usermod -aG docker $USER` (then log
> out and in).

## Run the app

```bash
flutter pub get
# Android emulator (reaches the host as 10.0.2.2):
flutter run
# Real phone on the same network as the computer:
flutter run --dart-define=RIDEGUARD_API_URL=http://192.168.1.20:8000
```

The server URL can also be changed in **Settings → Backend** (with a
connection test). Cleartext HTTP is enabled for development. Put the API
behind HTTPS before using it outside your LAN.

## Tests

```bash
flutter test                                        # app: fusion, analysis, sync, UI
docker compose --profile test run --rm api-test     # backend against real Postgres
RIDEGUARD_LIVE_API=http://localhost:8000 \
  flutter test test/integration                     # app → API → Postgres end to end
                                                    # (catalogue bike, Other bike, model check, label, clip)
```

The app tests use a physics-based ride simulator
(`test/support/ride_simulator.dart`). It generates phone-frame
accelerometer, gyro and GPS data for coordinated turns, side-stand lean,
acceleration and braking, with the phone mounted at any rotation.

## API

| Method | Path | |
|---|---|---|
| PUT/GET | `/v1/riders/{id}` | Upsert (platform, phone model, OS version) / read rider |
| PUT/GET | `/v1/bikes/{id}` | Upsert / read bike (catalogue model + version, or Other make / model / year) |
| PUT | `/v1/bikes/{id}/model-checks/{check_id}` | Init-ride spec check (idempotent; first write wins) |
| GET | `/v1/bikes/{id}/model-checks` | A bike's checks, newest first |
| GET | `/v1/bikes/{id}/rides` | Ride history (`?kind=ride\|calibration`) |
| GET | `/v1/bikes/{id}/stats` | All-time bests + latest calibration |
| PUT/GET | `/v1/rides/{id}` | Start (header) / read ride |
| POST | `/v1/rides/{id}/samples` | Batch of 10 Hz samples (idempotent) |
| PUT | `/v1/rides/{id}/summary` | Finish: totals, window stats, brake events, `safety_stats` (with `bands`), `performance` |
| GET | `/v1/rides/{id}/analysis?window_min=15` | Server-side window recomputation (default 15) |
| PUT/GET | `/v1/calibrations/{id}` | Calibration result (immutable) |
| PUT | `/v1/rides/{id}/incidents/{incident_id}` | Crash / wobble / impact / extreme lean (upsert; a crash moves from `pending` to its outcome once; warnings can get a `rider_label`; the deprecated `false_alarm` is still accepted) |
| GET | `/v1/rides/{id}/incidents` | A ride's incidents in order |
| PUT | `/v1/rides/{id}/incidents/{incident_id}/clip` | Raw motion around an incident (accelerometer + gyro) |
| GET | `/health` | API + database health |

## Safety

The init ride asks for a top-speed run and a firm stop. The app requires
explicit acknowledgement (closed track or empty legal road, full gear,
phone mounted and untouched) and repeats the warning during those tasks.
Every task except "hold still" can be skipped.

## Known limitations

* The lean reading is the *effective* (centre-of-mass) lean the physics
  reference converges to. The bike's own lean can be a few degrees more,
  depending on tyre width and how far the rider hangs off.
* The API has no authentication yet. Add it before exposing the API
  beyond a trusted network.
* The Android application id is still `com.example.motorcycle_rider_app`.
  Change it before publishing.
* Crash and wobble thresholds are set from physics and checked against the
  simulator, not tuned on real crash data. Learning only adapts them to
  what *normal* riding looks like. It can't prove that a real crash or
  wobble is caught, so field-test on your own mount (Settings → Test alarm
  checks the alarm itself).
* Detection runs while the ride screen is open, which the app keeps awake.
  It doesn't run in the background or after the app is killed. Calling
  without a tap works on Android only. Android always opens the dialer
  for emergency numbers such as 112/911, so the contact should be a person.
