# RideGuard

Motorcycle ride analytics on a phone: calibrated **lean angle**, **top speed**
and **braking / stop time**, analysed over a rolling window of the last
15 minutes and stored in Postgres through a small API.

```
lib/            Flutter app
  core/         Pure Dart: sensor fusion, rolling buffer, analysis, calibration
  data/         Backend client, offline outbox, local storage
  services/     Sensor binding and the ride / calibration controllers
  screens/      UI
backend/        FastAPI + asyncpg service, SQL migrations, tests
docker-compose.yml   Postgres + API (+ test runner)
```

## How it works

### 1. Setup → init ride
The app starts on **bike setup** (model + fastest possible speed). It then
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

## Run the backend

```bash
cp .env.example .env              # optional: change the password/ports
docker compose up -d --build      # Postgres 17 + API on :8000
curl localhost:8000/health        # {"status":"ok","database":"ok"}
open http://localhost:8000/docs   # interactive API docs
```

Postgres is published on `127.0.0.1:5432` only. The API listens on all
interfaces so a phone on the same Wi-Fi can reach it. Migrations run
automatically at API start.

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
```

The app tests use a physics-based ride simulator
(`test/support/ride_simulator.dart`). It generates phone-frame
accelerometer, gyro and GPS data for coordinated turns, side-stand lean,
acceleration and braking, with the phone mounted at any rotation.

## API

| Method | Path | |
|---|---|---|
| PUT | `/v1/riders/{id}` | Upsert rider (device) |
| PUT/GET | `/v1/bikes/{id}` | Upsert / read bike |
| GET | `/v1/bikes/{id}/rides` | Ride history (`?kind=ride\|calibration`) |
| GET | `/v1/bikes/{id}/stats` | All-time bests + latest calibration |
| PUT/GET | `/v1/rides/{id}` | Start (header) / read ride |
| POST | `/v1/rides/{id}/samples` | Batch of 10 Hz samples (idempotent) |
| PUT | `/v1/rides/{id}/summary` | Finish: totals, window stats, brake events |
| GET | `/v1/rides/{id}/analysis?window_min=15` | Server-side window recomputation (default 15) |
| PUT/GET | `/v1/calibrations/{id}` | Calibration result (immutable) |
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
