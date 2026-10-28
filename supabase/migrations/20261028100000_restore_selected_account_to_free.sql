-- Keep the selected account on the Free plan. If it is already effectively
-- Free, or no entitlement row exists, this migration makes no change.

UPDATE private.subscription_entitlements AS entitlement
SET is_active = false,
    plan = 'free',
    scheduled_plan = NULL,
    scheduled_plan_effective_at = NULL,
    payment_grace_until = NULL,
    trial_ends_at = NULL,
    cancel_at_period_end = false,
    billing_status = 'canceled',
    current_period_end = COALESCE(
        entitlement.current_period_end,
        timezone('utc'::text, now())
    ),
    expires_at = COALESCE(
        entitlement.expires_at,
        timezone('utc'::text, now())
    ),
    updated_at = timezone('utc'::text, now())
WHERE entitlement.profile_id = 'f6cccd37-d24b-4959-8222-0f8dc9abf8a3'::UUID
  AND private.profile_effective_subscription_plan(entitlement.profile_id) <> 'free';
