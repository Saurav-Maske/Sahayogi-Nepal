import { createClient } from "npm:@supabase/supabase-js@2";
import { GoogleAuth } from "npm:google-auth-library@9";

interface Notification {
  id: string
  profile_id: string
  type: string
  title: string | null
  body: string
  data: Record<string, unknown> | null
}

interface WebhookPayload {
  type: 'INSERT'
  table: string
  record: Notification
  schema: 'public'
}

const APP_NAME = 'Sahayogi Nepal'

// The Firebase service-account JSON lives in a secret, not in the repo:
//   supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat service-account.json)"
const serviceAccount = JSON.parse(Deno.env.get('FIREBASE_SERVICE_ACCOUNT') ?? '{}')

// Triggered by a Database Webhook (INSERT on public.notifications), which authenticates with a secret key.
// Deploy with `verify_jwt = false`.
export default {
  fetch: withSupabase({ auth: 'secret' }, async (req, ctx) => {
    if (!serviceAccount.client_email || !serviceAccount.private_key || !serviceAccount.project_id) {
      console.error('push: FIREBASE_SERVICE_ACCOUNT secret is missing or incomplete')
      return Response.json({ error: 'push_not_configured' }, { status: 500 })
    }

    const payload: WebhookPayload = await req.json()
    if (payload.type !== 'INSERT' || payload.table !== 'notifications') {
      return Response.json({ skipped: true })
    }
    const n = payload.record

    // Every device the user has signed in on.
    const { data: tokens, error } = await ctx.supabaseAdmin
      .from('device_tokens')
      .select('id, token')
      .eq('profile_id', n.profile_id)
    if (error) {
      console.error('push: could not load device tokens:', error.message)
      return Response.json({ error: 'lookup_failed' }, { status: 500 })
    }
    if (!tokens?.length) return Response.json({ sent: 0, reason: 'no_devices' })

    // FCM data values must all be strings.
    const dataPayload: Record<string, string> = {
      notification_id: n.id,
      type: n.type ?? 'general',
    }
    for (const [k, v] of Object.entries(n.data ?? {})) {
      dataPayload[k] = typeof v === 'string' ? v : JSON.stringify(v)
    }

    const accessToken = await getAccessToken(serviceAccount.client_email, serviceAccount.private_key)
    const url = `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`

    const results = await Promise.all(
      tokens.map(async (t: { id: string; token: string }) => {
        const res = await fetch(url, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${accessToken}`,
          },
          body: JSON.stringify({
            message: {
              token: t.token,
              notification: { title: n.title ?? APP_NAME, body: n.body },
              data: dataPayload,
              android: { priority: 'high' },
            },
          }),
        })
        if (res.ok) return { id: t.id, ok: true, dead: false, status: res.status, code: null as string | null }

        const body = await res.json().catch(() => ({}))
        const code: string | null =
          body?.error?.details?.find((d: { errorCode?: string }) => d.errorCode)?.errorCode ??
          body?.error?.status ??
          null
        // UNREGISTERED means the app was uninstalled or the token expired: safe to delete.
        return { id: t.id, ok: false, dead: code === 'UNREGISTERED', status: res.status, code }
      })
    )

    const dead = results.filter((r) => r.dead).map((r) => r.id)
    if (dead.length) {
      await ctx.supabaseAdmin.from('device_tokens').delete().in('id', dead)
    }

    const failed = results.filter((r) => !r.ok && !r.dead)
    for (const f of failed) console.error('push: send failed', { device_token_id: f.id, status: f.status, code: f.code })

    const sent = results.filter((r) => r.ok).length
    const summary = { sent, removed: dead.length, failed: failed.length }
    // If nothing was delivered because of real errors, report it so the webhook shows a failure.
    return Response.json(summary, { status: sent === 0 && failed.length > 0 ? 502 : 200 })
  }),
}

const getAccessToken = async (clientEmail: string, privateKey: string): Promise<string> => {
  const jwtClient = new JWT({
    email: clientEmail,
    key: privateKey,
    scopes: ['https://www.googleapis.com/auth/firebase.messaging'],
  })
  const { access_token } = await jwtClient.authorize()
  if (!access_token) throw new Error('Could not get a Google access token')
  return access_token
}