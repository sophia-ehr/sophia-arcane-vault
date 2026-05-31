# PRD: SOPHIA Arcane Vault — Clean Fork & Selective Patch (v2.1 — two-repo)

> **Purpose:** Rebuild the SOPHIA Arcane Vault as a *clean* fork of GBrain with real upstream git ancestry, a minimal source-divergence surface, and a declarative schema pack instead of hardcoded taxonomy patches — split into **two git repos** (tool fork + brain) so neither pollutes the other. Supersedes "VAULT PRD.md" (the `git init` snapshot + heavy-source-patch + single-monorepo approach), now deprecated.
>
> **Audience:** Coding agent (Claude Code / Kilo Code) + implementing engineer (Julian / Sebastian).
>
> **Deliverables:** **Two repositories.**
> 1. `github.com/sophia-ehr/sophia-arcane-vault` — the GBrain fork: tool code, **exactly one** source patch, config templates. Real upstream ancestry.
> 2. `github.com/sophia-ehr/sophia-brain` — the markdown brain: its own git repo, holding the schema pack + all content. Linked to the tool only by the `GBRAIN_BRAIN_DIR` env var.
>
> A fresh clone of both passes the smoke test in §11.
>
> **Scope boundary:** This PRD produces the **two repos**, locally verified on PGLite. Deployment to netcup (Hermes, Dokploy, Postgres, Discord) is the companion **DEPLOYMENT PRD** (§13).
>
> **Upstream:** `github.com/garrytan/gbrain` (MIT). Fork pin: latest stable tag at fork time — at time of writing **v0.41.38.0** (commit `248fb7a9`). Record the exact hash in `CHANGELOG.md`.

---

## 0. Why this rewrite exists (context the agent must understand)

> **Reference — the deprecated v1 fork.** The previous attempt lives on disk at `C:\Users\draco\Desktop\sophia-arcane-vault-old`. It is a single monorepo (`gbrain/` + `sophia-brain/` under one `.git`) and also holds the original `VAULT PRD.md` and `DEPLOYMENT PRD.md`. It is the concrete embodiment of the problems described in this section — inspect it to understand what we're moving away from. Treat it as **read-only reference, not a base**:
> - **Salvage (copy forward):** the markdown brain content under `sophia-brain/`, the SOPHIA-adapted skills, the identity files (`SOUL.md` / `USER.md` / `ACCESS_POLICY.md` / `HEARTBEAT.md`), the seed pages, and the *intent* of the two source patches.
> - **Do NOT reuse:** its `.git` history (orphan — no upstream ancestry), its source patches / OpenClaw deletions, or its single-monorepo layout. The new build starts from a clean clone (§2), never from this folder.

The previous fork was created with `git init` over a *snapshot* of GBrain's files, leaving **no common ancestor with `upstream/master`** — so `git merge upstream` can't do a real three-way merge and every sync degraded into manual whole-tree reconciliation (symptom: `VERSION` drifted to `0.41.38.0` while `package.json` stayed `0.41.14.0`). Against an upstream shipping ~5 commits / ~3 releases per day, that is unsustainable.

Upstream also moved since v1 was written:

1. **Schema packs exist now** (v0.39.1.0; modular default `gbrain-base-v2` at v0.41.22.0). Page-type classification on import is **already pack-driven** (`import-file.ts` reads the active pack's `path_prefixes`). SOPHIA's taxonomy belongs in a **declarative pack**, not source.
2. **Most old source patches are unnecessary** (verified against v0.41.38.0):
   - `link-extraction.ts` — still hardcodes its directory whitelist; no pack path. → **the one patch we keep.**
   - `enrichment-service.ts` — **unreferenced legacy code.** → **drop;** use the pack.
   - `source-boost.ts` — already supports the `GBRAIN_SOURCE_BOOST` env override. → **drop the edit;** use env.
   - OpenClaw deletions — deleting churned files generates recurring conflicts. → **drop;** leave unused.

**And the brain must be its own git repo, not nested in the fork.** gbrain's incremental sync and `doctor sync_freshness` read the brain's HEAD via `git -C <GBRAIN_BRAIN_DIR> rev-parse HEAD` and compare it to the last-synced commit SHA (`git-head.ts`). If the brain sits under the tool repo, that resolves to the *tool* repo's HEAD — which advances on every code commit, breaking the freshness short-circuit. Nesting a `git init`'d brain under the fork also creates an **embedded-repository gitlink** (mode `160000`, `warning: adding embedded git repository`): no `.gitmodules`, content not actually tracked, fresh clones get an empty dir. gbrain's default brain path is `~/git/brain` — a standalone repo — for exactly these reasons.

**Design principle:** *Everything that can live outside the tool source tree, does.* Taxonomy → pack (brain repo). Tuning → env/config. Content → brain repo. Tool fork = code + one seam.

---

## 1. Architecture decisions (LOCKED)

1. **Real ancestry.** The tool fork is a `git clone` of `garrytan/gbrain` at a pinned commit. Never `git init` a snapshot. `upstream` remote + a real merge base must exist.
2. **Pin to a tag/commit, never track `master`.**
3. **Two separate repos.** Tool fork (code) and brain (markdown) are independent git repos, siblings on disk, **never nested**. Linked only by `GBRAIN_BRAIN_DIR`. No submodule, no embedded repo.
4. **Taxonomy lives in a schema pack** (`sophia-base`), source `pack.yaml` version-controlled in the **brain repo**, activated with `gbrain schema use`. Not in TypeScript.
5. **Exactly one source patch:** make `link-extraction.ts`'s directory whitelist extensible via `GBRAIN_LINK_DIRS` (§3). Nothing else in `src/` changes.
6. **Config, not code,** for the rest: source boosts (`GBRAIN_SOURCE_BOOST`), link dirs (`GBRAIN_LINK_DIRS`), storage tiering (`gbrain.yml` in the brain repo), search mode (`gbrain config`).
7. **Retained GBrain mechanics (unchanged):** compiled-truth + timeline, MECE + RESOLVER, takes-vs-facts, tiered concept synthesis, frontmatter-queries + body-link-graph.
8. **Branding is cosmetic and deferred** — non-blocking for the Definition of Done.

---

## 2. The two repos

### 2.1 Repo 1 — the tool fork (code, real upstream ancestry)

```bash
git clone https://github.com/garrytan/gbrain.git sophia-arcane-vault
cd sophia-arcane-vault
git checkout 248fb7a9               # v0.41.38.0 — replace with chosen pin; record in CHANGELOG.md
git checkout -b main
git remote rename origin upstream   # origin (the clone source) = garrytan/gbrain → upstream
git remote add origin https://github.com/sophia-ehr/sophia-arcane-vault.git
git merge-base main upstream/master # MUST print a hash (ancestry real, not "unrelated histories")
```

Apply the §3 patch, add `.env`/`.env.example` (§5). **No brain content lives here.**

### 2.2 Repo 2 — the brain (its own git repo, NOT nested under the fork)

```bash
# Sibling of the fork on disk, e.g. both under Desktop. NOT inside sophia-arcane-vault/.
cd ..                               # back out of the fork
git init sophia-brain               # the brain is its OWN repo root
cd sophia-brain
git remote add origin https://github.com/sophia-ehr/sophia-brain.git
# (existing content at C:\Users\draco\Desktop\sophia-brain can seed this repo as-is)
```

### 2.3 On-disk layout (two siblings, never nested)

```
Desktop/
├── sophia-arcane-vault/        ← Repo 1: the fork (descends from garrytan/gbrain)
│   ├── .git/                   ← real upstream ancestry
│   ├── src/ skills/ docs/ …    ← upstream tool code (untouched except §3)
│   ├── package.json AGENTS.md …
│   └── .env / .env.example     ← config; GBRAIN_BRAIN_DIR points OUT to the brain
│
└── sophia-brain/               ← Repo 2: the brain (sophia-ehr/sophia-brain)
    ├── .git/                   ← its OWN; never nested under the fork
    ├── RESOLVER.md schema.md index.md log.md
    ├── SOUL.md USER.md ACCESS_POLICY.md HEARTBEAT.md gbrain.yml
    ├── _schema/sophia-base/pack.yaml   ← schema-pack source (§4)
    ├── people/ organizations/ tools/ concepts/ meetings/
    ├── strategy/ conferences/ decisions/ deliverables/
    └── inbox/ archive/ sources/
```

### 2.4 Link the tool to the brain + verify the topology

In the fork's `.env`:

```bash
GBRAIN_BRAIN_DIR="../sophia-brain"     # absolute path on the server; relative locally
```

Then **prove the brain resolves to its own repo, not the fork** (the check that prevents the nesting bug):

```bash
git -C "$GBRAIN_BRAIN_DIR" rev-parse --show-toplevel
# → must print the sophia-brain path. If it prints the fork's path, the brain is
#   nested/embedded — STOP and move it out to a sibling directory.
```

---

## 3. The ONLY source patch — `link-extraction.ts` (Repo 1)

The link extractor's directory whitelist is a hardcoded module constant with no config/pack path. Make it env-extensible, mirroring the existing `GBRAIN_SOURCE_BOOST` convention in `search/source-boost.ts`. Additive, upstreamable, and the only `src/` divergence.

**File:** `src/core/link-extraction.ts` — **replace** the single `const DIR_PATTERN = '(?:people|companies|…|entities)';` line with:

```typescript
// SOPHIA: directory whitelist is extensible at runtime via GBRAIN_LINK_DIRS
// (comma-separated), mirroring the GBRAIN_SOURCE_BOOST override in
// search/source-boost.ts. This is the ONLY source divergence from upstream —
// taxonomy lives in the schema pack, tuning in env. Upstreamable as a generic
// "configurable DIR_PATTERN".
const BASE_DIRS = [
  'people', 'companies', 'meetings', 'concepts', 'deal', 'civic',
  'project', 'projects', 'source', 'media', 'yc',
  'tech', 'finance', 'personal', 'openclaw', 'entities',
];
const EXTRA_DIRS = (process.env.GBRAIN_LINK_DIRS ?? '')
  .split(',')
  .map((s) => s.trim())
  .filter(Boolean);
const DIR_PATTERN = `(?:${[...new Set([...BASE_DIRS, ...EXTRA_DIRS])].join('|')})`;
```

**No other edits.** The four regexes interpolating `${DIR_PATTERN}` pick up the new value (computed at module load; env present at startup).

**Config** (fork `.env`):

```bash
GBRAIN_LINK_DIRS=organizations,tools,strategy,conferences,decisions,deliverables,sophia
```

(`people`, `meetings`, `concepts` are already in `BASE_DIRS`.)

**Test:** cross-referencing pages in `tools/` and `decisions/`, run `gbrain extract links --source db`, confirm `gbrain backlinks <slug>` shows the edges.

---

## 4. The Schema Pack — `sophia-base` (replaces the `enrichment-service.ts` patch)

Nine entity types declared once, declaratively. `import-file.ts` classifies pages from the pack's `path_prefixes` automatically — no TS union, no `enrichment-service` patch.

### 4.1 Author and activate

```bash
gbrain schema init sophia-base            # scaffolds a stub pack.yaml
# Replace the stub with §4.2. Version-control the source in the BRAIN repo:
#   sophia-brain/_schema/sophia-base/pack.yaml
# (If `gbrain schema init` scaffolds elsewhere, move the file there and re-point.)
gbrain schema validate                    # must pass
gbrain schema use sophia-base             # activate (stores into the brain DB)
gbrain schema active                      # verify resolution
```

### 4.2 `pack.yaml`

```yaml
api_version: gbrain-schema-pack-v1
name: sophia-base
version: 1.0.0
description: >-
  SOPHIA Health company-brain taxonomy. Nine founder-world entity types
  (person, organization, tool, concept, meeting, strategy, conference,
  decision, deliverable) plus a note catch-all. Standalone — deliberately does
  NOT inherit GBrain's VC-world types (deal, tweet, social-digest, etc.).
gbrain_min_version: 0.41.0   # bump if `gbrain schema validate` requires it
extends: null                # standalone, like gbrain-base-v2
borrow_from: []
takes_kinds: [fact, take, bet, hunch]

page_types:
  - name: person
    primitive: entity
    path_prefixes: [people/, person/]
    aliases: [contact, individual, founder, partner, advisor, hire-candidate]
    extractable: false
    expert_routing: true

  - name: organization
    primitive: entity
    path_prefixes: [organizations/, organization/, companies/, company/, orgs/]
    aliases: [company, org, hospital, competitor, partner-org, vendor, association]
    extractable: false
    expert_routing: false

  - name: tool
    primitive: entity
    path_prefixes: [tools/, tool/]
    aliases: [library, framework, package, platform, saas, software]
    extractable: false
    expert_routing: false

  - name: concept
    primitive: concept
    path_prefixes: [concepts/, concept/]
    aliases: [topic, pattern, regulation, domain-knowledge]
    extractable: false       # forward-compat marker; backstop eligibility is
    expert_routing: false    # still hardcoded in eligibility.ts pre-v0.43

  - name: meeting
    primitive: temporal
    path_prefixes: [meetings/, meeting/]
    aliases: [call, sync, standup]
    extractable: true
    expert_routing: false

  - name: strategy
    primitive: concept
    path_prefixes: [strategy/]
    aliases: [positioning, strategic-doc, plan]
    extractable: true
    expert_routing: false

  - name: conference
    primitive: temporal
    path_prefixes: [conferences/, conference/, events/]
    aliases: [event, trade-show, congress, demo-day]
    extractable: false
    expert_routing: false

  - name: decision
    primitive: annotation
    path_prefixes: [decisions/, decision/]
    aliases: [adr, choice, ruling]
    extractable: true
    expert_routing: false

  - name: deliverable
    primitive: entity
    path_prefixes: [deliverables/, deliverable/]
    aliases: [artifact, deck, proposal, one-pager, application]
    extractable: false
    expert_routing: false

  - name: note
    primitive: annotation
    path_prefixes: [inbox/, notes/]
    aliases: []
    extractable: false
    expert_routing: false

link_types:
  - { name: works_at,        inverse: employs }
  - { name: advises,         inverse: advised_by }
  - { name: part_of,         inverse: has_part }
  - { name: competes_with,   inverse: competes_with }
  - { name: partners_with,   inverse: partners_with }
  - { name: integrates_with, inverse: integrates_with }
  - { name: replaces,        inverse: replaced_by }
  - { name: evaluated_in }
  - { name: produced,        inverse: produced_by }
  - { name: affects,         inverse: affected_by }
  - { name: informed_by,     inverse: informs }
  - { name: derived_from,    inverse: derives }
  - { name: targets,         inverse: targeted_by }
  - { name: presented_at }
  - { name: attended,        inverse: attended_by }
  - { name: authored,        inverse: authored_by }
  - { name: supersedes,      inverse: superseded_by }
  - { name: mentions }
  - { name: relates_to,      inverse: relates_to }
```

### 4.3 Notes

- `primitive` is a closed enum: `entity | media | temporal | annotation | concept`. Drives default link verbs, enrichment rubric, expert-routing. Don't invent primitives.
- `mapping_rules` omitted — fresh brain, no legacy pages to migrate. Add a `*unknown*` catch-all retype only if importing legacy content later.
- If validation rejects `gbrain_min_version: 0.41.0`, raise to match the pin (base-v2 declares `0.42.0`).
- The pack source lives in the **brain repo** → not fork divergence; survives every upstream merge untouched.

---

## 5. Config, not code

**Fork `.env`** (gitignored) + `.env.example` (committed, no secrets):

```bash
GBRAIN_BRAIN_DIR="../sophia-brain"      # the separate brain repo; absolute on server
GBRAIN_LINK_DIRS=organizations,tools,strategy,conferences,decisions,deliverables,sophia
GBRAIN_SOURCE_BOOST="strategy/:1.5,organizations/:1.3,people/:1.2,decisions/:1.2,concepts/:1.2,tools/:1.1,deliverables/:1.0,conferences/:1.0,meetings/:1.0,inbox/:0.8,sources/:0.7,archive/:0.6"
GBRAIN_SEARCH_EXCLUDE=".raw/,archive/"
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
ZEROENTROPY_API_KEY=
```

**Storage tiering** — `sophia-brain/gbrain.yml` (brain repo):

```yaml
storage:
  db_tracked:        # version-controlled, human-curated
    - people/
    - organizations/
    - tools/
    - concepts/
    - strategy/
    - decisions/
    - conferences/
    - deliverables/
  db_only:           # machine-generated bulk; gitignored by `gbrain sync`
    - meetings/transcripts/
    - sources/
```

**Search mode:** `gbrain config set search.mode balanced`.

---

## 6. DO-NOT list (anti-patterns that re-create the mess)

- ❌ **Do not `git init` a snapshot** for the fork — clone with history (§2.1).
- ❌ **Do not nest the brain inside the fork** (or `git init` a subdir of it). That creates an embedded-repo gitlink and pollutes gbrain's HEAD-based freshness. Brain = its own repo, sibling on disk (§2.2). Verify with `--show-toplevel` (§2.4).
- ❌ **Do not make the brain a submodule.** High friction for an agent that writes to it continuously.
- ❌ **Do not track `upstream/master`** — pin to a tag/commit.
- ❌ **Do not patch `enrichment-service.ts`** (unreferenced legacy; pack handles typing).
- ❌ **Do not edit `source-boost.ts`** — use `GBRAIN_SOURCE_BOOST`.
- ❌ **Do not delete OpenClaw files** — leave them unused (avoid merge churn).
- ❌ **Do not hardcode SOPHIA dirs in `link-extraction.ts`** — use the `GBRAIN_LINK_DIRS` seam.
- ❌ **Do not put the schema pack in the fork's `src/`** — it lives in the brain repo.

---

## 7. Entity taxonomy reference (page conventions)

The pack (§4) governs *typing*; this governs *page shape*. Every page uses **compiled-truth + timeline**: current-state summary above `---`, append-only dated/sourced timeline below. Frontmatter → metadata queries; inline `[Name](dir/slug)` body links → graph (intentional redundancy).

**Frontmatter contracts (required fields in bold):**

- **person** — `**type**: person`, `**title**`, `role`, `organization` (link), `relationship: team|advisor|hospital-user|hospital-buyer|investor|coach|researcher|industry|content-creator|hire-candidate`, `status: active|dormant|former`, `aliases`, `tags`. Claims tagged `(observed: …)` / `(self-described: …)` / `(inferred: …, confidence: …)`.
- **organization** — `**type**: organization`, `**title**`, `**category**: hospital|competitor|accelerator|funding-body|infra-provider|partner|vendor|association|department`, `**status**: captured|in-conversation|active-pilot|contracted|rejected|watching`, `parent_org` (slug, for `department`), `region: DACH|EU|global`, `product_relevance`, `company_relevance`, `deadline`.
- **tool** — `**type**: tool`, `**title**`, `**category**: product|team|reference`, `**status**: captured|evaluating|adopted|rejected|watching`, `license`, `discovered_by` (link), relevance fields, `tags`. Status changes reference the relevant `decisions/` page.
- **concept** — `**type**: concept`, `**title**`, `domain: technical|business|regulatory|clinical`, relevance fields. Compiled truth = SOPHIA's own synthesis, kept short; bulk captures → timeline riffs; re-tier periodically.
- **meeting** — `**type**: meeting`, `**title**`, `**date**`, `meeting_type: full-team|tech|orga|advisory|coaching|hospital|investor|conference-followup`, `attendees` (links). After creation, propagate to referenced people/decisions/strategy pages.
- **strategy** — `**type**: strategy`, `**title**`, `category: product|business|technical|positioning|compliance`, `status: draft|active|superseded|archived`, `owner` (link), `last_reviewed`. Living doc — compiled truth always current.
- **conference** — `**type**: conference`, `**title**`, `**date**`, `location`, `status: scouted|registered|attended|skipped`, relevance fields, `deadline`.
- **decision** — `**type**: decision`, `**title**`, `**date**`, `made_by` (link), `status: proposed|accepted|revisited|superseded`, `supersedes` (link), `tags`. Body: Decision / Context / Options / Rationale / Consequences.
- **deliverable** — `**type**: deliverable`, `**title**`, `**date**`, `audience: investor|advisor|customer|accelerator|internal`, `format`, `location` (URL), `status: current|outdated|archived`, `derived_from` (links). Includes a staleness-check note vs current strategy.

**Slug formats:** entities `dir/kebab-name`; meetings `meetings/YYYY-MM-DD-name`; conferences `conferences/name-year`.

---

## 8. Brain scaffolding (Repo 2)

Recreate (or verify, if seeding from the existing `sophia-brain` folder) this structure. Each entity dir has a `README.md` resolver and a gitignored `.raw/`.

```
sophia-brain/
├── RESOLVER.md schema.md index.md log.md
├── SOUL.md USER.md ACCESS_POLICY.md HEARTBEAT.md gbrain.yml
├── _schema/sophia-base/pack.yaml
├── people/ organizations/ tools/ concepts/ meetings/
├── strategy/ conferences/ decisions/ deliverables/
└── inbox/ archive/ sources/
```

### 8.1 `RESOLVER.md` — master filing decision tree (first match wins)

1. Human → `people/`
2. Org / hospital / company / professional body → `organizations/` (`category`; `parent_org` for departments)
3. Software tool / library / framework / platform / SaaS → `tools/` (`category: product|team|reference`)
4. Reusable concept / pattern / regulation / domain knowledge → `concepts/` (`domain`)
5. Meeting / call record → `meetings/`
6. Living strategic document → `strategy/`
7. Event / conference / demo day → `conferences/`
8. Discrete team choice → `decisions/`
9. External-audience artifact → `deliverables/`
10. Fits nothing → `inbox/` (schema needs a new type)

Include the misfiling table (tool-eval→`tools/` not `concepts/`; YouTube-about-a-tool→timeline entry not new page; department→own `organizations/` page w/ `parent_org`; meeting outcome→ALSO update decisions/strategy/tools; accelerator application→`deliverables/` not `strategy/`; current pricing→`strategy/` not `deliverables/`; competitor→`organizations/ category: competitor`; regulatory requirement→`concepts/ domain: regulatory`). MECE: one primary home per fact; cross-refs preserve adjacency.

### 8.2 Per-directory `README.md`

Each states (a) what goes here + a concrete test, (b) what does NOT (neighbor distinctions), (c) required frontmatter. Use the `tools/README.md` template from v1 §5.3.

### 8.3 Seed pages

- `organizations/sophia-health.md`
- `strategy/`: pricing-model, tech-architecture, competitive-positioning, product-roadmap
- `people/`: moritz, julian, sebastian, fiona, robert; advisors carsten-jacobsen, michael-stickel
- `organizations/`: kantonsspital-st-gallen, klinikum-landshut, charite-berlin, mvz-singen, akh-wien
- `tools/` (status: adopted): langchain, langgraph, copilotkit, docling, orpc, supabase, stackit, vite, react, bun
- `decisions/`: langchain-over-llamaindex, stackit-as-sole-provider, bun-over-node

Verify cross-references resolve; `gbrain sync` to index.

### 8.4 `scripts/seed.sh` (brain repo)

Create this in the brain repo. It seeds the DB from the markdown system of record using the globally-installed `gbrain` (from the fork) and `GBRAIN_BRAIN_DIR`. Defaults to PGLite; pass `--postgres` with `DATABASE_URL` set for the deployed engine (the DEPLOYMENT PRD uses this path).

```bash
#!/usr/bin/env bash
# Seed the SOPHIA brain DB from the markdown system of record.
# Run once after clone, or after wiping the DB. Idempotent where possible.
# Default engine: PGLite (zero-config). For Postgres: ./seed.sh --postgres (needs DATABASE_URL).
set -euo pipefail

# Resolve brain dir: explicit env wins, else this script's parent (scripts/ -> brain root).
BRAIN_DIR="${GBRAIN_BRAIN_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
export GBRAIN_BRAIN_DIR="$BRAIN_DIR"

ENGINE_FLAG=""
if [[ "${1:-}" == "--postgres" ]]; then
  : "${DATABASE_URL:?--postgres requires DATABASE_URL}"
  ENGINE_FLAG="--postgres"
fi

# Topology guard: the brain must be its OWN git repo, not nested in the fork.
TOPLEVEL="$(git -C "$BRAIN_DIR" rev-parse --show-toplevel 2>/dev/null || echo '')"
if [[ "$TOPLEVEL" != "$BRAIN_DIR" ]]; then
  echo "WARN: '$BRAIN_DIR' is not its own git root (toplevel: '${TOPLEVEL:-none}')." 1>&2
  echo "      gbrain commit-relative sync freshness will be unreliable. See PRD §2.4." 1>&2
fi

echo "=== SOPHIA Brain seed — $BRAIN_DIR (${ENGINE_FLAG:-pglite}) ==="
gbrain init $ENGINE_FLAG 2>/dev/null || true     # 0) init DB (idempotent)
gbrain schema use sophia-base                     # 1) ensure taxonomy active
gbrain import "$BRAIN_DIR" --no-embed             # 2) import markdown
gbrain embed --stale                              # 3) embeddings (needs OPENAI/ZEROENTROPY key)
gbrain extract links --source db                  # 4) wire the graph
gbrain extract timeline --source db               # 5) index timeline
gbrain doctor --json                              # 6) verify
echo "=== done — try: gbrain query 'What tools has SOPHIA adopted?' ==="
```

`chmod +x scripts/seed.sh`. Commit it to the brain repo.

---

## 9. Identity & branding

Identity files ship in the **brain repo** so it works without the interactive soul-audit: `SOUL.md` (Archivar persona — direct, cite sources, German clinical / English technical, Forbidden-Lore boundary = no patient data here), `USER.md` (operator Moritz + team), `ACCESS_POLICY.md` (shared team read; Archivar read/write; source-trust hierarchy), `HEARTBEAT.md` (cadence template; deployment values filled by the DEPLOYMENT PRD).

**Branding (deferred, non-blocking, in the fork repo):** README/AGENTS/CLAUDE/INSTALL narrative rewrites, URL swaps to `sophia-ehr`, `package.json` name → `arcane-vault`, llms.txt regen. Single late commit; does not gate §11.

---

## 10. Implementation checklist

**Phase 0a — Tool fork (§2.1)**
- [ ] Clone upstream; checkout pin; create `main`; rename remotes; add `origin`
- [ ] `git merge-base main upstream/master` returns a hash
- [ ] Record pin hash in `CHANGELOG.md`

**Phase 0b — Brain repo (§2.2)**
- [ ] `git init sophia-brain` as a **sibling** of the fork; add `origin` (`sophia-ehr/sophia-brain`)
- [ ] `git -C "$GBRAIN_BRAIN_DIR" rev-parse --show-toplevel` == the brain path (NOT the fork)

**Phase 1 — The one patch (§3)**
- [ ] Apply the `GBRAIN_LINK_DIRS` seam in `link-extraction.ts`; `bun test` green

**Phase 2 — Schema pack (§4)**
- [ ] `gbrain schema init sophia-base`; paste §4.2; store source in `sophia-brain/_schema/`
- [ ] `gbrain schema validate` passes; `gbrain schema use sophia-base`; `gbrain schema active` confirms

**Phase 3 — Config (§5)**
- [ ] Fork `.env` + `.env.example`; `sophia-brain/gbrain.yml`; `gbrain config set search.mode balanced`

**Phase 4 — Brain content (§8)**
- [ ] Structure, RESOLVER, READMEs, seed pages, identity files in the brain repo

**Phase 5 — Seed & verify (§11)**
- [ ] `sophia-brain/scripts/seed.sh` (init → import → embed → extract links → extract timeline → doctor)
- [ ] Smoke-test queries pass

**Phase 6 — Branding (deferred, §9)** — optional, single commit

**Phase 7 — Maintenance (§12)**
- [ ] `git fetch upstream && git log --oneline upstream/master..HEAD` shows only the §3 patch + config in the fork

---

## 11. Smoke test & Definition of Done

```bash
# Two repos, sibling dirs
git clone https://github.com/sophia-ehr/sophia-arcane-vault.git
git clone https://github.com/sophia-ehr/sophia-brain.git
cd sophia-arcane-vault
bun install
cp .env.example .env                       # set GBRAIN_BRAIN_DIR=../sophia-brain, fill keys
git -C ../sophia-brain rev-parse --show-toplevel   # == sophia-brain path (topology check)
gbrain schema validate && gbrain schema use sophia-base
../sophia-brain/scripts/seed.sh            # PGLite locally
gbrain query "What tools has SOPHIA adopted?"      # → tools with status: adopted
gbrain query "Who are our hospital contacts?"      # → people w/ hospital relationships
gbrain backlinks decisions/langchain-over-llamaindex   # → edges to tools/strategy
```

**Done when:** (1) fork ancestry verified via `git merge-base`; (2) brain `--show-toplevel` == brain repo (not nested); (3) fork `src/` diff vs the pin is **only** the `link-extraction.ts` seam; (4) `gbrain schema active` = `sophia-base`; (5) smoke-test queries return correct results; (6) an agent can reproduce the build from this PRD unattended.

---

## 12. Fork maintenance (now clean)

Fork divergence = **1 source file** (`link-extraction.ts`) + `.env`. The brain (pack, content, `gbrain.yml`) isn't in the fork at all. Periodic sync:

```bash
cd sophia-arcane-vault
git fetch upstream
git log --oneline <current-pin>..upstream/master   # review churn
git checkout -b sync/<new-tag>
git merge <new-tag>                                 # REAL 3-way merge; conflicts only possible
                                                    # in link-extraction.ts (and only if upstream
                                                    # also makes DIR_PATTERN configurable)
bun run ci:local
GBRAIN_BRAIN_DIR=../sophia-brain ../sophia-brain/scripts/seed.sh   # re-verify against the brain
```

- **Pin forward deliberately,** tag by tag.
- **Upstream the patch** if possible (a configurable-`DIR_PATTERN` PR drops divergence to zero).
- **Watch pack-eligibility wiring (v0.43+):** when `extractableTypesFromPack` lands in `facts/eligibility.ts`, the pack's `extractable: true` flags go live automatically.
- **Brain repo** versions independently — `git diff` shows exactly what the agent learned, with no tool-code noise.

---

## 13. Handoff to the DEPLOYMENT PRD

This PRD ends at **two locally-verified repos** (PGLite, smoke test green). The companion **SOPHIA Brain Deployment PRD** (`C:\Users\draco\Desktop\sophia-arcane-vault` → DEPLOYMENT) begins here and owns:

- Hermes as a standalone service on netcup (Dokploy/Docker)
- Hermes deploying the brain stack (the fork + **Postgres**, not PGLite) via Dokploy API; cloning the **brain repo** onto the server and pointing `GBRAIN_BRAIN_DIR` at it
- Connecting Hermes to GBrain over HTTP MCP
- Running `seed.sh` against Postgres (`--postgres` + `DATABASE_URL`)
- Finalizing `HEARTBEAT.md` deployment values (host, orchestration, both repo URLs)
- Discord channel + bot setup; monitoring; operational cadence

**Precondition:** §11 Definition of Done met. The deployment PRD assumes two clean, pinned, ancestry-correct repos with `sophia-base` active and the smoke test passing — it re-does no fork or patch work.

---

### Appendix A — What changed (v1 → v2.1)

| v1 (deprecated) | v2.1 (this doc) |
|---|---|
| `git init` snapshot, no upstream ancestry | `git clone` + pin → real merge base |
| Single monorepo; brain nested under the tool tree | **Two repos**: fork (code) + brain (markdown), siblings, linked by `GBRAIN_BRAIN_DIR` |
| (risk) brain `git init` inside repo → embedded-repo gitlink + polluted HEAD freshness | brain is its own repo; `--show-toplevel` check enforces it |
| Nine types hardcoded; patch `enrichment-service.ts` | Nine types in `sophia-base` pack (in the brain repo) |
| Patch `link-extraction.ts` w/ hardcoded SOPHIA dirs | One env seam (`GBRAIN_LINK_DIRS`), no hardcoded dirs |
| Patch `source-boost.ts` | `GBRAIN_SOURCE_BOOST` env |
| Delete OpenClaw files | Leave them |
| ~4 patched files + deletions | **1** patched file + pack + config |
| Fork pin v0.41.14.0 (pre-pack) | Pin v0.41.38.0 (pack system mature) |
