#!/bin/bash
set -e
cd /app

# Role-dispatch entrypoint (A2 decomposition). The compose passes the role as the
# command arg: "serve" (default) or "autopilot". One image, two long-lived roles.
ROLE="${1:-serve}"

# Install the repo-canonical schema pack into THIS container's locator path and
# select it. The engine locator only sees bundled packs + ~/.gbrain/schema-packs/
# — never the repo-committed /brain/_schema/ — so without this the brain silently
# falls back to a broken gbrain-base (the production bug fixed in A1). Per-container,
# re-run every boot. NO failure-swallowing: a missing/bad pack fails the boot loudly.
ensure_pack() {
  test -f /brain/_schema/sophia-base/pack.yaml \
    || { echo "FATAL: /brain/_schema/sophia-base/pack.yaml missing"; exit 1; }
  mkdir -p /root/.gbrain/schema-packs
  cp -r /brain/_schema/sophia-base /root/.gbrain/schema-packs/sophia-base
  gbrain schema use sophia-base
  gbrain config set search.mode balanced
  gbrain schema active | grep -q "sophia-base" \
    || { echo "FATAL: sophia-base not active after install"; gbrain schema active; exit 1; }
  echo "Schema pack active: sophia-base"
}

case "$ROLE" in
  serve)
    # The serve role OWNS content population on first boot: clone the brain repo
    # into the shared /brain volume, init the DB, activate the pack, initial sync.
    # serve performs the one-time clone but NEVER commits/pushes — autopilot is the
    # sole git writer (put_page write-through to the working tree is fine).
    if [ ! -d /brain/.git ]; then
      echo "Cloning sophia-brain into /brain..."
      git clone "https://${GIT_TOKEN}@github.com/sophia-ehr/sophia-brain.git" /brain
    fi
    TOP="$(git -C /brain rev-parse --show-toplevel 2>/dev/null || echo '')"
    [ "$TOP" = "/brain" ] || echo "WARN: /brain not its own git root (toplevel: '${TOP:-none}')" 1>&2
    gbrain init --postgres || echo "gbrain init: continuing (brain likely already initialized)"
    ensure_pack
    # Initial sync types pages per the ACTIVE pack — ensure_pack MUST precede it.
    # Idempotent: fresh DB imports + sets the Postgres repo_path anchor; existing
    # DB is "already up to date".
    gbrain sync --repo /brain --yes 2>&1 || true
    # --bind 0.0.0.0 REQUIRED: Hermes is a separate container on dokploy-network.
    exec gbrain serve --http --port 3131 --bind 0.0.0.0 \
         --public-url "${GBRAIN_PUBLIC_URL:-http://localhost:3131}"
    ;;
  autopilot)
    # Follower role: wait for the serve container to populate /brain, then run the
    # self-maintaining cycle (sync/embed/dream). Autopilot is the SOLE git writer
    # (commits + pushes). Supervised by the compose restart policy (fixes the prior
    # unsupervised-`&` finding: a crash now restarts instead of silently stopping).
    echo "Waiting for /brain to be populated by the serve container..."
    for _ in $(seq 1 120); do
      { [ -d /brain/.git ] && [ -f /brain/_schema/sophia-base/pack.yaml ]; } && break
      sleep 5
    done
    [ -d /brain/.git ] || { echo "FATAL: /brain not populated after wait"; exit 1; }
    ensure_pack
    exec gbrain autopilot --repo /brain
    ;;
  *)
    echo "FATAL: unknown role '$ROLE' (expected: serve | autopilot)"; exit 1 ;;
esac
