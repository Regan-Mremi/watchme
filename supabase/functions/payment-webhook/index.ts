
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function respond(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function confirmPaid(
  reference: string,
  amount: number,
  currency: string,
): Promise<boolean> {
  const apiKey = Deno.env.get("ABLINER_API_KEY");
  const baseUrl = Deno.env.get("ABLINER_API_URL") ?? "https://abliner.net";

  if (!apiKey) throw new Error("Payment provider configuration missing");

  const response = await fetch(
    `${baseUrl}/api/v1/checkout?reference=${encodeURIComponent(reference)}`,
    { headers: { Authorization: `Bearer ${apiKey}` } },
  );

  if (!response.ok) return false;

  const body = await response.json().catch(() => null);
  let data = body?.data ?? body;
  if (Array.isArray(data)) data = data[0];
  if (!data) return false;

  const status = String(data.status ?? "").toLowerCase();
  const paid = ["paid", "completed", "success", "succeeded"].includes(status);

  return (
    paid &&
    Number(data.amount) === amount &&
    String(data.currency ?? "").toUpperCase() === currency.toUpperCase()
  );
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return respond({ error: "method_not_allowed" }, 405);
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !serviceKey) {
      return respond({ error: "server_configuration_missing" }, 500);
    }

    const raw = await req.text();
    let event: Record<string, unknown>;

    try {
      event = JSON.parse(raw);
    } catch {
      return respond({ error: "bad_json" }, 400);
    }

    if (event.event !== "checkout.paid") {
      return respond({ ok: true, ignored: true });
    }

    const reference = String(event.reference ?? "");
    if (!reference) return respond({ error: "missing_reference" }, 400);

    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: payment, error: paymentError } = await admin
      .from("payments")
      .select("id, user_id, movie_id, plan_id, amount, currency, status")
      .eq("id", reference)
      .maybeSingle();

    if (paymentError) {
      console.error("Payment lookup failed:", paymentError);
      return respond({ error: "payment_lookup_failed" }, 500);
    }

    if (!payment) return respond({ error: "payment_not_found" }, 404);

    if (payment.status === "succeeded") {
      return respond({ ok: true, duplicate: true });
    }

    if (
      !(await confirmPaid(
        reference,
        Number(payment.amount),
        String(payment.currency),
      ))
    ) {
      return respond({ error: "payment_not_confirmed" }, 409);
    }

    // This version is for one-time movie purchases.
    if (!payment.movie_id) {
      return respond({ error: "payment_is_not_for_a_movie" }, 400);
    }

    const now = new Date().toISOString();

    // Record the purchase. The unique constraint prevents duplicate
    // purchase rows for the same user and movie.
    const { error: purchaseError } = await admin
      .from("movie_purchases")
      .upsert(
        {
          user_id: payment.user_id,
          movie_id: payment.movie_id,
          payment_id: payment.id,
        },
        { onConflict: "user_id,movie_id", ignoreDuplicates: true },
      );

    if (purchaseError) {
      console.error("Purchase recording failed:", purchaseError);
      return respond({ error: "purchase_recording_failed" }, 500);
    }

    const { error: updateError } = await admin
      .from("payments")
      .update({ status: "succeeded", paid_at: now })
      .eq("id", payment.id)
      .neq("status", "succeeded");

    if (updateError) {
      console.error("Payment update failed:", updateError);
      return respond({ error: "payment_update_failed" }, 500);
    }

    return respond({ ok: true, purchase_recorded: true });
  } catch (error) {
    console.error("payment-webhook error:", error);
    return respond({ error: "internal_error" }, 500);
  }
});