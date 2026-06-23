# Deploying Lexika (free tier)

This is the **$0/month** setup:

- **Database** → [Neon](https://neon.tech) (free Postgres)
- **Backend** → [Render](https://render.com) (free web service, from `render.yaml` + `backend/Dockerfile`)
- **Web app** → [Cloudflare Pages](https://pages.cloudflare.com) (free static hosting)

> ⚠️ Render's free backend **sleeps after ~15 min idle**, so the first request
> after a nap takes ~30–50s to wake. Fine for a demo/portfolio.

The three pieces depend on each other's URLs, so do them in this order.

---

## 1. Database — Neon

1. Sign up at <https://neon.tech> and create a project (pick a region near you).
2. On the project dashboard, copy the **connection string**. It looks like:
   ```
   postgresql://USER:PASSWORD@ep-xxxx.REGION.aws.neon.tech/neondb?sslmode=require
   ```
3. **Seed the word catalogue** from your machine (one time). From the repo root:
   ```sh
   cd backend
   DATABASE_URL="<your-neon-connection-string>" uv run python seed_catalogue.py
   ```
   You should see `catalogue seeded.` (Tables are created automatically.)

Keep the connection string handy for the next step.

---

## 2. Backend — Render

1. Sign up at <https://render.com> and connect your GitHub account.
2. **New ➜ Blueprint**, choose the `teslaoruz/lexika` repo. Render reads
   `render.yaml` and proposes the `lexika-backend` service.
3. When prompted for environment variables, set:
   - `DATABASE_URL` → your Neon connection string from step 1.
   - `LEXIKA_ALLOWED_ORIGINS` → leave a placeholder for now (e.g. `https://example.pages.dev`);
     you'll update it in step 4 once you have the real Pages URL.
4. Click **Apply / Deploy**. First build takes a few minutes.
5. When it's live, note the backend URL, e.g. `https://lexika-backend.onrender.com`.
   Verify:
   - `https://lexika-backend.onrender.com/health` → `{"status":"ok"}`
   - `https://lexika-backend.onrender.com/docs` → Swagger UI

---

## 3. Web app — Cloudflare Pages

1. Build the Flutter web bundle locally, pointing it at your Render backend:
   ```sh
   cd app
   flutter build web --release \
     --dart-define=API_BASE=https://lexika-backend.onrender.com
   ```
   Output is in `app/build/web`.
2. Sign up at <https://dash.cloudflare.com> ➜ **Workers & Pages ➜ Create ➜ Pages
   ➜ Upload assets**.
3. Name the project `lexika`, then **drag-and-drop the `app/build/web` folder**
   (or its contents). Deploy.
4. You'll get a URL like `https://lexika.pages.dev`. Open it — the app loads.

> Prefer the CLI? `npm i -g wrangler && wrangler pages deploy app/build/web --project-name lexika`

---

## 4. Connect them (CORS)

1. Back in Render ➜ `lexika-backend` ➜ **Environment**, set
   `LEXIKA_ALLOWED_ORIGINS` to your real Pages URL, e.g. `https://lexika.pages.dev`
   (no trailing slash; comma-separate if you have more than one).
2. Save — Render redeploys automatically.
3. Open `https://lexika.pages.dev`, register an account, look up a word, save it
   to a deck. Done. 🎉

---

## One-command web deploys

After a one-time login, `./deploy_web.sh` builds the web bundle and ships it to
Cloudflare Pages in one step.

```sh
# one-time
npx wrangler login
npx wrangler pages project create lexika --production-branch main

# every deploy after that
./deploy_web.sh
```

The script bakes in `API_BASE=https://lexika-backend.onrender.com`; override with
`API_BASE=... ./deploy_web.sh` if your backend URL changes.

## Updating later

- **Backend / API:** push to `main` → Render auto-deploys.
- **Web app:** run `./deploy_web.sh`.
- **Android:** `flutter build apk --release --dart-define=API_BASE=https://lexika-backend.onrender.com`
  and reinstall `app/build/app/outputs/flutter-apk/app-release.apk`.
- **Custom domain:** both Render and Cloudflare Pages let you attach one for free;
  remember to add the new web origin to `LEXIKA_ALLOWED_ORIGINS`.
