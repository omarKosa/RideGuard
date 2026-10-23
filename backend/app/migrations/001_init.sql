-- RideGuard schema v1.
-- Ids are generated on the phone so every write is an idempotent upsert
-- and the offline outbox can retry safely. Units are in the column names.

CREATE TABLE riders (
    id          uuid PRIMARY KEY,
    platform    text CHECK (char_length(platform) <= 32),
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE bikes (
    id                   uuid PRIMARY KEY,
    rider_id             uuid NOT NULL REFERENCES riders (id) ON DELETE CASCADE,
    model                text NOT NULL CHECK (char_length(model) BETWEEN 2 AND 80),
    rated_top_speed_kmh  real NOT NULL CHECK (rated_top_speed_kmh BETWEEN 40 AND 420),
    created_at           timestamptz NOT NULL DEFAULT now(),
    updated_at           timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX bikes_rider_idx ON bikes (rider_id);

CREATE TABLE rides (
    id                    uuid PRIMARY KEY,
    bike_id               uuid NOT NULL REFERENCES bikes (id) ON DELETE CASCADE,
    calibration_id        uuid,
    kind                  text NOT NULL CHECK (kind IN ('calibration', 'ride')),
    status                text NOT NULL DEFAULT 'recording'
                          CHECK (status IN ('recording', 'completed', 'aborted')),
    started_at            timestamptz NOT NULL,
    ended_at              timestamptz,
    analysis_window_min   smallint NOT NULL CHECK (analysis_window_min BETWEEN 5 AND 60),
    mount_realignments    integer CHECK (mount_realignments >= 0),
    reported_sample_count integer CHECK (reported_sample_count >= 0),
    -- Whole-ride results as computed on the phone.
    max_speed_kmh         real CHECK (max_speed_kmh BETWEEN 0 AND 500),
    max_lean_left_deg     real CHECK (max_lean_left_deg BETWEEN 0 AND 90),
    max_lean_right_deg    real CHECK (max_lean_right_deg BETWEEN 0 AND 90),
    max_stop_time_s       real CHECK (max_stop_time_s BETWEEN 0 AND 120),
    best_decel_mps2       real CHECK (best_decel_mps2 BETWEEN 0 AND 30),
    brake_event_count     integer CHECK (brake_event_count >= 0),
    distance_m            double precision CHECK (distance_m >= 0),
    moving_time_s         double precision CHECK (moving_time_s >= 0),
    avg_moving_speed_kmh  real CHECK (avg_moving_speed_kmh BETWEEN 0 AND 500),
    -- Same metrics over the final analysis window ("last N minutes").
    window_stats          jsonb,
    created_at            timestamptz NOT NULL DEFAULT now(),
    updated_at            timestamptz NOT NULL DEFAULT now(),
    CHECK (ended_at IS NULL OR ended_at >= started_at)
);
CREATE INDEX rides_bike_started_idx ON rides (bike_id, started_at DESC);

CREATE TABLE calibrations (
    id                      uuid PRIMARY KEY,
    bike_id                 uuid NOT NULL REFERENCES bikes (id) ON DELETE CASCADE,
    ride_id                 uuid NOT NULL REFERENCES rides (id) ON DELETE CASCADE,
    calibrated_at           timestamptz NOT NULL,
    -- Phone-frame unit vectors and biases.
    mount_up                double precision[] NOT NULL CHECK (cardinality(mount_up) = 3),
    mount_forward           double precision[] NOT NULL CHECK (cardinality(mount_forward) = 3),
    gyro_bias               double precision[] NOT NULL CHECK (cardinality(gyro_bias) = 3),
    linear_accel_bias       double precision[] NOT NULL CHECK (cardinality(linear_accel_bias) = 3),
    lean_gain               real NOT NULL CHECK (lean_gain BETWEEN 0.5 AND 2),
    forward_from_motion     boolean NOT NULL,
    straight_offset_deg     real NOT NULL CHECK (straight_offset_deg BETWEEN -90 AND 90),
    quality                 real NOT NULL CHECK (quality BETWEEN 0 AND 1),
    achieved_top_speed_kmh  real CHECK (achieved_top_speed_kmh BETWEEN 0 AND 500),
    stop_time_s             real CHECK (stop_time_s > 0 AND stop_time_s <= 120),
    stop_start_speed_kmh    real CHECK (stop_start_speed_kmh BETWEEN 0 AND 500),
    stop_distance_m         real CHECK (stop_distance_m >= 0),
    max_decel_mps2          real CHECK (max_decel_mps2 BETWEEN 0 AND 30),
    skipped_tasks           text[] NOT NULL DEFAULT '{}',
    warnings                text[] NOT NULL DEFAULT '{}',
    created_at              timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX calibrations_bike_idx ON calibrations (bike_id, calibrated_at DESC);

ALTER TABLE rides
    ADD CONSTRAINT rides_calibration_fk FOREIGN KEY (calibration_id)
    REFERENCES calibrations (id) ON DELETE SET NULL;

-- 10 Hz processed samples. (ride_id, seq) makes uploads idempotent.
CREATE TABLE ride_samples (
    ride_id             uuid NOT NULL REFERENCES rides (id) ON DELETE CASCADE,
    seq                 integer NOT NULL CHECK (seq >= 0),
    recorded_at         timestamptz NOT NULL,
    speed_kmh           real NOT NULL CHECK (speed_kmh BETWEEN 0 AND 500),
    speed_source        text NOT NULL
                        CHECK (speed_source IN ('none', 'gps', 'deadReckoning', 'stale')),
    lean_deg            real NOT NULL CHECK (lean_deg BETWEEN -90 AND 90),
    roll_rate_dps       real NOT NULL CHECK (abs(roll_rate_dps) <= 2000),
    yaw_rate_dps        real NOT NULL CHECK (abs(yaw_rate_dps) <= 2000),
    forward_accel_mps2  real NOT NULL CHECK (abs(forward_accel_mps2) <= 100),
    lateral_accel_mps2  real NOT NULL CHECK (abs(lateral_accel_mps2) <= 100),
    latitude            double precision CHECK (latitude BETWEEN -90 AND 90),
    longitude           double precision CHECK (longitude BETWEEN -180 AND 180),
    gps_accuracy_m      real CHECK (gps_accuracy_m >= 0),
    PRIMARY KEY (ride_id, seq)
);
CREATE INDEX ride_samples_time_idx ON ride_samples (ride_id, recorded_at);

CREATE TABLE brake_events (
    ride_id          uuid NOT NULL REFERENCES rides (id) ON DELETE CASCADE,
    idx              smallint NOT NULL CHECK (idx >= 0),
    started_at       timestamptz NOT NULL,
    ended_at         timestamptz NOT NULL,
    start_speed_kmh  real NOT NULL CHECK (start_speed_kmh > 0 AND start_speed_kmh <= 500),
    duration_s       real NOT NULL CHECK (duration_s > 0 AND duration_s <= 120),
    distance_m       real NOT NULL CHECK (distance_m >= 0),
    peak_decel_mps2  real NOT NULL CHECK (peak_decel_mps2 BETWEEN 0 AND 30),
    PRIMARY KEY (ride_id, idx),
    CHECK (ended_at >= started_at)
);
