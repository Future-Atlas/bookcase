import { createClient } from 'npm:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

type JsonRecord = Record<string, unknown>

function json(body: JsonRecord, status = 200) {
  return Response.json(body, { status, headers: corsHeaders })
}

function cleanText(value: unknown, maxLength: number) {
  return typeof value === 'string' ? value.trim().slice(0, maxLength) : ''
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (request.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

  const authorization = request.headers.get('Authorization')
  const token = authorization?.replace(/^Bearer\s+/i, '') ?? ''
  if (!token) return json({ error: 'Unauthorized' }, 401)

  const supabaseUrl = Deno.env.get('SUPABASE_URL') ?? ''
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY') ?? ''
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return json({ error: 'Server configuration is incomplete' }, 500)
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  })
  const userClient = createClient(supabaseUrl, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false },
    global: { headers: { Authorization: `Bearer ${token}` } },
  })
  const { data: userData, error: userError } = await admin.auth.getUser(token)
  const caller = userData.user
  if (userError || !caller) return json({ error: 'Unauthorized' }, 401)

  const body = await request.json().catch(() => null) as JsonRecord | null
  const mode = cleanText(body?.mode, 40)

  if (mode === 'status') {
    const purpose = normalizePurpose(body?.purpose)
    if (!purpose) return json({ error: 'Invalid purpose' }, 400)
    if (purpose === 'login') {
      return json({ failed_attempts: 0, remaining_attempts: 5, locked: false })
    }
    const state = await readState(admin, caller.id, purpose)
    return state ? json(state) : json({ error: 'Unable to read TOTP status' }, 500)
  }

  if (mode === 'verify') {
    const purpose = normalizePurpose(body?.purpose)
    const factorId = cleanText(body?.factorId, 80)
    const code = cleanText(body?.code, 10)
    if (!purpose || !isUuid(factorId) || !/^\d{6}$/.test(code)) {
      return json({ error: 'Invalid verification request' }, 400)
    }

    const state = await readState(admin, caller.id, purpose)
    if (!state) return json({ error: 'Unable to read TOTP status' }, 500)
    if (purpose === 'privacy_recovery' && state.locked === true) {
      return json({ error: 'TOTP verification is locked', ...state }, 429)
    }

    if (purpose === 'privacy_recovery') {
      const { data: oauthValid, error: oauthError } = await userClient.rpc(
        'validate_privacy_password_recovery_oauth',
      )
      if (oauthError || oauthValid !== true) {
        return json({ error: 'Fresh OAuth verification is required' }, 403)
      }
    }

    const { data: factorsData, error: factorsError } =
      await admin.auth.admin.mfa.listFactors({ userId: caller.id })
    const factors = factorsData?.factors ?? []
    const factor = factors.find((item) =>
      item.id === factorId && item.factor_type === 'totp' && item.status === 'verified'
    )
    if (factorsError || !factor) return json({ error: 'TOTP factor not found' }, 404)

    const challenge = await authRequest(
      `${supabaseUrl}/auth/v1/factors/${factorId}/challenge`,
      token,
      anonKey,
      {},
    )
    if (!challenge.ok || typeof challenge.data.id !== 'string') {
      return json({ error: 'Unable to start TOTP verification' }, 502)
    }
    const verification = await authRequest(
      `${supabaseUrl}/auth/v1/factors/${factorId}/verify`,
      token,
      anonKey,
      { challenge_id: challenge.data.id, code },
    )
    if (!verification.ok) {
      if (purpose === 'login') {
        return json({
          error: 'Invalid TOTP code',
          failed_attempts: 0,
          remaining_attempts: 5,
          locked: false,
        }, 400)
      }
      const failed = await admin.rpc('record_totp_verification_failure', {
        p_target_profile: caller.id,
        p_purpose: purpose,
      })
      const failedState = asRecord(failed.data) ?? state
      const status = failedState.locked === true ? 429 : 400
      return json({ error: 'Invalid TOTP code', ...failedState }, status)
    }

    const { error: successError } = await admin.rpc(
      'record_totp_verification_success',
      { p_target_profile: caller.id, p_purpose: purpose },
    )
    if (successError) return json({ error: 'Unable to finalize TOTP verification' }, 500)

    return json({
      accessToken: verification.data.access_token,
      refreshToken: verification.data.refresh_token,
      remainingAttempts: 5,
    })
  }

  if (mode === 'self_reenroll') {
    const password = cleanText(body?.password, 100)
    if (!password) return json({ error: 'Privacy password is required' }, 400)
    const { data: allowed, error: authorizationError } = await userClient.rpc(
      'authorize_self_totp_reenrollment',
      { p_password: password },
    )
    if (authorizationError || allowed !== true) {
      return json({ error: 'Privacy password verification failed' }, 403)
    }
    const sessionId = readSessionId(token)
    const requestReference = `self-${crypto.randomUUID()}`
    const auditBase = {
      actor_profile_id: caller.id,
      target_profile_id: caller.id,
      action: 'self_reenroll',
      reason: '本人が個人情報変更用パスワードで認証アプリを再登録',
      request_reference: requestReference,
      session_id: sessionId,
    }
    const { error: authorizationAuditError } = await admin
      .from('totp_recovery_audit')
      .insert({ ...auditBase, outcome: 'authorized' })
    if (authorizationAuditError) {
      return json({ error: 'Unable to record recovery audit' }, 500)
    }
    const deletionError = await deleteTotpFactors(admin, caller.id)
    const { error: completionAuditError } = await admin
      .from('totp_recovery_audit')
      .insert({ ...auditBase, outcome: deletionError ? 'failed' : 'completed' })
    if (completionAuditError) return json({ error: 'Unable to record recovery audit' }, 500)
    if (deletionError) return json({ error: deletionError }, 500)
    return json({ reset: true })
  }

  if (mode === 'admin_reset') {
    const targetIdentifier = cleanText(body?.targetIdentifier, 100)
    const adminPassword = cleanText(body?.adminPassword, 100)
    const reason = cleanText(body?.reason, 500)
    const requestReference = cleanText(body?.requestReference, 100)
    if (!targetIdentifier || !adminPassword || reason.length < 10 || !requestReference) {
      return json({ error: 'Target, password, reason and reference are required' }, 400)
    }
    const { data: targetProfile, error: authorizationError } = await userClient.rpc(
      'authorize_admin_totp_reset',
      {
        p_target_identifier: targetIdentifier,
        p_admin_password: adminPassword,
        p_reason: reason,
        p_request_reference: requestReference,
      },
    )
    if (authorizationError || typeof targetProfile !== 'string') {
      return json({ error: 'Administrator authorization failed' }, 403)
    }
    const auditBase = {
      actor_profile_id: caller.id,
      target_profile_id: targetProfile,
      action: 'admin_reset',
      reason,
      request_reference: requestReference,
      session_id: readSessionId(token),
    }
    const { error: authorizationAuditError } = await admin
      .from('totp_recovery_audit')
      .insert({ ...auditBase, outcome: 'authorized' })
    if (authorizationAuditError) {
      return json({ error: 'Unable to record recovery audit' }, 500)
    }
    const deletionError = await deleteTotpFactors(admin, targetProfile)
    const { error: completionAuditError } = await admin
      .from('totp_recovery_audit')
      .insert({ ...auditBase, outcome: deletionError ? 'failed' : 'completed' })
    if (completionAuditError) return json({ error: 'Unable to record recovery audit' }, 500)
    if (deletionError) return json({ error: deletionError }, 500)
    return json({ reset: true, targetProfileId: targetProfile })
  }

  return json({ error: 'Unsupported mode' }, 400)
})

function normalizePurpose(value: unknown) {
  return value === 'login' || value === 'privacy_recovery' ? value : null
}

function isUuid(value: string) {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)
}

function asRecord(value: unknown): JsonRecord | null {
  return value && typeof value === 'object' && !Array.isArray(value)
    ? value as JsonRecord
    : null
}

async function readState(
  admin: ReturnType<typeof createClient>,
  profileId: string,
  purpose: 'login' | 'privacy_recovery',
) {
  const { data, error } = await admin.rpc('get_totp_verification_state', {
    p_target_profile: profileId,
    p_purpose: purpose,
  })
  return error ? null : asRecord(data)
}

async function authRequest(
  url: string,
  token: string,
  apiKey: string,
  body: JsonRecord,
) {
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      apikey: apiKey,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  })
  const data = await response.json().catch(() => ({})) as JsonRecord
  return { ok: response.ok, data }
}

async function deleteTotpFactors(
  admin: ReturnType<typeof createClient>,
  userId: string,
) {
  const { data, error } = await admin.auth.admin.mfa.listFactors({ userId })
  if (error) return 'Unable to list TOTP factors'
  const factors = (data?.factors ?? []).filter((factor) => factor.factor_type === 'totp')
  for (const factor of factors) {
    const { error: deletionError } = await admin.auth.admin.mfa.deleteFactor({
      userId,
      factorId: factor.id,
    })
    if (deletionError) return 'Unable to reset TOTP factors'
  }
  return null
}

function readSessionId(token: string) {
  try {
    const payload = JSON.parse(
      atob(token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')),
    ) as JsonRecord
    const sessionId = payload.session_id
    return typeof sessionId === 'string' && isUuid(sessionId) ? sessionId : null
  } catch {
    return null
  }
}
