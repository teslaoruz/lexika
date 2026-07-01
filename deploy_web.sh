#!/usr/bin/env bash
# Build the Flutter web app (pointed at the production backend) and deploy it to
# Cloudflare Pages — one command.
#
# One-time setup:
#   npx wrangler login                                   # authenticate the CLI
#   npx wrangler pages project create lexika --production-branch main
#
# Then deploy any time with:   ./deploy_web.sh
#
# Override the backend URL or project name via env vars if needed:
#   API_BASE=https://api.example.com CF_PAGES_PROJECT=lexika ./deploy_web.sh
set -euo pipefail

API_BASE="${API_BASE:-https://lexika-backend.onrender.com}"
PROJECT="${CF_PAGES_PROJECT:-lexika-app}"
# Google OAuth web client id — the "Sign in with Google" button only appears when
# this is set (must match the id in web/index.html and the backend GOOGLE_CLIENT_IDS).
GOOGLE_CLIENT_ID="${GOOGLE_CLIENT_ID:-611009492322-rk7q0bs2t4v8uenm9ib0qr4pq9utmdug.apps.googleusercontent.com}"

cd "$(dirname "$0")/app"

echo "▸ Building web bundle (API_BASE=$API_BASE)…"
flutter build web --release \
  --dart-define=API_BASE="$API_BASE" \
  --dart-define=GOOGLE_CLIENT_ID="$GOOGLE_CLIENT_ID"

echo "▸ Deploying build/web to Cloudflare Pages project '$PROJECT'…"
npx wrangler pages deploy build/web --project-name "$PROJECT" --commit-dirty=true

echo "✓ Done."
