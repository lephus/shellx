-- The native iPhone app sends its APNs device token itself (no Firebase): apns_topic is the app's
-- bundle id and apns_env the APNs host the token belongs to (sandbox for Debug builds). Both NULL for
-- an FCM token; both set for an APNs one.
ALTER TABLE push_tokens ADD COLUMN apns_topic TEXT CHECK (apns_topic IN ('com.shellx.prod', 'com.shellx.dev'));
ALTER TABLE push_tokens ADD COLUMN apns_env TEXT CHECK (apns_env IN ('sandbox', 'production'));
