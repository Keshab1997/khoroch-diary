const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: Record<string, unknown>, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const authorization = request.headers.get("Authorization") ?? "";
  const token = authorization.toLowerCase().startsWith("bearer ")
    ? authorization.slice(7).trim()
    : null;
  if (!token) {
    return json({ error: "Authentication required" }, 401);
  }

  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceRoleKey) {
    console.error("Missing Supabase function configuration");
    return json({ error: "Deletion service unavailable" }, 500);
  }

  // Resolve the account from the presented, verified access token only. Never
  // accept a user ID from the request body or query string.
  let userId: string;
  try {
    const userResponse = await fetch(`${url}/auth/v1/user`, {
      headers: {
        apikey: anonKey,
        Authorization: `Bearer ${token}`,
      },
    });
    if (!userResponse.ok) {
      return json({ error: "Invalid or expired session" }, 401);
    }
    const user = await userResponse.json();
    if (typeof user.id !== "string" || user.id.length === 0) {
      return json({ error: "Invalid account session" }, 401);
    }
    userId = user.id;
  } catch (error) {
    console.error("Could not verify deletion request", error);
    return json({ error: "Could not verify account. Please try again." }, 503);
  }

  // Deleting auth.users cascades to public.khatas and public.transactions;
  // both tables' user_id foreign keys use ON DELETE CASCADE.
  try {
    const deleteResponse = await fetch(
      `${url}/auth/v1/admin/users/${encodeURIComponent(userId)}`,
      {
        method: "DELETE",
        headers: {
          apikey: serviceRoleKey,
          Authorization: `Bearer ${serviceRoleKey}`,
        },
      },
    );
    if (!deleteResponse.ok) {
      console.error("Account deletion failed", deleteResponse.status);
      return json({ error: "Could not delete account" }, 500);
    }
  } catch (error) {
    console.error("Account deletion request failed", error);
    return json({ error: "Could not delete account. Please try again." }, 503);
  }

  return json({ deleted: true }, 200);
});
