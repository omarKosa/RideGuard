-- Bike catalogue, bike model fields and rider phone fields.
-- (Later tasks append: model_checks table, incident labels/clips.)

CREATE TABLE catalogue_models (
    id                text PRIMARY KEY,
    catalogue_version text NOT NULL,
    make              text,
    model             text,
    year_from         smallint,
    year_to           smallint,
    markets           text[],
    category          text,
    abs               text,
    displacement_cc   real,
    power_kw          real,
    weight_kg         real,
    top_speed_kmh     real,
    zero_to_100_s     real,
    spec              jsonb NOT NULL,
    updated_at        timestamptz DEFAULT now()
);

ALTER TABLE riders
    ADD COLUMN phone_model text CHECK (char_length(phone_model) <= 80),
    ADD COLUMN os_version  text CHECK (char_length(os_version) <= 40);

-- catalogue_model_id deliberately has no FK: the catalogue ships with the
-- app and may be newer than the backend's copy.
ALTER TABLE bikes
    ADD COLUMN catalogue_model_id text,
    ADD COLUMN catalogue_version  text,
    ADD COLUMN other_make  text CHECK (char_length(other_make) BETWEEN 1 AND 40),
    ADD COLUMN other_model text CHECK (char_length(other_model) BETWEEN 1 AND 60),
    ADD COLUMN other_year  smallint CHECK (other_year BETWEEN 1950 AND 2030),
    ADD COLUMN top_speed_source text NOT NULL DEFAULT 'rider'
        CHECK (top_speed_source IN ('catalogue', 'rider', 'measured')),
    ADD CONSTRAINT bikes_catalogue_xor_other CHECK (
        catalogue_model_id IS NULL OR (other_make IS NULL AND other_model IS NULL));

-- Init-ride model checks: what the phone measured vs the catalogue spec.
CREATE TABLE model_checks (
    id                 uuid PRIMARY KEY,
    bike_id            uuid NOT NULL REFERENCES bikes (id) ON DELETE CASCADE,
    calibration_id     uuid NOT NULL REFERENCES calibrations (id) ON DELETE CASCADE,
    ride_id            uuid NOT NULL REFERENCES rides (id) ON DELETE CASCADE,
    reason             text NOT NULL CHECK (reason IN ('init_ride', 'model_corrected')),
    catalogue_model_id text,
    catalogue_version  text,
    other_make         text CHECK (char_length(other_make) BETWEEN 1 AND 40),
    other_model        text CHECK (char_length(other_model) BETWEEN 1 AND 60),
    other_year         smallint CHECK (other_year BETWEEN 1950 AND 2030),
    phone_model        text CHECK (char_length(phone_model) <= 80),
    imu_hz             real CHECK (imu_hz > 0 AND imu_hz <= 1000),
    expected           jsonb,
    measured           jsonb NOT NULL,
    results            jsonb NOT NULL,
    mismatch           boolean NOT NULL,
    checked_at         timestamptz NOT NULL,
    created_at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX model_checks_catalogue_idx ON model_checks (catalogue_model_id);
CREATE INDEX model_checks_bike_idx ON model_checks (bike_id, checked_at DESC);

-- Bikes the rider entered as "Other": what the catalogue is missing.
CREATE VIEW catalogue_gaps AS
SELECT lower(trim(b.other_make))  AS make,
       lower(trim(b.other_model)) AS model,
       count(DISTINCT b.id)       AS bikes,
       array_agg(DISTINCT b.other_year) FILTER (WHERE b.other_year IS NOT NULL) AS years,
       (array_agg(c.measured ORDER BY c.checked_at DESC)
            FILTER (WHERE c.id IS NOT NULL))[1] AS latest_measured,
       max((c.measured ->> 'sustained_top_speed_kmh')::double precision)
            AS max_sustained_speed_kmh,
       max((c.measured ->> 'peak_accel_mps2')::double precision) AS max_accel_mps2,
       max((c.measured ->> 'peak_decel_mps2')::double precision) AS max_decel_mps2
FROM bikes b
LEFT JOIN model_checks c ON c.bike_id = b.id
WHERE b.other_model IS NOT NULL
GROUP BY lower(trim(b.other_make)), lower(trim(b.other_model));

-- Catalogue models whose specs the measurements contradict.
CREATE VIEW catalogue_mismatches AS
SELECT c.catalogue_model_id,
       count(*)                           AS checks,
       count(*) FILTER (WHERE c.mismatch) AS mismatches,
       (SELECT coalesce(array_agg(DISTINCT r.key ORDER BY r.key), '{}')
          FROM model_checks m, jsonb_each_text(m.results) r
         WHERE m.catalogue_model_id = c.catalogue_model_id
           AND r.value = 'mismatch') AS mismatch_items,
       (array_agg(c.measured ORDER BY c.checked_at DESC))[1] AS latest_measured,
       (array_agg(c.expected ORDER BY c.checked_at DESC))[1] AS latest_expected
FROM model_checks c
WHERE c.catalogue_model_id IS NOT NULL
GROUP BY c.catalogue_model_id;
