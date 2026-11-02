import { createClient } from 'npm:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function response(body: Record<string, unknown>, status = 200) {
  return Response.json(body, { status, headers: corsHeaders })
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (request.method !== 'POST') return response({ error: 'Method not allowed' }, 405)

  const body = await request.json().catch(() => null)
  const targetProfileId = body?.targetProfileId?.toString() ?? ''
  const reason = body?.reason?.toString().trim() ?? ''
  if (body?.confirmation !== 'DELETE' || !targetProfileId || reason.length > 500) {
    return response({ error: 'Invalid deletion request' }, 400)
  }

  const token = request.headers.get('Authorization')?.replace(/^Bearer\s+/i, '')
  const supabaseUrl = Deno.env.get('SUPABASE_URL')
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
  if (!token || !supabaseUrl || !serviceRoleKey) {
    return response({ error: 'Unauthorized or incomplete configuration' }, 401)
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  })
  const { data: callerData, error: callerError } = await admin.auth.getUser(token)
  const caller = callerData.user
  if (callerError || !caller) return response({ error: 'Unauthorized' }, 401)
  if (caller.id === targetProfileId) {
    return response({ error: 'Administrators cannot delete themselves' }, 400)
  }

  const { data: adminRow, error: adminError } = await admin
    .from('app_admins')
    .select('profile_id')
    .eq('profile_id', caller.id)
    .maybeSingle()
  if (adminError || !adminRow) return response({ error: 'Forbidden' }, 403)

  // Irreversible account deletion needs a recently MFA-verified JWT.
  const { data: assurance, error: assuranceError } =
    await admin.auth.mfa.getAuthenticatorAssuranceLevel(token)
  if (assuranceError || assurance?.currentLevel !== 'aal2') {
    return response({ error: 'admin_mfa_required' }, 403)
  }

  const { data: denialId, error: recordError } = await admin.rpc(
    'record_admin_account_deletion',
    {
      target_profile: targetProfileId,
      deleting_admin: caller.id,
      deletion_reason: reason || null,
    },
  )
  if (recordError || !denialId) {
    return response({ error: recordError?.message ?? 'Unable to record deletion' }, 500)
  }

  const { data: auditId, error: auditError } = await admin.rpc(
    'prepare_deleted_account_record',
    {
      target_profile: targetProfileId,
      deletion_kind: 'admin',
      deleting_admin: caller.id,
      deletion_notes: reason || 'Administrator account deletion',
    },
  )
  if (auditError || !auditId) {
    await admin.rpc('cancel_admin_account_deletion_record', {
      denial_record: denialId,
      deleting_admin: caller.id,
    })
    return response(
      { error: auditError?.message ?? 'Unable to record account deletion' },
      500,
    )
  }

  const { data: openReports } = await admin
    .from('moderation_reports')
    .select('id')
    .eq('reported_profile_id', targetProfileId)
    .eq('status', 'open')

  const { error: deleteError } = await admin.auth.admin.deleteUser(targetProfileId)
  if (deleteError) {
    await admin.rpc('cancel_admin_account_deletion_record', {
      denial_record: denialId,
      deleting_admin: caller.id,
    })
    await admin.rpc('finalize_deleted_account_record', {
      audit_record: auditId,
      succeeded: false,
      failure_message: deleteError.message,
    })
    return response({ error: deleteError.message }, 500)
  }

  await admin.rpc('finalize_deleted_account_record', {
    audit_record: auditId,
    succeeded: true,
    failure_message: null,
  })

  const reportIds = (openReports ?? []).map((report) => report.id)
  if (reportIds.length > 0) {
    await admin
      .from('moderation_reports')
      .update({
        status: 'resolved',
        resolution: 'account_deleted',
        resolved_by: caller.id,
        resolved_at: new Date().toISOString(),
      })
      .in('id', reportIds)
  }

  const { error: profileDeleteError } = await admin
    .from('profiles')
    .delete()
    .eq('id', targetProfileId)
  if (profileDeleteError) {
    return response({ error: profileDeleteError.message }, 500)
  }

  return response({ deleted: true })
})
