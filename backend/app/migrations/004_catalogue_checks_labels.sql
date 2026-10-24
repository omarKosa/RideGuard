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
