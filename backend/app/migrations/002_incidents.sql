-- Crashes, speed wobbles and other anomalies detected on the phone.
-- A crash is written when detected ('pending') and again once the rider
-- cancelled or the emergency contact was called.

CREATE TABLE incidents (
    id            uuid PRIMARY KEY,
    ride_id       uuid NOT NULL REFERENCES rides (id) ON DELETE CASCADE,
    kind          text NOT NULL
                  CHECK (kind IN ('crash', 'wobble', 'impact', 'extreme_lean')),
    detected_at   timestamptz NOT NULL,
    speed_kmh     real NOT NULL CHECK (speed_kmh BETWEEN 0 AND 500),
    lean_deg      real NOT NULL CHECK (lean_deg BETWEEN -90 AND 90),
    peak_accel_g  real CHECK (peak_accel_g BETWEEN 0 AND 100),
    wobble_hz     real CHECK (wobble_hz > 0 AND wobble_hz <= 25),
    latitude      double precision CHECK (latitude BETWEEN -90 AND 90),
    longitude     double precision CHECK (longitude BETWEEN -180 AND 180),
    outcome       text NOT NULL CHECK (outcome IN (
                      'pending', 'warned', 'cancelled', 'called',
                      'dialer_opened', 'call_failed', 'no_contact')),
    resolved_at   timestamptz,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    CHECK ((latitude IS NULL) = (longitude IS NULL)),
    -- Only crashes escalate; everything else is a warning.
    CHECK ((kind = 'crash') = (outcome <> 'warned')),
    CHECK (CASE outcome
               WHEN 'warned' THEN resolved_at IS NULL
               WHEN 'pending' THEN resolved_at IS NULL
               ELSE resolved_at IS NOT NULL
           END),
    CHECK (resolved_at IS NULL OR resolved_at >= detected_at)
);
CREATE INDEX incidents_ride_idx ON incidents (ride_id, detected_at);
