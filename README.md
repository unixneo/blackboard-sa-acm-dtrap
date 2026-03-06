# Blackboard SA: Situation Awareness Architecture

**Version 0.1**

An implementation of Tim Bass's 1999 multisensor data fusion architecture for
continuous situation awareness, updated for the age of large language models.

Evidence windowing, hypothesis gating, and configurable thresholds are built in.
Original event-bus implementation is preserved on the `original_blackboard` branch.


## Citation (Preprint)

Bass, Tim. "Blackboard SA: Operationalizing LLM Knowledge Source Specialization for Cyber Situational Awareness." Preprint, Zenodo, 2026. https://zenodo.org/records/18824512

## Code (Private Repo - Request Access)

https://github.com/unixneo/blackboard

---

## Architecture

### Key Insight: LLMs Replace Data Refinement

The original Bass 1999 architecture defined **Level 0 (Data Refinement)** as a
preprocessing layer requiring format-specific parsers, timestamp normalization, regex field
extraction, and data cleansing.

**In 2026, this layer is no longer necessary.** Large language models can directly
understand raw log data without preprocessing. The LLM *is* the data refinement layer.
Raw logs go directly into the blackboard; the LLM Normalizer produces human-readable
descriptions and entity extractions in a single step.

### Fusion Levels (Updated for LLMs)

| Bass 1999 | Blackboard 2026 | Implementation |
|-----------|-----------------|----------------|
| L0: Data Refinement | ~~Not needed~~ | Raw ingestion only |
| L1: Object Refinement | LLM Normalizer | Natural language + entity extraction |
| L2: Situation Assessment | LLM Proposer + Devil's Advocate + Verifier | Hypothesis generation, critique, verification |
| L3: Threat Assessment | LLM Correlator → Alerts | Cross-hypothesis correlation and escalation |
| L4: Resource Management | Control Shell (health monitor) | System health observation |

### Architecture Name: Blackboard SA (Situation Awareness)

This system uses **structured dialectic deliberation** rather than the purist opportunistic
blackboard model. Every knowledge source gets a guaranteed voice in a fixed logical sequence:
propose → critique → verify → correlate. The control shell is kept simple — it knows the
event type and queues the appropriate job, with no priority scoring or capability modeling.

The result is an SA-oriented architecture: the objective is persistent, explainable context
for operator decisions, not only binary intrusion detection.

The analogy is an expert panel with a fixed agenda: everyone sees the same evidence, each
expert speaks in a defined order, and no expert is crowded out by volume or speed.

### Pipeline: Job-Chaining Architecture

The pipeline is implemented as a **direct job chain**: each Sidekiq job enqueues the next
stage when it completes. There is no intermediate event bus or registry — the chain is
explicit and traceable in Sidekiq's queue.

```
SensorIngestionJob (recurring, 30s)
  └─→ NormalizerJob        (batched; up to 50 observables per LLM call)
        └─→ WindowBuilderJob   (stratified sampling into EvidenceWindows; novelty filter)
              └─→ ProposerJob  (batched; proposes hypotheses from an EvidenceWindow)
                    └─→ HypothesisGateJob   (confidence/evidence/novelty gate; no LLM)
                          └─→ CriticJob     (batched; devil's advocate critique)
                                └─→ VerifierJob      (per hypothesis; staggered dispatch)
                                      └─→ [Verification.check_corroboration]
                                            └─→ AlertJob      (per corroborated hypothesis)
                                      └─→ [Verification.after_create_commit]
                                            └─→ CorrelatorJob (debounced; links patterns)
```

**Entry point:** `SensorIngestionJob` reads log files, creates `Observable` records, and
calls `NormalizerJob.enqueue_once`. Everything downstream is driven by job completion.

**Prefilter stages (cost + noise control):**
- Sensor prefilter (`filter_patterns`) runs before observable creation in ingestion.
- L1 KS prefilter runs in `NormalizerJob` before L1 LLM calls (`normalizer_pre` stage).
- Proposer prefilter fallback runs post-normalization (`proposer` stage) for residual low-value rows.

**EvidenceWindow:** `WindowBuilderJob` groups normalized observables into time-bounded
windows using stratified sampling (min K per sensor type, max total cap, novelty
suppression via Jaccard similarity). During historical backlog-drain mode (when the live
window is empty and processing older unlinked observables), novelty suppression is bypassed
so proposer throughput cannot deadlock on repeated low-novelty windows. The `Proposer` LLM
analyzes one window at a time, giving it a coherent multi-sensor evidence set rather than
a raw firehose.

Proposer always chooses the oldest evidence window that still contains actionable unlinked
observables (even if that window already produced earlier hypotheses), so partially covered
windows keep draining. When Proposer returns `[]` for a window, those observables are marked
in metadata as `proposer_skipped` (triaged non-actionable). All proposer backlog checks
(dashboard, supervisor, KS-enable kick, and window selection) use the same actionable
definition: normalized observables not linked to a hypothesis and not `proposer_skipped`.
To avoid endless parse-retry loops, proposer attempt metadata is tracked per observable and
items that exceed `proposer.max_attempts_per_observable` are auto-triaged with explicit
skip reasons.

**HypothesisGate:** A lightweight (no LLM) filter between Proposer and Critic. Hypotheses
below any of four configurable signal thresholds (`gate.min_confidence`,
`gate.min_evidence_count`, `gate.min_sensor_diversity`, `gate.min_novelty`) are discarded
before incurring Critic LLM cost.

**Deduplication:** Each batched job class has a `self.enqueue_once` method with a
Rails.cache gate that prevents duplicate concurrent runs. Per-hypothesis jobs
(`VerifierJob`, `AlertJob`) have no gate — they're naturally deduplicated by hypothesis ID.

**Supervisor safety net:** `PipelineSupervisorJob` runs every `supervisor.interval` seconds
to kick stalled stages when a KS is active but backlog is waiting.

### Knowledge Sources

Each LLM agent is a `KnowledgeSource` record (stored in the DB) with a configurable
system prompt, provider, and model. The job fetches the active KS for its role at runtime.

> **Detection behavior is controlled by KS system prompts, not code.** Adding a new attack
> class (e.g. DoS, bot/scraper) means editing the Proposer's system prompt — no deploy
> required. Prompts are version-controlled in `db/seeds.rb` and editable live via
> `/knowledge_sources`. See DESIGN.md §9 for the full treatment.

| Job | Role | Trigger |
|-----|------|---------|
| `SensorIngestionJob` | Log reader | Self-scheduling, every 30s |
| `NormalizerJob` | L1 normalizer | Sensor ingestion produces new observables |
| `WindowBuilderJob` | L2 evidence assembly | Normalizer completes |
| `ProposerJob` | L2 proposer | WindowBuilder creates an EvidenceWindow |
| `HypothesisGateJob` | L2 gate (no LLM) | Proposer creates hypotheses |
| `CriticJob` | L2 devil's advocate | Gate passes hypotheses |
| `VerifierJob` | L2 verifier | CriticJob dispatches per qualifying hypothesis |
| `CorrelatorJob` | L3 correlator | Any new Verification |
| `AlertJob` | L3 alert | Hypothesis reaches `corroborated` |

### LLM Provider Support

Four providers supported; configurable per knowledge source or globally:

| Provider | Default Model | Wire Format | Notes |
|----------|---------------|-------------|-------|
| Anthropic | `claude-sonnet-4-6` | Anthropic | Explicit prompt caching |
| DeepSeek | `deepseek-chat` | Anthropic-compatible | Auto KV prefix caching |
| Groq | `llama-3.3-70b-versatile` | OpenAI-compatible | No caching |
| Mistral | `mistral-small-latest` | OpenAI-compatible | No caching |
| Ollama (local) | `llama3.2:3b` | OpenAI-compatible | No API key; 120s read timeout |

`KsProviderClient.for(ks)` builds the right client. `KsProviderClient.build(provider_key)`
builds a client from a provider string directly (used by the fallback path).

**Seed defaults:** New KS records are seeded to use Groq with `llama-3.1-8b-instant` as the
primary model and Mistral `mistral-small-latest` as the fallback. These can be overridden
per KS in `/knowledge_sources`.

Ollama is configured with a 120-second read timeout to accommodate local hardware latency.
Add locally-pulled models to the `models` array in `KsProviderClient::PROVIDERS["ollama"]`.

**LLM Fallback:** On any LLM error, the pipeline automatically retries with a configurable
fallback provider/model (default: Anthropic Haiku for the global fallback setting). If both fail, Sidekiq retries the job
with exponential backoff. Each attempt is logged as a separate `LlmCall` record with a
`fallback` boolean for observability.

**Prompt caching:**
- Anthropic: explicit `cache_control: ephemeral` on system prompts (~10× cheaper on hits)
- DeepSeek: automatic KV prefix caching, no config needed
- Groq/Ollama: no caching

### Hypothesis State Machine

`Hypothesis#transition_status!` enforces forward-only status progression under a
PostgreSQL row lock (`SELECT FOR UPDATE`). Invalid or concurrent transitions are silently
skipped with a log warning.

```
proposed → critiqued → corroborated → alerted
    ↓           ↓            ↓
dismissed   dismissed    dismissed
```

### LLM Attribution

Every pipeline entity is linked back to the `LlmCall` record that created it, enabling
full per-entity auditability of which provider and model did the work.

**Schema additions (migration `20260220000002`):**
- `llm_calls.provider` — denormalized at call time for historical accuracy (provider config
  can change; the record captures what was actually used)
- `observables.llm_call_id`, `hypotheses.llm_call_id`, `critiques.llm_call_id`,
  `verifications.llm_call_id` — nullable FK to `llm_calls`

**How it flows:**
1. `LlmPipelineMethods#execute_llm_call` stores the created `LlmCall` in `@last_llm_call`
   and records `provider:` on it
2. Each job passes `llm_call_id: @last_llm_call&.id` when creating or updating the
   pipeline entity it produces
3. Controllers eager-load `:llm_call` via `includes` to avoid N+1 queries

**UI surfaces:**
- `/observables` — "LLM" column showing provider + model + duration for each normalized observable
- `/observables/:id` — provider/model shown in the Normalized Description card header
- `/hypotheses` — "LLM" column showing the proposer LLM + duration for proposed/critiqued hypotheses; correlator LLM for corroborated/alerted
- `/hypotheses/:id` — LLM info in the detail-meta line next to "Proposed by"; attack chain visualization when correlator has linked hypotheses; confidence history timeline (per-step delta + reason from `metadata["confidence_history"]`); gate scores breakdown grid from `metadata["gate_scores"]`
- `/campaigns` — L3 Campaigns view: corroborated/alerted hypotheses that are part of multi-stage attack chains (have a parent hypothesis); nav link under L3 Threat Assessment with live count badge
- `/critiques` — provider/model/duration appended to the "By: … • date" footer of each critique card
- `/verifications` — "LLM" column per verification row with duration
- `/alerts` — clean table with severity, summary, hypothesis, status, created; attack chain moved to detail page
- `/alerts/:id` — ⛓ Attack Chain card (amber left border) showing parent → child attack type and full correlation reason; appears when hypothesis has a parent
- `/knowledge_sources` — cards ordered by MSDF pipeline position (L1 → L2 → L3) with section dividers; each card shows its L? level badge; avg latency per KS shown next to model name
- `/knowledge_sources/:id` — "Provider" and "Model" columns in the Recent LLM Calls table; resolved provider shown in the header detail-meta
- `/settings` — Display section for `display.timezone`; Data Management table with per-dataset clear buttons
- Dashboard (`/`) — Pipeline Backlog table now shows **actionable** backlog counts at each handoff (not raw status totals), includes proposer drain trend (`Δ/5m`) under `Normalized → Hypothesis`, and includes live Sidekiq queue depth breakdown (`default`, `sensors`, `supervisor`, `control_shell`, `mailers`, `other`) with reconciled total; KS Performance table (24h calls, avg latency, success rate, cost per KS; all-time total) with rows grouped and sorted descending by MSDF level (L3 → L2 → L1) and a compact L? badge per row; LLM Observability block (calls, tokens in/out, avg latency, cost today); per-call cost in the recent calls table; Provider Consoles card with direct links to each provider's usage page
- `/sensors` — enabled and disabled sensors shown in separate cards; disabled card omits the Ingestion column and shows only Enable / Edit / Delete actions
- `/sensors` — separate prefilter observability cards: `Sensor Prefilter` (drops before observables exist) and `L1 KS Prefilter` (drops before L1 LLM calls).
- `/observables` — status distinguishes `L1 KS Prefiltered` (no LLM call) vs `Proposer Prefiltered` (post-LLM fallback); sensor-prefilter drops are not listed because no observable row is created.

### Cost Tracking

`KsProviderClient::MODEL_COSTS` stores per-model input/output/cache-read prices (USD per million tokens). Every successful LLM call computes and stores `cost_usd` on the `LlmCall` record at creation time via `KsProviderClient.compute_cost`.

- Providers with `free_tier: true` (Mistral, Ollama) always return `nil` from `compute_cost` — no cost recorded
- Cache-read tokens are billed at the provider's `cost_cache_read` rate (Anthropic: 10% of input; DeepSeek: 10% of input)
- Failed calls receive `nil` cost (no token counts available)
- Free-tier calls display `$0.000000` in the UI rather than `—` to distinguish "zero cost" from "no data"

**Dashboard cost metrics and domain filtering:**

| Metric | Domain Filtered |
|--------|----------------|
| Cost Today (`@llm_cost_today`) | ✅ Yes |
| Total 24h cost (`@total_cost_24h`) | ✅ Yes |
| All-time cost (`@total_cost_alltime`) | ✅ Yes |
| Per-KS cost_24h / cost_alltime | ✅ Yes |

To upgrade a provider from free to paid: set `free_tier: false` on its `PROVIDERS` entry and fill in real prices in `MODEL_COSTS`.

### Configurable Thresholds

All pipeline gates are stored in the `settings` table and editable live via `/settings`
— no code changes or restarts required.

| Setting | Default | Controls |
|---------|---------|----------|
| `gate.min_confidence` | 0.3 | Minimum Proposer confidence to pass HypothesisGate |
| `gate.min_evidence_count` | 2 | Minimum events in EvidenceWindow to pass gate |
| `gate.min_sensor_diversity` | 1 | Minimum distinct sensor types to pass gate |
| `gate.min_novelty` | 0.2 | Minimum Jaccard novelty vs recent hypotheses |
| `threshold.corroborate_min_confidence` | 0.4 | Minimum confidence (+ ≥1 supporting verification) to corroborate |
| `threshold.alert_min_confidence` | 0.1 | Minimum confidence to create an Alert |
| `alerts.min_severity` | `low` | Minimum severity allowed to be created (low/medium/high/critical) |
| `ingestion.enabled` | `true` | Enable/disable recurring SensorIngestion scheduling; preserved across restarts |
| `supervisor.interval` | 10 | Pipeline supervisor interval (seconds) |
| `correlator.lookback_hours` | 24 | Correlator lookback window for confirmed hypotheses |
| `correlator.max_hypotheses` | 200 | Max confirmed hypotheses per correlation run |
| `correlator.min_interval_seconds` | 300 | Minimum seconds between correlator runs |

**Domain vocabulary:** The `ui.domain` setting (Settings → UI) switches entity names throughout the UI. Bundled profiles: `cybersecurity` (Observable / Hypothesis / Campaign) and `netops` (Log Entry / Incident / Attack Chain). New profiles require only a YAML file in `config/locales/domains/`. See DESIGN.md §10.

**Domain tagging:** `observables`, `hypotheses`, `alerts`, and `evidence_windows` carry a `domain`
column so pipeline artifacts can be scoped end-to-end.

**Quick tuning:** The Control Shell (`/decisions`) has LOW / MED / HIGH / CRIT sensitivity preset
buttons that atomically apply gate thresholds, `threshold.alert_min_confidence`, and
`alerts.min_severity` in a coherent bundle. Use individual Settings edits only for fine-tuning
beyond what a preset provides.

**Manual tuning:** If too many low-severity alerts appear, raise `alerts.min_severity` and/or
`threshold.alert_min_confidence`.
If too few alerts reach the alert queue, lower `threshold.corroborate_min_confidence` first,
then `threshold.alert_min_confidence`. These values are calibrated for production data; synthetic
test events produce conservative LLM confidence scores (0.4–0.6) near the lower thresholds.

### Alert Creation

`AlertJob` uses double-checked locking: fast-path guards before acquiring the row lock,
then re-checks inside the lock before `Alert.create!` to prevent duplicates under
concurrent Sidekiq workers.

---

## Prerequisites

- Ruby 3.2+
- PostgreSQL 14+ (local socket auth, no password required)
- Redis
- At least one API key: `ANTHROPIC_API_KEY`, `DEEPSEEK_API_KEY`, `GROQ_API_KEY`, or `MISTRAL_API_KEY`
- Optional: [Ollama](https://ollama.com) for local model inference (no API key required)

On macOS with Homebrew:
```bash
brew install postgresql@17 redis
brew services start postgresql@17
brew services start redis
```

## Setup

```bash
git clone https://github.com/unixneo/blackboard.git
cd blackboard
bundle install
bin/rails db:create db:migrate db:seed

# Set API keys in .env
ANTHROPIC_API_KEY=your_key_here
DEEPSEEK_API_KEY=your_key_here
GROQ_API_KEY=your_key_here
MISTRAL_API_KEY=your_key_here  # optional
```

## Running

Blackboard requires three processes: Redis, Rails, and Sidekiq.

```bash
bin/blackboard start    # Start Redis, Rails, Sidekiq
bin/blackboard status   # Show service health and processing state
bin/blackboard stop     # Graceful shutdown
bin/blackboard flush    # Wipe all pipeline data for a clean-slate test run
```

`bin/blackboard flush` deletes all pipeline data (observables, hypotheses, critiques,
verifications, alerts, LLM calls, board events, evidence windows), resets sensor read
positions, clears all Sidekiq queues and the BlackboardEvent Redis stream, and truncates
the test event log. Uses `psql` directly — works even if Rails won't boot. Requires
confirmation (`flush`) before proceeding.

`bin/blackboard status` displays:
- Service health (Redis, Rails, Sidekiq)
- LLM processing on/off state
- Observable counts (total and unnormalized)
- Per-KS call stats for the last 24h: call count, avg latency, success rate, last-used LLM
- Fallback LLM line per KS when a fallback provider is configured, with its own call stats
- Pipeline idle/busy indicator: Sidekiq queue depth + running workers, or "idle — last activity Nm ago" when the pipeline has drained

Use `watch --color bin/blackboard status` for a live updating view with ANSI colors rendered correctly.

**Web interfaces** (default port 3005):

| URL | Purpose |
|-----|---------|
| `localhost:3005` | Dashboard |
| `localhost:3005/knowledge_sources` | Edit LLM agents |
| `localhost:3005/hypotheses` | View attack hypotheses |
| `localhost:3005/campaigns` | View multi-stage attack campaigns (L3) |
| `localhost:3005/alerts` | View escalated threats |
| `localhost:3005/sensors` | Configure log sources |
| `localhost:3005/settings` | Toggle processing, set providers, set UI domain |
| `localhost:3005/admin/sidekiq` | Sidekiq job queue admin |

## Generating Test Events

```bash
bin/rake "events:generate[ssh_brute_force,10,0]"   # SSH brute force events
bin/rake "events:attack_scenario[300]"             # Full 7-phase attack scenario
bin/rake events:clear                              # Clear test log
```

## Infrastructure

- **PostgreSQL** — primary database; the shared "blackboard" (data store)
- **Redis** — Sidekiq job queues
- **Sidekiq** — async job processing; concurrency 3 (LLM calls are I/O-bound)
- **`LlmPipelineMethods`** — shared concern included by all pipeline jobs; contains
  `call_llm`, `execute_llm_call`, fallback logic, JSON helpers
- **`KsProviderClient`** — factory for LLM clients; handles Anthropic, DeepSeek, Groq, Mistral, Ollama
- **`BlackboardEvent`** — audit log writer; records events to `BlackboardLog` for the UI
- **`ControlShell`** — health monitor; `observe_blackboard` and `health_check` used by
  `bin/blackboard status` and the Control Shell web page (`/decisions`)

## Why This Architecture?

From the 1999 Bass paper:

> "ID systems that examine operating system audit trails, or network traffic and other
> similar detection systems, have not matured to a level where sophisticated attacks are
> reliably detected, verified, and assessed."

This remains true 25+ years later. The Bass MSDF model addresses it by:
1. **Fusing multiple sensors** into a coherent picture
2. **Building hypotheses** that explain patterns across events
3. **Critiquing hypotheses** to reduce false positives
4. **Verifying externally** before escalating
5. **Maintaining state** over time to catch slow-moving attacks

LLMs bring to this architecture:
- Direct understanding of heterogeneous log formats — no rigid parsers
- Natural language hypothesis generation and critique
- Cross-domain correlation without explicit rules

The blackboard (PostgreSQL) provides what LLMs lack:
- Persistent memory across time
- Structured confidence tracking
- Explicit reasoning traces
- Human oversight integration

## License

MIT

## References

- [Bass, T. (2000). "Intrusion Detection Systems and Multisensor Data Fusion." *Communications of the ACM*, 43(4), 99-105.](https://www.researchgate.net/publication/220420389_Intrusion_Detection_Systems_and_Multisensor_Data_Fusion)
- MITRE ATT&CK Framework: https://attack.mitre.org/
