# sophia-arcane-vault

Fork of [GBrain](https://github.com/garrytan/gbrain) that serves as the engine for
SOPHIA's company knowledge brain. GBrain keeps a knowledge base as plain markdown
(the system of record) and layers hybrid search, a self-wiring knowledge graph, and
a nightly enrichment cycle on top. This repo is the tool code; the content lives in
the sibling `sophia-brain` repo.

Company knowledge only — no clinical or patient data lives here.

## Layout

```
Desktop/
├── sophia-arcane-vault/   ← this repo (GBrain fork, TypeScript/Bun)
└── sophia-brain/          ← markdown content (system of record)
```

The brain is a sibling, never nested. The engine finds it via
`GBRAIN_BRAIN_DIR=../sophia-brain` in `.env`. `sophia-brain/scripts/seed.sh`
warns if the brain isn't its own git root (commit-relative sync breaks otherwise).

## Setup

```bash
git clone https://github.com/sophia-ehr/sophia-arcane-vault.git
git clone https://github.com/sophia-ehr/sophia-brain.git
cd sophia-arcane-vault

bun install
cp .env.example .env          # add OPENAI / ANTHROPIC / ZEROENTROPY keys;
                              # GBRAIN_BRAIN_DIR already points at ../sophia-brain

../sophia-brain/scripts/seed.sh        # init → schema → import → embed → links → timeline → doctor
gbrain query "What tools has SOPHIA adopted?"
```

`embed` needs an OpenAI or ZeroEntropy key. For Postgres instead of PGLite:
`../sophia-brain/scripts/seed.sh --postgres` (needs `DATABASE_URL`).

## SOPHIA-specific config

Most of `src/` is upstream GBrain and should stay identical to the pin. Our
divergence is configured through `.env` plus one schema pack:

- `GBRAIN_BRAIN_DIR=../sophia-brain` — sibling topology
- `GBRAIN_LINK_DIRS=…,sophia` — link-extraction directory whitelist (extends `BASE_DIRS` in `link-extraction.ts`)
- `GBRAIN_SOURCE_BOOST="strategy/:1.5,organizations/:1.3,…"` — per-directory search weighting
- `GBRAIN_SEARCH_EXCLUDE=".raw/,archive/"`
- `sophia-base` schema pack — 9 types (person, organization, tool, concept, meeting, strategy, conference, decision, deliverable). Source in `sophia-brain/_schema/sophia-base/`; activated by `gbrain schema use sophia-base`.

Hybrid search, the knowledge graph, the dream cycle, Minions, and the MCP server
are upstream. This README doesn't repeat the upstream docs.

## Status

*Snapshot: 2026-05-31.*

Done:
- Working checkout pinned at v0.41.38.0 (`VERSION` and `package.json` agree). `bun install` done.
- SOPHIA `.env.example` with the four seams above.
- `sophia-base` schema pack; `sophia-brain/scripts/seed.sh`.
- PRDs in repo: `VAULT-PRD-v2.1-two-repo.md`, `DEPLOYMENT-PRD-v2-two-repo.md`, `DESIGN.md`.
- Brain seeded (~30 pages) and queryable end-to-end.

Not done:
- De-brand commit (still upstream-branded):
  - `package.json` `name` is `gbrain` → rename to `arcane-vault`; remove the `openclaw` block and the `clawhub` publish scripts.
  - Remove `openclaw.plugin.json` and the `src/openclaw-context-engine.ts` extension.
  - Rewrite `README.md`, `AGENTS.md`, `CLAUDE.md`, `INSTALL_FOR_AGENTS.md`; regenerate `llms.txt` / `llms-full.txt`; swap `garrytan/gbrain` URLs → `sophia-ehr`.
- Hermes / the Archivar is not deployed (`sophia-brain/HEARTBEAT.md` → `[filled after deployment]`). Until then the brain is maintained by hand; the 15-min patrol, nightly `gbrain dream`, weekly doctor, and Discord channels are idle.
- Meeting transcript capture not set up.
- Clean upstream ancestry: the fork was created from a snapshot, so it may lack a merge-base with upstream. A re-fork from the pinned tag makes future merges real three-way merges. Track against the pin, not `master`.

## Querying

```bash
gbrain search "DACH-compliant documentation"      # ranked pages, no LLM
gbrain query  "What's our position vs 44ai?"        # synthesized answer + citations
gbrain backlinks decisions/langchain-over-llamaindex
```

## Fork maintenance

- Upstream `garrytan/gbrain`, pinned v0.41.38.0. Don't track `master` (it ships several releases a day).
- `git fetch upstream && git log --oneline upstream/master..HEAD` should show only the seams + config + branding.
- Record the pin hash in `CHANGELOG.md` on every intentional bump.

## Pointers

- Engine config → `.env` (template `.env.example`)
- Storage tiering → `gbrain.yml` (both repos)
- Plan of record → the two PRDs above
- Content + page conventions → `sophia-brain` and its `README.md` / `RESOLVER.md` / `schema.md`
- Agent context → `AGENTS.md`, `CLAUDE.md` (still upstream; part of the de-brand commit)