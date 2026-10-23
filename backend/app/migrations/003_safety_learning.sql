-- Learning to avoid false alarms. The phone tunes its own thresholds; the
-- server keeps the evidence so default thresholds can be tuned across
-- riders later.

-- Strength of a wobble, and the rider's "that was not real" label.
ALTER TABLE incidents
    ADD COLUMN wobble_rms real CHECK (wobble_rms BETWEEN 0 AND 100),
    ADD COLUMN false_alarm boolean NOT NULL DEFAULT false,
    ADD CONSTRAINT incidents_crash_not_false_alarm
        CHECK (NOT (false_alarm AND kind = 'crash'));

-- Normal-riding statistics of each ride and the thresholds it used.
ALTER TABLE rides ADD COLUMN safety_stats jsonb;
