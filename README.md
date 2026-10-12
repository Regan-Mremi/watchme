# MovieBox

Flutter app + Supabase backend + admin upload page. Every movie has episodes.
Episodes 1-3 are free for any signed-in user; later episodes need an active
subscription paid through Abliner (abliner.net).

```
moviebox/
  app/        Flutter app (what users install)
  admin/      One web page for you to add movies and upload episodes
  supabase/   Database SQL + server functions
  tools/      Optional command-line uploader (same job as the admin page)
```

## How it works

```
App ──sign in──────────────▶ Supabase Auth
App ──list movies/episodes─▶ Database (only published movies are visible)
App ──"play episode X"─────▶ get-playback function
                               ├ episode_number <= free_episodes? → allowed
                               ├ else active subscription?       → allowed
                               └ else                            → "subscribe" (402)
                             returns a 2-hour link to the private video
App ──"subscribe"──────────▶ create-payment function ─▶ Abliner checkout page
Abliner ──callback─────────▶ payment-webhook function ─▶ subscription saved
Admin page ──(your login)──▶ uploads videos, creates movies and episodes
```

The free/paid rule is checked on the server, not in the app. Videos are in a
private bucket, and the path to each file is in a table users cannot read.

## 1. Supabase setup

1. Create a project at supabase.com.
2. Install the Supabase CLI, then from this folder:
   ```
   supabase login
   supabase link --project-ref YOUR_PROJECT_REF
   supabase db push
   ```
   This creates all tables, security rules and storage buckets (files 001 and 002).
3. Get your keys from abliner.net (API key, and the webhook secret that starts
   with `whsec_`), then:
   ```
   supabase secrets set ABLINER_API_KEY=your_api_key ABLINER_WEBHOOK_SECRET=whsec_xxxxx
   ```
4. Deploy the functions:
   ```
   supabase functions deploy get-playback
   supabase functions deploy create-payment
   supabase functions deploy payment-webhook --no-verify-jwt
   ```
5. In the Supabase dashboard under Authentication, choose whether new users
   must confirm their email.

Prices live in the `plans` table (default weekly 2000, monthly 6000, yearly
60000 TZS). Abliner's minimum payment is 500 TZS.

## 2. Make yourself an admin

Create your own account first (sign up in the app, or in Supabase dashboard ->
Authentication -> Add user). Then in dashboard -> SQL editor run:

```sql
update public.profiles set is_admin = true
where id = (select id from auth.users where email = 'YOUR_EMAIL');
```

## 3. Use the admin upload page

1. Open `admin/index.html` in a text editor and set `SUPABASE_URL` and
   `SUPABASE_ANON_KEY` (dashboard -> Settings -> API). The anon key is public
   by design.
2. Run it: `cd admin && python3 -m http.server 8000`, then open
   http://localhost:8000
3. Sign in with your admin account.
4. **Add a movie**: title, description, poster, then tick Publish when it is ready.
5. **Upload an episode**: pick the movie, the number is filled in for you, pick
   the video file, press Upload. A progress bar shows the upload. If your
   internet drops, choose the same file again and it continues.

Nobody can use the page without an admin login: the database itself refuses
uploads from anyone who is not an admin. You can also put the `admin` folder on
any static host (Netlify, Cloudflare Pages, GitHub Pages).

Check your Supabase plan's maximum file size. If your episodes are larger, see
"Before launch".

## 4. Payments with Abliner

Done in `create-payment` (creates the checkout) and `payment-webhook`
(receives `checkout.paid`). Set your callback in the Abliner dashboard only if
Abliner asks for it. The function already sends its own `callback_url` with
each checkout.

The webhook does not trust the callback message alone. After receiving it, it
asks Abliner's API directly whether that payment is really paid and for the
right amount, so a fake callback cannot unlock content.

Two things to confirm with Abliner, because their docs do not say:
- What the `status` of a paid checkout is called. The webhook accepts `paid`,
  `completed`, `success` or `succeeded`. If theirs is different, add it to the
  list in `confirmPaid` in `payment-webhook/index.ts`.
- Whether the callback is signed with the `x-webhook-signature` headers.
  The code checks them when present.

Test with one small real payment before you open to users.

## 5. Run the app

```
cd app
flutter create .          # generates android/ and ios/ (keeps lib/ and pubspec.yaml)
flutter pub get
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

Android: add this inside `<manifest>` in
`android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.INTERNET"/>
```

Never put the service role key in the app or the admin page.

## Before launch

- Use a video host with adaptive streaming (HLS), such as Cloudflare Stream,
  Mux or Bunny Stream. Plain MP4 files buffer badly on weak mobile networks and
  large files may exceed your Supabase plan's limit. Only `get-playback` and
  the admin upload need to change.
- Check Google Play and App Store rules about selling subscriptions outside
  their own billing.
