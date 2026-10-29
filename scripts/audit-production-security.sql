\set ON_ERROR_STOP on

-- This script is deliberately read-only and must never select personal-data
-- values. It inspects only catalog metadata, role privileges, and migration
-- identifiers.
begin read only;

do $$
declare
  missing_table text;
begin
  select required.name
  into missing_table
  from (values
    ('account_details'),
    ('account_suspensions'),
    ('adult_content_terms'),
    ('app_admins'),
    ('auth_session_ip_guards'),
    ('blocks'),
    ('collections'),
    ('legal_consents'),
    ('contact_requests'),
    ('favorites'),
    ('featured_books'),
    ('follows'),
    ('moderation_reports'),
    ('notifications'),
    ('post_reactions'),
    ('post_replies'),
    ('post_want_to_reads'),
    ('posts'),
    ('privacy_password_credentials'),
    ('privacy_password_recovery_requests'),
    ('profiles'),
    ('session_ip_guards'),
    ('want_to_read_books')
  ) as required(name)
  left join pg_class as relation
    on relation.relname = required.name
   and relation.relnamespace = 'public'::regnamespace
   and relation.relkind = 'r'
  where relation.oid is null
  limit 1;

  if missing_table is not null then
    raise exception 'SECURITY_AUDIT_MISSING_TABLE:%', missing_table;
  end if;
end;
$$;

do $$
declare
  unprotected_table text;
begin
  select relation.relname
  into unprotected_table
  from pg_class as relation
  where relation.relnamespace = 'public'::regnamespace
    and relation.relname = any (array[
      'account_details',
      'account_suspensions',
      'adult_content_terms',
      'app_admins',
      'auth_session_ip_guards',
      'blocks',
      'collections',
      'legal_consents',
      'contact_requests',
      'favorites',
      'featured_books',
      'follows',
      'moderation_reports',
      'notifications',
      'post_reactions',
      'post_replies',
      'post_want_to_reads',
      'posts',
      'privacy_password_credentials',
      'privacy_password_recovery_requests',
      'profiles',
      'session_ip_guards',
      'want_to_read_books'
    ])
    and not relation.relrowsecurity
  limit 1;

  if unprotected_table is not null then
    raise exception 'SECURITY_AUDIT_RLS_DISABLED:%', unprotected_table;
  end if;
end;
$$;

do $$
begin
  if has_table_privilege('anon', 'public.account_details', 'SELECT') then
    raise exception 'SECURITY_AUDIT_ANON_ACCOUNT_DETAILS_READ';
  end if;
  if has_table_privilege('anon', 'public.legal_consents', 'SELECT') then
    raise exception 'SECURITY_AUDIT_ANON_LEGAL_CONSENT_READ';
  end if;
  if has_table_privilege('authenticated', 'public.contact_requests', 'SELECT') then
    raise exception 'SECURITY_AUDIT_CONTACT_MESSAGE_READ';
  end if;
  if has_table_privilege('authenticated', 'public.privacy_password_credentials', 'SELECT') then
    raise exception 'SECURITY_AUDIT_PASSWORD_HASH_READ';
  end if;
  if has_table_privilege('authenticated', 'public.privacy_password_recovery_requests', 'SELECT') then
    raise exception 'SECURITY_AUDIT_PASSWORD_RECOVERY_READ';
  end if;
end;
$$;

do $$
declare
  expected_policy text;
begin
  select required.table_name || ':' || required.policy_name
  into expected_policy
  from (values
    ('account_details', 'Users can read their own account details'),
    ('account_details', 'Users can insert their own account details'),
    ('account_details', 'Users can update their own account details'),
    ('legal_consents', 'Users can read their own legal consents'),
    ('legal_consents', 'Users can insert their own legal consents'),
    ('contact_requests', 'Anyone can submit a contact request')
  ) as required(table_name, policy_name)
  left join pg_policies as policy
    on policy.schemaname = 'public'
   and policy.tablename = required.table_name
   and policy.policyname = required.policy_name
  where policy.policyname is null
  limit 1;

  if expected_policy is not null then
    raise exception 'SECURITY_AUDIT_MISSING_POLICY:%', expected_policy;
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from supabase_migrations.schema_migrations
    where version = '20261029100000'
  ) then
    raise exception 'SECURITY_AUDIT_PENDING_HARDENING_MIGRATION';
  end if;
end;
$$;

rollback;

\echo 'Production security catalog audit passed (no personal-data rows were read).'
