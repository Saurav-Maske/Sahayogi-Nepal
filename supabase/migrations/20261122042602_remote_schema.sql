SET local check_function_bodies = off;

SELECT cron.unschedule('purge-auth-attempts');

SELECT cron.unschedule('purge-email-otps');

SELECT cron.unschedule('purge-push-outbox');

SELECT cron.unschedule('push-escalations');

DROP TRIGGER "push_new_offer_ins" ON "public"."assignments";

DROP TRIGGER "push_new_offer_released" ON "public"."assignments";

ALTER TABLE "public"."auth_attempts"
  DROP CONSTRAINT "auth_attempts_kind_check";

ALTER TABLE "public"."push_outbox"
  DROP CONSTRAINT "push_outbox_assignment_id_fkey";

ALTER TABLE "public"."push_outbox"
  DROP CONSTRAINT "push_outbox_request_id_fkey";

DROP FUNCTION "public"."_push_enqueue_escalations"();

DROP FUNCTION "public"."_push_enqueue_offers"();

DROP FUNCTION "public"."_push_enqueue_released"();

DROP FUNCTION "public"."_push_kick"();

DROP FUNCTION "public"."_push_purge"();

DROP FUNCTION "public"."_push_tick"();

DROP FUNCTION "public"."purge_email_otps"();

DROP FUNCTION "public"."push_claim_batch"(integer);

DROP FUNCTION "public"."push_recipients"(uuid, text);

DROP FUNCTION "public"."revoke_user_sessions"(uuid);

ALTER TABLE "public"."volunteer_applications"
  DROP COLUMN "email_verified_at";

DROP TABLE "public"."push_outbox";

DROP EXTENSION "pg_net";

ALTER TABLE "public"."audit_hash_checkpoints"
  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.append_audit_log (
  p_action    text,
  p_actor_id  uuid,
  p_entity    text,
  p_entity_id uuid  DEFAULT NULL::uuid,
  p_detail    jsonb DEFAULT NULL::jsonb
)
  RETURNS bigint
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public', 'extensions'
  AS $function$
declare
  v_id bigint;
begin
  perform pg_advisory_xact_lock(hashtext('public.audit_logs_hash_chain'));

  insert into public.audit_logs (action, actor_id, entity, entity_id, detail)
  values (p_action, p_actor_id, p_entity, p_entity_id, p_detail)
  returning id into v_id;

  return v_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.audit_row_hash (
  p_prev      text,
  p_action    text,
  p_actor     uuid,
  p_entity    text,
  p_entity_id uuid,
  p_detail    jsonb,
  p_date      timestamp with time zone
)
  RETURNS text
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO 'public', 'extensions'
  AS $function$
  select encode(digest(
    json_build_array(
      p_prev,
      coalesce(p_action, ''),
      coalesce(p_actor::text, ''),
      coalesce(p_entity, ''),
      coalesce(p_entity_id::text, ''),
      coalesce(p_detail::text, ''),
      to_char(p_date at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"')
    )::text,
    'sha256'), 'hex');
$function$;

CREATE OR REPLACE FUNCTION public.auto_assign_request_district_id()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public', 'extensions'
  AS $function$
BEGIN
  IF NEW.location IS NOT NULL THEN
    SELECT d.id
    INTO NEW.district_id
    FROM public.districts d
    WHERE d.geom IS NOT NULL
      AND ST_Covers(d.geom, ST_SetSRID(NEW.location::geometry, 4326))
    LIMIT 1;
  ELSE
    NEW.district_id := NULL;
  END IF;

  RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_audit_logs_append_only()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO 'public'
  AS $function$
begin
  raise exception 'audit_logs is append-only (% is forbidden)', tg_op;
end;
$function$;

CREATE OR REPLACE FUNCTION public.fn_audit_logs_hash_chain()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO 'public', 'extensions'
  AS $function$
declare
  v_prev text;
begin
  perform pg_advisory_xact_lock(hashtext('public.audit_logs_hash_chain'));

  select l.hash_value into v_prev
    from public.audit_logs l
   order by l.id desc
   limit 1;

  v_prev := coalesce(v_prev, repeat('0', 64));

  new.date := coalesce(new.date, now());
  new.prev_hash := v_prev;  -- always overwrite whatever the caller sent
  new.hash_value := public.audit_row_hash(
    v_prev, new.action, new.actor_id, new.entity, new.entity_id, new.detail, new.date
  );
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.purge_auth_attempts()
  RETURNS void
  LANGUAGE sql
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
  delete from auth_attempts where created_at < now() - interval '2 days';
$function$;

CREATE OR REPLACE FUNCTION public.verify_audit_chain()
  RETURNS TABLE (
    broken_id bigint,
    reason    text
  )
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public', 'extensions'
  AS $function$
declare
  r record;
  v_prev text := repeat('0', 64);
begin
  for r in select * from public.audit_logs order by id loop
    if r.prev_hash is distinct from v_prev then
      broken_id := r.id; reason := 'prev_hash does not match previous row';
      return next; return;
    end if;
    if r.hash_value is distinct from public.audit_row_hash(
         r.prev_hash, r.action, r.actor_id, r.entity, r.entity_id, r.detail, r.date) then
      broken_id := r.id; reason := 'row contents do not match hash_value';
      return next; return;
    end if;
    v_prev := r.hash_value;
  end loop;
end;
$function$;

ALTER TABLE "public"."auth_attempts"
  ADD CONSTRAINT "auth_attempts_kind_check" CHECK ((kind = ANY (ARRAY['login'::text, 'reset'::text, 'apply'::text, 'upload'::text])));

ALTER TABLE "public"."email_otps"
  ADD CONSTRAINT "email_otps_email_check" CHECK ((email = lower(email)));

