-- The name a rider chose for themselves in the app. Separate from
-- google_name, which is whatever the linked Google account says.

ALTER TABLE riders
    ADD COLUMN display_name text CHECK (char_length(display_name) BETWEEN 1 AND 60);
