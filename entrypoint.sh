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
gbrain init --postgres 2>/dev/null || true

# Ensure SOPHIA taxonomy + balanced search mode (PRD §5.2).
gbrain schema use sophia-base 2>/dev/null || true
gbrain config set search.mode balanced 2>/dev/null || true

# Start autopilot daemon (sync/embed/dream) in background.
gbrain autopilot &

# Start HTTP MCP server (foreground).
# --bind 0.0.0.0 is REQUIRED: `gbrain serve --http` defaults to 127.0.0.1
# (v0.34+), so without it Hermes — a separate container on dokploy-network —
# gets ECONNREFUSED.
exec gbrain serve --http --port 3131 --bind 0.0.0.0 \
     --public-url "${GBRAIN_PUBLIC_URL:-http://localhost:3131}"
