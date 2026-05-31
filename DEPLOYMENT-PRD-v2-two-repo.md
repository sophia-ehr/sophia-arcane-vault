# PRD: SOPHIA Brain Deployment (v2 — two-repo aligned)

> **Purpose:** Deploy the SOPHIA Brain system on the netcup server so the team can interact with the company brain via Discord.
>
> **Prerequisite:** The *Vault PRD v2.1 (two-repo)* is complete. **Two** repos pass the local smoke test: the fork `github.com/sophia-ehr/sophia-arcane-vault` (tool code + the one `link-extraction.ts` patch) and the brain `github.com/sophia-ehr/sophia-brain` (markdown + schema pack). They are linked only by `GBRAIN_BRAIN_DIR`.
>
> **Deliverable:** A running brain system where a team member types a question in Discord and gets a brain-sourced answer.
>
> **What changed from v1:** v1 assumed a single monorepo (`sophia-arcane-vault/gbrain/` + `sophia-arcane-vault/sophia-brain/`). v2 reflects the two-repo split — most importantly, the brain volume is populated by **cloning the `sophia-brain` repo directly** (preserving its `.git`), not by copying a subdirectory out of the monorepo and re-`git init`-ing it. See the changelog at the end.

---

## 1. Context

SOPHIA Health has **two** repos: a GBrain fork (tool code) and a `sophia-brain` repo (markdown content + the `sophia-base` schema pack). This PRD gets them running on the team's infrastructure 24/7.

### 1.1 Infrastructure

- **Server:** netcup VPS — 16 GB RAM, 500 GB disk, near-idle CPU
- **Orchestration:** Dokploy (already installed)
- **Docker usage:** ~5 GB currently
- **Headroom:** comfortable — the brain stack (Postgres + GBrain + Hermes) needs ~1.5–2 GB RAM total

### 1.2 Architecture Overview

Three components, two Dokploy services:

```
Team (Discord)
  → Hermes (standalone Dokploy Compose service — the agent)
    → GBrain HTTP MCP (inside Brain Stack Compose — the memory)
      → Postgres + pgvector (inside Brain Stack Compose — the database)
        ← sophia-brain repo (cloned into /brain volume — the source of truth)

Repos:
  • sophia-ehr/sophia-arcane-vault  — fork: tool code, Dockerfile.deploy,
    docker-compose.brain.yml, entrypoint.sh, skills/  (all at repo root)
  • sophia-ehr/sophia-brain         — brain: markdown content + _schema/sophia-base/pack.yaml
```

Hermes is deployed first, standalone. Hermes then deploys the brain stack via the Dokploy API.

### 1.3 Why This Topology

- **Hermes standalone:** the agent that manages infrastructure must not be managed by it.
- **Brain Stack as Compose:** GBrain and Postgres resolve each other by container name on a shared default network.
- **Hermes → GBrain via `dokploy-network`:** Dokploy's shared external network bridges separately-deployed services.
- **No public domains initially:** Hermes connects outbound to Discord; GBrain and Postgres are internal-only.

### 1.4 Brain directory & path (server) — FIRST-CLASS REQUIREMENT

The two-repo split makes the brain's location and git state load-bearing:

- **`GBRAIN_BRAIN_DIR` must be an absolute path in the deployed environment** — `/brain` inside the GBrain container (a Docker named volume). The relative `../sophia-brain` from the Vault PRD is **local-dev only** and must never appear in server config.
- **The brain volume must contain the brain repo's `.git`.** gbrain's incremental sync and `doctor sync_freshness` read `git -C "$GBRAIN_BRAIN_DIR" rev-parse HEAD` and compare to the last-synced commit SHA. This only works if `/brain` is a real git repo root. We guarantee that by **cloning `sophia-ehr/sophia-brain` directly into `/brain`** (§3.3), not by copying loose markdown into a volume.
- **Never bind-mount only the markdown** (no `.git`) — same failure mode as the old nesting bug, different cause. Mount/clone the whole repo.
- **Topology guard (in-container):** `git -C /brain rev-parse --show-toplevel` must equal `/brain`.

### 1.5 Embedding Strategy

**ZeroEntropy free tier** (zembed-1, 1280 dims) is the default — zero config; the free tier (500K bytes/min) trivially handles SOPHIA's volume. Hot-swappable later via `gbrain providers` (incl. Ollama for local CPU embedding) — a config change, not a re-architecture.

---

# ═══════════════════════════════════════════════════════════════
# PART I — HUMAN BOOTSTRAP
# Executor: Moritz, via Dokploy CLI + Kilo Code
# Scope: Deploy Hermes as a standalone service, verify it runs
# ═══════════════════════════════════════════════════════════════

## 2. Deploy Hermes

### 2.1 Method

Create a Dokploy Compose service using the official Hermes Agent Docker image. No custom Dockerfile needed. Compose adapted from [Dokploy/templates#908](https://github.com/Dokploy/templates/pull/908).

**Steps:**
1. Create a Dokploy API token (Settings → API Tokens)
2. Create a Dokploy Project: "SOPHIA Brain"
3. Create a Compose service: "hermes"
4. Paste the YAML from §2.2
5. Set env vars per §2.3
6. Deploy

### 2.2 Docker Compose

```yaml
version: "3.8"
services:
  hermes-agent:
    image: nousresearch/hermes-agent:v2026.5.16
    restart: unless-stopped
    command: ["gateway", "run"]
    environment:
      - HERMES_DASHBOARD=1
      - HERMES_DASHBOARD_HOST=0.0.0.0
      - API_SERVER_ENABLED=true
      - API_SERVER_HOST=0.0.0.0
      - API_SERVER_KEY=${API_SERVER_KEY}
      # Inference via Kilo Gateway (OpenAI-compatible)
      - OPENAI_API_KEY=${KILO_API_KEY}
      - OPENAI_BASE_URL=https://api.kilo.ai/api/gateway
      # Dokploy API access (for brain stack management in Part II)
      - DOKPLOY_API_KEY=${DOKPLOY_API_KEY}
      - DOKPLOY_API_URL=${DOKPLOY_API_URL}
    volumes:
      - hermes-agent-data:/opt/data
    healthcheck:
      test: ["CMD-SHELL", "curl -fsS http://localhost:8642/health && curl -fsS http://localhost:9119/api/status || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    networks:
      - dokploy-network

networks:
  dokploy-network:
    external: true

volumes:
  hermes-agent-data:
```

- Inference routes through Kilo Gateway — one key; model names use `provider/model` (e.g. `anthropic/claude-sonnet-4-20250514`).
- `DOKPLOY_API_KEY`/`DOKPLOY_API_URL` let Hermes deploy the brain stack in Part II.
- Web dashboard on port 9119 — assign a domain in Dokploy if you want browser access.

### 2.3 Environment Variables

```
KILO_API_KEY=<kilo-gateway-key>
API_SERVER_KEY=<strong-random-string>
DOKPLOY_API_KEY=<from-step-1>
DOKPLOY_API_URL=https://<your-dokploy-domain>/api
```

`KILO_API_KEY` maps to `OPENAI_API_KEY` in compose (Kilo is OpenAI-compatible).

### 2.4 Verification

- [ ] hermes service "Running" with passing health checks
- [ ] Logs show the gateway started
- [ ] (Optional) dashboard reachable if a domain is assigned

### 2.5 GitHub Access Tokens (two repos)

The brain stack needs to **clone and push the brain repo** and **clone the fork** (for the image build + skills). Create fine-grained PAT(s):

- **Brain repo token (`GIT_TOKEN`):** scope `sophia-ehr/sophia-brain`, permission **Contents: read/write** (autopilot commits + pushes brain updates).
- **Fork access:** if the fork is private, a second read-only token (Contents: read) scoped to `sophia-ehr/sophia-arcane-vault`; if public, no token needed for the build.

The GBrain entrypoint embeds `GIT_TOKEN` in the brain repo's clone/push URL (`https://${GIT_TOKEN}@github.com/sophia-ehr/sophia-brain.git`). No SSH keys needed.

### 2.6 Install SOPHIA Skills

Skills live at the **fork repo root** (`skills/`), not a `gbrain/` subdir. Clone the fork on the host, copy skills into the Hermes volume:

```bash
git clone https://github.com/sophia-ehr/sophia-arcane-vault.git /tmp/sophia-fork
docker ps | grep hermes
docker cp /tmp/sophia-fork/skills/ <hermes-container-id>:/opt/data/skills/   # verify target path vs Hermes docs
rm -rf /tmp/sophia-fork
```

Key skills: `brain-ops`, `enrich`, `signal-detector`, and `deploy-brain-stack` (the Part II skill, §4).

### 2.7 Part I Definition of Done

- [ ] Hermes running as a Dokploy Compose service in "SOPHIA Brain"
- [ ] Health checks pass; reachable via dashboard/API
- [ ] Hermes has `DOKPLOY_API_KEY` and can reach the Dokploy API
- [ ] `deploy-brain-stack` skill installed

**Once Part I is complete, hand control to Hermes.**

---

# ═══════════════════════════════════════════════════════════════
# PART II — HERMES TAKES OVER
# Executor: Hermes agent (autonomous, via skills and MCP)
# Trigger: Moritz sends the instruction to deploy the brain stack
# ═══════════════════════════════════════════════════════════════

## 3. Brain Stack Specification

Reference material for Hermes. The compose, Dockerfile, and entrypoint all live at the **fork repo root**; the brain content comes from the **brain repo**, cloned into the `/brain` volume at boot.

### 3.1 Docker Compose (docker-compose.brain.yml — fork repo root)

```yaml
name: sophia-brain-stack

services:
  brain-db:
    image: pgvector/pgvector:pg17
    restart: unless-stopped
    volumes:
      - db-data:/var/lib/postgresql/data
    environment:
      POSTGRES_DB: brain
      POSTGRES_USER: sophia
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "sophia", "-d", "brain"]
      interval: 5s
      timeout: 5s
      retries: 10

  gbrain:
    build:
      context: .                 # fork IS the repo root now (was ./gbrain)
      dockerfile: Dockerfile.deploy
    restart: unless-stopped
    depends_on:
      brain-db:
        condition: service_healthy
    environment:
      DATABASE_URL: postgres://sophia:${POSTGRES_PASSWORD}@brain-db:5432/brain
      GBRAIN_BRAIN_DIR: /brain   # absolute, in-container (NOT ../sophia-brain)
      GBRAIN_ENGINE: postgres
      GBRAIN_LINK_DIRS: organizations,tools,strategy,conferences,decisions,deliverables,sophia
      GBRAIN_SOURCE_BOOST: "strategy/:1.5,organizations/:1.3,people/:1.2,decisions/:1.2,concepts/:1.2,tools/:1.1,inbox/:0.8,sources/:0.7,archive/:0.6"
      ZEROENTROPY_API_KEY: ${ZEROENTROPY_API_KEY}
      GIT_TOKEN: ${GIT_TOKEN}
    volumes:
      - brain-repo:/brain        # named volume; populated by entrypoint clone of sophia-brain
    expose:
      - "3131"
    networks:
      - default          # inter-service DNS (brain-db)
      - dokploy-network  # external access (Hermes)

networks:
  dokploy-network:
    external: true

volumes:
  db-data:
  brain-repo:
```

> Note `GBRAIN_LINK_DIRS` and `GBRAIN_SOURCE_BOOST` are set here — these replace the old source patches (Vault PRD §3/§5) and must be present at runtime.

### 3.2 GBrain Dockerfile (Dockerfile.deploy — fork repo root)

```dockerfile
FROM oven/bun:1.3-debian

RUN apt-get update && apt-get install -y git tini && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY . .                         # build context = fork repo root
RUN bun install --production

VOLUME /brain
ENV GBRAIN_BRAIN_DIR=/brain
ENV GBRAIN_ENGINE=postgres

ENTRYPOINT ["/usr/bin/tini", "--"]
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
CMD ["/entrypoint.sh"]
```

### 3.3 Entrypoint Script (entrypoint.sh — fork repo root)

```bash
#!/bin/bash
set -e
cd /app

# Populate the brain volume by cloning the BRAIN repo DIRECTLY.
# This preserves .git natively → /brain is its own git repo root → gbrain
# commit-relative sync_freshness works, and autopilot can commit + push.
# (No copy-from-subdir, no fresh `git init` — that was the v1 monorepo bug.)
if [ ! -d /brain/.git ]; then
  echo "Cloning sophia-brain into /brain..."
  git clone "https://${GIT_TOKEN}@github.com/sophia-ehr/sophia-brain.git" /brain
fi

# Topology guard (mirrors Vault PRD §2.4): /brain must be its own repo root.
TOP="$(git -C /brain rev-parse --show-toplevel 2>/dev/null || echo '')"
[ "$TOP" = "/brain" ] || echo "WARN: /brain is not its own git root (toplevel: '${TOP:-none}')" 1>&2

# Initialize the Postgres database if needed
gbrain init --postgres 2>/dev/null || true

# Ensure the SOPHIA taxonomy is active
gbrain schema use sophia-base 2>/dev/null || true

# Start autopilot daemon in background
gbrain autopilot &

# Start HTTP MCP server (foreground)
exec gbrain serve --http --port 3131 --public-url http://localhost:3131
```

> **Why clone the brain repo directly:** GBrain's `gbrain sync` runs `git status/add/commit/push` against `GBRAIN_BRAIN_DIR`, and `doctor sync_freshness` compares `/brain`'s HEAD to the last-synced SHA. Cloning the standalone `sophia-brain` repo gives `/brain` a real `.git` with the correct remote (`origin → sophia-ehr/sophia-brain`), so pushes land in the brain repo and freshness is accurate. The v1 approach (clone monorepo → copy `sophia-brain/*` → `git init`) created an orphan repo whose pushes had nowhere correct to go.

### 3.4 Environment Variables for Brain Stack

```
POSTGRES_PASSWORD=<strong-password>
ZEROENTROPY_API_KEY=<key>
GIT_TOKEN=<brain-repo fine-grained PAT from §2.5 — Contents R/W on sophia-ehr/sophia-brain>
```

### 3.5 Brain Repo Volume

First boot: the entrypoint clones `sophia-ehr/sophia-brain` into the empty `brain-repo` volume, `.git` included. Autopilot handles ongoing sync and pushes back to the brain repo using `GIT_TOKEN`.

### 3.6 Networking

GBrain joins `default` (for `brain-db` DNS) and `dokploy-network` (for Hermes). If a public domain is later added, explicitly keep `default` to avoid breaking inter-service DNS.

---

## 4. Hermes Skill: deploy-brain-stack

### 4.1 Prerequisites

- `DOKPLOY_API_KEY` / `DOKPLOY_API_URL` set (Part I)
- The fork repo (`sophia-ehr/sophia-arcane-vault`) holds `docker-compose.brain.yml`, `Dockerfile.deploy`, `entrypoint.sh` at root
- The brain repo (`sophia-ehr/sophia-brain`) is reachable with `GIT_TOKEN`

> Dokploy API paths follow its tRPC-style convention; verify against `<DOKPLOY_API_URL>/api-doc`.

### 4.2 Skill Definition

```markdown
# deploy-brain-stack — Deploy or redeploy the SOPHIA brain stack

## When to use
- First-time deployment of the brain stack
- Redeploying after fork code changes
- Recovering from a crashed brain stack

## Steps

### First-time deployment
1. Dokploy API: create Compose service in "SOPHIA Brain"
   POST /api/compose.create {
     projectId: <SOPHIA Brain project ID>,
     name: "brain-stack",
     sourceType: "github",
     repository: "sophia-ehr/sophia-arcane-vault",   # fork: holds the compose + Dockerfile
     composePath: "docker-compose.brain.yml",         # at fork repo root
     branch: "main"
   }
2. Dokploy API: set env vars (§3.4) — incl. GIT_TOKEN for the BRAIN repo
   POST /api/compose.update { ... }
3. Dokploy API: deploy
   POST /api/compose.deploy { composeId: <from step 1> }
4. Poll for healthy (every 10s, timeout 5 min)
   GET /api/compose.one { composeId }
5. Discover GBrain container name; update own config:
   mcp_servers.gbrain.url = "http://<gbrain-container-name>:3131/mcp"
6. Test MCP: get_stats → verify page count > 0
7. If page count is 0, run initial seed (§5)
8. Report: "Brain stack deployed. {pages} pages, {embeddings} embeddings, search operational."

### Redeployment
1. POST /api/compose.deploy { composeId: <known> }
2. Wait for healthy; verify MCP; report.

### Recovery
1. Check service status via Dokploy API
2. If down, redeploy; if up but MCP fails, pull logs
3. Report findings with log excerpts.
```

---

## 5. Database Seeding

After the stack is running and Hermes is connected via MCP:

### 5.1 Seed Sequence
1. **Import:** GBrain MCP `sync_brain` — sync the `/brain` repo into Postgres
2. **Embed:** `embed_stale`
3. **Links:** `extract_links`
4. **Timeline:** `extract_timeline`
5. **Health:** `get_stats` — verify page count, embed coverage, link count

### 5.2 Search Mode

`GBRAIN_SEARCH_MODE=balanced` (or `gbrain config set search.mode balanced`).

### 5.3 Verification Queries
- "What tools has SOPHIA adopted?" → tools with status: adopted
- "What decisions affected our tech architecture?" → decision → strategy edges
- "Who are our hospital contacts?" → people with hospital relationships
- "Tell me about Charité Berlin" → enriched org page

Report results.

---

## 6. Operational Cadence

### 6.1 GBrain Autopilot (inside the GBrain container)

| Frequency | Job | What it does |
|-----------|-----|-------------|
| Every 15 min | Sync | `gbrain sync && gbrain embed --stale` (commits/pushes brain repo) |
| Nightly 02:00 CET | Dream cycle | entity sweep, citation fixes, consolidation |
| Weekly Sun 03:00 | Doctor | `gbrain doctor --json` |
| Daily | Update check | `gbrain check-update --json` — notify, never auto-install |

### 6.2 Hermes Operations

| Trigger | Action |
|---------|--------|
| Message mentioning an entity | signal detect → enrich → update brain via MCP |
| Question about SOPHIA | query brain via MCP → sourced answer |
| `/brain-health` | `get_stats` + `doctor` → report |
| `/brain-redeploy` | redeploy via Dokploy API |
| Daily morning | briefing: deadlines, stale pages, pipeline |

### 6.3 Discord Channels (when connector ready)

| Channel | Purpose | Who writes |
|---------|---------|-----------|
| `#summoning-circle` | ask @Hermes about SOPHIA's knowledge | Team → Hermes |
| `#scroll-drop` | drop links/notes/transcripts for capture | Team → Hermes |
| `#goblin-ops` | health, deploy status, alerts | Hermes → Team |

### 6.4 Standing Orders Finalization

Fill the `[filled after deployment]` placeholders in `HEARTBEAT.md` (in the **brain repo**) with host, orchestration, and **both repo URLs**. Commit via GBrain MCP `put_page` (lands in the brain repo).

---

## 7. Monitoring & Health

- **GBrain doctor** (weekly, autopilot)
- **Hermes heartbeat** (every 5 min): ping `get_stats`; 3 consecutive failures → alert + recovery via `deploy-brain-stack`
- **Dokploy monitoring:** CPU/memory/disk; Discord notifications for service failures
- **Backups:** Dokploy `pg_dump` of `brain-db` daily 04:00 CET, 7-day retention, local disk
- **Alert on:** GBrain MCP unreachable (3 fails), deploy failure, doctor criticals (broken links > 10%, orphans > 20%), embed coverage < 90%

---

## 8. Upgrade Paths

### 8.1 Upgrading GBrain (the fork)
1. On the dev machine, in the **fork repo root**: `git fetch upstream && git merge <new-tag>` (real 3-way merge per Vault PRD §12)
2. Push to `sophia-ehr/sophia-arcane-vault`
3. Hermes redeploys via Dokploy API; verifies MCP + smoke tests

> Brain content changes are independent — they flow through the `sophia-brain` repo via autopilot sync/push, no redeploy needed.

### 8.2 Upgrading to Full Supabase
1. Deploy Dokploy Supabase template as a separate Compose service
2. Point `DATABASE_URL` at Supabase Postgres
3. Remove standalone `brain-db`; redeploy — GBrain only needs `DATABASE_URL`

### 8.3 Scaling
Netcup (16 GB / 500 GB) is comfortable for ~200 pages + the stack. Triggers to scale: brain > 5,000 pages, many concurrent users, clinical-data workloads (→ STACKIT).

---

## 9. Implementation Checklist

### Part I — Human Bootstrap
- [ ] Dokploy API token; Project "SOPHIA Brain"
- [ ] Deploy Hermes Compose (§2.2); set env vars (§2.3)
- [ ] Create GitHub PAT(s) — brain repo Contents R/W; fork read if private (§2.5)
- [ ] Verify Hermes healthy; install skills incl. `deploy-brain-stack` (§2.6)
- [ ] **→ Hand off to Hermes**

### Part II — Hermes Autonomous
- [ ] Deploy brain stack via `deploy-brain-stack` (§4) — clones `sophia-brain` into `/brain`
- [ ] Confirm in-container: `git -C /brain rev-parse --show-toplevel` == `/brain`
- [ ] Seed DB: import, embed, links, timeline (§5)
- [ ] Verification queries (§5.3)
- [ ] Operational cadence (§6); monitoring + heartbeat (§7); backups (§7)
- [ ] Finalize `HEARTBEAT.md` in the brain repo (§6.4)
- [ ] (When ready) Discord gateway + channels (§6.3)
- [ ] Report deployment summary

---

## 10. Definition of Done

1. **Part I:** Hermes running standalone, healthy, skills installed
2. **Part II:** brain stack deployed by Hermes, `/brain` is the cloned `sophia-brain` repo (`.git` present, `--show-toplevel` == `/brain`), seeded, correct query results
3. GBrain autopilot running (sync pushes to the brain repo; dream cycle; doctor)
4. Database backups scheduled
5. Hermes can redeploy autonomously on command or failure

---

### Changelog (v1 → v2, two-repo alignment)

| v1 (monorepo) | v2 (two-repo) |
|---|---|
| Brain stack clones `sophia-arcane-vault`, copies `sophia-brain/*`, `git init`s `/brain` | Entrypoint clones **`sophia-ehr/sophia-brain` directly into `/brain`**, `.git` preserved (§3.3) |
| `build: context: ./gbrain` | `context: .` (fork is the repo root) (§3.1) |
| Dockerfile/entrypoint under `gbrain/` | at fork repo root (§3.2/§3.3) |
| Skills from `gbrain/skills/` | from fork root `skills/` (§2.6) |
| One PAT (monorepo) | brain-repo PAT (Contents R/W) + optional fork read (§2.5) |
| `GBRAIN_LINK_DIRS`/`GBRAIN_SOURCE_BOOST` implicit (source-patched) | set as container env (§3.1) — replaces the dropped source patches |
| Upgrade merges in `gbrain/` subdir | merges in fork repo root; brain content flows independently (§8.1) |
| (implicit) | **Brain-path requirement made first-class** (§1.4) + in-container topology guard (§3.3, §9) |
