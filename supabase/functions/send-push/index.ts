// Edge Function: envía notificaciones push (FCM HTTP v1) disparadas por Database Webhooks.
// Despliegue: supabase functions deploy send-push --no-verify-jwt
// Secrets:    supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat service-account.json)" WEBHOOK_SECRET=<clave-larga>
// Webhooks (Dashboard > Database > Webhooks), con header x-webhook-secret = WEBHOOK_SECRET:
//   live_requests -> Insert, Update      panic_events -> Insert      patrol_reports -> Insert
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SignJWT, importPKCS8 } from "https://deno.land/x/jose@v5.2.0/index.ts";

const sa = JSON.parse(Deno.env.get("FIREBASE_SERVICE_ACCOUNT")!);
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

async function getAccessToken(): Promise<string> {
  const key = await importPKCS8(sa.private_key, "RS256");
  const jwt = await new SignJWT({ scope: "https://www.googleapis.com/auth/firebase.messaging" })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(sa.client_email)
    .setSubject(sa.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt()
    .setExpirationTime("1h")
    .sign(key);
  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: jwt }),
  });
  const j = await r.json();
  if (!j.access_token) throw new Error("OAuth FCM: " + JSON.stringify(j));
  return j.access_token;
}

async function push(accessToken: string, token: string, title: string, body: string, data: Record<string, string>) {
  const r = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
    method: "POST",
    headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      message: {
        token,
        notification: { title, body },
        data,
        android: { priority: "HIGH", notification: { channel_id: "access_alerts", sound: "default" } },
        apns: { headers: { "apns-priority": "10" }, payload: { aps: { sound: "default" } } },
      },
    }),
  });
  if (!r.ok) {
    const t = await r.text();
    // Token vencido o app desinstalada: lo limpiamos
    if (t.includes("UNREGISTERED") || t.includes("INVALID_ARGUMENT")) {
      await db.from("profiles").update({ fcm_token: null }).eq("fcm_token", token);
    }
    return false;
  }
  return true;
}

Deno.serve(async (req) => {
  if (req.headers.get("x-webhook-secret") !== Deno.env.get("WEBHOOK_SECRET")) {
    return new Response("forbidden", { status: 403 });
  }
  const p = await req.json();
  const rec = p.record ?? {};
  const old = p.old_record ?? {};

  let tokens: string[] = [];
  let title = "";
  let body = "";
  const data: Record<string, string> = {};

  if (p.table === "live_requests" && p.type === "INSERT") {
    const { data: lot } = await db.from("lots").select("code").eq("id", rec.lot_id).single();
    const { data: owners } = await db
      .from("lot_owners")
      .select("profiles(fcm_token, active)")
      .eq("lot_id", rec.lot_id);
    tokens = (owners ?? [])
      .map((o: any) => o.profiles)
      .filter((pr: any) => pr?.active && pr?.fcm_token)
      .map((pr: any) => pr.fcm_token);
    title = "Visita en portería";
    body = `${rec.visitor_name} solicita ingresar a ${lot?.code ?? "tu lote"}`;
    data.type = "live_request";
    data.id = rec.id;
  } else if (p.table === "live_requests" && p.type === "UPDATE" && rec.status !== old.status && rec.status !== "pending") {
    const { data: g } = await db.from("profiles").select("fcm_token, active").eq("id", rec.guard_id).single();
    if (g?.active && g?.fcm_token) tokens = [g.fcm_token];
    title = rec.status === "authorized" ? "Propietario autorizó" : "Propietario rechazó";
    body = rec.visitor_name;
    data.type = "live_response";
    data.id = rec.id;
  } else if (p.table === "panic_events" && p.type === "INSERT") {
    const { data: staff } = await db
      .from("profiles")
      .select("id, fcm_token")
      .eq("country_id", rec.country_id)
      .in("role", ["admin", "guard"])
      .eq("active", true)
      .not("fcm_token", "is", null);
    tokens = (staff ?? []).filter((s: any) => s.id !== rec.guard_id).map((s: any) => s.fcm_token);
    title = "⚠ ALERTA DE PÁNICO";
    body = "Un guardia activó el botón de pánico";
    data.type = "panic";
    data.id = rec.id;
  } else if (p.table === "patrol_reports" && p.type === "INSERT" && rec.kind === "incident") {
    const { data: g } = await db.from("profiles").select("full_name").eq("id", rec.guard_id).single();
    const { data: staff } = await db
      .from("profiles")
      .select("fcm_token")
      .eq("country_id", rec.country_id)
      .eq("role", "admin")
      .eq("active", true)
      .not("fcm_token", "is", null);
    tokens = (staff ?? []).map((s: any) => s.fcm_token);
    title = "Novedad en ronda";
    body = `${g?.full_name ?? "Guardia"}: ${String(rec.description ?? "").slice(0, 120)}`;
    data.type = "patrol";
    data.id = rec.id;
  } else {
    return new Response(JSON.stringify({ sent: 0 }), { status: 200 });
  }

  tokens = [...new Set(tokens)];
  if (!tokens.length) return new Response(JSON.stringify({ sent: 0 }), { status: 200 });

  const at = await getAccessToken();
  const results = await Promise.all(tokens.map((t) => push(at, t, title, body, data)));
  return new Response(JSON.stringify({ sent: results.filter(Boolean).length }), { status: 200 });
});
