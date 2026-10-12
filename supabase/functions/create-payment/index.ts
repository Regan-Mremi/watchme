
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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return respond({ error: "method_not_allowed" }, 405);
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const ablinerKey = Deno.env.get("ABLINER_API_KEY");
    const ablinerUrl =
      Deno.env.get("ABLINER_API_URL") ?? "https://abliner.net";

    if (!supabaseUrl || !anonKey || !serviceKey || !ablinerKey) {
      return respond({ error: "payment_configuration_missing" }, 500);
    }

    const authorization = req.headers.get("Authorization");
    if (!authorization) {
      return respond({ error: "unauthorized" }, 401);
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: userData, error: userError } =
      await userClient.auth.getUser();

    if (userError || !userData.user) {
      return respond({ error: "unauthorized" }, 401);
    }

    const input = await req.json();
    const movieId = input.movie_id;

    if (typeof movieId !== "string" || !movieId) {
      return respond({ error: "movie_id_required" }, 400);
    }

    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: movie, error: movieError } = await admin
      .from("movies")
      .select("id, title, price, published")
      .eq("id", movieId)
      .eq("published", true)
      .maybeSingle();

    if (movieError) {
      return respond({ error: "movie_lookup_failed" }, 500);
    }

    if (!movie) {
      return respond({ error: "movie_not_found" }, 404);
    }

    if (
      movie.price == null ||
      !Number.isSafeInteger(Number(movie.price)) ||
      Number(movie.price) < 500
    ) {
      return respond({
        error: "invalid_movie_price",
        message: "Set this movie's price to at least 500 in TZS.",
      }, 400);
    }

    const { data: existing, error: existingError } = await admin
      .from("movie_purchases")
      .select("id")
      .eq("user_id", userData.user.id)
      .eq("movie_id", movie.id)
      .maybeSingle();

    if (existingError) {
      return respond({ error: "purchase_check_failed" }, 500);
    }

    if (existing) {
      return respond({ error: "movie_already_purchased" }, 409);
    }

    const { data: payment, error: paymentError } = await admin
      .from("payments")
      .insert({
        user_id: userData.user.id,
        plan_id: null,
        movie_id: movie.id,
        amount: Number(movie.price),
        currency: "TZS",
        status: "pending",
      })
      .select("id, amount, currency")
      .single();

    if (paymentError || !payment) {
      return respond({ error: "payment_create_failed" }, 500);
    }

    const checkoutResponse = await fetch(
      `${ablinerUrl}/api/v1/checkout`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${ablinerKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          amount: payment.amount,
          currency: payment.currency,
          title: "MovieBox",
          description: `Purchase: ${movie.title}`,
          reference: payment.id,
          callback_url:
            `${supabaseUrl}/functions/v1/payment-webhook`,
          expires_in_minutes: 30,
        }),
      },
    );

    const checkoutBody = await checkoutResponse.json().catch(() => ({}));
    const checkoutData = checkoutBody?.data ?? checkoutBody;

    if (!checkoutResponse.ok || !checkoutData?.checkout_url) {
      await admin
        .from("payments")
        .update({ status: "failed" })
        .eq("id", payment.id);

      console.error("Abliner checkout failed:", checkoutBody);
      return respond({ error: "provider_error" }, 502);
    }

    await admin
      .from("payments")
      .update({ provider_ref: checkoutData.id ?? null })
      .eq("id", payment.id);

    return respond({
      payment_id: payment.id,
      checkout_url: checkoutData.checkout_url,
    });
  } catch (error) {
    console.error("create-payment error:", error);
    return respond({ error: "internal_error" }, 500);
  }
});