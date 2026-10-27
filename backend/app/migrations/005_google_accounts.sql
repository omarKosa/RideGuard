-- Riders sign in with Google. The phone keeps its rider id; the verified
-- Google account is linked to it (and moves to the newest rider when the
-- same person signs in on another install).

ALTER TABLE riders
    ADD COLUMN google_sub text UNIQUE CHECK (char_length(google_sub) BETWEEN 1 AND 255),
    ADD COLUMN google_email text CHECK (char_length(google_email) <= 254),
    ADD COLUMN google_name text CHECK (char_length(google_name) <= 120),
    ADD COLUMN google_linked_at timestamptz,
    ADD CONSTRAINT riders_google_linked
        CHECK ((google_sub IS NULL) = (google_linked_at IS NULL));
