// Edge Function: ABM de usuarios para administradores.
// Despliegue: supabase functions deploy admin-users
// Usa SUPABASE_URL, SUPABASE_ANON_KEY y SUPABASE_SERVICE_ROLE_KEY (inyectadas por Supabase).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const url = Deno.env.get("SUPABASE_URL")!;
  const anon = Deno.env.get("SUPABASE_ANON_KEY")!;
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "No autenticado" }, 401);

  const userClient = createClient(url, anon, { global: { headers: { Authorization: authHeader } } });
  const { data: { user } } = await userClient.auth.getUser();
  if (!user) return json({ error: "No autenticado" }, 401);

  const admin = createClient(url, service);
  const { data: me } = await admin.from("profiles").select("role, country_id, active").eq("id", user.id).single();
  if (!me || !me.active || me.role !== "admin") return json({ error: "Solo administradores" }, 403);

  let b: any;
  try { b = await req.json(); } catch { return json({ error: "JSON inválido" }, 400); }

  // Verifica que el usuario objetivo sea del mismo country
  const sameCountry = async (id: string) => {
    const { data } = await admin.from("profiles").select("country_id").eq("id", id).single();
    return data?.country_id === me.country_id;
  };

  switch (b.action) {
    case "create": {
      const { email, password, full_name, role, dni, phone, lot_ids } = b;
      if (!email || !password || !full_name || !["admin", "guard", "owner"].includes(role))
        return json({ error: "Datos incompletos" }, 400);
      if (String(password).length < 8) return json({ error: "La contraseña debe tener al menos 8 caracteres" }, 400);

      const { data: created, error } = await admin.auth.admin.createUser({
        email, password, email_confirm: true,
      });
      if (error || !created.user) return json({ error: error?.message ?? "No se pudo crear" }, 400);

      const uid = created.user.id;
      const { error: pErr } = await admin.from("profiles").insert({
        id: uid, country_id: me.country_id, role, full_name, dni: dni || null, phone: phone || null, email,
      });
      if (pErr) {
        await admin.auth.admin.deleteUser(uid);
        return json({ error: pErr.message }, 400);
      }
      if (role === "owner" && Array.isArray(lot_ids) && lot_ids.length) {
        const { data: okLots } = await admin.from("lots").select("id").eq("country_id", me.country_id).in("id", lot_ids);
        const rows = (okLots ?? []).map((l) => ({ lot_id: l.id, profile_id: uid }));
        if (rows.length) await admin.from("lot_owners").insert(rows);
      }
      return json({ id: uid });
    }

    case "set_password": {
      if (!b.user_id || String(b.password ?? "").length < 8) return json({ error: "Datos inválidos" }, 400);
      if (!(await sameCountry(b.user_id))) return json({ error: "Usuario inexistente" }, 404);
      const { error } = await admin.auth.admin.updateUserById(b.user_id, { password: b.password });
      return error ? json({ error: error.message }, 400) : json({ ok: true });
    }

    case "set_active": {
      if (!b.user_id || typeof b.active !== "boolean") return json({ error: "Datos inválidos" }, 400);
      if (b.user_id === user.id) return json({ error: "No podés desactivarte a vos mismo" }, 400);
      if (!(await sameCountry(b.user_id))) return json({ error: "Usuario inexistente" }, 404);
      await admin.from("profiles").update({ active: b.active }).eq("id", b.user_id);
      // Banea o rehabilita el login
      await admin.auth.admin.updateUserById(b.user_id, { ban_duration: b.active ? "none" : "876000h" });
      return json({ ok: true });
    }

    default:
      return json({ error: "Acción desconocida" }, 400);
  }
});
