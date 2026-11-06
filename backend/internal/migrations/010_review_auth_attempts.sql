-- 010: Durable account-wide review-auth attempt budgets (demo-account-access).
--
-- review_auth_attempts records one row per admitted review-code evaluation
-- (correct or not) for the single configured review account. Rows carry no
-- code, IP, device, email, or outcome payload — only the admitted timestamp
-- the rolling 15-minute (5) and 24-hour (20) budgets count against.
-- Reservation and pruning happen atomically inside one store transaction
-- (account-row lock first); a denied evaluation appends nothing, and store
-- failure fails closed without an in-memory fallback.
--
-- Account deletion explicitly removes these rows inside the existing purge
-- transaction (both stores) — no FK-cascade or pragma reliance. The user FK
-- is a plain integrity link, never a cascade path.
--
-- Postgres dialect; migrations.adaptToSQLite converts this for the SQLite
-- test store (TIMESTAMPTZ->TEXT, UUID->TEXT, NOW()->(datetime('now')),
-- DEFAULT false/true->0/1, IF NOT EXISTS stripped on CREATE/ADD COLUMN).

CREATE TABLE IF NOT EXISTS review_auth_attempts (
    id TEXT PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id),
    admitted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_review_auth_attempts_user_time
    ON review_auth_attempts(user_id, admitted_at);
