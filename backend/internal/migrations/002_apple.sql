-- Sign in with Apple (F2). Users created via Apple sign-in are keyed by
-- Apple's stable `sub` identifier rather than (only) email, because Apple may
-- withhold the email after the first authorization. The partial unique index
-- keeps OTP-only users (apple_subject NULL) unconstrained.
ALTER TABLE users ADD COLUMN IF NOT EXISTS apple_subject TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_apple_subject
    ON users(apple_subject) WHERE apple_subject IS NOT NULL;