#!/bin/bash
set -e
cd /app

# Populate the brain volume by cloning the BRAIN repo DIRECTLY.
# Preserves .git natively → /brain is its own git repo root → gbrain
# commit-relative sync_freshness works and autopilot can commit + push.
# (No copy-from-subdir, no fresh `git init` — that was the v1 monorepo bug.)
if [ ! -d /brain/.git ]; then
  echo "Cloning sophia-brain into /brain..."
  git clone "https://${GIT_TOKEN}@github.com/sophia-ehr/sophia-brain.git" /brain
fi

# Topology guard (Vault PRD §2.4): /brain must be its own repo root.
TOP="$(git -C /brain rev-parse --show-toplevel 2>/dev/null || echo '')"
[ "$TOP" = "/brain" ] || echo "WARN: /brain is not its own git root (toplevel: '${TOP:-none}')" 1>&2

# Initialize the Postgres-backed brain if needed. ZEROENTROPY_API_KEY is present
# in the runtime env, so headless init resolves the embedding provider
# (gbrain v0.37+ fails loud on init when no embedding key is present).
# Tolerate re-init on an existing brain, but keep stderr visible (no 2>/dev/null).
gbrain init --postgres || echo "gbrain init: continuing (brain likely already initialized)"

# --- Schema-pack activation (FIX 2026-06) -----------------------------------
# The engine pack locator ONLY looks at bundled packs + ~/.gbrain/schema-packs/<name>/
# — it does NOT discover the repo-committed /brain/_schema/. Previously this step
# was `gbrain schema use sophia-base 2>/dev/null || true`, which FAILED SILENTLY:
# the pack was never installed where the locator looks, so the brain ran on a
# broken `gbrain-base` fallback (`gbrain schema active` → "unknown schema pack").
# Fix: install the repo-canonical pack into the locator path, then SELECT it with
# `gbrain schema use` (writes schema_pack into ~/.gbrain/config.json; re-applied on
# every boot, so it is robust even though ~/.gbrain is container-local). NB:
# `gbrain config set schema_pack` is rejected as an unknown key — `schema use` is
# the supported selector. NO failure-swallowing: a missing/bad pack must fail the
# boot loudly rather than silently degrade to the wrong taxonomy.
test -f /brain/_schema/sophia-base/pack.yaml \
  || { echo "FATAL: /brain/_schema/sophia-base/pack.yaml missing"; exit 1; }
mkdir -p /root/.gbrain/schema-packs
cp -r /brain/_schema/sophia-base /root/.gbrain/schema-packs/sophia-base
gbrain schema use sophia-base
gbrain config set search.mode balanced
gbrain schema active | grep -q "sophia-base" \
  || { echo "FATAL: sophia-base not active after install"; gbrain schema active; exit 1; }
echo "Schema pack active: sophia-base"

# Register the brain repo + run the initial sync.
# v0.41 reality: GBRAIN_BRAIN_DIR is a no-op, and `gbrain init` creates a
# "default" source with NO local_path — so plain `gbrain sync` fails with
# 'Source "default" has no local_path'. `sync --repo` resolves the path AND, on
# success, writes a per-source repo_path anchor into Postgres (persists in the
# db volume). After this, plain `gbrain sync` — including autopilot's — works.
# Idempotent: fresh DB imports + sets the anchor; existing DB is "Already up to
# date". (NOTE: `gbrain config set sync.repo_path` does NOT feed sync — verified.)
gbrain sync --repo /brain --yes 2>&1 || true

# Start autopilot daemon (sync/embed/dream) in background. --repo keeps it robust
# even before the anchor exists (brand-new DB on first boot).
gbrain autopilot --repo /brain &

# Start HTTP MCP server (foreground).
# --bind 0.0.0.0 is REQUIRED: `gbrain serve --http` defaults to 127.0.0.1
# (v0.34+), so without it Hermes — a separate container on dokploy-network —
# gets ECONNREFUSED.
exec gbrain serve --http --port 3131 --bind 0.0.0.0 \
     --public-url "${GBRAIN_PUBLIC_URL:-http://localhost:3131}"
