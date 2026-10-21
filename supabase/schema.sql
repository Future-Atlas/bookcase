


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "auth";


ALTER SCHEMA "auth" OWNER TO "supabase_admin";


CREATE SCHEMA IF NOT EXISTS "graphql_public";


ALTER SCHEMA "graphql_public" OWNER TO "supabase_admin";


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE SCHEMA IF NOT EXISTS "storage";


ALTER SCHEMA "storage" OWNER TO "supabase_admin";


CREATE TYPE "auth"."aal_level" AS ENUM (
    'aal1',
    'aal2',
    'aal3'
);


ALTER TYPE "auth"."aal_level" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."code_challenge_method" AS ENUM (
    's256',
    'plain'
);


ALTER TYPE "auth"."code_challenge_method" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."factor_status" AS ENUM (
    'unverified',
    'verified'
);


ALTER TYPE "auth"."factor_status" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."factor_type" AS ENUM (
    'totp',
    'webauthn',
    'phone'
);


ALTER TYPE "auth"."factor_type" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."oauth_authorization_status" AS ENUM (
    'pending',
    'approved',
    'denied',
    'expired'
);


ALTER TYPE "auth"."oauth_authorization_status" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."oauth_client_type" AS ENUM (
    'public',
    'confidential'
);


ALTER TYPE "auth"."oauth_client_type" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."oauth_registration_type" AS ENUM (
    'dynamic',
    'manual'
);


ALTER TYPE "auth"."oauth_registration_type" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."oauth_response_type" AS ENUM (
    'code'
);


ALTER TYPE "auth"."oauth_response_type" OWNER TO "supabase_auth_admin";


CREATE TYPE "auth"."one_time_token_type" AS ENUM (
    'confirmation_token',
    'reauthentication_token',
    'recovery_token',
    'email_change_token_new',
    'email_change_token_current',
    'phone_change_token'
);


ALTER TYPE "auth"."one_time_token_type" OWNER TO "supabase_auth_admin";


CREATE TYPE "storage"."buckettype" AS ENUM (
    'STANDARD',
    'ANALYTICS',
    'VECTOR'
);


ALTER TYPE "storage"."buckettype" OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "auth"."email"() RETURNS "text"
    LANGUAGE "sql" STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.email', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email')
  )::text
$$;


ALTER FUNCTION "auth"."email"() OWNER TO "supabase_auth_admin";


COMMENT ON FUNCTION "auth"."email"() IS 'Deprecated. Use auth.jwt() -> ''email'' instead.';



CREATE OR REPLACE FUNCTION "auth"."jwt"() RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    AS $$
  select 
    coalesce(
        nullif(current_setting('request.jwt.claim', true), ''),
        nullif(current_setting('request.jwt.claims', true), '')
    )::jsonb
$$;


ALTER FUNCTION "auth"."jwt"() OWNER TO "supabase_auth_admin";


CREATE OR REPLACE FUNCTION "auth"."role"() RETURNS "text"
    LANGUAGE "sql" STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  )::text
$$;


ALTER FUNCTION "auth"."role"() OWNER TO "supabase_auth_admin";


COMMENT ON FUNCTION "auth"."role"() IS 'Deprecated. Use auth.jwt() -> ''role'' instead.';



CREATE OR REPLACE FUNCTION "auth"."uid"() RETURNS "uuid"
    LANGUAGE "sql" STABLE
    AS $$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$$;


ALTER FUNCTION "auth"."uid"() OWNER TO "supabase_auth_admin";


COMMENT ON FUNCTION "auth"."uid"() IS 'Deprecated. Use auth.jwt() -> ''sub'' instead.';



CREATE OR REPLACE FUNCTION "graphql_public"."graphql"("operationName" "text" DEFAULT NULL::"text", "query" "text" DEFAULT NULL::"text", "variables" "jsonb" DEFAULT NULL::"jsonb", "extensions" "jsonb" DEFAULT NULL::"jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql"
    AS $$
            DECLARE
                server_version float;
            BEGIN
                server_version = (SELECT (SPLIT_PART((select version()), ' ', 2))::float);

                IF server_version >= 14 THEN
                    RETURN jsonb_build_object(
                        'errors', jsonb_build_array(
                            jsonb_build_object(
                                'message', 'pg_graphql extension is not enabled.'
                            )
                        )
                    );
                ELSE
                    RETURN jsonb_build_object(
                        'errors', jsonb_build_array(
                            jsonb_build_object(
                                'message', 'pg_graphql is only available on projects running Postgres 14 onwards.'
                            )
                        )
                    );
                END IF;
            END;
        $$;


ALTER FUNCTION "graphql_public"."graphql"("operationName" "text", "query" "text", "variables" "jsonb", "extensions" "jsonb") OWNER TO "supabase_admin";


CREATE OR REPLACE FUNCTION "public"."admin_delete_reported_post"("target_report" bigint) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    target_post UUID;
BEGIN
    IF NOT public.is_current_user_admin() THEN
        RAISE EXCEPTION 'Administrator access required';
    END IF;

    SELECT post_id INTO target_post
    FROM public.moderation_reports
    WHERE id = target_report;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Report not found';
    END IF;

    UPDATE public.moderation_reports
    SET status = 'resolved',
        resolution = 'post_deleted',
        resolved_by = auth.uid(),
        resolved_at = timezone('utc'::text, now())
    WHERE status = 'open'
      AND (id = target_report OR post_id = target_post);

    IF target_post IS NOT NULL THEN
        DELETE FROM public.posts WHERE id = target_post;
    END IF;
END;
$$;


ALTER FUNCTION "public"."admin_delete_reported_post"("target_report" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_resolve_report"("target_report" bigint, "resolution_note" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    IF NOT public.is_current_user_admin() THEN
        RAISE EXCEPTION 'Administrator access required';
    END IF;
    UPDATE public.moderation_reports
    SET status = 'resolved',
        resolution = NULLIF(btrim(resolution_note), ''),
        resolved_by = auth.uid(),
        resolved_at = timezone('utc'::text, now())
    WHERE id = target_report;
END;
$$;


ALTER FUNCTION "public"."admin_resolve_report"("target_report" bigint, "resolution_note" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_set_account_suspension"("target_profile" "uuid", "suspend" boolean, "reason" "text" DEFAULT NULL::"text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    IF NOT public.is_current_user_admin() THEN
        RAISE EXCEPTION 'Administrator access required';
    END IF;
    IF target_profile = auth.uid() THEN
        RAISE EXCEPTION 'Cannot suspend your own administrator account';
    END IF;
    IF suspend AND EXISTS (
        SELECT 1 FROM public.app_admins WHERE profile_id = target_profile
    ) THEN
        RAISE EXCEPTION 'Cannot suspend an administrator account';
    END IF;

    UPDATE public.profiles
    SET is_suspended = suspend
    WHERE id = target_profile;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Profile not found';
    END IF;

    IF suspend THEN
        INSERT INTO public.account_suspensions (
            profile_id, reason, suspended_at, suspended_by
        ) VALUES (
            target_profile,
            NULLIF(btrim(reason), ''),
            timezone('utc'::text, now()),
            auth.uid()
        )
        ON CONFLICT (profile_id) DO UPDATE
        SET reason = EXCLUDED.reason,
            suspended_at = EXCLUDED.suspended_at,
            suspended_by = EXCLUDED.suspended_by;
        DELETE FROM public.follows
        WHERE follower_id = target_profile OR following_id = target_profile;
        DELETE FROM public.post_reactions WHERE profile_id = target_profile;
    ELSE
        DELETE FROM public.account_suspensions WHERE profile_id = target_profile;
    END IF;
END;
$$;


ALTER FUNCTION "public"."admin_set_account_suspension"("target_profile" "uuid", "suspend" boolean, "reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."begin_privacy_password_recovery"() RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    current_provider TEXT := auth.jwt() -> 'app_metadata' ->> 'provider';
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;
    IF current_provider NOT IN ('google', 'twitter', 'x', 'facebook', 'apple', 'discord') THEN
        RAISE EXCEPTION 'Unsupported recovery provider' USING ERRCODE = '22023';
    END IF;
    INSERT INTO public.privacy_password_recovery_requests (
        profile_id, provider, requested_at
    ) VALUES (
        auth.uid(), current_provider, timezone('utc'::text, now())
    )
    ON CONFLICT (profile_id) DO UPDATE
    SET provider = EXCLUDED.provider,
        requested_at = EXCLUDED.requested_at;
END;
$$;


ALTER FUNCTION "public"."begin_privacy_password_recovery"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."block_profile"("target_profile" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    blocker UUID := auth.uid();
BEGIN
    IF NOT public.is_profile_active(blocker) THEN
        RAISE EXCEPTION 'Account is not active';
    END IF;
    IF blocker = target_profile THEN
        RAISE EXCEPTION 'Invalid block target';
    END IF;
    INSERT INTO public.blocks (blocker_id, blocked_id)
    VALUES (blocker, target_profile)
    ON CONFLICT DO NOTHING;
    DELETE FROM public.follows
    WHERE (follower_id = blocker AND following_id = target_profile)
       OR (follower_id = target_profile AND following_id = blocker);
    DELETE FROM public.notifications
    WHERE (recipient_id = blocker AND actor_id = target_profile)
       OR (recipient_id = target_profile AND actor_id = blocker);
END;
$$;


ALTER FUNCTION "public"."block_profile"("target_profile" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."can_view_profile_content"("owner_profile" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles AS owner
        WHERE owner.id = owner_profile
          AND owner.is_suspended = false
          AND public.is_profile_active(auth.uid())
          AND (
              auth.uid() = owner.id
              OR (
                  NOT public.is_blocked_between(auth.uid(), owner.id)
                  AND (
                      owner.is_private = false
                      OR EXISTS (
                          SELECT 1
                          FROM public.follows
                          WHERE follower_id = auth.uid()
                            AND following_id = owner.id
                            AND status = 'accepted'
                      )
                  )
              )
          )
    );
$$;


ALTER FUNCTION "public"."can_view_profile_content"("owner_profile" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cancel_admin_account_deletion_record"("denial_record" "uuid", "deleting_admin" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'private'
    AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM public.app_admins WHERE profile_id = deleting_admin
    ) THEN
        RAISE EXCEPTION 'Administrator access required' USING ERRCODE = '42501';
    END IF;
    DELETE FROM private.registration_denials
    WHERE id = denial_record AND deleted_by = deleting_admin;
END;
$$;


ALTER FUNCTION "public"."cancel_admin_account_deletion_record"("denial_record" "uuid", "deleting_admin" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cancel_self_account_deletion"("target_profile" "uuid") RETURNS "void"
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'private'
    AS $$
    DELETE FROM private.account_deletion_exemptions
    WHERE profile_id = target_profile;
$$;


ALTER FUNCTION "public"."cancel_self_account_deletion"("target_profile" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."change_privacy_password"("p_current_password" "text", "p_new_password" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
BEGIN
    IF NOT public.is_valid_privacy_password(p_new_password) THEN
        RAISE EXCEPTION 'Invalid privacy password' USING ERRCODE = '23514';
    END IF;
    IF NOT public.verify_privacy_password(p_current_password) THEN
        RETURN false;
    END IF;
    UPDATE public.privacy_password_credentials
    SET password_hash = extensions.crypt(p_new_password, extensions.gen_salt('bf', 12)),
        failed_attempts = 0,
        locked_until = NULL,
        updated_at = timezone('utc'::text, now())
    WHERE profile_id = auth.uid();
    RETURN true;
END;
$$;


ALTER FUNCTION "public"."change_privacy_password"("p_current_password" "text", "p_new_password" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."classify_post_age_restriction"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    NEW.is_age_restricted :=
        COALESCE(NEW.is_age_restricted, false)
        OR public.matches_adult_content_terms(
            NEW.book_title,
            NEW.book_author,
            NEW.book_publisher,
            NEW.book_description,
            NEW.comment
        );
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."classify_post_age_restriction"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."complete_registration"("p_full_name" "text", "p_birth_date" "date", "p_phone_number" "text", "p_username" "text", "p_user_id" "text", "p_privacy_password" "text", "p_guardian_consent" boolean, "p_terms_version" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'private', 'extensions'
    AS $_$
DECLARE
    current_profile_id UUID := auth.uid();
    normalized_user_id TEXT := lower(btrim(p_user_id));
    normalized_phone TEXT := regexp_replace(p_phone_number, '[^0-9+]', '', 'g');
    is_minor BOOLEAN := p_birth_date > (CURRENT_DATE - INTERVAL '18 years')::date;
BEGIN
    IF current_profile_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;
    IF char_length(btrim(p_full_name)) NOT BETWEEN 1 AND 100
       OR p_birth_date < DATE '1900-01-01'
       OR p_birth_date > CURRENT_DATE
       OR normalized_phone !~ '^\+?[0-9]{7,15}$'
       OR char_length(btrim(p_username)) NOT BETWEEN 1 AND 30
       OR normalized_user_id !~ '^[a-z0-9_]{3,20}$'
       OR NOT public.is_valid_privacy_password(p_privacy_password)
       OR char_length(btrim(p_terms_version)) NOT BETWEEN 1 AND 50 THEN
        RAISE EXCEPTION 'Invalid registration data' USING ERRCODE = '23514';
    END IF;
    IF is_minor AND NOT COALESCE(p_guardian_consent, false) THEN
        RAISE EXCEPTION 'GUARDIAN_CONSENT_REQUIRED' USING ERRCODE = '23514';
    END IF;
    IF normalized_user_id IN (
        'admin', 'administrator', 'support', 'sharemarium', 'system', 'official'
    ) THEN
        RAISE EXCEPTION 'Reserved user ID' USING ERRCODE = '23514';
    END IF;
    IF private.registration_denial_matches(
        p_full_name, p_birth_date, normalized_phone
    ) THEN
        RAISE EXCEPTION 'REGISTRATION_DENIED' USING ERRCODE = 'P0001';
    END IF;

    UPDATE public.profiles
    SET username = btrim(p_username), user_id = normalized_user_id
    WHERE id = current_profile_id;

    INSERT INTO public.account_details (
        profile_id,
        full_name,
        birth_date,
        phone_number,
        guardian_consent_declared_at,
        guardian_consent_terms_version
    ) VALUES (
        current_profile_id,
        btrim(p_full_name),
        p_birth_date,
        normalized_phone,
        CASE WHEN is_minor THEN timezone('utc'::text, now()) ELSE NULL END,
        CASE WHEN is_minor THEN btrim(p_terms_version) ELSE NULL END
    )
    ON CONFLICT (profile_id) DO UPDATE
    SET full_name = EXCLUDED.full_name,
        birth_date = EXCLUDED.birth_date,
        phone_number = EXCLUDED.phone_number,
        phone_verified_at = CASE
            WHEN public.account_details.phone_number = EXCLUDED.phone_number
                THEN public.account_details.phone_verified_at
            ELSE NULL
        END,
        guardian_consent_declared_at = EXCLUDED.guardian_consent_declared_at,
        guardian_consent_terms_version = EXCLUDED.guardian_consent_terms_version,
        updated_at = timezone('utc'::text, now());

    INSERT INTO public.privacy_password_credentials (profile_id, password_hash)
    VALUES (
        current_profile_id,
        extensions.crypt(p_privacy_password, extensions.gen_salt('bf', 12))
    )
    ON CONFLICT (profile_id) DO NOTHING;
END;
$_$;


ALTER FUNCTION "public"."complete_registration"("p_full_name" "text", "p_birth_date" "date", "p_phone_number" "text", "p_username" "text", "p_user_id" "text", "p_privacy_password" "text", "p_guardian_consent" boolean, "p_terms_version" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_follow_notification"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    INSERT INTO public.notifications (recipient_id, actor_id, type)
    VALUES (
        NEW.following_id,
        NEW.follower_id,
        CASE WHEN NEW.status = 'pending' THEN 'follow_request' ELSE 'follow' END
    );
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."create_follow_notification"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."create_reaction_notification"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    post_owner UUID;
BEGIN
    SELECT profile_id INTO post_owner
    FROM public.posts
    WHERE id = NEW.post_id;

    IF post_owner IS NOT NULL AND post_owner <> NEW.profile_id THEN
        INSERT INTO public.notifications (recipient_id, actor_id, type, post_id)
        VALUES (post_owner, NEW.profile_id, 'reaction', NEW.post_id);
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."create_reaction_notification"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."current_user_can_view_age_restricted"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    SELECT public.current_user_is_adult()
        OR EXISTS (
            SELECT 1
            FROM public.app_admins
            WHERE profile_id = auth.uid()
        );
$$;


ALTER FUNCTION "public"."current_user_can_view_age_restricted"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."current_user_is_adult"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.account_details
        WHERE profile_id = auth.uid()
          AND birth_date <= (CURRENT_DATE - INTERVAL '18 years')::date
    );
$$;


ALTER FUNCTION "public"."current_user_is_adult"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."declare_guardian_consent"("p_terms_version" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    current_profile_id UUID := auth.uid();
    registered_birth_date DATE;
BEGIN
    IF current_profile_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;
    IF char_length(btrim(p_terms_version)) NOT BETWEEN 1 AND 50 THEN
        RAISE EXCEPTION 'Invalid terms version' USING ERRCODE = '23514';
    END IF;

    SELECT birth_date INTO registered_birth_date
    FROM public.account_details
    WHERE profile_id = current_profile_id;

    IF registered_birth_date IS NULL THEN
        RAISE EXCEPTION 'Registration details required' USING ERRCODE = '23514';
    END IF;
    IF registered_birth_date <= (CURRENT_DATE - INTERVAL '18 years')::date THEN
        RETURN;
    END IF;

    UPDATE public.account_details
    SET guardian_consent_declared_at = timezone('utc'::text, now()),
        guardian_consent_terms_version = btrim(p_terms_version),
        updated_at = timezone('utc'::text, now())
    WHERE profile_id = current_profile_id;
END;
$$;


ALTER FUNCTION "public"."declare_guardian_consent"("p_terms_version" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."enforce_favorites_limit"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
BEGIN
    PERFORM pg_advisory_xact_lock(hashtext(NEW.profile_id::text)::bigint);

    IF NOT EXISTS (
        SELECT 1
        FROM public.posts
        WHERE profile_id = NEW.profile_id
          AND book_id = NEW.book_id
    ) THEN
        RAISE EXCEPTION 'favorite_requires_post'
            USING ERRCODE = 'P0001';
    END IF;

    IF (
        SELECT count(*)
        FROM public.favorites
        WHERE profile_id = NEW.profile_id
    ) >= 12 THEN
        RAISE EXCEPTION 'favorite_limit_reached'
            USING ERRCODE = 'P0001';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."enforce_favorites_limit"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."enforce_profile_user_id_immutability"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
BEGIN
    IF NEW.user_id IS DISTINCT FROM OLD.user_id
       AND EXISTS (
           SELECT 1
           FROM public.account_details AS details
           WHERE details.profile_id = OLD.id
       )
       AND COALESCE(auth.role(), '') <> 'service_role' THEN
        RAISE EXCEPTION 'USER_ID_IMMUTABLE' USING ERRCODE = '23514';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."enforce_profile_user_id_immutability"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."get_profile_follow_list"("target_profile" "uuid", "list_type" "text") RETURNS TABLE("id" "uuid", "username" "text", "user_id" "text", "avatar_url" "text", "bio" "text", "followers_count" integer, "following_count" integer, "read_count" integer, "is_private" boolean, "followed_at" timestamp with time zone)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    viewer_id UUID := auth.uid();
    target_is_private BOOLEAN;
BEGIN
    IF viewer_id IS NULL OR list_type NOT IN ('followers', 'following') THEN
        RETURN;
    END IF;

    SELECT profiles.is_private
    INTO target_is_private
    FROM public.profiles
    WHERE profiles.id = target_profile
      AND profiles.is_suspended = false;

    IF NOT FOUND
       OR public.is_blocked_between(viewer_id, target_profile)
       OR (viewer_id <> target_profile AND target_is_private) THEN
        RETURN;
    END IF;

    IF list_type = 'followers' THEN
        RETURN QUERY
        SELECT p.id, p.username, p.user_id, p.avatar_url, p.bio,
               p.followers_count, p.following_count, p.read_count,
               p.is_private, COALESCE(f.responded_at, f.requested_at)
        FROM public.follows AS f
        JOIN public.profiles AS p ON p.id = f.follower_id
        WHERE f.following_id = target_profile
          AND f.status = 'accepted'
          AND p.is_suspended = false
          AND NOT public.is_blocked_between(viewer_id, p.id)
        ORDER BY COALESCE(f.responded_at, f.requested_at) DESC;
    ELSE
        RETURN QUERY
        SELECT p.id, p.username, p.user_id, p.avatar_url, p.bio,
               p.followers_count, p.following_count, p.read_count,
               p.is_private, COALESCE(f.responded_at, f.requested_at)
        FROM public.follows AS f
        JOIN public.profiles AS p ON p.id = f.following_id
        WHERE f.follower_id = target_profile
          AND f.status = 'accepted'
          AND p.is_suspended = false
          AND NOT public.is_blocked_between(viewer_id, p.id)
        ORDER BY COALESCE(f.responded_at, f.requested_at) DESC;
    END IF;
END;
$$;


ALTER FUNCTION "public"."get_profile_follow_list"("target_profile" "uuid", "list_type" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."has_privacy_password"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
    SELECT auth.uid() IS NOT NULL AND EXISTS (
        SELECT 1
        FROM public.privacy_password_credentials
        WHERE profile_id = auth.uid()
    );
$$;


ALTER FUNCTION "public"."has_privacy_password"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."initialize_privacy_password"("p_password" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;
    IF NOT public.is_valid_privacy_password(p_password) THEN
        RAISE EXCEPTION 'Invalid privacy password' USING ERRCODE = '23514';
    END IF;
    INSERT INTO public.privacy_password_credentials (profile_id, password_hash)
    VALUES (auth.uid(), extensions.crypt(p_password, extensions.gen_salt('bf', 12)));
END;
$$;


ALTER FUNCTION "public"."initialize_privacy_password"("p_password" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_blocked_between"("first_profile" "uuid", "second_profile" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    SELECT CASE
        WHEN first_profile IS NULL OR second_profile IS NULL THEN false
        ELSE EXISTS (
            SELECT 1
            FROM public.blocks
            WHERE (blocker_id = first_profile AND blocked_id = second_profile)
               OR (blocker_id = second_profile AND blocked_id = first_profile)
        )
    END;
$$;


ALTER FUNCTION "public"."is_blocked_between"("first_profile" "uuid", "second_profile" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_current_user_admin"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.app_admins WHERE profile_id = auth.uid()
    );
$$;


ALTER FUNCTION "public"."is_current_user_admin"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_profile_active"("profile" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    SELECT CASE
        WHEN profile IS NULL THEN true
        ELSE COALESCE((
            SELECT NOT is_suspended FROM public.profiles WHERE id = profile
        ), false)
    END;
$$;


ALTER FUNCTION "public"."is_profile_active"("profile" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_valid_privacy_password"("candidate" "text") RETURNS boolean
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO 'public'
    AS $$
    SELECT candidate IS NOT NULL
       AND char_length(candidate) BETWEEN 8 AND 20
       AND candidate ~ '[a-z]'
       AND candidate ~ '[A-Z]'
       AND candidate ~ '[0-9]';
$$;


ALTER FUNCTION "public"."is_valid_privacy_password"("candidate" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."matches_adult_content_terms"("book_title" "text", "book_author" "text", "book_publisher" "text", "book_description" "text", "post_comment" "text" DEFAULT ''::"text") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.adult_content_terms AS filter_term
        WHERE filter_term.is_active = true
          AND position(
              public.normalize_content_filter_text(filter_term.term)
              IN public.normalize_content_filter_text(
                  concat_ws(
                      ' ',
                      book_title,
                      book_author,
                      book_publisher,
                      book_description,
                      post_comment
                  )
              )
          ) > 0
    );
$$;


ALTER FUNCTION "public"."matches_adult_content_terms"("book_title" "text", "book_author" "text", "book_publisher" "text", "book_description" "text", "post_comment" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."normalize_content_filter_text"("source" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE PARALLEL SAFE
    SET "search_path" TO 'public'
    AS $$
    SELECT lower(
        regexp_replace(
            coalesce(source, ''),
            '[[:space:]　_\-‐‑‒–—―・･.／/]+',
            '',
            'g'
        )
    );
$$;


ALTER FUNCTION "public"."normalize_content_filter_text"("source" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prepare_self_account_deletion"("target_profile" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'private'
    AS $$
BEGIN
    IF target_profile IS NULL THEN
        RAISE EXCEPTION 'Invalid account deletion request' USING ERRCODE = '22023';
    END IF;
    DELETE FROM private.account_deletion_exemptions
    WHERE expires_at <= timezone('utc'::text, now());
    INSERT INTO private.account_deletion_exemptions (profile_id, expires_at)
    VALUES (
        target_profile,
        timezone('utc'::text, now()) + INTERVAL '5 minutes'
    )
    ON CONFLICT (profile_id) DO UPDATE
    SET expires_at = EXCLUDED.expires_at;
END;
$$;


ALTER FUNCTION "public"."prepare_self_account_deletion"("target_profile" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."prevent_duplicate_book_post"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
BEGIN
    PERFORM pg_advisory_xact_lock(
        hashtextextended(NEW.profile_id::text || ':' || NEW.book_id, 0)
    );

    IF EXISTS (
        SELECT 1
        FROM public.posts
        WHERE profile_id = NEW.profile_id
          AND book_id = NEW.book_id
    ) THEN
        RAISE EXCEPTION 'duplicate_book_post'
            USING ERRCODE = 'P0001';
    END IF;

    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."prevent_duplicate_book_post"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."protect_post_identity_on_update"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    SET "search_path" TO 'public'
    AS $$
BEGIN
    IF NEW.profile_id IS DISTINCT FROM OLD.profile_id
       OR NEW.book_id IS DISTINCT FROM OLD.book_id THEN
        RAISE EXCEPTION 'post_identity_cannot_be_changed'
            USING ERRCODE = 'P0001';
    END IF;

    NEW.created_at := OLD.created_at;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."protect_post_identity_on_update"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."record_admin_account_deletion"("target_profile" "uuid", "deleting_admin" "uuid", "deletion_reason" "text" DEFAULT NULL::"text") RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'private', 'auth', 'extensions'
    AS $$
DECLARE
    details RECORD;
    denial_id UUID;
BEGIN
    IF target_profile IS NULL OR deleting_admin IS NULL OR target_profile = deleting_admin THEN
        RAISE EXCEPTION 'Invalid account deletion request' USING ERRCODE = '22023';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.app_admins WHERE profile_id = deleting_admin
    ) THEN
        RAISE EXCEPTION 'Administrator access required' USING ERRCODE = '42501';
    END IF;

    SELECT account.full_name, account.birth_date, account.phone_number, users.email
    INTO details
    FROM public.account_details AS account
    JOIN auth.users AS users ON users.id = account.profile_id
    WHERE account.profile_id = target_profile;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Account details not found' USING ERRCODE = 'P0002';
    END IF;

    DELETE FROM private.registration_denials
    WHERE expires_at <= timezone('utc'::text, now());

    INSERT INTO private.registration_denials (
        name_birth_email_hash,
        name_birth_phone_hash,
        deleted_by,
        reason,
        expires_at
    ) VALUES (
        private.registration_denial_hash(
            'email', details.full_name, details.birth_date, details.email
        ),
        private.registration_denial_hash(
            'phone', details.full_name, details.birth_date, details.phone_number
        ),
        deleting_admin,
        NULLIF(btrim(deletion_reason), ''),
        timezone('utc'::text, now()) + INTERVAL '3 years'
    ) RETURNING id INTO denial_id;

    RETURN denial_id;
END;
$$;


ALTER FUNCTION "public"."record_admin_account_deletion"("target_profile" "uuid", "deleting_admin" "uuid", "deletion_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."remove_favorite_after_post_delete"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM public.posts
        WHERE profile_id = OLD.profile_id
          AND book_id = OLD.book_id
    ) THEN
        DELETE FROM public.favorites
        WHERE profile_id = OLD.profile_id
          AND book_id = OLD.book_id;
    END IF;
    RETURN OLD;
END;
$$;


ALTER FUNCTION "public"."remove_favorite_after_post_delete"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."request_follow"("target_profile" "uuid") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    requester UUID := auth.uid();
    target_is_private BOOLEAN;
    existing_status TEXT;
    next_status TEXT;
BEGIN
    IF requester IS NULL OR NOT public.is_profile_active(requester) THEN
        RAISE EXCEPTION 'Account is not active';
    END IF;
    IF requester = target_profile THEN
        RAISE EXCEPTION 'Cannot follow yourself';
    END IF;
    IF NOT public.is_profile_active(target_profile) THEN
        RAISE EXCEPTION 'Profile is not available';
    END IF;
    IF public.is_blocked_between(requester, target_profile) THEN
        RAISE EXCEPTION 'Follow is not available';
    END IF;

    SELECT is_private INTO target_is_private
    FROM public.profiles
    WHERE id = target_profile;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Profile not found';
    END IF;

    SELECT status INTO existing_status
    FROM public.follows
    WHERE follower_id = requester AND following_id = target_profile;
    IF existing_status IS NOT NULL THEN
        RETURN existing_status;
    END IF;

    next_status := CASE WHEN target_is_private THEN 'pending' ELSE 'accepted' END;
    INSERT INTO public.follows (follower_id, following_id, status, responded_at)
    VALUES (
        requester,
        target_profile,
        next_status,
        CASE WHEN next_status = 'accepted' THEN timezone('utc'::text, now()) ELSE NULL END
    );
    RETURN next_status;
END;
$$;


ALTER FUNCTION "public"."request_follow"("target_profile" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."reset_privacy_password_after_reauthentication"("p_new_password" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
DECLARE
    recovery public.privacy_password_recovery_requests%ROWTYPE;
    has_recent_oauth BOOLEAN;
BEGIN
    IF NOT public.is_valid_privacy_password(p_new_password) THEN
        RAISE EXCEPTION 'Invalid privacy password' USING ERRCODE = '23514';
    END IF;
    SELECT * INTO recovery
    FROM public.privacy_password_recovery_requests
    WHERE profile_id = auth.uid()
      AND requested_at >= timezone('utc'::text, now()) - interval '15 minutes';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Recovery request expired' USING ERRCODE = '42501';
    END IF;
    IF (auth.jwt() -> 'app_metadata' ->> 'provider') IS DISTINCT FROM recovery.provider THEN
        RAISE EXCEPTION 'Recovery provider mismatch' USING ERRCODE = '42501';
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM jsonb_array_elements(COALESCE(auth.jwt() -> 'amr', '[]'::jsonb)) AS entry
        WHERE entry ->> 'method' = 'oauth'
          AND to_timestamp((entry ->> 'timestamp')::double precision)
              >= recovery.requested_at - interval '5 seconds'
    ) INTO has_recent_oauth;
    IF NOT has_recent_oauth THEN
        RAISE EXCEPTION 'Fresh OAuth authentication required' USING ERRCODE = '42501';
    END IF;

    UPDATE public.privacy_password_credentials
    SET password_hash = extensions.crypt(p_new_password, extensions.gen_salt('bf', 12)),
        failed_attempts = 0,
        locked_until = NULL,
        updated_at = timezone('utc'::text, now())
    WHERE profile_id = auth.uid();
    DELETE FROM public.privacy_password_recovery_requests
    WHERE profile_id = auth.uid();
END;
$$;


ALTER FUNCTION "public"."reset_privacy_password_after_reauthentication"("p_new_password" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."respond_follow_request"("requester_profile" "uuid", "approve" boolean) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    IF NOT public.is_profile_active(auth.uid()) THEN
        RAISE EXCEPTION 'Account is not active';
    END IF;
    IF approve AND NOT public.is_profile_active(requester_profile) THEN
        RAISE EXCEPTION 'Profile is not available';
    END IF;
    IF approve THEN
        UPDATE public.follows
        SET status = 'accepted', responded_at = timezone('utc'::text, now())
        WHERE follower_id = requester_profile
          AND following_id = auth.uid()
          AND status = 'pending';
    ELSE
        DELETE FROM public.follows
        WHERE follower_id = requester_profile
          AND following_id = auth.uid()
          AND status = 'pending';
    END IF;
    UPDATE public.notifications
    SET read_at = COALESCE(read_at, timezone('utc'::text, now()))
    WHERE recipient_id = auth.uid()
      AND actor_id = requester_profile
      AND type = 'follow_request';
END;
$$;


ALTER FUNCTION "public"."respond_follow_request"("requester_profile" "uuid", "approve" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."search_profiles_by_public_identity"("search_query" "text") RETURNS TABLE("id" "uuid", "username" "text", "user_id" "text", "avatar_url" "text", "bio" "text", "followers_count" integer, "following_count" integer, "read_count" integer, "is_private" boolean)
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
    viewer_id UUID := auth.uid();
    normalized_query TEXT := lower(regexp_replace(btrim(search_query), '^@', ''));
BEGIN
    IF viewer_id IS NULL
       OR char_length(normalized_query) NOT BETWEEN 1 AND 50 THEN
        RETURN;
    END IF;

    RETURN QUERY
    SELECT p.id, p.username, p.user_id, p.avatar_url, p.bio,
           p.followers_count, p.following_count, p.read_count, p.is_private
    FROM public.profiles AS p
    WHERE p.is_suspended = false
      AND EXISTS (
          SELECT 1
          FROM auth.users AS auth_user
          WHERE auth_user.id = p.id
      )
      AND EXISTS (
          SELECT 1
          FROM public.account_details AS details
          WHERE details.profile_id = p.id
      )
      AND NOT public.is_blocked_between(viewer_id, p.id)
      AND (
          position(normalized_query IN lower(p.username)) > 0
          OR position(normalized_query IN lower(p.user_id)) > 0
      )
    ORDER BY
      CASE
        WHEN lower(p.user_id) = normalized_query THEN 0
        WHEN lower(p.username) = normalized_query THEN 1
        WHEN lower(p.user_id) LIKE normalized_query || '%' THEN 2
        WHEN lower(p.username) LIKE normalized_query || '%' THEN 3
        ELSE 4
      END,
      lower(p.username),
      p.id
    LIMIT 50;
END;
$$;


ALTER FUNCTION "public"."search_profiles_by_public_identity"("search_query" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."submit_post_report"("target_post" "uuid", "report_category" "text", "report_details" "text" DEFAULT NULL::"text") RETURNS bigint
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    reporter UUID := auth.uid();
    target_row public.posts%ROWTYPE;
    existing_id BIGINT;
    created_id BIGINT;
BEGIN
    IF reporter IS NULL OR NOT public.is_profile_active(reporter) THEN
        RAISE EXCEPTION 'Account is not active';
    END IF;
    IF report_category NOT IN ('spam', 'harassment', 'bullying', 'offensive', 'other') THEN
        RAISE EXCEPTION 'Invalid report category';
    END IF;
    IF report_details IS NOT NULL AND char_length(report_details) > 1000 THEN
        RAISE EXCEPTION 'Report details are too long';
    END IF;

    SELECT * INTO target_row FROM public.posts WHERE id = target_post;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Post not found';
    END IF;
    IF target_row.profile_id = reporter THEN
        RAISE EXCEPTION 'Cannot report your own post';
    END IF;

    SELECT id INTO existing_id
    FROM public.moderation_reports
    WHERE reporter_id = reporter AND post_id = target_post AND status = 'open';
    IF existing_id IS NOT NULL THEN
        RETURN existing_id;
    END IF;

    INSERT INTO public.moderation_reports (
        reporter_id,
        reported_profile_id,
        post_id,
        category,
        details,
        post_snapshot
    ) VALUES (
        reporter,
        target_row.profile_id,
        target_row.id,
        report_category,
        NULLIF(btrim(report_details), ''),
        jsonb_build_object(
            'post_id', target_row.id,
            'profile_id', target_row.profile_id,
            'book_id', target_row.book_id,
            'rating', target_row.rating,
            'review', target_row.comment,
            'created_at', target_row.created_at
        )
    ) RETURNING id INTO created_id;

    RETURN created_id;
END;
$$;


ALTER FUNCTION "public"."submit_post_report"("target_post" "uuid", "report_category" "text", "report_details" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."sync_bookshelf_after_post_change"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
DECLARE
    affected_profile_id UUID;
    affected_book_id TEXT;
    latest_post_at TIMESTAMP WITH TIME ZONE;
BEGIN
    affected_profile_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.profile_id ELSE NEW.profile_id END;
    affected_book_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.book_id ELSE NEW.book_id END;

    SELECT max(created_at)
    INTO latest_post_at
    FROM public.posts
    WHERE profile_id = affected_profile_id
      AND book_id = affected_book_id;

    IF latest_post_at IS NULL THEN
        DELETE FROM public.collections
        WHERE profile_id = affected_profile_id
          AND book_id = affected_book_id;
    ELSE
        INSERT INTO public.collections (profile_id, book_id, status, created_at)
        VALUES (affected_profile_id, affected_book_id, 'read', latest_post_at)
        ON CONFLICT (profile_id, book_id) DO UPDATE
        SET status = 'read',
            created_at = EXCLUDED.created_at;
    END IF;

    UPDATE public.profiles
    SET read_count = (
        SELECT count(DISTINCT book_id)::INTEGER
        FROM public.posts
        WHERE profile_id = affected_profile_id
    )
    WHERE id = affected_profile_id;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."sync_bookshelf_after_post_change"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."sync_bookshelf_after_post_change"() IS 'Keeps completed-book shelves and read counts synchronized with posts.';



CREATE OR REPLACE FUNCTION "public"."sync_profile_to_auth_metadata"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
    public_display_name TEXT :=
        NEW.username || ' (@' || NEW.user_id || ')';
BEGIN
    UPDATE auth.users
    SET raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
        || jsonb_build_object(
            'display_name', public_display_name,
            'name', public_display_name,
            'full_name', public_display_name,
            'sharemarium_username', NEW.username,
            'sharemarium_user_id', NEW.user_id
        ),
        updated_at = now()
    WHERE id = NEW.id;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."sync_profile_to_auth_metadata"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."unblock_profile"("target_profile" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    IF NOT public.is_profile_active(auth.uid()) THEN
        RAISE EXCEPTION 'Account is not active';
    END IF;
    DELETE FROM public.blocks
    WHERE blocker_id = auth.uid() AND blocked_id = target_profile;
END;
$$;


ALTER FUNCTION "public"."unblock_profile"("target_profile" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."unfollow_profile"("target_profile" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    IF NOT public.is_profile_active(auth.uid()) THEN
        RAISE EXCEPTION 'Account is not active';
    END IF;
    DELETE FROM public.follows
    WHERE follower_id = auth.uid() AND following_id = target_profile;
    DELETE FROM public.notifications
    WHERE recipient_id = target_profile
      AND actor_id = auth.uid()
      AND type = 'follow_request'
      AND read_at IS NULL;
END;
$$;


ALTER FUNCTION "public"."unfollow_profile"("target_profile" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_follow_counts"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
    IF TG_OP = 'INSERT' AND NEW.status = 'accepted' THEN
        UPDATE public.profiles
        SET following_count = COALESCE(following_count, 0) + 1
        WHERE id = NEW.follower_id;
        UPDATE public.profiles
        SET followers_count = COALESCE(followers_count, 0) + 1
        WHERE id = NEW.following_id;
    ELSIF TG_OP = 'UPDATE' AND OLD.status <> 'accepted' AND NEW.status = 'accepted' THEN
        UPDATE public.profiles
        SET following_count = COALESCE(following_count, 0) + 1
        WHERE id = NEW.follower_id;
        UPDATE public.profiles
        SET followers_count = COALESCE(followers_count, 0) + 1
        WHERE id = NEW.following_id;
    ELSIF TG_OP = 'UPDATE' AND OLD.status = 'accepted' AND NEW.status <> 'accepted' THEN
        UPDATE public.profiles
        SET following_count = GREATEST(COALESCE(following_count, 0) - 1, 0)
        WHERE id = OLD.follower_id;
        UPDATE public.profiles
        SET followers_count = GREATEST(COALESCE(followers_count, 0) - 1, 0)
        WHERE id = OLD.following_id;
    ELSIF TG_OP = 'DELETE' AND OLD.status = 'accepted' THEN
        UPDATE public.profiles
        SET following_count = GREATEST(COALESCE(following_count, 0) - 1, 0)
        WHERE id = OLD.follower_id;
        UPDATE public.profiles
        SET followers_count = GREATEST(COALESCE(followers_count, 0) - 1, 0)
        WHERE id = OLD.following_id;
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION "public"."update_follow_counts"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_private_account_details"("p_password" "text", "p_full_name" "text", "p_birth_date" "date", "p_phone_number" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $_$
DECLARE
    normalized_phone TEXT := regexp_replace(p_phone_number, '[^0-9+]', '', 'g');
BEGIN
    IF NOT public.verify_privacy_password(p_password) THEN
        RETURN false;
    END IF;
    IF char_length(btrim(p_full_name)) NOT BETWEEN 1 AND 100
       OR p_birth_date < DATE '1900-01-01'
       OR p_birth_date > CURRENT_DATE
       OR normalized_phone !~ '^\+?[0-9]{7,15}$' THEN
        RAISE EXCEPTION 'Invalid private account data' USING ERRCODE = '23514';
    END IF;
    UPDATE public.account_details
    SET full_name = btrim(p_full_name),
        birth_date = p_birth_date,
        phone_number = normalized_phone,
        phone_verified_at = CASE
            WHEN phone_number = normalized_phone THEN phone_verified_at
            ELSE NULL
        END,
        updated_at = timezone('utc'::text, now())
    WHERE profile_id = auth.uid();
    RETURN FOUND;
END;
$_$;


ALTER FUNCTION "public"."update_private_account_details"("p_password" "text", "p_full_name" "text", "p_birth_date" "date", "p_phone_number" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_profile_page_color"("p_page_color" "text") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    IF p_page_color IS NULL OR p_page_color NOT IN (
        'red',
        'magenta',
        'blue',
        'yellow',
        'green',
        'purple',
        'gray',
        'orange',
        'pink',
        'light_blue',
        'emerald',
        'red_purple',
        'yellow_green',
        'brown'
    ) THEN
        RAISE EXCEPTION 'Invalid page color' USING ERRCODE = '23514';
    END IF;

    UPDATE public.profiles
    SET page_color = p_page_color
    WHERE id = auth.uid();

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Profile not found' USING ERRCODE = 'P0002';
    END IF;
END;
$$;


ALTER FUNCTION "public"."update_profile_page_color"("p_page_color" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_public_profile"("p_username" "text", "p_user_id" "text", "p_is_private" boolean) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
DECLARE
    normalized_user_id TEXT := lower(btrim(p_user_id));
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;
    IF char_length(btrim(p_username)) NOT BETWEEN 1 AND 30
       OR normalized_user_id !~ '^[a-z0-9_]{3,20}$'
       OR normalized_user_id IN (
           'admin', 'administrator', 'support', 'sharemarium', 'system', 'official'
       ) THEN
        RAISE EXCEPTION 'Invalid profile data' USING ERRCODE = '23514';
    END IF;
    UPDATE public.profiles
    SET username = btrim(p_username),
        user_id = normalized_user_id,
        is_private = p_is_private
    WHERE id = auth.uid();
END;
$_$;


ALTER FUNCTION "public"."update_public_profile"("p_username" "text", "p_user_id" "text", "p_is_private" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_public_profile"("p_username" "text", "p_user_id" "text", "p_bio" "text", "p_is_private" boolean) RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
    normalized_user_id TEXT := lower(btrim(p_user_id));
    normalized_bio TEXT := btrim(COALESCE(p_bio, ''));
    existing_user_id TEXT;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required' USING ERRCODE = '42501';
    END IF;

    SELECT profile.user_id
    INTO existing_user_id
    FROM public.profiles AS profile
    WHERE profile.id = auth.uid();

    IF existing_user_id IS NULL THEN
        RAISE EXCEPTION 'Profile not found' USING ERRCODE = 'P0002';
    END IF;
    IF normalized_user_id IS DISTINCT FROM existing_user_id THEN
        RAISE EXCEPTION 'USER_ID_IMMUTABLE' USING ERRCODE = '23514';
    END IF;
    IF char_length(btrim(p_username)) NOT BETWEEN 1 AND 30
       OR char_length(normalized_bio) > 300 THEN
        RAISE EXCEPTION 'Invalid profile data' USING ERRCODE = '23514';
    END IF;

    UPDATE public.profiles
    SET username = btrim(p_username),
        bio = normalized_bio,
        is_private = p_is_private
    WHERE id = auth.uid();
END;
$$;


ALTER FUNCTION "public"."update_public_profile"("p_username" "text", "p_user_id" "text", "p_bio" "text", "p_is_private" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."verify_privacy_password"("p_password" "text") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public', 'extensions'
    AS $$
DECLARE
    credential public.privacy_password_credentials%ROWTYPE;
    next_attempts SMALLINT;
BEGIN
    IF auth.uid() IS NULL THEN RETURN false; END IF;
    SELECT * INTO credential
    FROM public.privacy_password_credentials
    WHERE profile_id = auth.uid()
    FOR UPDATE;

    IF NOT FOUND OR credential.locked_until > timezone('utc'::text, now()) THEN
        RETURN false;
    END IF;

    IF credential.password_hash = extensions.crypt(p_password, credential.password_hash) THEN
        UPDATE public.privacy_password_credentials
        SET failed_attempts = 0, locked_until = NULL
        WHERE profile_id = auth.uid();
        RETURN true;
    END IF;

    next_attempts := credential.failed_attempts + 1;
    UPDATE public.privacy_password_credentials
    SET failed_attempts = CASE WHEN next_attempts >= 5 THEN 0 ELSE next_attempts END,
        locked_until = CASE
            WHEN next_attempts >= 5 THEN timezone('utc'::text, now()) + interval '15 minutes'
            ELSE NULL
        END
    WHERE profile_id = auth.uid();
    RETURN false;
END;
$$;


ALTER FUNCTION "public"."verify_privacy_password"("p_password" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "storage"."allow_any_operation"("expected_operations" "text"[]) RETURNS boolean
    LANGUAGE "sql" STABLE
    AS $$
  WITH current_operation AS (
    SELECT storage.operation() AS raw_operation
  ),
  normalized AS (
    SELECT CASE
      WHEN raw_operation LIKE 'storage.%' THEN substr(raw_operation, 9)
      ELSE raw_operation
    END AS current_operation
    FROM current_operation
  )
  SELECT EXISTS (
    SELECT 1
    FROM normalized n
    CROSS JOIN LATERAL unnest(expected_operations) AS expected_operation
    WHERE expected_operation IS NOT NULL
      AND expected_operation <> ''
      AND n.current_operation = CASE
        WHEN expected_operation LIKE 'storage.%' THEN substr(expected_operation, 9)
        ELSE expected_operation
      END
  );
$$;


ALTER FUNCTION "storage"."allow_any_operation"("expected_operations" "text"[]) OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."allow_only_operation"("expected_operation" "text") RETURNS boolean
    LANGUAGE "sql" STABLE
    AS $$
  WITH current_operation AS (
    SELECT storage.operation() AS raw_operation
  ),
  normalized AS (
    SELECT
      CASE
        WHEN raw_operation LIKE 'storage.%' THEN substr(raw_operation, 9)
        ELSE raw_operation
      END AS current_operation,
      CASE
        WHEN expected_operation LIKE 'storage.%' THEN substr(expected_operation, 9)
        ELSE expected_operation
      END AS requested_operation
    FROM current_operation
  )
  SELECT CASE
    WHEN requested_operation IS NULL OR requested_operation = '' THEN FALSE
    ELSE COALESCE(current_operation = requested_operation, FALSE)
  END
  FROM normalized;
$$;


ALTER FUNCTION "storage"."allow_only_operation"("expected_operation" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."can_insert_object"("bucketid" "text", "name" "text", "owner" "uuid", "metadata" "jsonb") RETURNS "void"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
  INSERT INTO "storage"."objects" ("bucket_id", "name", "owner", "metadata") VALUES (bucketid, name, owner, metadata);
  -- hack to rollback the successful insert
  RAISE sqlstate 'PT200' using
  message = 'ROLLBACK',
  detail = 'rollback successful insert';
END
$$;


ALTER FUNCTION "storage"."can_insert_object"("bucketid" "text", "name" "text", "owner" "uuid", "metadata" "jsonb") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."enforce_bucket_name_length"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
    if length(new.name) > 100 then
        raise exception 'bucket name "%" is too long (% characters). Max is 100.', new.name, length(new.name);
    end if;
    return new;
end;
$$;


ALTER FUNCTION "storage"."enforce_bucket_name_length"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."extension"("name" "text") RETURNS "text"
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
    _parts text[];
    _filename text;
BEGIN
    -- Split on "/" to get path segments
    SELECT string_to_array(name, '/') INTO _parts;
    -- Get the last path segment (the actual filename)
    SELECT _parts[array_length(_parts, 1)] INTO _filename;
    -- Extract extension: reverse, split on '.', then reverse again
    RETURN reverse(split_part(reverse(_filename), '.', 1));
END
$$;


ALTER FUNCTION "storage"."extension"("name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."filename"("name" "text") RETURNS "text"
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
    _parts text[];
BEGIN
    SELECT string_to_array(name, '/') INTO _parts;
    RETURN _parts[array_length(_parts, 1)];
END
$$;


ALTER FUNCTION "storage"."filename"("name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."foldername"("name" "text") RETURNS "text"[]
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
DECLARE
    _parts text[];
BEGIN
    -- Split on "/" to get path segments
    SELECT string_to_array(name, '/') INTO _parts;
    -- Return everything except the last segment
    RETURN _parts[1 : array_length(_parts,1) - 1];
END
$$;


ALTER FUNCTION "storage"."foldername"("name" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."get_common_prefix"("p_key" "text", "p_prefix" "text", "p_delimiter" "text") RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    AS $$
SELECT CASE
    WHEN position(p_delimiter IN substring(p_key FROM length(p_prefix) + 1)) > 0
    THEN left(p_key, length(p_prefix) + position(p_delimiter IN substring(p_key FROM length(p_prefix) + 1)))
    ELSE NULL
END;
$$;


ALTER FUNCTION "storage"."get_common_prefix"("p_key" "text", "p_prefix" "text", "p_delimiter" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."get_size_by_bucket"() RETURNS TABLE("size" bigint, "bucket_id" "text")
    LANGUAGE "plpgsql" STABLE
    AS $$
BEGIN
    return query
        select sum((metadata->>'size')::bigint)::bigint as size, obj.bucket_id
        from "storage".objects as obj
        group by obj.bucket_id;
END
$$;


ALTER FUNCTION "storage"."get_size_by_bucket"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."list_multipart_uploads_with_delimiter"("bucket_id" "text", "prefix_param" "text", "delimiter_param" "text", "max_keys" integer DEFAULT 100, "next_key_token" "text" DEFAULT ''::"text", "next_upload_token" "text" DEFAULT ''::"text") RETURNS TABLE("key" "text", "id" "text", "created_at" timestamp with time zone)
    LANGUAGE "plpgsql"
    AS $_$
BEGIN
    RETURN QUERY EXECUTE
        'SELECT DISTINCT ON(key COLLATE "C") * from (
            SELECT
                CASE
                    WHEN position($2 IN substring(key from length($1) + 1)) > 0 THEN
                        substring(key from 1 for length($1) + position($2 IN substring(key from length($1) + 1)))
                    ELSE
                        key
                END AS key, id, created_at
            FROM
                storage.s3_multipart_uploads
            WHERE
                bucket_id = $5 AND
                key ILIKE $1 || ''%'' AND
                CASE
                    WHEN $4 != '''' AND $6 = '''' THEN
                        CASE
                            WHEN position($2 IN substring(key from length($1) + 1)) > 0 THEN
                                substring(key from 1 for length($1) + position($2 IN substring(key from length($1) + 1))) COLLATE "C" > $4
                            ELSE
                                key COLLATE "C" > $4
                            END
                    ELSE
                        true
                END AND
                CASE
                    WHEN $6 != '''' THEN
                        id COLLATE "C" > $6
                    ELSE
                        true
                    END
            ORDER BY
                key COLLATE "C" ASC, created_at ASC) as e order by key COLLATE "C" LIMIT $3'
        USING prefix_param, delimiter_param, max_keys, next_key_token, bucket_id, next_upload_token;
END;
$_$;


ALTER FUNCTION "storage"."list_multipart_uploads_with_delimiter"("bucket_id" "text", "prefix_param" "text", "delimiter_param" "text", "max_keys" integer, "next_key_token" "text", "next_upload_token" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."list_objects_with_delimiter"("_bucket_id" "text", "prefix_param" "text", "delimiter_param" "text", "max_keys" integer DEFAULT 100, "start_after" "text" DEFAULT ''::"text", "next_token" "text" DEFAULT ''::"text", "sort_order" "text" DEFAULT 'asc'::"text") RETURNS TABLE("name" "text", "id" "uuid", "metadata" "jsonb", "updated_at" timestamp with time zone, "created_at" timestamp with time zone, "last_accessed_at" timestamp with time zone)
    LANGUAGE "plpgsql" STABLE
    AS $_$
DECLARE
    v_peek_name TEXT;
    v_current RECORD;
    v_common_prefix TEXT;

    -- Configuration
    v_is_asc BOOLEAN;
    v_prefix TEXT;
    v_start TEXT;
    v_upper_bound TEXT;
    v_file_batch_size INT;

    -- Seek state
    v_next_seek TEXT;
    v_count INT := 0;

    -- Dynamic SQL for batch query only
    v_batch_query TEXT;

BEGIN
    -- ========================================================================
    -- INITIALIZATION
    -- ========================================================================
    v_is_asc := lower(coalesce(sort_order, 'asc')) = 'asc';
    v_prefix := coalesce(prefix_param, '');
    v_start := CASE WHEN coalesce(next_token, '') <> '' THEN next_token ELSE coalesce(start_after, '') END;
    v_file_batch_size := LEAST(GREATEST(max_keys * 2, 100), 1000);

    -- Calculate upper bound for prefix filtering (bytewise, using COLLATE "C")
    IF v_prefix = '' THEN
        v_upper_bound := NULL;
    ELSIF right(v_prefix, 1) = delimiter_param THEN
        v_upper_bound := left(v_prefix, -1) || chr(ascii(delimiter_param) + 1);
    ELSE
        v_upper_bound := left(v_prefix, -1) || chr(ascii(right(v_prefix, 1)) + 1);
    END IF;

    -- Build batch query (dynamic SQL - called infrequently, amortized over many rows)
    IF v_is_asc THEN
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND o.name COLLATE "C" >= $2 ' ||
                'AND o.name COLLATE "C" < $3 ORDER BY o.name COLLATE "C" ASC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND o.name COLLATE "C" >= $2 ' ||
                'ORDER BY o.name COLLATE "C" ASC LIMIT $4';
        END IF;
    ELSE
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND o.name COLLATE "C" < $2 ' ||
                'AND o.name COLLATE "C" >= $3 ORDER BY o.name COLLATE "C" DESC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND o.name COLLATE "C" < $2 ' ||
                'ORDER BY o.name COLLATE "C" DESC LIMIT $4';
        END IF;
    END IF;

    -- ========================================================================
    -- SEEK INITIALIZATION: Determine starting position
    -- ========================================================================
    IF v_start = '' THEN
        IF v_is_asc THEN
            v_next_seek := v_prefix;
        ELSE
            -- DESC without cursor: find the last item in range
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_next_seek FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" >= v_prefix AND o.name COLLATE "C" < v_upper_bound
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            ELSIF v_prefix <> '' THEN
                SELECT o.name INTO v_next_seek FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" >= v_prefix
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            ELSE
                SELECT o.name INTO v_next_seek FROM storage.objects o
                WHERE o.bucket_id = _bucket_id
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            END IF;

            IF v_next_seek IS NOT NULL THEN
                v_next_seek := v_next_seek || delimiter_param;
            ELSE
                RETURN;
            END IF;
        END IF;
    ELSE
        -- Cursor provided: determine if it refers to a folder or leaf
        IF EXISTS (
            SELECT 1 FROM storage.objects o
            WHERE o.bucket_id = _bucket_id
              AND o.name COLLATE "C" LIKE v_start || delimiter_param || '%'
            LIMIT 1
        ) THEN
            -- Cursor refers to a folder
            IF v_is_asc THEN
                v_next_seek := v_start || chr(ascii(delimiter_param) + 1);
            ELSE
                v_next_seek := v_start || delimiter_param;
            END IF;
        ELSE
            -- Cursor refers to a leaf object
            IF v_is_asc THEN
                v_next_seek := v_start || delimiter_param;
            ELSE
                v_next_seek := v_start;
            END IF;
        END IF;
    END IF;

    -- ========================================================================
    -- MAIN LOOP: Hybrid peek-then-batch algorithm
    -- Uses STATIC SQL for peek (hot path) and DYNAMIC SQL for batch
    -- ========================================================================
    LOOP
        EXIT WHEN v_count >= max_keys;

        -- STEP 1: PEEK using STATIC SQL (plan cached, very fast)
        IF v_is_asc THEN
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" >= v_next_seek AND o.name COLLATE "C" < v_upper_bound
                ORDER BY o.name COLLATE "C" ASC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" >= v_next_seek
                ORDER BY o.name COLLATE "C" ASC LIMIT 1;
            END IF;
        ELSE
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" < v_next_seek AND o.name COLLATE "C" >= v_prefix
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            ELSIF v_prefix <> '' THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" < v_next_seek AND o.name COLLATE "C" >= v_prefix
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = _bucket_id AND o.name COLLATE "C" < v_next_seek
                ORDER BY o.name COLLATE "C" DESC LIMIT 1;
            END IF;
        END IF;

        EXIT WHEN v_peek_name IS NULL;

        -- STEP 2: Check if this is a FOLDER or FILE
        v_common_prefix := storage.get_common_prefix(v_peek_name, v_prefix, delimiter_param);

        IF v_common_prefix IS NOT NULL THEN
            -- FOLDER: Emit and skip to next folder (no heap access needed)
            name := rtrim(v_common_prefix, delimiter_param);
            id := NULL;
            updated_at := NULL;
            created_at := NULL;
            last_accessed_at := NULL;
            metadata := NULL;
            RETURN NEXT;
            v_count := v_count + 1;

            -- Advance seek past the folder range
            IF v_is_asc THEN
                v_next_seek := left(v_common_prefix, -1) || chr(ascii(delimiter_param) + 1);
            ELSE
                v_next_seek := v_common_prefix;
            END IF;
        ELSE
            -- FILE: Batch fetch using DYNAMIC SQL (overhead amortized over many rows)
            -- For ASC: upper_bound is the exclusive upper limit (< condition)
            -- For DESC: prefix is the inclusive lower limit (>= condition)
            FOR v_current IN EXECUTE v_batch_query USING _bucket_id, v_next_seek,
                CASE WHEN v_is_asc THEN COALESCE(v_upper_bound, v_prefix) ELSE v_prefix END, v_file_batch_size
            LOOP
                v_common_prefix := storage.get_common_prefix(v_current.name, v_prefix, delimiter_param);

                IF v_common_prefix IS NOT NULL THEN
                    -- Hit a folder: exit batch, let peek handle it
                    v_next_seek := v_current.name;
                    EXIT;
                END IF;

                -- Emit file
                name := v_current.name;
                id := v_current.id;
                updated_at := v_current.updated_at;
                created_at := v_current.created_at;
                last_accessed_at := v_current.last_accessed_at;
                metadata := v_current.metadata;
                RETURN NEXT;
                v_count := v_count + 1;

                -- Advance seek past this file
                IF v_is_asc THEN
                    v_next_seek := v_current.name || delimiter_param;
                ELSE
                    v_next_seek := v_current.name;
                END IF;

                EXIT WHEN v_count >= max_keys;
            END LOOP;
        END IF;
    END LOOP;
END;
$_$;


ALTER FUNCTION "storage"."list_objects_with_delimiter"("_bucket_id" "text", "prefix_param" "text", "delimiter_param" "text", "max_keys" integer, "start_after" "text", "next_token" "text", "sort_order" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."operation"() RETURNS "text"
    LANGUAGE "plpgsql" STABLE
    AS $$
BEGIN
    RETURN current_setting('storage.operation', true);
END;
$$;


ALTER FUNCTION "storage"."operation"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."protect_delete"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    -- Check if storage.allow_delete_query is set to 'true'
    IF COALESCE(current_setting('storage.allow_delete_query', true), 'false') != 'true' THEN
        RAISE EXCEPTION 'Direct deletion from storage tables is not allowed. Use the Storage API instead.'
            USING HINT = 'This prevents accidental data loss from orphaned objects.',
                  ERRCODE = '42501';
    END IF;
    RETURN NULL;
END;
$$;


ALTER FUNCTION "storage"."protect_delete"() OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."search"("prefix" "text", "bucketname" "text", "limits" integer DEFAULT 100, "levels" integer DEFAULT 1, "offsets" integer DEFAULT 0, "search" "text" DEFAULT ''::"text", "sortcolumn" "text" DEFAULT 'name'::"text", "sortorder" "text" DEFAULT 'asc'::"text") RETURNS TABLE("name" "text", "id" "uuid", "updated_at" timestamp with time zone, "created_at" timestamp with time zone, "last_accessed_at" timestamp with time zone, "metadata" "jsonb")
    LANGUAGE "plpgsql" STABLE
    AS $_$
DECLARE
    v_peek_name TEXT;
    v_current RECORD;
    v_common_prefix TEXT;
    v_delimiter CONSTANT TEXT := '/';

    -- Configuration
    v_limit INT;
    v_prefix TEXT;
    v_prefix_lower TEXT;
    v_is_asc BOOLEAN;
    v_order_by TEXT;
    v_sort_order TEXT;
    v_upper_bound TEXT;
    v_file_batch_size INT;

    -- Dynamic SQL for batch query only
    v_batch_query TEXT;

    -- Seek state
    v_next_seek TEXT;
    v_count INT := 0;
    v_skipped INT := 0;
BEGIN
    -- ========================================================================
    -- INITIALIZATION
    -- ========================================================================
    v_limit := LEAST(coalesce(limits, 100), 1500);
    v_prefix := coalesce(prefix, '') || coalesce(search, '');
    v_prefix_lower := lower(v_prefix);
    v_is_asc := lower(coalesce(sortorder, 'asc')) = 'asc';
    v_file_batch_size := LEAST(GREATEST(v_limit * 2, 100), 1000);

    -- Validate sort column
    CASE lower(coalesce(sortcolumn, 'name'))
        WHEN 'name' THEN v_order_by := 'name';
        WHEN 'updated_at' THEN v_order_by := 'updated_at';
        WHEN 'created_at' THEN v_order_by := 'created_at';
        WHEN 'last_accessed_at' THEN v_order_by := 'last_accessed_at';
        ELSE v_order_by := 'name';
    END CASE;

    v_sort_order := CASE WHEN v_is_asc THEN 'asc' ELSE 'desc' END;

    -- ========================================================================
    -- NON-NAME SORTING: Use path_tokens approach (unchanged)
    -- ========================================================================
    IF v_order_by != 'name' THEN
        RETURN QUERY EXECUTE format(
            $sql$
            WITH folders AS (
                SELECT path_tokens[$1] AS folder
                FROM storage.objects
                WHERE objects.name ILIKE $2 || '%%'
                  AND bucket_id = $3
                  AND array_length(objects.path_tokens, 1) <> $1
                GROUP BY folder
                ORDER BY folder %s
            )
            (SELECT folder AS "name",
                   NULL::uuid AS id,
                   NULL::timestamptz AS updated_at,
                   NULL::timestamptz AS created_at,
                   NULL::timestamptz AS last_accessed_at,
                   NULL::jsonb AS metadata FROM folders)
            UNION ALL
            (SELECT path_tokens[$1] AS "name",
                   id, updated_at, created_at, last_accessed_at, metadata
             FROM storage.objects
             WHERE objects.name ILIKE $2 || '%%'
               AND bucket_id = $3
               AND array_length(objects.path_tokens, 1) = $1
             ORDER BY %I %s)
            LIMIT $4 OFFSET $5
            $sql$, v_sort_order, v_order_by, v_sort_order
        ) USING levels, v_prefix, bucketname, v_limit, offsets;
        RETURN;
    END IF;

    -- ========================================================================
    -- NAME SORTING: Hybrid skip-scan with batch optimization
    -- ========================================================================

    -- Calculate upper bound for prefix filtering
    IF v_prefix_lower = '' THEN
        v_upper_bound := NULL;
    ELSIF right(v_prefix_lower, 1) = v_delimiter THEN
        v_upper_bound := left(v_prefix_lower, -1) || chr(ascii(v_delimiter) + 1);
    ELSE
        v_upper_bound := left(v_prefix_lower, -1) || chr(ascii(right(v_prefix_lower, 1)) + 1);
    END IF;

    -- Build batch query (dynamic SQL - called infrequently, amortized over many rows)
    IF v_is_asc THEN
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" >= $2 ' ||
                'AND lower(o.name) COLLATE "C" < $3 ORDER BY lower(o.name) COLLATE "C" ASC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" >= $2 ' ||
                'ORDER BY lower(o.name) COLLATE "C" ASC LIMIT $4';
        END IF;
    ELSE
        IF v_upper_bound IS NOT NULL THEN
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" < $2 ' ||
                'AND lower(o.name) COLLATE "C" >= $3 ORDER BY lower(o.name) COLLATE "C" DESC LIMIT $4';
        ELSE
            v_batch_query := 'SELECT o.name, o.id, o.updated_at, o.created_at, o.last_accessed_at, o.metadata ' ||
                'FROM storage.objects o WHERE o.bucket_id = $1 AND lower(o.name) COLLATE "C" < $2 ' ||
                'ORDER BY lower(o.name) COLLATE "C" DESC LIMIT $4';
        END IF;
    END IF;

    -- Initialize seek position
    IF v_is_asc THEN
        v_next_seek := v_prefix_lower;
    ELSE
        -- DESC: find the last item in range first (static SQL)
        IF v_upper_bound IS NOT NULL THEN
            SELECT o.name INTO v_peek_name FROM storage.objects o
            WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_prefix_lower AND lower(o.name) COLLATE "C" < v_upper_bound
            ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
        ELSIF v_prefix_lower <> '' THEN
            SELECT o.name INTO v_peek_name FROM storage.objects o
            WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_prefix_lower
            ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
        ELSE
            SELECT o.name INTO v_peek_name FROM storage.objects o
            WHERE o.bucket_id = bucketname
            ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
        END IF;

        IF v_peek_name IS NOT NULL THEN
            v_next_seek := lower(v_peek_name) || v_delimiter;
        ELSE
            RETURN;
        END IF;
    END IF;

    -- ========================================================================
    -- MAIN LOOP: Hybrid peek-then-batch algorithm
    -- Uses STATIC SQL for peek (hot path) and DYNAMIC SQL for batch
    -- ========================================================================
    LOOP
        EXIT WHEN v_count >= v_limit;

        -- STEP 1: PEEK using STATIC SQL (plan cached, very fast)
        IF v_is_asc THEN
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_next_seek AND lower(o.name) COLLATE "C" < v_upper_bound
                ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" >= v_next_seek
                ORDER BY lower(o.name) COLLATE "C" ASC LIMIT 1;
            END IF;
        ELSE
            IF v_upper_bound IS NOT NULL THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek AND lower(o.name) COLLATE "C" >= v_prefix_lower
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            ELSIF v_prefix_lower <> '' THEN
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek AND lower(o.name) COLLATE "C" >= v_prefix_lower
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            ELSE
                SELECT o.name INTO v_peek_name FROM storage.objects o
                WHERE o.bucket_id = bucketname AND lower(o.name) COLLATE "C" < v_next_seek
                ORDER BY lower(o.name) COLLATE "C" DESC LIMIT 1;
            END IF;
        END IF;

        EXIT WHEN v_peek_name IS NULL;

        -- STEP 2: Check if this is a FOLDER or FILE
        v_common_prefix := storage.get_common_prefix(lower(v_peek_name), v_prefix_lower, v_delimiter);

        IF v_common_prefix IS NOT NULL THEN
            -- FOLDER: Handle offset, emit if needed, skip to next folder
            IF v_skipped < offsets THEN
                v_skipped := v_skipped + 1;
            ELSE
                name := split_part(rtrim(storage.get_common_prefix(v_peek_name, v_prefix, v_delimiter), v_delimiter), v_delimiter, levels);
                id := NULL;
                updated_at := NULL;
                created_at := NULL;
                last_accessed_at := NULL;
                metadata := NULL;
                RETURN NEXT;
                v_count := v_count + 1;
            END IF;

            -- Advance seek past the folder range
            IF v_is_asc THEN
                v_next_seek := lower(left(v_common_prefix, -1)) || chr(ascii(v_delimiter) + 1);
            ELSE
                v_next_seek := lower(v_common_prefix);
            END IF;
        ELSE
            -- FILE: Batch fetch using DYNAMIC SQL (overhead amortized over many rows)
            -- For ASC: upper_bound is the exclusive upper limit (< condition)
            -- For DESC: prefix_lower is the inclusive lower limit (>= condition)
            FOR v_current IN EXECUTE v_batch_query
                USING bucketname, v_next_seek,
                    CASE WHEN v_is_asc THEN COALESCE(v_upper_bound, v_prefix_lower) ELSE v_prefix_lower END, v_file_batch_size
            LOOP
                v_common_prefix := storage.get_common_prefix(lower(v_current.name), v_prefix_lower, v_delimiter);

                IF v_common_prefix IS NOT NULL THEN
                    -- Hit a folder: exit batch, let peek handle it
                    v_next_seek := lower(v_current.name);
                    EXIT;
                END IF;

                -- Handle offset skipping
                IF v_skipped < offsets THEN
                    v_skipped := v_skipped + 1;
                ELSE
                    -- Emit file
                    name := split_part(v_current.name, v_delimiter, levels);
                    id := v_current.id;
                    updated_at := v_current.updated_at;
                    created_at := v_current.created_at;
                    last_accessed_at := v_current.last_accessed_at;
                    metadata := v_current.metadata;
                    RETURN NEXT;
                    v_count := v_count + 1;
                END IF;

                -- Advance seek past this file
                IF v_is_asc THEN
                    v_next_seek := lower(v_current.name) || v_delimiter;
                ELSE
                    v_next_seek := lower(v_current.name);
                END IF;

                EXIT WHEN v_count >= v_limit;
            END LOOP;
        END IF;
    END LOOP;
END;
$_$;


ALTER FUNCTION "storage"."search"("prefix" "text", "bucketname" "text", "limits" integer, "levels" integer, "offsets" integer, "search" "text", "sortcolumn" "text", "sortorder" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."search_by_timestamp"("p_prefix" "text", "p_bucket_id" "text", "p_limit" integer, "p_level" integer, "p_start_after" "text", "p_sort_order" "text", "p_sort_column" "text", "p_sort_column_after" "text") RETURNS TABLE("key" "text", "name" "text", "id" "uuid", "updated_at" timestamp with time zone, "created_at" timestamp with time zone, "last_accessed_at" timestamp with time zone, "metadata" "jsonb")
    LANGUAGE "plpgsql" STABLE
    AS $_$
DECLARE
    v_cursor_op text;
    v_query text;
    v_prefix text;
BEGIN
    v_prefix := coalesce(p_prefix, '');

    IF p_sort_order = 'asc' THEN
        v_cursor_op := '>';
    ELSE
        v_cursor_op := '<';
    END IF;

    v_query := format($sql$
        WITH raw_objects AS (
            SELECT
                o.name AS obj_name,
                o.id AS obj_id,
                o.updated_at AS obj_updated_at,
                o.created_at AS obj_created_at,
                o.last_accessed_at AS obj_last_accessed_at,
                o.metadata AS obj_metadata,
                storage.get_common_prefix(o.name, $1, '/') AS common_prefix
            FROM storage.objects o
            WHERE o.bucket_id = $2
              AND o.name COLLATE "C" LIKE $1 || '%%'
        ),
        -- Aggregate common prefixes (folders)
        -- Both created_at and updated_at use MIN(obj_created_at) to match the old prefixes table behavior
        aggregated_prefixes AS (
            SELECT
                rtrim(common_prefix, '/') AS name,
                NULL::uuid AS id,
                MIN(obj_created_at) AS updated_at,
                MIN(obj_created_at) AS created_at,
                NULL::timestamptz AS last_accessed_at,
                NULL::jsonb AS metadata,
                TRUE AS is_prefix
            FROM raw_objects
            WHERE common_prefix IS NOT NULL
            GROUP BY common_prefix
        ),
        leaf_objects AS (
            SELECT
                obj_name AS name,
                obj_id AS id,
                obj_updated_at AS updated_at,
                obj_created_at AS created_at,
                obj_last_accessed_at AS last_accessed_at,
                obj_metadata AS metadata,
                FALSE AS is_prefix
            FROM raw_objects
            WHERE common_prefix IS NULL
        ),
        combined AS (
            SELECT * FROM aggregated_prefixes
            UNION ALL
            SELECT * FROM leaf_objects
        ),
        filtered AS (
            SELECT *
            FROM combined
            WHERE (
                $5 = ''
                OR ROW(
                    date_trunc('milliseconds', %I),
                    name COLLATE "C"
                ) %s ROW(
                    COALESCE(NULLIF($6, '')::timestamptz, 'epoch'::timestamptz),
                    $5
                )
            )
        )
        SELECT
            split_part(name, '/', $3) AS key,
            name,
            id,
            updated_at,
            created_at,
            last_accessed_at,
            metadata
        FROM filtered
        ORDER BY
            COALESCE(date_trunc('milliseconds', %I), 'epoch'::timestamptz) %s,
            name COLLATE "C" %s
        LIMIT $4
    $sql$,
        p_sort_column,
        v_cursor_op,
        p_sort_column,
        p_sort_order,
        p_sort_order
    );

    RETURN QUERY EXECUTE v_query
    USING v_prefix, p_bucket_id, p_level, p_limit, p_start_after, p_sort_column_after;
END;
$_$;


ALTER FUNCTION "storage"."search_by_timestamp"("p_prefix" "text", "p_bucket_id" "text", "p_limit" integer, "p_level" integer, "p_start_after" "text", "p_sort_order" "text", "p_sort_column" "text", "p_sort_column_after" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."search_v2"("prefix" "text", "bucket_name" "text", "limits" integer DEFAULT 100, "levels" integer DEFAULT 1, "start_after" "text" DEFAULT ''::"text", "sort_order" "text" DEFAULT 'asc'::"text", "sort_column" "text" DEFAULT 'name'::"text", "sort_column_after" "text" DEFAULT ''::"text") RETURNS TABLE("key" "text", "name" "text", "id" "uuid", "updated_at" timestamp with time zone, "created_at" timestamp with time zone, "last_accessed_at" timestamp with time zone, "metadata" "jsonb")
    LANGUAGE "plpgsql" STABLE
    AS $$
DECLARE
    v_sort_col text;
    v_sort_ord text;
    v_limit int;
BEGIN
    -- Cap limit to maximum of 1500 records
    v_limit := LEAST(coalesce(limits, 100), 1500);

    -- Validate and normalize sort_order
    v_sort_ord := lower(coalesce(sort_order, 'asc'));
    IF v_sort_ord NOT IN ('asc', 'desc') THEN
        v_sort_ord := 'asc';
    END IF;

    -- Validate and normalize sort_column
    v_sort_col := lower(coalesce(sort_column, 'name'));
    IF v_sort_col NOT IN ('name', 'updated_at', 'created_at') THEN
        v_sort_col := 'name';
    END IF;

    -- Route to appropriate implementation
    IF v_sort_col = 'name' THEN
        -- Use list_objects_with_delimiter for name sorting (most efficient: O(k * log n))
        RETURN QUERY
        SELECT
            split_part(l.name, '/', levels) AS key,
            l.name AS name,
            l.id,
            l.updated_at,
            l.created_at,
            l.last_accessed_at,
            l.metadata
        FROM storage.list_objects_with_delimiter(
            bucket_name,
            coalesce(prefix, ''),
            '/',
            v_limit,
            start_after,
            '',
            v_sort_ord
        ) l;
    ELSE
        -- Use aggregation approach for timestamp sorting
        -- Not efficient for large datasets but supports correct pagination
        RETURN QUERY SELECT * FROM storage.search_by_timestamp(
            prefix, bucket_name, v_limit, levels, start_after,
            v_sort_ord, v_sort_col, sort_column_after
        );
    END IF;
END;
$$;


ALTER FUNCTION "storage"."search_v2"("prefix" "text", "bucket_name" "text", "limits" integer, "levels" integer, "start_after" "text", "sort_order" "text", "sort_column" "text", "sort_column_after" "text") OWNER TO "supabase_storage_admin";


CREATE OR REPLACE FUNCTION "storage"."update_updated_at_column"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW; 
END;
$$;


ALTER FUNCTION "storage"."update_updated_at_column"() OWNER TO "supabase_storage_admin";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "auth"."audit_log_entries" (
    "instance_id" "uuid",
    "id" "uuid" NOT NULL,
    "payload" json,
    "created_at" timestamp with time zone,
    "ip_address" character varying(64) DEFAULT ''::character varying NOT NULL
);


ALTER TABLE "auth"."audit_log_entries" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."audit_log_entries" IS 'Auth: Audit trail for user actions.';



CREATE TABLE IF NOT EXISTS "auth"."custom_oauth_providers" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "provider_type" "text" NOT NULL,
    "identifier" "text" NOT NULL,
    "name" "text" NOT NULL,
    "client_id" "text" NOT NULL,
    "client_secret" "text" NOT NULL,
    "acceptable_client_ids" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "scopes" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    "pkce_enabled" boolean DEFAULT true NOT NULL,
    "attribute_mapping" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "authorization_params" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "enabled" boolean DEFAULT true NOT NULL,
    "email_optional" boolean DEFAULT false NOT NULL,
    "issuer" "text",
    "discovery_url" "text",
    "skip_nonce_check" boolean DEFAULT false NOT NULL,
    "cached_discovery" "jsonb",
    "discovery_cached_at" timestamp with time zone,
    "authorization_url" "text",
    "token_url" "text",
    "userinfo_url" "text",
    "jwks_uri" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "custom_claims_allowlist" "text"[] DEFAULT '{}'::"text"[] NOT NULL,
    CONSTRAINT "custom_oauth_providers_authorization_url_https" CHECK ((("authorization_url" IS NULL) OR ("authorization_url" ~~ 'https://%'::"text"))),
    CONSTRAINT "custom_oauth_providers_authorization_url_length" CHECK ((("authorization_url" IS NULL) OR ("char_length"("authorization_url") <= 2048))),
    CONSTRAINT "custom_oauth_providers_client_id_length" CHECK ((("char_length"("client_id") >= 1) AND ("char_length"("client_id") <= 512))),
    CONSTRAINT "custom_oauth_providers_discovery_url_length" CHECK ((("discovery_url" IS NULL) OR ("char_length"("discovery_url") <= 2048))),
    CONSTRAINT "custom_oauth_providers_identifier_format" CHECK (("identifier" ~ '^[a-z0-9][a-z0-9:-]{0,48}[a-z0-9]$'::"text")),
    CONSTRAINT "custom_oauth_providers_issuer_length" CHECK ((("issuer" IS NULL) OR (("char_length"("issuer") >= 1) AND ("char_length"("issuer") <= 2048)))),
    CONSTRAINT "custom_oauth_providers_jwks_uri_https" CHECK ((("jwks_uri" IS NULL) OR ("jwks_uri" ~~ 'https://%'::"text"))),
    CONSTRAINT "custom_oauth_providers_jwks_uri_length" CHECK ((("jwks_uri" IS NULL) OR ("char_length"("jwks_uri") <= 2048))),
    CONSTRAINT "custom_oauth_providers_name_length" CHECK ((("char_length"("name") >= 1) AND ("char_length"("name") <= 100))),
    CONSTRAINT "custom_oauth_providers_oauth2_requires_endpoints" CHECK ((("provider_type" <> 'oauth2'::"text") OR (("authorization_url" IS NOT NULL) AND ("token_url" IS NOT NULL) AND ("userinfo_url" IS NOT NULL)))),
    CONSTRAINT "custom_oauth_providers_oidc_discovery_url_https" CHECK ((("provider_type" <> 'oidc'::"text") OR ("discovery_url" IS NULL) OR ("discovery_url" ~~ 'https://%'::"text"))),
    CONSTRAINT "custom_oauth_providers_oidc_issuer_https" CHECK ((("provider_type" <> 'oidc'::"text") OR ("issuer" IS NULL) OR ("issuer" ~~ 'https://%'::"text"))),
    CONSTRAINT "custom_oauth_providers_oidc_requires_issuer" CHECK ((("provider_type" <> 'oidc'::"text") OR ("issuer" IS NOT NULL))),
    CONSTRAINT "custom_oauth_providers_provider_type_check" CHECK (("provider_type" = ANY (ARRAY['oauth2'::"text", 'oidc'::"text"]))),
    CONSTRAINT "custom_oauth_providers_token_url_https" CHECK ((("token_url" IS NULL) OR ("token_url" ~~ 'https://%'::"text"))),
    CONSTRAINT "custom_oauth_providers_token_url_length" CHECK ((("token_url" IS NULL) OR ("char_length"("token_url") <= 2048))),
    CONSTRAINT "custom_oauth_providers_userinfo_url_https" CHECK ((("userinfo_url" IS NULL) OR ("userinfo_url" ~~ 'https://%'::"text"))),
    CONSTRAINT "custom_oauth_providers_userinfo_url_length" CHECK ((("userinfo_url" IS NULL) OR ("char_length"("userinfo_url") <= 2048)))
);


ALTER TABLE "auth"."custom_oauth_providers" OWNER TO "supabase_auth_admin";


CREATE TABLE IF NOT EXISTS "auth"."flow_state" (
    "id" "uuid" NOT NULL,
    "user_id" "uuid",
    "auth_code" "text",
    "code_challenge_method" "auth"."code_challenge_method",
    "code_challenge" "text",
    "provider_type" "text" NOT NULL,
    "provider_access_token" "text",
    "provider_refresh_token" "text",
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "authentication_method" "text" NOT NULL,
    "auth_code_issued_at" timestamp with time zone,
    "invite_token" "text",
    "referrer" "text",
    "oauth_client_state_id" "uuid",
    "linking_target_id" "uuid",
    "email_optional" boolean DEFAULT false NOT NULL
);


ALTER TABLE "auth"."flow_state" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."flow_state" IS 'Stores metadata for all OAuth/SSO login flows';



CREATE TABLE IF NOT EXISTS "auth"."identities" (
    "provider_id" "text" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "identity_data" "jsonb" NOT NULL,
    "provider" "text" NOT NULL,
    "last_sign_in_at" timestamp with time zone,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "email" "text" GENERATED ALWAYS AS ("lower"(("identity_data" ->> 'email'::"text"))) STORED,
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL
);


ALTER TABLE "auth"."identities" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."identities" IS 'Auth: Stores identities associated to a user.';



COMMENT ON COLUMN "auth"."identities"."email" IS 'Auth: Email is a generated column that references the optional email property in the identity_data';



CREATE TABLE IF NOT EXISTS "auth"."instances" (
    "id" "uuid" NOT NULL,
    "uuid" "uuid",
    "raw_base_config" "text",
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone
);


ALTER TABLE "auth"."instances" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."instances" IS 'Auth: Manages users across multiple sites.';



CREATE TABLE IF NOT EXISTS "auth"."mfa_amr_claims" (
    "session_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone NOT NULL,
    "updated_at" timestamp with time zone NOT NULL,
    "authentication_method" "text" NOT NULL,
    "id" "uuid" NOT NULL
);


ALTER TABLE "auth"."mfa_amr_claims" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."mfa_amr_claims" IS 'auth: stores authenticator method reference claims for multi factor authentication';



CREATE TABLE IF NOT EXISTS "auth"."mfa_challenges" (
    "id" "uuid" NOT NULL,
    "factor_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone NOT NULL,
    "verified_at" timestamp with time zone,
    "ip_address" "inet" NOT NULL,
    "otp_code" "text",
    "web_authn_session_data" "jsonb"
);


ALTER TABLE "auth"."mfa_challenges" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."mfa_challenges" IS 'auth: stores metadata about challenge requests made';



CREATE TABLE IF NOT EXISTS "auth"."mfa_factors" (
    "id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "friendly_name" "text",
    "factor_type" "auth"."factor_type" NOT NULL,
    "status" "auth"."factor_status" NOT NULL,
    "created_at" timestamp with time zone NOT NULL,
    "updated_at" timestamp with time zone NOT NULL,
    "secret" "text",
    "phone" "text",
    "last_challenged_at" timestamp with time zone,
    "web_authn_credential" "jsonb",
    "web_authn_aaguid" "uuid",
    "last_webauthn_challenge_data" "jsonb"
);


ALTER TABLE "auth"."mfa_factors" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."mfa_factors" IS 'auth: stores metadata about factors';



COMMENT ON COLUMN "auth"."mfa_factors"."last_webauthn_challenge_data" IS 'Stores the latest WebAuthn challenge data including attestation/assertion for customer verification';



CREATE TABLE IF NOT EXISTS "auth"."oauth_authorizations" (
    "id" "uuid" NOT NULL,
    "authorization_id" "text" NOT NULL,
    "client_id" "uuid" NOT NULL,
    "user_id" "uuid",
    "redirect_uri" "text" NOT NULL,
    "scope" "text" NOT NULL,
    "state" "text",
    "resource" "text",
    "code_challenge" "text",
    "code_challenge_method" "auth"."code_challenge_method",
    "response_type" "auth"."oauth_response_type" DEFAULT 'code'::"auth"."oauth_response_type" NOT NULL,
    "status" "auth"."oauth_authorization_status" DEFAULT 'pending'::"auth"."oauth_authorization_status" NOT NULL,
    "authorization_code" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "expires_at" timestamp with time zone DEFAULT ("now"() + '00:03:00'::interval) NOT NULL,
    "approved_at" timestamp with time zone,
    "nonce" "text",
    CONSTRAINT "oauth_authorizations_authorization_code_length" CHECK (("char_length"("authorization_code") <= 255)),
    CONSTRAINT "oauth_authorizations_code_challenge_length" CHECK (("char_length"("code_challenge") <= 128)),
    CONSTRAINT "oauth_authorizations_expires_at_future" CHECK (("expires_at" > "created_at")),
    CONSTRAINT "oauth_authorizations_nonce_length" CHECK (("char_length"("nonce") <= 255)),
    CONSTRAINT "oauth_authorizations_redirect_uri_length" CHECK (("char_length"("redirect_uri") <= 2048)),
    CONSTRAINT "oauth_authorizations_resource_length" CHECK (("char_length"("resource") <= 2048)),
    CONSTRAINT "oauth_authorizations_scope_length" CHECK (("char_length"("scope") <= 4096)),
    CONSTRAINT "oauth_authorizations_state_length" CHECK (("char_length"("state") <= 4096))
);


ALTER TABLE "auth"."oauth_authorizations" OWNER TO "supabase_auth_admin";


CREATE TABLE IF NOT EXISTS "auth"."oauth_client_states" (
    "id" "uuid" NOT NULL,
    "provider_type" "text" NOT NULL,
    "code_verifier" "text",
    "created_at" timestamp with time zone NOT NULL
);


ALTER TABLE "auth"."oauth_client_states" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."oauth_client_states" IS 'Stores OAuth states for third-party provider authentication flows where Supabase acts as the OAuth client.';



CREATE TABLE IF NOT EXISTS "auth"."oauth_clients" (
    "id" "uuid" NOT NULL,
    "client_secret_hash" "text",
    "registration_type" "auth"."oauth_registration_type" NOT NULL,
    "redirect_uris" "text" NOT NULL,
    "grant_types" "text" NOT NULL,
    "client_name" "text",
    "client_uri" "text",
    "logo_uri" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deleted_at" timestamp with time zone,
    "client_type" "auth"."oauth_client_type" DEFAULT 'confidential'::"auth"."oauth_client_type" NOT NULL,
    "token_endpoint_auth_method" "text" NOT NULL,
    CONSTRAINT "oauth_clients_client_name_length" CHECK (("char_length"("client_name") <= 1024)),
    CONSTRAINT "oauth_clients_client_uri_length" CHECK (("char_length"("client_uri") <= 2048)),
    CONSTRAINT "oauth_clients_logo_uri_length" CHECK (("char_length"("logo_uri") <= 2048)),
    CONSTRAINT "oauth_clients_token_endpoint_auth_method_check" CHECK (("token_endpoint_auth_method" = ANY (ARRAY['client_secret_basic'::"text", 'client_secret_post'::"text", 'none'::"text"])))
);


ALTER TABLE "auth"."oauth_clients" OWNER TO "supabase_auth_admin";


CREATE TABLE IF NOT EXISTS "auth"."oauth_consents" (
    "id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "client_id" "uuid" NOT NULL,
    "scopes" "text" NOT NULL,
    "granted_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "revoked_at" timestamp with time zone,
    CONSTRAINT "oauth_consents_revoked_after_granted" CHECK ((("revoked_at" IS NULL) OR ("revoked_at" >= "granted_at"))),
    CONSTRAINT "oauth_consents_scopes_length" CHECK (("char_length"("scopes") <= 2048)),
    CONSTRAINT "oauth_consents_scopes_not_empty" CHECK (("char_length"(TRIM(BOTH FROM "scopes")) > 0))
);


ALTER TABLE "auth"."oauth_consents" OWNER TO "supabase_auth_admin";


CREATE TABLE IF NOT EXISTS "auth"."one_time_tokens" (
    "id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "token_type" "auth"."one_time_token_type" NOT NULL,
    "token_hash" "text" NOT NULL,
    "relates_to" "text" NOT NULL,
    "created_at" timestamp without time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp without time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "one_time_tokens_token_hash_check" CHECK (("char_length"("token_hash") > 0))
);


ALTER TABLE "auth"."one_time_tokens" OWNER TO "supabase_auth_admin";


CREATE TABLE IF NOT EXISTS "auth"."refresh_tokens" (
    "instance_id" "uuid",
    "id" bigint NOT NULL,
    "token" character varying(255),
    "user_id" character varying(255),
    "revoked" boolean,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "parent" character varying(255),
    "session_id" "uuid"
);


ALTER TABLE "auth"."refresh_tokens" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."refresh_tokens" IS 'Auth: Store of tokens used to refresh JWT tokens once they expire.';



CREATE SEQUENCE IF NOT EXISTS "auth"."refresh_tokens_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "auth"."refresh_tokens_id_seq" OWNER TO "supabase_auth_admin";


ALTER SEQUENCE "auth"."refresh_tokens_id_seq" OWNED BY "auth"."refresh_tokens"."id";



CREATE TABLE IF NOT EXISTS "auth"."saml_providers" (
    "id" "uuid" NOT NULL,
    "sso_provider_id" "uuid" NOT NULL,
    "entity_id" "text" NOT NULL,
    "metadata_xml" "text" NOT NULL,
    "metadata_url" "text",
    "attribute_mapping" "jsonb",
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "name_id_format" "text",
    CONSTRAINT "entity_id not empty" CHECK (("char_length"("entity_id") > 0)),
    CONSTRAINT "metadata_url not empty" CHECK ((("metadata_url" = NULL::"text") OR ("char_length"("metadata_url") > 0))),
    CONSTRAINT "metadata_xml not empty" CHECK (("char_length"("metadata_xml") > 0))
);


ALTER TABLE "auth"."saml_providers" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."saml_providers" IS 'Auth: Manages SAML Identity Provider connections.';



CREATE TABLE IF NOT EXISTS "auth"."saml_relay_states" (
    "id" "uuid" NOT NULL,
    "sso_provider_id" "uuid" NOT NULL,
    "request_id" "text" NOT NULL,
    "for_email" "text",
    "redirect_to" "text",
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "flow_state_id" "uuid",
    CONSTRAINT "request_id not empty" CHECK (("char_length"("request_id") > 0))
);


ALTER TABLE "auth"."saml_relay_states" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."saml_relay_states" IS 'Auth: Contains SAML Relay State information for each Service Provider initiated login.';



CREATE TABLE IF NOT EXISTS "auth"."schema_migrations" (
    "version" character varying(255) NOT NULL
);


ALTER TABLE "auth"."schema_migrations" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."schema_migrations" IS 'Auth: Manages updates to the auth system.';



CREATE TABLE IF NOT EXISTS "auth"."sessions" (
    "id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "factor_id" "uuid",
    "aal" "auth"."aal_level",
    "not_after" timestamp with time zone,
    "refreshed_at" timestamp without time zone,
    "user_agent" "text",
    "ip" "inet",
    "tag" "text",
    "oauth_client_id" "uuid",
    "refresh_token_hmac_key" "text",
    "refresh_token_counter" bigint,
    "scopes" "text",
    CONSTRAINT "sessions_scopes_length" CHECK (("char_length"("scopes") <= 4096))
);


ALTER TABLE "auth"."sessions" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."sessions" IS 'Auth: Stores session data associated to a user.';



COMMENT ON COLUMN "auth"."sessions"."not_after" IS 'Auth: Not after is a nullable column that contains a timestamp after which the session should be regarded as expired.';



COMMENT ON COLUMN "auth"."sessions"."refresh_token_hmac_key" IS 'Holds a HMAC-SHA256 key used to sign refresh tokens for this session.';



COMMENT ON COLUMN "auth"."sessions"."refresh_token_counter" IS 'Holds the ID (counter) of the last issued refresh token.';



CREATE TABLE IF NOT EXISTS "auth"."sso_domains" (
    "id" "uuid" NOT NULL,
    "sso_provider_id" "uuid" NOT NULL,
    "domain" "text" NOT NULL,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    CONSTRAINT "domain not empty" CHECK (("char_length"("domain") > 0))
);


ALTER TABLE "auth"."sso_domains" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."sso_domains" IS 'Auth: Manages SSO email address domain mapping to an SSO Identity Provider.';



CREATE TABLE IF NOT EXISTS "auth"."sso_providers" (
    "id" "uuid" NOT NULL,
    "resource_id" "text",
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "disabled" boolean,
    CONSTRAINT "resource_id not empty" CHECK ((("resource_id" = NULL::"text") OR ("char_length"("resource_id") > 0)))
);


ALTER TABLE "auth"."sso_providers" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."sso_providers" IS 'Auth: Manages SSO identity provider information; see saml_providers for SAML.';



COMMENT ON COLUMN "auth"."sso_providers"."resource_id" IS 'Auth: Uniquely identifies a SSO provider according to a user-chosen resource ID (case insensitive), useful in infrastructure as code.';



CREATE TABLE IF NOT EXISTS "auth"."users" (
    "instance_id" "uuid",
    "id" "uuid" NOT NULL,
    "aud" character varying(255),
    "role" character varying(255),
    "email" character varying(255),
    "encrypted_password" character varying(255),
    "email_confirmed_at" timestamp with time zone,
    "invited_at" timestamp with time zone,
    "confirmation_token" character varying(255),
    "confirmation_sent_at" timestamp with time zone,
    "recovery_token" character varying(255),
    "recovery_sent_at" timestamp with time zone,
    "email_change_token_new" character varying(255),
    "email_change" character varying(255),
    "email_change_sent_at" timestamp with time zone,
    "last_sign_in_at" timestamp with time zone,
    "raw_app_meta_data" "jsonb",
    "raw_user_meta_data" "jsonb",
    "is_super_admin" boolean,
    "created_at" timestamp with time zone,
    "updated_at" timestamp with time zone,
    "phone" "text" DEFAULT NULL::character varying,
    "phone_confirmed_at" timestamp with time zone,
    "phone_change" "text" DEFAULT ''::character varying,
    "phone_change_token" character varying(255) DEFAULT ''::character varying,
    "phone_change_sent_at" timestamp with time zone,
    "confirmed_at" timestamp with time zone GENERATED ALWAYS AS (LEAST("email_confirmed_at", "phone_confirmed_at")) STORED,
    "email_change_token_current" character varying(255) DEFAULT ''::character varying,
    "email_change_confirm_status" smallint DEFAULT 0,
    "banned_until" timestamp with time zone,
    "reauthentication_token" character varying(255) DEFAULT ''::character varying,
    "reauthentication_sent_at" timestamp with time zone,
    "is_sso_user" boolean DEFAULT false NOT NULL,
    "deleted_at" timestamp with time zone,
    "is_anonymous" boolean DEFAULT false NOT NULL,
    CONSTRAINT "users_email_change_confirm_status_check" CHECK ((("email_change_confirm_status" >= 0) AND ("email_change_confirm_status" <= 2)))
);


ALTER TABLE "auth"."users" OWNER TO "supabase_auth_admin";


COMMENT ON TABLE "auth"."users" IS 'Auth: Stores user login data within a secure schema.';



COMMENT ON COLUMN "auth"."users"."is_sso_user" IS 'Auth: Set this column to true when the account comes from SSO. These accounts can have duplicate emails.';



CREATE TABLE IF NOT EXISTS "auth"."webauthn_challenges" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "challenge_type" "text" NOT NULL,
    "session_data" "jsonb" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "expires_at" timestamp with time zone NOT NULL,
    CONSTRAINT "webauthn_challenges_challenge_type_check" CHECK (("challenge_type" = ANY (ARRAY['signup'::"text", 'registration'::"text", 'authentication'::"text"])))
);


ALTER TABLE "auth"."webauthn_challenges" OWNER TO "supabase_auth_admin";


CREATE TABLE IF NOT EXISTS "auth"."webauthn_credentials" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "credential_id" "bytea" NOT NULL,
    "public_key" "bytea" NOT NULL,
    "attestation_type" "text" DEFAULT ''::"text" NOT NULL,
    "aaguid" "uuid",
    "sign_count" bigint DEFAULT 0 NOT NULL,
    "transports" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "backup_eligible" boolean DEFAULT false NOT NULL,
    "backed_up" boolean DEFAULT false NOT NULL,
    "friendly_name" "text" DEFAULT ''::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "last_used_at" timestamp with time zone
);


ALTER TABLE "auth"."webauthn_credentials" OWNER TO "supabase_auth_admin";


CREATE TABLE IF NOT EXISTS "public"."account_details" (
    "profile_id" "uuid" NOT NULL,
    "full_name" "text" NOT NULL,
    "birth_date" "date" NOT NULL,
    "phone_number" "text" NOT NULL,
    "phone_verified_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "guardian_consent_declared_at" timestamp with time zone,
    "guardian_consent_terms_version" "text",
    CONSTRAINT "account_details_birth_date_check" CHECK ((("birth_date" >= '1900-01-01'::"date") AND ("birth_date" <= CURRENT_DATE))),
    CONSTRAINT "account_details_full_name_check" CHECK ((("char_length"("btrim"("full_name")) >= 1) AND ("char_length"("btrim"("full_name")) <= 100))),
    CONSTRAINT "account_details_phone_number_check" CHECK (("phone_number" ~ '^\+?[0-9]{7,15}$'::"text"))
);


ALTER TABLE "public"."account_details" OWNER TO "postgres";


COMMENT ON COLUMN "public"."account_details"."guardian_consent_declared_at" IS 'Time when a minor declared that their legal guardian had consented.';



COMMENT ON COLUMN "public"."account_details"."guardian_consent_terms_version" IS 'Terms version shown when the guardian consent declaration was recorded.';



CREATE TABLE IF NOT EXISTS "public"."account_suspensions" (
    "profile_id" "uuid" NOT NULL,
    "reason" "text",
    "suspended_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "suspended_by" "uuid"
);


ALTER TABLE "public"."account_suspensions" OWNER TO "postgres";


COMMENT ON TABLE "public"."account_suspensions" IS 'Private suspension reasons visible only to the affected user and administrators.';



CREATE TABLE IF NOT EXISTS "public"."adult_content_terms" (
    "term" "text" NOT NULL,
    "is_active" boolean DEFAULT true NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "adult_content_terms_term_check" CHECK ((("char_length"("btrim"("term")) >= 2) AND ("char_length"("btrim"("term")) <= 100)))
);


ALTER TABLE "public"."adult_content_terms" OWNER TO "postgres";


COMMENT ON TABLE "public"."adult_content_terms" IS 'Server-side terms used to identify age-restricted books and posts. Only administrators can access this table.';



CREATE TABLE IF NOT EXISTS "public"."app_admins" (
    "profile_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "public"."app_admins" OWNER TO "postgres";


COMMENT ON TABLE "public"."app_admins" IS 'Server-protected allowlist of profiles permitted to moderate Sharemarium.';



CREATE TABLE IF NOT EXISTS "public"."blocks" (
    "blocker_id" "uuid" NOT NULL,
    "blocked_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "blocks_check" CHECK (("blocker_id" <> "blocked_id"))
);


ALTER TABLE "public"."blocks" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."collections" (
    "profile_id" "uuid" NOT NULL,
    "book_id" "text" NOT NULL,
    "status" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "collections_status_check" CHECK (("status" = ANY (ARRAY['to_read'::"text", 'reading'::"text", 'read'::"text"])))
);


ALTER TABLE "public"."collections" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."contact_requests" (
    "id" bigint NOT NULL,
    "profile_id" "uuid",
    "email" "text" NOT NULL,
    "category" "text" NOT NULL,
    "subject" "text" NOT NULL,
    "message" "text" NOT NULL,
    "status" "text" DEFAULT 'received'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "contact_requests_category_check" CHECK (("category" = ANY (ARRAY['general'::"text", 'privacy'::"text", 'infringement'::"text", 'report'::"text", 'account'::"text", 'other'::"text"]))),
    CONSTRAINT "contact_requests_email_check" CHECK ((("char_length"("email") >= 3) AND ("char_length"("email") <= 320))),
    CONSTRAINT "contact_requests_message_check" CHECK ((("char_length"("message") >= 1) AND ("char_length"("message") <= 4000))),
    CONSTRAINT "contact_requests_status_check" CHECK (("status" = ANY (ARRAY['received'::"text", 'in_progress'::"text", 'closed'::"text"]))),
    CONSTRAINT "contact_requests_subject_check" CHECK ((("char_length"("subject") >= 1) AND ("char_length"("subject") <= 120)))
);


ALTER TABLE "public"."contact_requests" OWNER TO "postgres";


ALTER TABLE "public"."contact_requests" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."contact_requests_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."favorites" (
    "profile_id" "uuid" NOT NULL,
    "book_id" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "public"."favorites" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."follows" (
    "follower_id" "uuid" NOT NULL,
    "following_id" "uuid" NOT NULL,
    "status" "text" NOT NULL,
    "requested_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "responded_at" timestamp with time zone,
    CONSTRAINT "follows_check" CHECK (("follower_id" <> "following_id")),
    CONSTRAINT "follows_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'accepted'::"text"])))
);


ALTER TABLE "public"."follows" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."legal_consents" (
    "id" bigint NOT NULL,
    "profile_id" "uuid" NOT NULL,
    "bundle_version" "text" NOT NULL,
    "terms_version" "text" NOT NULL,
    "privacy_version" "text" NOT NULL,
    "community_guidelines_version" "text" NOT NULL,
    "infringement_policy_version" "text" NOT NULL,
    "external_transmission_version" "text" NOT NULL,
    "auth_provider" "text",
    "accepted_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "public"."legal_consents" OWNER TO "postgres";


ALTER TABLE "public"."legal_consents" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."legal_consents_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."moderation_reports" (
    "id" bigint NOT NULL,
    "reporter_id" "uuid",
    "reported_profile_id" "uuid",
    "post_id" "uuid",
    "category" "text" NOT NULL,
    "details" "text",
    "post_snapshot" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "status" "text" DEFAULT 'open'::"text" NOT NULL,
    "resolution" "text",
    "resolved_by" "uuid",
    "resolved_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "moderation_reports_category_check" CHECK (("category" = ANY (ARRAY['spam'::"text", 'harassment'::"text", 'bullying'::"text", 'offensive'::"text", 'other'::"text"]))),
    CONSTRAINT "moderation_reports_details_check" CHECK ((("details" IS NULL) OR ("char_length"("details") <= 1000))),
    CONSTRAINT "moderation_reports_status_check" CHECK (("status" = ANY (ARRAY['open'::"text", 'resolved'::"text"])))
);


ALTER TABLE "public"."moderation_reports" OWNER TO "postgres";


COMMENT ON TABLE "public"."moderation_reports" IS 'Post reports visible only to allowlisted administrators.';



ALTER TABLE "public"."moderation_reports" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."moderation_reports_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."notifications" (
    "id" bigint NOT NULL,
    "recipient_id" "uuid" NOT NULL,
    "actor_id" "uuid" NOT NULL,
    "type" "text" NOT NULL,
    "post_id" "uuid",
    "read_at" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "notifications_check" CHECK (("recipient_id" <> "actor_id")),
    CONSTRAINT "notifications_check1" CHECK (((("type" = 'reaction'::"text") AND ("post_id" IS NOT NULL)) OR (("type" = ANY (ARRAY['follow'::"text", 'follow_request'::"text"])) AND ("post_id" IS NULL)))),
    CONSTRAINT "notifications_type_check" CHECK (("type" = ANY (ARRAY['reaction'::"text", 'follow'::"text", 'follow_request'::"text"])))
);


ALTER TABLE "public"."notifications" OWNER TO "postgres";


ALTER TABLE "public"."notifications" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."notifications_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."post_reactions" (
    "post_id" "uuid" NOT NULL,
    "profile_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "reaction_type" "text" DEFAULT 'like'::"text" NOT NULL,
    CONSTRAINT "post_reactions_reaction_type_check" CHECK (("reaction_type" = ANY (ARRAY['like'::"text", 'love'::"text", 'sad'::"text"])))
);


ALTER TABLE "public"."post_reactions" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."posts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "profile_id" "uuid" NOT NULL,
    "book_id" "text" NOT NULL,
    "rating" double precision NOT NULL,
    "comment" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "book_title" "text" DEFAULT ''::"text" NOT NULL,
    "book_author" "text" DEFAULT ''::"text" NOT NULL,
    "book_publisher" "text" DEFAULT ''::"text" NOT NULL,
    "book_description" "text" DEFAULT ''::"text" NOT NULL,
    "is_age_restricted" boolean DEFAULT false NOT NULL,
    "is_spoiler" boolean DEFAULT false NOT NULL,
    "edited_at" timestamp with time zone,
    CONSTRAINT "posts_rating_check" CHECK ((("rating" >= (1.0)::double precision) AND ("rating" <= (5.0)::double precision)))
);


ALTER TABLE "public"."posts" OWNER TO "postgres";


COMMENT ON COLUMN "public"."posts"."is_age_restricted" IS 'Set automatically when book metadata or the review matches an active adult-content term.';



COMMENT ON COLUMN "public"."posts"."is_spoiler" IS 'When true, clients conceal the review body from other users until they explicitly reveal it.';



COMMENT ON COLUMN "public"."posts"."edited_at" IS 'Set when the post author edits the review, rating, or spoiler setting.';



CREATE TABLE IF NOT EXISTS "public"."privacy_password_credentials" (
    "profile_id" "uuid" NOT NULL,
    "password_hash" "text" NOT NULL,
    "failed_attempts" smallint DEFAULT 0 NOT NULL,
    "locked_until" timestamp with time zone,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    CONSTRAINT "privacy_password_credentials_failed_attempts_check" CHECK ((("failed_attempts" >= 0) AND ("failed_attempts" <= 20)))
);


ALTER TABLE "public"."privacy_password_credentials" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."privacy_password_recovery_requests" (
    "profile_id" "uuid" NOT NULL,
    "provider" "text" NOT NULL,
    "requested_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL
);


ALTER TABLE "public"."privacy_password_recovery_requests" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "username" "text" NOT NULL,
    "avatar_url" "text",
    "bio" "text",
    "followers_count" integer DEFAULT 0,
    "following_count" integer DEFAULT 0,
    "read_count" integer DEFAULT 0,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "user_id" "text" NOT NULL,
    "is_private" boolean DEFAULT false NOT NULL,
    "is_suspended" boolean DEFAULT false NOT NULL,
    "page_color" "text" DEFAULT 'yellow'::"text" NOT NULL,
    CONSTRAINT "profiles_page_color_check" CHECK (("page_color" = ANY (ARRAY['red'::"text", 'magenta'::"text", 'blue'::"text", 'yellow'::"text", 'green'::"text", 'purple'::"text", 'gray'::"text", 'orange'::"text", 'pink'::"text", 'light_blue'::"text", 'emerald'::"text", 'red_purple'::"text", 'yellow_green'::"text", 'brown'::"text"]))),
    CONSTRAINT "profiles_user_id_format_check" CHECK ((("user_id" = "lower"("user_id")) AND ("user_id" ~ '^[a-z0-9_]{3,20}$'::"text")))
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


COMMENT ON COLUMN "public"."profiles"."is_private" IS 'When true, posts, collections and favorites are hidden from everyone except the owner.';



CREATE TABLE IF NOT EXISTS "storage"."buckets" (
    "id" "text" NOT NULL,
    "name" "text" NOT NULL,
    "owner" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "public" boolean DEFAULT false,
    "avif_autodetection" boolean DEFAULT false,
    "file_size_limit" bigint,
    "allowed_mime_types" "text"[],
    "owner_id" "text",
    "type" "storage"."buckettype" DEFAULT 'STANDARD'::"storage"."buckettype" NOT NULL
);


ALTER TABLE "storage"."buckets" OWNER TO "supabase_storage_admin";


COMMENT ON COLUMN "storage"."buckets"."owner" IS 'Field is deprecated, use owner_id instead';



CREATE TABLE IF NOT EXISTS "storage"."buckets_analytics" (
    "name" "text" NOT NULL,
    "type" "storage"."buckettype" DEFAULT 'ANALYTICS'::"storage"."buckettype" NOT NULL,
    "format" "text" DEFAULT 'ICEBERG'::"text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "deleted_at" timestamp with time zone
);


ALTER TABLE "storage"."buckets_analytics" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."buckets_vectors" (
    "id" "text" NOT NULL,
    "type" "storage"."buckettype" DEFAULT 'VECTOR'::"storage"."buckettype" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "storage"."buckets_vectors" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."iceberg_namespaces" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "bucket_name" "text" NOT NULL,
    "name" "text" NOT NULL COLLATE "pg_catalog"."C",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "metadata" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "catalog_id" "uuid" NOT NULL
);


ALTER TABLE "storage"."iceberg_namespaces" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."iceberg_tables" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "namespace_id" "uuid" NOT NULL,
    "bucket_name" "text" NOT NULL,
    "name" "text" NOT NULL COLLATE "pg_catalog"."C",
    "location" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "remote_table_id" "text",
    "shard_key" "text",
    "shard_id" "text",
    "catalog_id" "uuid" NOT NULL
);


ALTER TABLE "storage"."iceberg_tables" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."migrations" (
    "id" integer NOT NULL,
    "name" character varying(100) NOT NULL,
    "hash" character varying(40) NOT NULL,
    "executed_at" timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE "storage"."migrations" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."objects" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "bucket_id" "text",
    "name" "text",
    "owner" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "last_accessed_at" timestamp with time zone DEFAULT "now"(),
    "metadata" "jsonb",
    "path_tokens" "text"[] GENERATED ALWAYS AS ("string_to_array"("name", '/'::"text")) STORED,
    "version" "text",
    "owner_id" "text",
    "user_metadata" "jsonb"
);


ALTER TABLE "storage"."objects" OWNER TO "supabase_storage_admin";


COMMENT ON COLUMN "storage"."objects"."owner" IS 'Field is deprecated, use owner_id instead';



CREATE TABLE IF NOT EXISTS "storage"."s3_multipart_uploads" (
    "id" "text" NOT NULL,
    "in_progress_size" bigint DEFAULT 0 NOT NULL,
    "upload_signature" "text" NOT NULL,
    "bucket_id" "text" NOT NULL,
    "key" "text" NOT NULL COLLATE "pg_catalog"."C",
    "version" "text" NOT NULL,
    "owner_id" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "user_metadata" "jsonb",
    "metadata" "jsonb"
);


ALTER TABLE "storage"."s3_multipart_uploads" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."s3_multipart_uploads_parts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "upload_id" "text" NOT NULL,
    "size" bigint DEFAULT 0 NOT NULL,
    "part_number" integer NOT NULL,
    "bucket_id" "text" NOT NULL,
    "key" "text" NOT NULL COLLATE "pg_catalog"."C",
    "etag" "text" NOT NULL,
    "owner_id" "text",
    "version" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "storage"."s3_multipart_uploads_parts" OWNER TO "supabase_storage_admin";


CREATE TABLE IF NOT EXISTS "storage"."vector_indexes" (
    "id" "text" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL COLLATE "pg_catalog"."C",
    "bucket_id" "text" NOT NULL,
    "data_type" "text" NOT NULL,
    "dimension" integer NOT NULL,
    "distance_metric" "text" NOT NULL,
    "metadata_configuration" "jsonb",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "storage"."vector_indexes" OWNER TO "supabase_storage_admin";


ALTER TABLE ONLY "auth"."refresh_tokens" ALTER COLUMN "id" SET DEFAULT "nextval"('"auth"."refresh_tokens_id_seq"'::"regclass");



ALTER TABLE ONLY "auth"."mfa_amr_claims"
    ADD CONSTRAINT "amr_id_pk" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."audit_log_entries"
    ADD CONSTRAINT "audit_log_entries_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."custom_oauth_providers"
    ADD CONSTRAINT "custom_oauth_providers_identifier_key" UNIQUE ("identifier");



ALTER TABLE ONLY "auth"."custom_oauth_providers"
    ADD CONSTRAINT "custom_oauth_providers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."flow_state"
    ADD CONSTRAINT "flow_state_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."identities"
    ADD CONSTRAINT "identities_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."identities"
    ADD CONSTRAINT "identities_provider_id_provider_unique" UNIQUE ("provider_id", "provider");



ALTER TABLE ONLY "auth"."instances"
    ADD CONSTRAINT "instances_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."mfa_amr_claims"
    ADD CONSTRAINT "mfa_amr_claims_session_id_authentication_method_pkey" UNIQUE ("session_id", "authentication_method");



ALTER TABLE ONLY "auth"."mfa_challenges"
    ADD CONSTRAINT "mfa_challenges_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."mfa_factors"
    ADD CONSTRAINT "mfa_factors_last_challenged_at_key" UNIQUE ("last_challenged_at");



ALTER TABLE ONLY "auth"."mfa_factors"
    ADD CONSTRAINT "mfa_factors_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."oauth_authorizations"
    ADD CONSTRAINT "oauth_authorizations_authorization_code_key" UNIQUE ("authorization_code");



ALTER TABLE ONLY "auth"."oauth_authorizations"
    ADD CONSTRAINT "oauth_authorizations_authorization_id_key" UNIQUE ("authorization_id");



ALTER TABLE ONLY "auth"."oauth_authorizations"
    ADD CONSTRAINT "oauth_authorizations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."oauth_client_states"
    ADD CONSTRAINT "oauth_client_states_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."oauth_clients"
    ADD CONSTRAINT "oauth_clients_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."oauth_consents"
    ADD CONSTRAINT "oauth_consents_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."oauth_consents"
    ADD CONSTRAINT "oauth_consents_user_client_unique" UNIQUE ("user_id", "client_id");



ALTER TABLE ONLY "auth"."one_time_tokens"
    ADD CONSTRAINT "one_time_tokens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."refresh_tokens"
    ADD CONSTRAINT "refresh_tokens_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."refresh_tokens"
    ADD CONSTRAINT "refresh_tokens_token_unique" UNIQUE ("token");



ALTER TABLE ONLY "auth"."saml_providers"
    ADD CONSTRAINT "saml_providers_entity_id_key" UNIQUE ("entity_id");



ALTER TABLE ONLY "auth"."saml_providers"
    ADD CONSTRAINT "saml_providers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."saml_relay_states"
    ADD CONSTRAINT "saml_relay_states_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."schema_migrations"
    ADD CONSTRAINT "schema_migrations_pkey" PRIMARY KEY ("version");



ALTER TABLE ONLY "auth"."sessions"
    ADD CONSTRAINT "sessions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."sso_domains"
    ADD CONSTRAINT "sso_domains_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."sso_providers"
    ADD CONSTRAINT "sso_providers_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."users"
    ADD CONSTRAINT "users_phone_key" UNIQUE ("phone");



ALTER TABLE ONLY "auth"."users"
    ADD CONSTRAINT "users_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."webauthn_challenges"
    ADD CONSTRAINT "webauthn_challenges_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "auth"."webauthn_credentials"
    ADD CONSTRAINT "webauthn_credentials_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."account_details"
    ADD CONSTRAINT "account_details_pkey" PRIMARY KEY ("profile_id");



ALTER TABLE ONLY "public"."account_suspensions"
    ADD CONSTRAINT "account_suspensions_pkey" PRIMARY KEY ("profile_id");



ALTER TABLE ONLY "public"."adult_content_terms"
    ADD CONSTRAINT "adult_content_terms_pkey" PRIMARY KEY ("term");



ALTER TABLE ONLY "public"."app_admins"
    ADD CONSTRAINT "app_admins_pkey" PRIMARY KEY ("profile_id");



ALTER TABLE ONLY "public"."blocks"
    ADD CONSTRAINT "blocks_pkey" PRIMARY KEY ("blocker_id", "blocked_id");



ALTER TABLE ONLY "public"."collections"
    ADD CONSTRAINT "collections_pkey" PRIMARY KEY ("profile_id", "book_id");



ALTER TABLE ONLY "public"."contact_requests"
    ADD CONSTRAINT "contact_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."favorites"
    ADD CONSTRAINT "favorites_pkey" PRIMARY KEY ("profile_id", "book_id");



ALTER TABLE ONLY "public"."follows"
    ADD CONSTRAINT "follows_pkey" PRIMARY KEY ("follower_id", "following_id");



ALTER TABLE ONLY "public"."legal_consents"
    ADD CONSTRAINT "legal_consents_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."legal_consents"
    ADD CONSTRAINT "legal_consents_profile_id_bundle_version_key" UNIQUE ("profile_id", "bundle_version");



ALTER TABLE ONLY "public"."moderation_reports"
    ADD CONSTRAINT "moderation_reports_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."post_reactions"
    ADD CONSTRAINT "post_reactions_pkey" PRIMARY KEY ("post_id", "profile_id");



ALTER TABLE ONLY "public"."posts"
    ADD CONSTRAINT "posts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."privacy_password_credentials"
    ADD CONSTRAINT "privacy_password_credentials_pkey" PRIMARY KEY ("profile_id");



ALTER TABLE ONLY "public"."privacy_password_recovery_requests"
    ADD CONSTRAINT "privacy_password_recovery_requests_pkey" PRIMARY KEY ("profile_id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."buckets_analytics"
    ADD CONSTRAINT "buckets_analytics_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."buckets"
    ADD CONSTRAINT "buckets_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."buckets_vectors"
    ADD CONSTRAINT "buckets_vectors_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."iceberg_namespaces"
    ADD CONSTRAINT "iceberg_namespaces_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."iceberg_tables"
    ADD CONSTRAINT "iceberg_tables_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."migrations"
    ADD CONSTRAINT "migrations_name_key" UNIQUE ("name");



ALTER TABLE ONLY "storage"."migrations"
    ADD CONSTRAINT "migrations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."objects"
    ADD CONSTRAINT "objects_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."s3_multipart_uploads_parts"
    ADD CONSTRAINT "s3_multipart_uploads_parts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."s3_multipart_uploads"
    ADD CONSTRAINT "s3_multipart_uploads_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "storage"."vector_indexes"
    ADD CONSTRAINT "vector_indexes_pkey" PRIMARY KEY ("id");



CREATE INDEX "audit_logs_instance_id_idx" ON "auth"."audit_log_entries" USING "btree" ("instance_id");



CREATE UNIQUE INDEX "confirmation_token_idx" ON "auth"."users" USING "btree" ("confirmation_token") WHERE (("confirmation_token")::"text" !~ '^[0-9 ]*$'::"text");



CREATE INDEX "custom_oauth_providers_created_at_idx" ON "auth"."custom_oauth_providers" USING "btree" ("created_at");



CREATE INDEX "custom_oauth_providers_enabled_idx" ON "auth"."custom_oauth_providers" USING "btree" ("enabled");



CREATE INDEX "custom_oauth_providers_identifier_idx" ON "auth"."custom_oauth_providers" USING "btree" ("identifier");



CREATE INDEX "custom_oauth_providers_provider_type_idx" ON "auth"."custom_oauth_providers" USING "btree" ("provider_type");



CREATE UNIQUE INDEX "email_change_token_current_idx" ON "auth"."users" USING "btree" ("email_change_token_current") WHERE (("email_change_token_current")::"text" !~ '^[0-9 ]*$'::"text");



CREATE UNIQUE INDEX "email_change_token_new_idx" ON "auth"."users" USING "btree" ("email_change_token_new") WHERE (("email_change_token_new")::"text" !~ '^[0-9 ]*$'::"text");



CREATE INDEX "factor_id_created_at_idx" ON "auth"."mfa_factors" USING "btree" ("user_id", "created_at");



CREATE INDEX "flow_state_created_at_idx" ON "auth"."flow_state" USING "btree" ("created_at" DESC);



CREATE INDEX "identities_email_idx" ON "auth"."identities" USING "btree" ("email" "text_pattern_ops");



COMMENT ON INDEX "auth"."identities_email_idx" IS 'Auth: Ensures indexed queries on the email column';



CREATE INDEX "identities_user_id_idx" ON "auth"."identities" USING "btree" ("user_id");



CREATE INDEX "idx_auth_code" ON "auth"."flow_state" USING "btree" ("auth_code");



CREATE INDEX "idx_oauth_client_states_created_at" ON "auth"."oauth_client_states" USING "btree" ("created_at");



CREATE INDEX "idx_user_id_auth_method" ON "auth"."flow_state" USING "btree" ("user_id", "authentication_method");



CREATE INDEX "mfa_challenge_created_at_idx" ON "auth"."mfa_challenges" USING "btree" ("created_at" DESC);



CREATE UNIQUE INDEX "mfa_factors_user_friendly_name_unique" ON "auth"."mfa_factors" USING "btree" ("friendly_name", "user_id") WHERE (TRIM(BOTH FROM "friendly_name") <> ''::"text");



CREATE INDEX "mfa_factors_user_id_idx" ON "auth"."mfa_factors" USING "btree" ("user_id");



CREATE INDEX "oauth_auth_pending_exp_idx" ON "auth"."oauth_authorizations" USING "btree" ("expires_at") WHERE ("status" = 'pending'::"auth"."oauth_authorization_status");



CREATE INDEX "oauth_clients_deleted_at_idx" ON "auth"."oauth_clients" USING "btree" ("deleted_at");



CREATE INDEX "oauth_consents_active_client_idx" ON "auth"."oauth_consents" USING "btree" ("client_id") WHERE ("revoked_at" IS NULL);



CREATE INDEX "oauth_consents_active_user_client_idx" ON "auth"."oauth_consents" USING "btree" ("user_id", "client_id") WHERE ("revoked_at" IS NULL);



CREATE INDEX "oauth_consents_user_order_idx" ON "auth"."oauth_consents" USING "btree" ("user_id", "granted_at" DESC);



CREATE INDEX "one_time_tokens_relates_to_hash_idx" ON "auth"."one_time_tokens" USING "hash" ("relates_to");



CREATE INDEX "one_time_tokens_token_hash_hash_idx" ON "auth"."one_time_tokens" USING "hash" ("token_hash");



CREATE UNIQUE INDEX "one_time_tokens_user_id_token_type_key" ON "auth"."one_time_tokens" USING "btree" ("user_id", "token_type");



CREATE UNIQUE INDEX "reauthentication_token_idx" ON "auth"."users" USING "btree" ("reauthentication_token") WHERE (("reauthentication_token")::"text" !~ '^[0-9 ]*$'::"text");



CREATE UNIQUE INDEX "recovery_token_idx" ON "auth"."users" USING "btree" ("recovery_token") WHERE (("recovery_token")::"text" !~ '^[0-9 ]*$'::"text");



CREATE INDEX "refresh_tokens_instance_id_idx" ON "auth"."refresh_tokens" USING "btree" ("instance_id");



CREATE INDEX "refresh_tokens_instance_id_user_id_idx" ON "auth"."refresh_tokens" USING "btree" ("instance_id", "user_id");



CREATE INDEX "refresh_tokens_parent_idx" ON "auth"."refresh_tokens" USING "btree" ("parent");



CREATE INDEX "refresh_tokens_session_id_revoked_idx" ON "auth"."refresh_tokens" USING "btree" ("session_id", "revoked");



CREATE INDEX "refresh_tokens_updated_at_idx" ON "auth"."refresh_tokens" USING "btree" ("updated_at" DESC);



CREATE INDEX "saml_providers_sso_provider_id_idx" ON "auth"."saml_providers" USING "btree" ("sso_provider_id");



CREATE INDEX "saml_relay_states_created_at_idx" ON "auth"."saml_relay_states" USING "btree" ("created_at" DESC);



CREATE INDEX "saml_relay_states_for_email_idx" ON "auth"."saml_relay_states" USING "btree" ("for_email");



CREATE INDEX "saml_relay_states_sso_provider_id_idx" ON "auth"."saml_relay_states" USING "btree" ("sso_provider_id");



CREATE INDEX "sessions_not_after_idx" ON "auth"."sessions" USING "btree" ("not_after" DESC);



CREATE INDEX "sessions_oauth_client_id_idx" ON "auth"."sessions" USING "btree" ("oauth_client_id");



CREATE INDEX "sessions_user_id_idx" ON "auth"."sessions" USING "btree" ("user_id");



CREATE UNIQUE INDEX "sso_domains_domain_idx" ON "auth"."sso_domains" USING "btree" ("lower"("domain"));



CREATE INDEX "sso_domains_sso_provider_id_idx" ON "auth"."sso_domains" USING "btree" ("sso_provider_id");



CREATE UNIQUE INDEX "sso_providers_resource_id_idx" ON "auth"."sso_providers" USING "btree" ("lower"("resource_id"));



CREATE INDEX "sso_providers_resource_id_pattern_idx" ON "auth"."sso_providers" USING "btree" ("resource_id" "text_pattern_ops");



CREATE UNIQUE INDEX "unique_phone_factor_per_user" ON "auth"."mfa_factors" USING "btree" ("user_id", "phone");



CREATE INDEX "user_id_created_at_idx" ON "auth"."sessions" USING "btree" ("user_id", "created_at");



CREATE UNIQUE INDEX "users_email_partial_key" ON "auth"."users" USING "btree" ("email") WHERE ("is_sso_user" = false);



COMMENT ON INDEX "auth"."users_email_partial_key" IS 'Auth: A partial unique index that applies only when is_sso_user is false';



CREATE INDEX "users_instance_id_email_idx" ON "auth"."users" USING "btree" ("instance_id", "lower"(("email")::"text"));



CREATE INDEX "users_instance_id_idx" ON "auth"."users" USING "btree" ("instance_id");



CREATE INDEX "users_is_anonymous_idx" ON "auth"."users" USING "btree" ("is_anonymous");



CREATE INDEX "webauthn_challenges_expires_at_idx" ON "auth"."webauthn_challenges" USING "btree" ("expires_at");



CREATE INDEX "webauthn_challenges_user_id_idx" ON "auth"."webauthn_challenges" USING "btree" ("user_id");



CREATE UNIQUE INDEX "webauthn_credentials_credential_id_key" ON "auth"."webauthn_credentials" USING "btree" ("credential_id");



CREATE INDEX "webauthn_credentials_user_id_idx" ON "auth"."webauthn_credentials" USING "btree" ("user_id");



CREATE INDEX "blocks_blocked_idx" ON "public"."blocks" USING "btree" ("blocked_id");



CREATE INDEX "contact_requests_anonymous_email_created_at_idx" ON "public"."contact_requests" USING "btree" ("lower"("btrim"("email")), "created_at" DESC) WHERE ("profile_id" IS NULL);



CREATE INDEX "contact_requests_profile_created_at_idx" ON "public"."contact_requests" USING "btree" ("profile_id", "created_at" DESC) WHERE ("profile_id" IS NOT NULL);



CREATE INDEX "follows_follower_status_idx" ON "public"."follows" USING "btree" ("follower_id", "status");



CREATE INDEX "follows_following_status_idx" ON "public"."follows" USING "btree" ("following_id", "status");



CREATE UNIQUE INDEX "moderation_reports_open_unique" ON "public"."moderation_reports" USING "btree" ("reporter_id", "post_id") WHERE (("status" = 'open'::"text") AND ("post_id" IS NOT NULL));



CREATE INDEX "moderation_reports_profile_idx" ON "public"."moderation_reports" USING "btree" ("reported_profile_id", "created_at" DESC);



CREATE INDEX "moderation_reports_status_created_idx" ON "public"."moderation_reports" USING "btree" ("status", "created_at" DESC);



CREATE INDEX "notifications_recipient_created_idx" ON "public"."notifications" USING "btree" ("recipient_id", "created_at" DESC);



CREATE INDEX "notifications_recipient_unread_idx" ON "public"."notifications" USING "btree" ("recipient_id", "created_at" DESC) WHERE ("read_at" IS NULL);



CREATE INDEX "post_reactions_post_idx" ON "public"."post_reactions" USING "btree" ("post_id");



CREATE INDEX "posts_age_restricted_idx" ON "public"."posts" USING "btree" ("is_age_restricted") WHERE ("is_age_restricted" = true);



CREATE INDEX "posts_profile_book_created_at_idx" ON "public"."posts" USING "btree" ("profile_id", "book_id", "created_at" DESC);



CREATE INDEX "posts_profile_created_at_idx" ON "public"."posts" USING "btree" ("profile_id", "created_at" DESC);



CREATE UNIQUE INDEX "profiles_user_id_lower_unique" ON "public"."profiles" USING "btree" ("lower"("user_id"));



CREATE UNIQUE INDEX "bname" ON "storage"."buckets" USING "btree" ("name");



CREATE UNIQUE INDEX "bucketid_objname" ON "storage"."objects" USING "btree" ("bucket_id", "name");



CREATE UNIQUE INDEX "buckets_analytics_unique_name_idx" ON "storage"."buckets_analytics" USING "btree" ("name") WHERE ("deleted_at" IS NULL);



CREATE UNIQUE INDEX "idx_iceberg_namespaces_bucket_id" ON "storage"."iceberg_namespaces" USING "btree" ("catalog_id", "name");



CREATE UNIQUE INDEX "idx_iceberg_tables_location" ON "storage"."iceberg_tables" USING "btree" ("location");



CREATE UNIQUE INDEX "idx_iceberg_tables_namespace_id" ON "storage"."iceberg_tables" USING "btree" ("catalog_id", "namespace_id", "name");



CREATE INDEX "idx_multipart_uploads_list" ON "storage"."s3_multipart_uploads" USING "btree" ("bucket_id", "key", "created_at");



CREATE INDEX "idx_objects_bucket_id_name" ON "storage"."objects" USING "btree" ("bucket_id", "name" COLLATE "C");



CREATE INDEX "idx_objects_bucket_id_name_lower" ON "storage"."objects" USING "btree" ("bucket_id", "lower"("name") COLLATE "C");



CREATE INDEX "name_prefix_search" ON "storage"."objects" USING "btree" ("name" "text_pattern_ops");



CREATE UNIQUE INDEX "vector_indexes_name_bucket_id_idx" ON "storage"."vector_indexes" USING "btree" ("name", "bucket_id");



CREATE OR REPLACE TRIGGER "record_denial_before_auth_user_delete" BEFORE DELETE ON "auth"."users" FOR EACH ROW EXECUTE FUNCTION "private"."record_denial_before_auth_user_delete"();



CREATE OR REPLACE TRIGGER "classify_post_age_restriction_trigger" BEFORE INSERT OR UPDATE OF "book_title", "book_author", "book_publisher", "book_description", "comment" ON "public"."posts" FOR EACH ROW EXECUTE FUNCTION "public"."classify_post_age_restriction"();



CREATE OR REPLACE TRIGGER "enforce_contact_request_rate_limit_before_insert" BEFORE INSERT ON "public"."contact_requests" FOR EACH ROW EXECUTE FUNCTION "private"."enforce_contact_request_rate_limit"();



CREATE OR REPLACE TRIGGER "enforce_favorites_limit_before_insert" BEFORE INSERT ON "public"."favorites" FOR EACH ROW EXECUTE FUNCTION "public"."enforce_favorites_limit"();



CREATE OR REPLACE TRIGGER "enforce_profile_user_id_immutability_trigger" BEFORE UPDATE OF "user_id" ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."enforce_profile_user_id_immutability"();



CREATE OR REPLACE TRIGGER "follows_create_notification" AFTER INSERT ON "public"."follows" FOR EACH ROW EXECUTE FUNCTION "public"."create_follow_notification"();



CREATE OR REPLACE TRIGGER "follows_update_counts" AFTER INSERT OR DELETE OR UPDATE ON "public"."follows" FOR EACH ROW EXECUTE FUNCTION "public"."update_follow_counts"();



CREATE OR REPLACE TRIGGER "prevent_duplicate_book_post_before_insert" BEFORE INSERT ON "public"."posts" FOR EACH ROW EXECUTE FUNCTION "public"."prevent_duplicate_book_post"();



CREATE OR REPLACE TRIGGER "protect_post_identity_before_update" BEFORE UPDATE ON "public"."posts" FOR EACH ROW EXECUTE FUNCTION "public"."protect_post_identity_on_update"();



CREATE OR REPLACE TRIGGER "reactions_create_notification" AFTER INSERT ON "public"."post_reactions" FOR EACH ROW EXECUTE FUNCTION "public"."create_reaction_notification"();



CREATE OR REPLACE TRIGGER "remove_favorite_after_post_delete_trigger" AFTER DELETE ON "public"."posts" FOR EACH ROW EXECUTE FUNCTION "public"."remove_favorite_after_post_delete"();



CREATE OR REPLACE TRIGGER "sync_bookshelf_after_post_change_trigger" AFTER INSERT OR DELETE ON "public"."posts" FOR EACH ROW EXECUTE FUNCTION "public"."sync_bookshelf_after_post_change"();



CREATE OR REPLACE TRIGGER "sync_profile_to_auth_metadata_trigger" AFTER INSERT OR UPDATE OF "username", "user_id" ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."sync_profile_to_auth_metadata"();



CREATE OR REPLACE TRIGGER "enforce_bucket_name_length_trigger" BEFORE INSERT OR UPDATE OF "name" ON "storage"."buckets" FOR EACH ROW EXECUTE FUNCTION "storage"."enforce_bucket_name_length"();



CREATE OR REPLACE TRIGGER "protect_buckets_delete" BEFORE DELETE ON "storage"."buckets" FOR EACH STATEMENT EXECUTE FUNCTION "storage"."protect_delete"();



CREATE OR REPLACE TRIGGER "protect_objects_delete" BEFORE DELETE ON "storage"."objects" FOR EACH STATEMENT EXECUTE FUNCTION "storage"."protect_delete"();



CREATE OR REPLACE TRIGGER "update_objects_updated_at" BEFORE UPDATE ON "storage"."objects" FOR EACH ROW EXECUTE FUNCTION "storage"."update_updated_at_column"();



ALTER TABLE ONLY "auth"."identities"
    ADD CONSTRAINT "identities_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."mfa_amr_claims"
    ADD CONSTRAINT "mfa_amr_claims_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "auth"."sessions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."mfa_challenges"
    ADD CONSTRAINT "mfa_challenges_auth_factor_id_fkey" FOREIGN KEY ("factor_id") REFERENCES "auth"."mfa_factors"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."mfa_factors"
    ADD CONSTRAINT "mfa_factors_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."oauth_authorizations"
    ADD CONSTRAINT "oauth_authorizations_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "auth"."oauth_clients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."oauth_authorizations"
    ADD CONSTRAINT "oauth_authorizations_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."oauth_consents"
    ADD CONSTRAINT "oauth_consents_client_id_fkey" FOREIGN KEY ("client_id") REFERENCES "auth"."oauth_clients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."oauth_consents"
    ADD CONSTRAINT "oauth_consents_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."one_time_tokens"
    ADD CONSTRAINT "one_time_tokens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."refresh_tokens"
    ADD CONSTRAINT "refresh_tokens_session_id_fkey" FOREIGN KEY ("session_id") REFERENCES "auth"."sessions"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."saml_providers"
    ADD CONSTRAINT "saml_providers_sso_provider_id_fkey" FOREIGN KEY ("sso_provider_id") REFERENCES "auth"."sso_providers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."saml_relay_states"
    ADD CONSTRAINT "saml_relay_states_flow_state_id_fkey" FOREIGN KEY ("flow_state_id") REFERENCES "auth"."flow_state"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."saml_relay_states"
    ADD CONSTRAINT "saml_relay_states_sso_provider_id_fkey" FOREIGN KEY ("sso_provider_id") REFERENCES "auth"."sso_providers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."sessions"
    ADD CONSTRAINT "sessions_oauth_client_id_fkey" FOREIGN KEY ("oauth_client_id") REFERENCES "auth"."oauth_clients"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."sessions"
    ADD CONSTRAINT "sessions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."sso_domains"
    ADD CONSTRAINT "sso_domains_sso_provider_id_fkey" FOREIGN KEY ("sso_provider_id") REFERENCES "auth"."sso_providers"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."webauthn_challenges"
    ADD CONSTRAINT "webauthn_challenges_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "auth"."webauthn_credentials"
    ADD CONSTRAINT "webauthn_credentials_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."account_details"
    ADD CONSTRAINT "account_details_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."account_suspensions"
    ADD CONSTRAINT "account_suspensions_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."account_suspensions"
    ADD CONSTRAINT "account_suspensions_suspended_by_fkey" FOREIGN KEY ("suspended_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."app_admins"
    ADD CONSTRAINT "app_admins_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."blocks"
    ADD CONSTRAINT "blocks_blocked_id_fkey" FOREIGN KEY ("blocked_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."blocks"
    ADD CONSTRAINT "blocks_blocker_id_fkey" FOREIGN KEY ("blocker_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."collections"
    ADD CONSTRAINT "collections_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."contact_requests"
    ADD CONSTRAINT "contact_requests_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."favorites"
    ADD CONSTRAINT "favorites_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."follows"
    ADD CONSTRAINT "follows_follower_id_fkey" FOREIGN KEY ("follower_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."follows"
    ADD CONSTRAINT "follows_following_id_fkey" FOREIGN KEY ("following_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."legal_consents"
    ADD CONSTRAINT "legal_consents_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."moderation_reports"
    ADD CONSTRAINT "moderation_reports_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "public"."posts"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."moderation_reports"
    ADD CONSTRAINT "moderation_reports_reported_profile_id_fkey" FOREIGN KEY ("reported_profile_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."moderation_reports"
    ADD CONSTRAINT "moderation_reports_reporter_id_fkey" FOREIGN KEY ("reporter_id") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."moderation_reports"
    ADD CONSTRAINT "moderation_reports_resolved_by_fkey" FOREIGN KEY ("resolved_by") REFERENCES "public"."profiles"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_actor_id_fkey" FOREIGN KEY ("actor_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "public"."posts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_recipient_id_fkey" FOREIGN KEY ("recipient_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."post_reactions"
    ADD CONSTRAINT "post_reactions_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "public"."posts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."post_reactions"
    ADD CONSTRAINT "post_reactions_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."posts"
    ADD CONSTRAINT "posts_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."privacy_password_credentials"
    ADD CONSTRAINT "privacy_password_credentials_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."privacy_password_recovery_requests"
    ADD CONSTRAINT "privacy_password_recovery_requests_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_auth_user_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE NOT VALID;



ALTER TABLE ONLY "storage"."iceberg_namespaces"
    ADD CONSTRAINT "iceberg_namespaces_catalog_id_fkey" FOREIGN KEY ("catalog_id") REFERENCES "storage"."buckets_analytics"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "storage"."iceberg_tables"
    ADD CONSTRAINT "iceberg_tables_catalog_id_fkey" FOREIGN KEY ("catalog_id") REFERENCES "storage"."buckets_analytics"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "storage"."iceberg_tables"
    ADD CONSTRAINT "iceberg_tables_namespace_id_fkey" FOREIGN KEY ("namespace_id") REFERENCES "storage"."iceberg_namespaces"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "storage"."objects"
    ADD CONSTRAINT "objects_bucketId_fkey" FOREIGN KEY ("bucket_id") REFERENCES "storage"."buckets"("id");



ALTER TABLE ONLY "storage"."s3_multipart_uploads"
    ADD CONSTRAINT "s3_multipart_uploads_bucket_id_fkey" FOREIGN KEY ("bucket_id") REFERENCES "storage"."buckets"("id");



ALTER TABLE ONLY "storage"."s3_multipart_uploads_parts"
    ADD CONSTRAINT "s3_multipart_uploads_parts_bucket_id_fkey" FOREIGN KEY ("bucket_id") REFERENCES "storage"."buckets"("id");



ALTER TABLE ONLY "storage"."s3_multipart_uploads_parts"
    ADD CONSTRAINT "s3_multipart_uploads_parts_upload_id_fkey" FOREIGN KEY ("upload_id") REFERENCES "storage"."s3_multipart_uploads"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "storage"."vector_indexes"
    ADD CONSTRAINT "vector_indexes_bucket_id_fkey" FOREIGN KEY ("bucket_id") REFERENCES "storage"."buckets_vectors"("id");



ALTER TABLE "auth"."audit_log_entries" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."flow_state" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."identities" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."instances" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."mfa_amr_claims" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."mfa_challenges" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."mfa_factors" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."one_time_tokens" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."refresh_tokens" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."saml_providers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."saml_relay_states" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."schema_migrations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."sessions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."sso_domains" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."sso_providers" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "auth"."users" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "Administrators can manage adult content terms" ON "public"."adult_content_terms" TO "authenticated" USING ("public"."is_current_user_admin"()) WITH CHECK ("public"."is_current_user_admin"());



CREATE POLICY "Administrators can read reports" ON "public"."moderation_reports" FOR SELECT TO "authenticated" USING ("public"."is_current_user_admin"());



CREATE POLICY "Allow authenticated users to insert posts" ON "public"."posts" FOR INSERT TO "authenticated" WITH CHECK ((("auth"."uid"() = "profile_id") AND "public"."is_profile_active"("auth"."uid"()) AND ("char_length"("btrim"("book_title")) > 0) AND (("is_age_restricted" = false) OR "public"."current_user_is_adult"())));



CREATE POLICY "Allow authenticated users to insert/delete collections" ON "public"."collections" TO "authenticated" USING ((("auth"."uid"() = "profile_id") AND "public"."is_profile_active"("auth"."uid"()))) WITH CHECK ((("auth"."uid"() = "profile_id") AND "public"."is_profile_active"("auth"."uid"())));



CREATE POLICY "Allow authenticated users to insert/delete favorites" ON "public"."favorites" TO "authenticated" USING ((("auth"."uid"() = "profile_id") AND "public"."is_profile_active"("auth"."uid"()))) WITH CHECK ((("auth"."uid"() = "profile_id") AND "public"."is_profile_active"("auth"."uid"())));



CREATE POLICY "Allow public read access for profiles" ON "public"."profiles" FOR SELECT USING (true);



CREATE POLICY "Allow users to insert their own profile" ON "public"."profiles" FOR INSERT WITH CHECK (("auth"."uid"() = "id"));



CREATE POLICY "Allow users to update their own profile" ON "public"."profiles" FOR UPDATE TO "authenticated" USING ((("auth"."uid"() = "id") AND "public"."is_profile_active"("auth"."uid"()))) WITH CHECK ((("auth"."uid"() = "id") AND "public"."is_profile_active"("auth"."uid"())));



CREATE POLICY "Allow visible profile collections to be read" ON "public"."collections" FOR SELECT USING ("public"."can_view_profile_content"("profile_id"));



CREATE POLICY "Allow visible profile favorites to be read" ON "public"."favorites" FOR SELECT USING ("public"."can_view_profile_content"("profile_id"));



CREATE POLICY "Allow visible profile posts to be read" ON "public"."posts" FOR SELECT USING (("public"."can_view_profile_content"("profile_id") AND (("is_age_restricted" = false) OR "public"."current_user_can_view_age_restricted"())));



CREATE POLICY "Anyone can submit a contact request" ON "public"."contact_requests" FOR INSERT TO "authenticated", "anon" WITH CHECK ((("status" = 'received'::"text") AND (("profile_id" IS NULL) OR ("auth"."uid"() = "profile_id"))));



CREATE POLICY "Users and administrators can read suspensions" ON "public"."account_suspensions" FOR SELECT TO "authenticated" USING ((("auth"."uid"() = "profile_id") OR "public"."is_current_user_admin"()));



CREATE POLICY "Users can add their own reactions" ON "public"."post_reactions" FOR INSERT TO "authenticated" WITH CHECK ((("auth"."uid"() = "profile_id") AND "public"."is_profile_active"("auth"."uid"()) AND (EXISTS ( SELECT 1
   FROM "public"."posts"
  WHERE (("posts"."id" = "post_reactions"."post_id") AND ("posts"."profile_id" <> "auth"."uid"()) AND "public"."can_view_profile_content"("posts"."profile_id"))))));



CREATE POLICY "Users can delete their own posts" ON "public"."posts" FOR DELETE TO "authenticated" USING ((("auth"."uid"() = "profile_id") AND "public"."is_profile_active"("auth"."uid"())));



CREATE POLICY "Users can insert their own account details" ON "public"."account_details" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "profile_id"));



CREATE POLICY "Users can insert their own legal consents" ON "public"."legal_consents" FOR INSERT WITH CHECK (("auth"."uid"() = "profile_id"));



CREATE POLICY "Users can mark their notifications read" ON "public"."notifications" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "recipient_id")) WITH CHECK (("auth"."uid"() = "recipient_id"));



CREATE POLICY "Users can read their notifications" ON "public"."notifications" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "recipient_id"));



CREATE POLICY "Users can read their own account details" ON "public"."account_details" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "profile_id"));



CREATE POLICY "Users can read their own legal consents" ON "public"."legal_consents" FOR SELECT USING (("auth"."uid"() = "profile_id"));



CREATE POLICY "Users can remove their own reactions" ON "public"."post_reactions" FOR DELETE TO "authenticated" USING ((("auth"."uid"() = "profile_id") AND "public"."is_profile_active"("auth"."uid"())));



CREATE POLICY "Users can update their own posts" ON "public"."posts" FOR UPDATE TO "authenticated" USING (("auth"."uid"() = "profile_id")) WITH CHECK (("auth"."uid"() = "profile_id"));



CREATE POLICY "Users can update their own reactions" ON "public"."post_reactions" FOR UPDATE TO "authenticated" USING ((("auth"."uid"() = "profile_id") AND "public"."is_profile_active"("auth"."uid"()))) WITH CHECK ((("auth"."uid"() = "profile_id") AND "public"."is_profile_active"("auth"."uid"()) AND (EXISTS ( SELECT 1
   FROM "public"."posts"
  WHERE (("posts"."id" = "post_reactions"."post_id") AND ("posts"."profile_id" <> "auth"."uid"()) AND "public"."can_view_profile_content"("posts"."profile_id"))))));



CREATE POLICY "Users can view blocks they created" ON "public"."blocks" FOR SELECT TO "authenticated" USING (("auth"."uid"() = "blocker_id"));



CREATE POLICY "Users can view their follow relationships" ON "public"."follows" FOR SELECT TO "authenticated" USING ((("auth"."uid"() = "follower_id") OR ("auth"."uid"() = "following_id")));



CREATE POLICY "Visible reactions can be read" ON "public"."post_reactions" FOR SELECT USING ((EXISTS ( SELECT 1
   FROM "public"."posts"
  WHERE (("posts"."id" = "post_reactions"."post_id") AND "public"."can_view_profile_content"("posts"."profile_id")))));



ALTER TABLE "public"."account_details" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."account_suspensions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."adult_content_terms" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."app_admins" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."blocks" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."collections" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."contact_requests" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."favorites" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."follows" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."legal_consents" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."moderation_reports" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."notifications" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."post_reactions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."posts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."privacy_password_credentials" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."privacy_password_recovery_requests" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "Public profile avatars are readable" ON "storage"."objects" FOR SELECT USING (("bucket_id" = 'avatars'::"text"));



CREATE POLICY "Users can delete their own profile avatar" ON "storage"."objects" FOR DELETE TO "authenticated" USING ((("bucket_id" = 'avatars'::"text") AND (("storage"."foldername"("name"))[1] = ("auth"."uid"())::"text")));



CREATE POLICY "Users can update their own profile avatar" ON "storage"."objects" FOR UPDATE TO "authenticated" USING ((("bucket_id" = 'avatars'::"text") AND (("storage"."foldername"("name"))[1] = ("auth"."uid"())::"text"))) WITH CHECK ((("bucket_id" = 'avatars'::"text") AND (("storage"."foldername"("name"))[1] = ("auth"."uid"())::"text")));



CREATE POLICY "Users can upload their own profile avatar" ON "storage"."objects" FOR INSERT TO "authenticated" WITH CHECK ((("bucket_id" = 'avatars'::"text") AND (("storage"."foldername"("name"))[1] = ("auth"."uid"())::"text")));



ALTER TABLE "storage"."buckets" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."buckets_analytics" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."buckets_vectors" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."iceberg_namespaces" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."iceberg_tables" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."migrations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."objects" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."s3_multipart_uploads" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."s3_multipart_uploads_parts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "storage"."vector_indexes" ENABLE ROW LEVEL SECURITY;


GRANT USAGE ON SCHEMA "auth" TO "anon";
GRANT USAGE ON SCHEMA "auth" TO "authenticated";
GRANT USAGE ON SCHEMA "auth" TO "service_role";
GRANT ALL ON SCHEMA "auth" TO "supabase_auth_admin";
GRANT ALL ON SCHEMA "auth" TO "dashboard_user";
GRANT USAGE ON SCHEMA "auth" TO "postgres";



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT USAGE ON SCHEMA "storage" TO "postgres" WITH GRANT OPTION;
GRANT USAGE ON SCHEMA "storage" TO "anon";
GRANT USAGE ON SCHEMA "storage" TO "authenticated";
GRANT USAGE ON SCHEMA "storage" TO "service_role";
GRANT ALL ON SCHEMA "storage" TO "supabase_storage_admin" WITH GRANT OPTION;
GRANT ALL ON SCHEMA "storage" TO "dashboard_user";



GRANT ALL ON FUNCTION "auth"."email"() TO "dashboard_user";



GRANT ALL ON FUNCTION "auth"."jwt"() TO "postgres";
GRANT ALL ON FUNCTION "auth"."jwt"() TO "dashboard_user";



GRANT ALL ON FUNCTION "auth"."role"() TO "dashboard_user";



GRANT ALL ON FUNCTION "auth"."uid"() TO "dashboard_user";



GRANT ALL ON FUNCTION "graphql_public"."graphql"("operationName" "text", "query" "text", "variables" "jsonb", "extensions" "jsonb") TO "postgres";
GRANT ALL ON FUNCTION "graphql_public"."graphql"("operationName" "text", "query" "text", "variables" "jsonb", "extensions" "jsonb") TO "anon";
GRANT ALL ON FUNCTION "graphql_public"."graphql"("operationName" "text", "query" "text", "variables" "jsonb", "extensions" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "graphql_public"."graphql"("operationName" "text", "query" "text", "variables" "jsonb", "extensions" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_delete_reported_post"("target_report" bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_delete_reported_post"("target_report" bigint) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_resolve_report"("target_report" bigint, "resolution_note" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_resolve_report"("target_report" bigint, "resolution_note" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."admin_set_account_suspension"("target_profile" "uuid", "suspend" boolean, "reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_set_account_suspension"("target_profile" "uuid", "suspend" boolean, "reason" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."begin_privacy_password_recovery"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."begin_privacy_password_recovery"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."block_profile"("target_profile" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."block_profile"("target_profile" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."can_view_profile_content"("owner_profile" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."can_view_profile_content"("owner_profile" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."can_view_profile_content"("owner_profile" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."cancel_admin_account_deletion_record"("denial_record" "uuid", "deleting_admin" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cancel_admin_account_deletion_record"("denial_record" "uuid", "deleting_admin" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."cancel_self_account_deletion"("target_profile" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cancel_self_account_deletion"("target_profile" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."change_privacy_password"("p_current_password" "text", "p_new_password" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."change_privacy_password"("p_current_password" "text", "p_new_password" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."complete_registration"("p_full_name" "text", "p_birth_date" "date", "p_phone_number" "text", "p_username" "text", "p_user_id" "text", "p_privacy_password" "text", "p_guardian_consent" boolean, "p_terms_version" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."complete_registration"("p_full_name" "text", "p_birth_date" "date", "p_phone_number" "text", "p_username" "text", "p_user_id" "text", "p_privacy_password" "text", "p_guardian_consent" boolean, "p_terms_version" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."create_follow_notification"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."create_reaction_notification"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."current_user_can_view_age_restricted"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."current_user_can_view_age_restricted"() TO "anon";
GRANT ALL ON FUNCTION "public"."current_user_can_view_age_restricted"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."current_user_is_adult"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."current_user_is_adult"() TO "anon";
GRANT ALL ON FUNCTION "public"."current_user_is_adult"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."declare_guardian_consent"("p_terms_version" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."declare_guardian_consent"("p_terms_version" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."enforce_profile_user_id_immutability"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."get_profile_follow_list"("target_profile" "uuid", "list_type" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_profile_follow_list"("target_profile" "uuid", "list_type" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."has_privacy_password"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."has_privacy_password"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."initialize_privacy_password"("p_password" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."initialize_privacy_password"("p_password" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."is_blocked_between"("first_profile" "uuid", "second_profile" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_blocked_between"("first_profile" "uuid", "second_profile" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_blocked_between"("first_profile" "uuid", "second_profile" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."is_current_user_admin"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_current_user_admin"() TO "authenticated";



REVOKE ALL ON FUNCTION "public"."is_profile_active"("profile" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_profile_active"("profile" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."is_profile_active"("profile" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."is_valid_privacy_password"("candidate" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."matches_adult_content_terms"("book_title" "text", "book_author" "text", "book_publisher" "text", "book_description" "text", "post_comment" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."normalize_content_filter_text"("source" "text") FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."prepare_self_account_deletion"("target_profile" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."prepare_self_account_deletion"("target_profile" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."prevent_duplicate_book_post"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."record_admin_account_deletion"("target_profile" "uuid", "deleting_admin" "uuid", "deletion_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."record_admin_account_deletion"("target_profile" "uuid", "deleting_admin" "uuid", "deletion_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."remove_favorite_after_post_delete"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."request_follow"("target_profile" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."request_follow"("target_profile" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."reset_privacy_password_after_reauthentication"("p_new_password" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."reset_privacy_password_after_reauthentication"("p_new_password" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."respond_follow_request"("requester_profile" "uuid", "approve" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."respond_follow_request"("requester_profile" "uuid", "approve" boolean) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."search_profiles_by_public_identity"("search_query" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."search_profiles_by_public_identity"("search_query" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."submit_post_report"("target_post" "uuid", "report_category" "text", "report_details" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."submit_post_report"("target_post" "uuid", "report_category" "text", "report_details" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."sync_bookshelf_after_post_change"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."sync_profile_to_auth_metadata"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."unblock_profile"("target_profile" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."unblock_profile"("target_profile" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."unfollow_profile"("target_profile" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."unfollow_profile"("target_profile" "uuid") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."update_follow_counts"() FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."update_private_account_details"("p_password" "text", "p_full_name" "text", "p_birth_date" "date", "p_phone_number" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_private_account_details"("p_password" "text", "p_full_name" "text", "p_birth_date" "date", "p_phone_number" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."update_profile_page_color"("p_page_color" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_profile_page_color"("p_page_color" "text") TO "authenticated";



REVOKE ALL ON FUNCTION "public"."update_public_profile"("p_username" "text", "p_user_id" "text", "p_is_private" boolean) FROM PUBLIC;



REVOKE ALL ON FUNCTION "public"."update_public_profile"("p_username" "text", "p_user_id" "text", "p_bio" "text", "p_is_private" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_public_profile"("p_username" "text", "p_user_id" "text", "p_bio" "text", "p_is_private" boolean) TO "authenticated";



REVOKE ALL ON FUNCTION "public"."verify_privacy_password"("p_password" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."verify_privacy_password"("p_password" "text") TO "authenticated";



GRANT ALL ON TABLE "auth"."audit_log_entries" TO "dashboard_user";
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."audit_log_entries" TO "postgres";
GRANT SELECT ON TABLE "auth"."audit_log_entries" TO "postgres" WITH GRANT OPTION;



GRANT ALL ON TABLE "auth"."custom_oauth_providers" TO "postgres";
GRANT ALL ON TABLE "auth"."custom_oauth_providers" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."flow_state" TO "postgres";
GRANT SELECT ON TABLE "auth"."flow_state" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."flow_state" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."identities" TO "postgres";
GRANT SELECT ON TABLE "auth"."identities" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."identities" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."instances" TO "dashboard_user";
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."instances" TO "postgres";
GRANT SELECT ON TABLE "auth"."instances" TO "postgres" WITH GRANT OPTION;



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."mfa_amr_claims" TO "postgres";
GRANT SELECT ON TABLE "auth"."mfa_amr_claims" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."mfa_amr_claims" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."mfa_challenges" TO "postgres";
GRANT SELECT ON TABLE "auth"."mfa_challenges" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."mfa_challenges" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."mfa_factors" TO "postgres";
GRANT SELECT ON TABLE "auth"."mfa_factors" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."mfa_factors" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."oauth_authorizations" TO "postgres";
GRANT ALL ON TABLE "auth"."oauth_authorizations" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."oauth_client_states" TO "postgres";
GRANT ALL ON TABLE "auth"."oauth_client_states" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."oauth_clients" TO "postgres";
GRANT ALL ON TABLE "auth"."oauth_clients" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."oauth_consents" TO "postgres";
GRANT ALL ON TABLE "auth"."oauth_consents" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."one_time_tokens" TO "postgres";
GRANT SELECT ON TABLE "auth"."one_time_tokens" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."one_time_tokens" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."refresh_tokens" TO "dashboard_user";
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."refresh_tokens" TO "postgres";
GRANT SELECT ON TABLE "auth"."refresh_tokens" TO "postgres" WITH GRANT OPTION;



GRANT ALL ON SEQUENCE "auth"."refresh_tokens_id_seq" TO "dashboard_user";
GRANT ALL ON SEQUENCE "auth"."refresh_tokens_id_seq" TO "postgres";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."saml_providers" TO "postgres";
GRANT SELECT ON TABLE "auth"."saml_providers" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."saml_providers" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."saml_relay_states" TO "postgres";
GRANT SELECT ON TABLE "auth"."saml_relay_states" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."saml_relay_states" TO "dashboard_user";



GRANT SELECT ON TABLE "auth"."schema_migrations" TO "postgres" WITH GRANT OPTION;



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."sessions" TO "postgres";
GRANT SELECT ON TABLE "auth"."sessions" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."sessions" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."sso_domains" TO "postgres";
GRANT SELECT ON TABLE "auth"."sso_domains" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."sso_domains" TO "dashboard_user";



GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."sso_providers" TO "postgres";
GRANT SELECT ON TABLE "auth"."sso_providers" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "auth"."sso_providers" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."users" TO "dashboard_user";
GRANT INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "auth"."users" TO "postgres";
GRANT SELECT ON TABLE "auth"."users" TO "postgres" WITH GRANT OPTION;



GRANT ALL ON TABLE "auth"."webauthn_challenges" TO "postgres";
GRANT ALL ON TABLE "auth"."webauthn_challenges" TO "dashboard_user";



GRANT ALL ON TABLE "auth"."webauthn_credentials" TO "postgres";
GRANT ALL ON TABLE "auth"."webauthn_credentials" TO "dashboard_user";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."account_details" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "public"."account_details" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."account_details" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."account_suspensions" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."account_suspensions" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."account_suspensions" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."adult_content_terms" TO "anon";
GRANT ALL ON TABLE "public"."adult_content_terms" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."adult_content_terms" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."app_admins" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."app_admins" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."app_admins" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."blocks" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."blocks" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."blocks" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."collections" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."collections" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."collections" TO "service_role";



GRANT INSERT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."contact_requests" TO "anon";
GRANT INSERT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."contact_requests" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."contact_requests" TO "service_role";



GRANT ALL ON SEQUENCE "public"."contact_requests_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."contact_requests_id_seq" TO "authenticated";
GRANT UPDATE ON SEQUENCE "public"."contact_requests_id_seq" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."favorites" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."favorites" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."favorites" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."follows" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."follows" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."follows" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."legal_consents" TO "anon";
GRANT SELECT,INSERT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."legal_consents" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."legal_consents" TO "service_role";



GRANT UPDATE ON SEQUENCE "public"."legal_consents_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."legal_consents_id_seq" TO "authenticated";
GRANT UPDATE ON SEQUENCE "public"."legal_consents_id_seq" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."moderation_reports" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."moderation_reports" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."moderation_reports" TO "service_role";



GRANT UPDATE ON SEQUENCE "public"."moderation_reports_id_seq" TO "anon";
GRANT UPDATE ON SEQUENCE "public"."moderation_reports_id_seq" TO "authenticated";
GRANT UPDATE ON SEQUENCE "public"."moderation_reports_id_seq" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."notifications" TO "anon";
GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN,UPDATE ON TABLE "public"."notifications" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."notifications" TO "service_role";



GRANT UPDATE ON SEQUENCE "public"."notifications_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."notifications_id_seq" TO "authenticated";
GRANT UPDATE ON SEQUENCE "public"."notifications_id_seq" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."post_reactions" TO "anon";
GRANT ALL ON TABLE "public"."post_reactions" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."post_reactions" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."posts" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."posts" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."posts" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."privacy_password_credentials" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."privacy_password_recovery_requests" TO "service_role";



GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."profiles" TO "anon";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."profiles" TO "authenticated";
GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "public"."profiles" TO "service_role";



GRANT UPDATE("username") ON TABLE "public"."profiles" TO "authenticated";



GRANT UPDATE("avatar_url") ON TABLE "public"."profiles" TO "authenticated";



GRANT UPDATE("bio") ON TABLE "public"."profiles" TO "authenticated";



GRANT UPDATE("is_private") ON TABLE "public"."profiles" TO "authenticated";



GRANT ALL ON TABLE "storage"."buckets" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "storage"."buckets" TO "service_role";
GRANT ALL ON TABLE "storage"."buckets" TO "authenticated";
GRANT ALL ON TABLE "storage"."buckets" TO "anon";



GRANT ALL ON TABLE "storage"."buckets_analytics" TO "service_role";
GRANT ALL ON TABLE "storage"."buckets_analytics" TO "authenticated";
GRANT ALL ON TABLE "storage"."buckets_analytics" TO "anon";



GRANT SELECT ON TABLE "storage"."buckets_vectors" TO "service_role";
GRANT SELECT ON TABLE "storage"."buckets_vectors" TO "authenticated";
GRANT SELECT ON TABLE "storage"."buckets_vectors" TO "anon";



GRANT ALL ON TABLE "storage"."iceberg_namespaces" TO "service_role";
GRANT SELECT ON TABLE "storage"."iceberg_namespaces" TO "authenticated";
GRANT SELECT ON TABLE "storage"."iceberg_namespaces" TO "anon";



GRANT ALL ON TABLE "storage"."iceberg_tables" TO "service_role";
GRANT SELECT ON TABLE "storage"."iceberg_tables" TO "authenticated";
GRANT SELECT ON TABLE "storage"."iceberg_tables" TO "anon";



GRANT ALL ON TABLE "storage"."objects" TO "postgres" WITH GRANT OPTION;
GRANT ALL ON TABLE "storage"."objects" TO "service_role";
GRANT ALL ON TABLE "storage"."objects" TO "authenticated";
GRANT ALL ON TABLE "storage"."objects" TO "anon";



GRANT ALL ON TABLE "storage"."s3_multipart_uploads" TO "service_role";
GRANT SELECT ON TABLE "storage"."s3_multipart_uploads" TO "authenticated";
GRANT SELECT ON TABLE "storage"."s3_multipart_uploads" TO "anon";



GRANT ALL ON TABLE "storage"."s3_multipart_uploads_parts" TO "service_role";
GRANT SELECT ON TABLE "storage"."s3_multipart_uploads_parts" TO "authenticated";
GRANT SELECT ON TABLE "storage"."s3_multipart_uploads_parts" TO "anon";



GRANT SELECT ON TABLE "storage"."vector_indexes" TO "service_role";
GRANT SELECT ON TABLE "storage"."vector_indexes" TO "authenticated";
GRANT SELECT ON TABLE "storage"."vector_indexes" TO "anon";



ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_auth_admin" IN SCHEMA "auth" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_auth_admin" IN SCHEMA "auth" GRANT ALL ON SEQUENCES TO "dashboard_user";



ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_auth_admin" IN SCHEMA "auth" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_auth_admin" IN SCHEMA "auth" GRANT ALL ON FUNCTIONS TO "dashboard_user";



ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_auth_admin" IN SCHEMA "auth" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "supabase_auth_admin" IN SCHEMA "auth" GRANT ALL ON TABLES TO "dashboard_user";












ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT UPDATE ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT UPDATE ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT UPDATE ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON SEQUENCES TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON FUNCTIONS TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "storage" GRANT ALL ON TABLES TO "service_role";




