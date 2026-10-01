-- Per-device refresh families: revoke queries filter on (user_id, device_id).
CREATE INDEX IF NOT EXISTS idx_refresh_tokens_user_device
    ON refresh_tokens(user_id, device_id);