// Decides whether the caller may watch an episode and, if so, returns a
// short-lived signed URL for the private video file.
//
// Rule: episode_number <= movie.free_episodes  -> free for any signed-in user
//       otherwise                              -> needs an active subscription
import { adminClient, cors, getUser, json } from '../_shared/common.ts';

const SIGNED_URL_SECONDS = 60 * 60 * 2; // 2 hours

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });

  try {
    const user = await getUser(req);
    if (!user) return json({ error: 'unauthorized' }, 401);

    const { episode_id } = await req.json();
    if (!episode_id) return json({ error: 'episode_id required' }, 400);

    const admin = adminClient();

    const { data: ep, error: epErr } = await admin
      .from('episodes')
     .select('id, episode_number, movie_id, movies(id, free_episodes, published)')
      .eq('id', episode_id)
      .single();
    if (epErr || !ep) return json({ error: 'episode_not_found' }, 404);

    const movie = Array.isArray(ep.movies) ? ep.movies[0] : ep.movies;
    if (!movie?.published) return json({ error: 'episode_not_found' }, 404);

    const isFree = ep.episode_number <= movie.free_episodes;

if (!isFree) {
  const { data: purchase, error: purchaseError } = await admin
    .from('movie_purchases')
    .select('id')
    .eq('user_id', user.id)
    .eq('movie_id', ep.movie_id)
    .maybeSingle();

  if (purchaseError) {
    return json({ error: 'purchase_check_failed' }, 500);
  }

  if (!purchase) {
    return json({ error: 'movie_purchase_required' }, 402);
  }
}

    const { data: media } = await admin
      .from('episode_media')
      .select('video_path')
      .eq('episode_id', episode_id)
      .single();
    if (!media) return json({ error: 'video_missing' }, 404);

    const { data: signed, error: signErr } = await admin.storage
      .from('videos')
      .createSignedUrl(media.video_path, SIGNED_URL_SECONDS);
    if (signErr || !signed) return json({ error: 'sign_failed' }, 500);

    return json({ url: signed.signedUrl, expires_in: SIGNED_URL_SECONDS });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
