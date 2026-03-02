# Blackboard SA (Situation Awareness) — Architecture Design Notes

> Captured 2026-02-20. Documents settled design decisions and open questions
> from the first serious architectural review session.

---

## 1. Philosophical Foundation

This system is an implementation of Tim Bass's 1999 multisensor data fusion
(MSDF) architecture, updated to use LLMs as knowledge sources (KSs) for
continuous situation awareness. The
original blackboard model permits KSs to fire opportunistically — any KS can
write to the board at any time when its preconditions are met, with a control
shell deciding priority.

**We reject pure opportunistic blackboard dispatch.**

### Why

The purist BB model creates complexity that exceeds its benefits:

- A control shell (arbiter) must maintain an accurate model of every KS's
  capabilities and current board state. This becomes the hardest part of the
  system — harder than the KSs themselves.
- With LLM-backed KSs, opportunistic firing is expensive. Every premature or
  redundant invocation costs API money and adds latency.
- Debugging non-linear, opportunistic firing order is genuinely hard. When
  something goes wrong it is non-obvious which KS fired in what order and why.
- In practice, a room of 5 experts with no structure produces the same failure
  modes: the loudest voice dominates, the quiet expert never speaks, and half
  the time is spent on meta-discussion about who should talk next.

### The Middle Path: Structured Deliberation

We keep the blackboard as a shared state artifact and the KS concept, but we
control execution using **structured dialectic deliberation**, not
"anything goes." We call this architecture **Blackboard SA (Situation
Awareness)**.

The analogy is an expert panel with a fixed agenda:

1. Everyone sees the same evidence
2. Each expert speaks in a defined order
3. Each expert's output becomes context for the next
4. No expert is crowded out by volume or speed

This is also how high-functioning human deliberation works: courts (prosecution
→ defense → rebuttal), military intelligence (OSINT → hypothesis → red team →
assessment), medical diagnosis rounds.

**The name stays: Blackboard.** The shared state model and KS concept are
preserved. Only the dispatch model differs from the purist formulation.
The system intent is SA-first: provide persistent, explainable operational
context for human decisions, not only point-in-time IDS verdicts.

---

## 2. Pipeline Architecture (Settled)

```
Raw Log → Observable → [Normalizer] → Normalized Observable
                                              ↓
                                    [WindowBuilder] → EvidenceWindow
                                              ↓
                              [Proposer] → Hypothesis
                                              ↓
                         [HypothesisGate — non-LLM] → discarded_low_confidence
                                              ↓ passes
                    [Critic / Devil's Advocate] → Critique
                                              ↓
                              [Verifier] → Verification
                                              ↓
                            [Correlator] → Corroborated Hypothesis
                                              ↓
               [Historical Data Gate KS — non-LLM, L4] → (calibrated hypothesis)
                                              ↓
                              [Alert Job] → Alert
```

Each stage is triggered by direct job chaining (Sidekiq). The sequence is
fixed. No stage skips ahead. A lightweight supervisor job provides a safety
net for stalled backlogs.

### What "Dialectic" Means Here

Every KS gets a guaranteed voice in a logical sequence — propose, critique,
verify, correlate. No KS is starved by a high-volume peer. Fairness is
structural, not emergent. The control shell is simple: it knows the event
type and queues the appropriate job. No priority scoring. No capability
modeling.

**Supervisor safety net:** `PipelineSupervisorJob` runs on a fixed interval
(`supervisor.interval`) and kicks any stage with stale backlog when the KS is
active, preventing pipeline stalls after restarts or KS toggles.

---

## 3. The Sliding Window Problem (and Its Fix)

### The Problem

The current Proposer consumes "N most recent unconsumed observables." With
multiple sensors of different volumes:

- High-volume sensors (SSH) fill the pool and dominate every proposal
- Low-volume sensors (Firewall, IDS) are structurally starved
- Observables consumed into one hypothesis are never seen alongside later
  related events from other sensors

This is a symptom of the Proposer having a poorly defined input scope — not a
symptom of the round-robin architecture. The fix is to change the Proposer's
input artifact, not the architecture.

### The Fix: EvidenceWindow

A new first-class artifact captures a time-bounded, stratified sample of
normalized events before the Proposer ever fires.

#### EvidenceWindow schema

| Field | Description |
|---|---|
| `id` | Primary key |
| `time_start`, `time_end` | Window bounds |
| `sensor_mix` | JSON counts per sensor (e.g. `{ssh: 12, firewall: 3, ids: 1}`) |
| `event_ids[]` | References to normalized Observables included |
| `selection_policy` | e.g. `stratified`, `weighted_rr`, `quotas` |
| `window_hash` | SHA256 of `event_ids + time_start + time_end + selection_policy` for replay integrity |

#### WindowBuilder KS

- **Not an LLM.** Pure data manipulation — no API cost.
- Input: normalized Observables on the board
- Output: EvidenceWindow

**Selection algorithm:**

1. Time-bounded query (configurable window, e.g. last 10 minutes)
2. Per-sensor quota: `min_k` events each, `max_total` cap
3. If a sensor has more than quota: downsample (reservoir / uniform sampling)
4. If a sensor has fewer than `min_k`: fill from others but record the
   imbalance in `sensor_mix`

#### Proposer changes

Proposer consumes an EvidenceWindow, not raw observables. Its prompt receives:

- Summary statistics (counts by sensor, time span)
- The selected normalized events (bounded by token budget)
- Explicit instruction: *"Your hypothesis must cite specific event_ids from
  the window."*

Citation requirement makes every hypothesis traceable to specific evidence.
Debugging and auditing become tractable.

#### Fairness knobs

Two simple, cheap controls:

1. **Per-sensor backlog cap** *(implemented)* — `window.max_per_sensor_backlog`
   setting (default: 50) caps the candidate pool per sensor before stratified
   sampling runs. Applied in `WindowBuilderJob` via `grouped.transform_values`.
2. **Weighted quotas** — considered and deferred; backfill + backlog cap are sufficient without per-sensor weight configuration.

---

## 4. Replayability

Every EvidenceWindow is persisted as written (IDs + hash). Downstream KSs
(Critic, Verifier, Correlator) reference the `window_id` on the Hypothesis,
not the raw events. This means:

- Any hypothesis can be replayed with exactly the same evidence
- Regression testing becomes possible: fix a KS prompt, replay the window,
  compare outputs
- Auditors can reconstruct exactly what the Proposer saw

The hash covers `event_ids[] + time_start + time_end + selection_policy`.
Same events with a different policy is a different window.

---

## 5. Observable Re-use Semantics (Settled)

Under the windowing model, one Observable can participate in multiple
EvidenceWindows and therefore multiple Hypotheses. This is correct and
intentional — an SSH event that appears in both a brute-force hypothesis and a
lateral movement hypothesis is valuable signal in both contexts.

**Implication for Correlator:** The Correlator must not treat the same
event_id appearing in two Hypothesis windows as independent corroboration. It
must deduplicate by event_id when assessing evidence strength.

**Implemented:** `CorrelatorJob#build_overlap_notes` computes pairwise
`event_ids` intersections across all hypothesis windows in each correlation
batch and injects a "Shared evidence" section into the prompt, explicitly
instructing the LLM to treat overlapping events as a single piece of evidence.

---

## 6. HypothesisGate — Cheap Structural Pruning (Settled)

A non-LLM gate runs after the Proposer and before the Critic. Its sole job is
to discard hypotheses that are not worth the cost of LLM deliberation. If a
hypothesis fails the gate it is marked `discarded_low_confidence` and the
Critic + Verifier are never enqueued.

### Gate signals (all computed from data, no API calls)

| Signal | Source | Notes |
|---|---|---|
| `confidence_score` | Proposer LLM output (structured JSON) | Treat as weak signal — LLMs are poorly calibrated on self-reported confidence. One input among four, not the primary gate. |
| `evidence_count` | `event_ids[]` length on EvidenceWindow | Minimum viable evidence floor. |
| `sensor_diversity` | `sensor_mix` on EvidenceWindow | Count of distinct sensors represented. A hypothesis citing only one sensor type is structurally weaker. This is the strongest gate signal. |
| `novelty_vs_recent_hypotheses` | Jaccard similarity on `event_ids[]` | Compare against hypotheses created in the last N minutes. High overlap → likely duplicate from an overlapping window → discard. |

### Novelty computation

Use **Jaccard similarity on `event_ids[]`** as the first implementation:

```
novelty = 1 - (|A ∩ B| / |A ∪ B|)
```

If novelty < threshold against any recent hypothesis, discard. This is cheap,
deterministic, and leverages the EvidenceWindow IDs already being stored.
Embedding-based semantic similarity is a future upgrade if Jaccard proves
insufficient.

### What happens to discarded hypotheses

Persisted as `discarded_low_confidence` with all gate scores recorded. Never
deleted. The audit trail must show what was pruned and why — this is essential
for tuning thresholds and for post-incident review.

### Implementation

`HypothesisGateJob` — a lightweight Sidekiq job, not a KS role. No LLM.
Thresholds are stored in the `settings` table so they can be tuned without
code changes. KnowledgeSourceRegistry enqueues the Critic only after the gate
passes.

### What this solves

This directly resolves the "Deduplication of overlapping Hypotheses" open
question from the original design: the novelty check collapses near-duplicate
hypotheses from overlapping EvidenceWindows before any LLM cost is incurred.

---

## 7. Resolved Design Decisions

### WindowBuilder trigger frequency (resolved 2026-02-21)

**Decision: Hybrid event-driven + novelty suppression.**

`NormalizerJob` chains to `WindowBuilderJob` after each normalization batch
(event-driven). `WindowBuilderJob` computes Jaccard similarity against the
most-recent `EvidenceWindow`; if novelty < `window.novelty_threshold` (default
0.3) it logs and returns without creating a new window. This eliminates near-
duplicate windows without requiring a timer. The novelty threshold is tunable
in the Settings UI.

**Throughput note:** With a single active sensor, window size equals
`window.min_k_per_sensor` unless `window.max_total` is lower. If proposer
backlog drains slowly, raise `window.min_k_per_sensor` to increase batch size.

### Hypothesis-to-window cardinality (resolved 2026-02-21)

**Decision: One EvidenceWindow can produce multiple Hypotheses.**

The Proposer returns a JSON array; each element becomes a separate `Hypothesis`
with `evidence_window_id` set to the same window. Downstream stages (Critic,
Verifier, Correlator) track back to the window via the hypothesis. The
Correlator must deduplicate by `event_id` when assessing evidence strength
(see §5).

**Correlator batching (cost control):** Correlation runs are time-bounded and
capped. The correlator only considers confirmed hypotheses updated within
`correlator.lookback_hours`, limits to `correlator.max_hypotheses`, and enforces
`correlator.min_interval_seconds` between runs.

---

## 8. Operational Controls (As Implemented)

These controls are intentionally **processing gates**, not UI-only filters.

### Alert minimum severity

`alerts.min_severity` is enforced in `AlertJob` to decide whether a
corroborated hypothesis is promoted into a new alert. It **does not delete or
mutate existing alerts**; it only affects future alerts. UI filters are
separate and must never be conflated with processing thresholds.

### Historical Data pre-alert gate (L4, non-LLM)

Before `AlertJob` runs, corroborated hypotheses pass through `HistoricalDataJob`
(`historical_data` KS role). This stage is intentionally **non-LLM**:

- reads operator historical memory from `historical_knowledge_entries`
- applies deterministic calibration policy (confidence capping / severity shaping)
- stamps provenance (`historical_data_gate`) onto hypothesis metadata
- forwards to `AlertJob` for final emission

Operator annotation policy for this stage:
- `Common public scan` entries may omit notes for fast triage.
- All other historical knowledge types require notes for auditability.

This gate is the single pre-alert entrypoint regardless of trigger path
(normal chain, stale backlog recovery, or manual control-shell tick).

Reliability notes (2026-02-25):
- `VerifierJob` must stop additional verification creation once a hypothesis
  transitions out of `critiqued` (typically to `corroborated`). Otherwise,
  late verification callbacks can mutate confidence after L4 capping and before
  alert emission.
- L4 operational performance metrics (`historical_data` calls/match-success)
  are sourced from `hypotheses.metadata.historical_data_gate`, not alert rows,
  so alert-table maintenance operations do not erase L4 activity reporting.
- Clearing alerts is an alert-layer reset, not a hypothesis-state reset by
  default; operational tooling may intentionally reset orphaned `alerted`
  hypotheses back to `corroborated` to keep status views coherent after wipes.

### Supervisor interval

`supervisor.interval` controls how often `PipelineSupervisorJob` runs. The
Control Panel should display the live setting from `settings`, not a hard-coded
interval.

### Backlog drain visibility

Pipeline backlog totals are point-in-time snapshots and can mislead operators
when viewed without trend context. Dashboard operations should surface a short
horizon proposer drain signal (`awaiting_proposer Δ/5m`) so teams can separate
healthy drain from a stagnant queue.

### L1 pre-normalization noise gate

`NormalizerJob` includes an operator-configurable pre-normalization filter
(`proposer.filter_low_level_bot_scans` + `proposer.low_level_bot_signatures`)
that evaluates all incoming sensor observables before LLM normalization.

- Matched rows are short-circuited (not sent to the L1 LLM), stamped with
  `proposer_skipped`, and marked with `l1_bot_filter` metadata for audit.
- Web logs retain an extra HTTP status guard (`400/401/403/404/405/429`) to
  reduce false positives on normal traffic.
- Non-web logs (e.g., syslog/auth with signatures like `sshd`) use direct
  signature matching to support simple global noise suppression.

Operational outcome: lower L1 token spend, lower proposer backlog pressure,
and explicit telemetry (`l1_prefilter` row) for filter call volume and hit rate.

### Prefilter stages and observability semantics

The system now uses three distinct filtering stages, each with different
storage/visibility semantics:

- **Sensor Prefilter** (`SensorConfiguration.filter_patterns`): runs in
  ingestion before observable creation; dropped lines are counted per sensor
  but do not appear in the observables table.
- **L1 KS Prefilter** (`noise_filter_stage=normalizer_pre`): runs in
  `NormalizerJob` before L1 LLM invocation; matched rows are persisted as
  observables and shown as `L1 KS Prefiltered` with no LLM attribution.
- **Proposer Prefilter fallback** (`noise_filter_stage=proposer`): runs after
  normalization for residual low-value rows; records keep LLM attribution and
  are shown as `Proposer Prefiltered`.

---

## 9. Relationship to Prior Art

Academic work on LLM-based blackboard systems (arXiv:2510.01285, 2507.01701)
converged independently on similar architecture from a data science angle.
Their results (13–57% improvement over master-slave multi-agent systems)
provide indirect validation that the autonomous-KS, shared-state model is
correct.

Key differences from the academic work:

- We are explicitly rooted in Tim Bass's 1999 MSDF formulation
- We use multiple LLM providers (Anthropic, DeepSeek, Groq) with per-KS routing
- We have a running operational system, not a benchmark experiment
- Our pipeline stages map directly to fusion levels with an explicit non-LLM
  L4 process-refinement gate before alert emission

---

## 10. Prompt-Driven Detection Behavior

One of the most operationally significant properties of the Blackboard SA architecture
is that **detection behavior is controlled entirely by KS system prompts —
not by code**.

### What this means in practice

Adding a new attack class requires editing a text prompt, not a code deploy.
When we discovered that DoS/bot patterns were not being flagged, the root cause
was a two-line omission in the Proposer prompt: `denial_of_service` and
`automated_scanning` were absent from the `attack_type` enum and the "Look
for:" guidance. The LLM followed instructions precisely and found nothing,
because it was never asked to look for it. The fix was a prompt edit — live,
no restart required.

### Prompt roles in the detection pipeline

Each KS prompt has a distinct epistemic responsibility:

| KS | Prompt role | Attack-type awareness |
|----|-------------|----------------------|
| Normalizer | Describe what happened, extract entities | None — pure description |
| Proposer | Identify attack patterns and classify | Full — must enumerate all detectable attack types |
| Critic | Challenge evidence quality and plausibility | None — attack-agnostic skepticism |
| Verifier | Suggest tool-specific confirmation steps | Partial — tool selection varies by attack class (e.g. GreyNoise for bots) |
| Correlator | Link hypotheses into multi-stage campaigns | Partial — chain patterns vary by attack class |

The Normalizer and Critic intentionally carry no attack-type awareness. This
is not an oversight — it preserves separation of concerns. The Normalizer
should not interpret intent; the Critic should challenge any hypothesis with
the same rigor regardless of attack type.

### Implications for operations

**Prompts are a critical security artifact.** A silently weakened Proposer
prompt produces missed detections with no error, no alert, and no obvious
diagnostic. The failure mode is indistinguishable from a quiet period on the
network.

**Change control for prompts should mirror code review discipline:**
- Prompt changes should be committed to `db/seeds.rb` alongside the live DB
  update so the change is tracked in version control
- Detection gaps should be investigated at the prompt level first — before
  suspecting pipeline bugs

**Prompts are readable by domain experts, not just engineers.** A security
analyst can audit the Proposer prompt and immediately understand what the
system is and is not looking for — and close gaps themselves without writing
code. This is a deliberate architectural affordance.

---

## 11. Domain Generality

The system is domain-agnostic at the architecture level. Sensors are
newline-delimited text streams. Each KS role is fully configurable via system
prompt. Cybersecurity is the first application domain; financial analysis,
clinical monitoring, supply chain, and IoT are equally viable targets.

**Domain tagging:** `observables`, `hypotheses`, `alerts`, and
`evidence_windows` carry a `domain` column so pipeline artifacts can be scoped
end-to-end.

### Entity vocabulary (implemented)

The three pipeline entity names — Observable, Hypothesis, Campaign — are the
only UI labels that are domain-specific. These are now extracted into Rails
i18n and controlled by the `ui.domain` setting (editable in Settings → UI).

**How it works:**

- `config/locales/en.yml` defines the base (cybersecurity) vocabulary under
  `models.observable`, `models.hypothesis`, `models.campaign` with
  Rails pluralization (`one`/`other`).
- Domain profiles live in `config/locales/domains/<name>.yml` and override
  only the keys that differ. Adding a new domain requires no code changes —
  drop a YAML file and add the key to the `ui.domain` dropdown in
  `app/views/settings/index.html.erb`.
- The `dn(key, **opts)` helper in `ApplicationHelper` resolves the
  domain-scoped key first (`domains.<domain>.models.*`), falling back to the
  base `en.yml` key with the same options (including `count:` for
  pluralization). The 30-second `Setting` cache makes every call cheap.

**Bundled domain profiles:**

| Domain key | Observable | Hypothesis | Campaign |
|---|---|---|---|
| `cybersecurity` (default) | Observable / Observables | Hypothesis / Hypotheses | Campaign / Campaigns |
| `netops` | Log Entry / Log Entries | Incident / Incidents | Attack Chain / Attack Chains |
| `medical` | Patient Event / Patient Events | Clinical Finding / Clinical Findings | Care Episode / Care Episodes |
| `financial` | Market Signal / Market Signals | Risk Flag / Risk Flags | Fraud Pattern / Fraud Patterns |

L1/L2/L3/L4 level labels and pipeline-internal terms (Alert, Critique,
Verification) are architectural constants and remain hardcoded.
Current L1 label is **Object Refinement** (formerly "Object Assessment").

### §11.2 Domain-aware KS sets

UI vocabulary changes alone (§11.1) are insufficient: the LLM agents still
reasoned about SSH brute force and MITRE ATT&CK regardless of domain setting.

**Solution:** a `domain` column on `knowledge_sources` (string, default
`'cybersecurity'`, not null, composite index on `[domain, role]`). Each
pipeline role now has one domain-scoped KS record. Most roles are LLM-backed;
`historical_data` is non-LLM and executes policy in app code.

**Lookup semantics** (jobs resolve KS by `domain + role`, with cybersecurity fallback):

```ruby
domain = Setting.get('ui.domain', 'cybersecurity')
@ks = KnowledgeSource.active.for_domain(domain).find_by(role: 'normalizer') ||
      KnowledgeSource.active.for_domain('cybersecurity').find_by(role: 'normalizer')
```

When `ui.domain == 'cybersecurity'` Ruby short-circuits `||` so only one
query runs. When the domain KS is disabled (the initial state for non-
cybersecurity records) fallback to cybersecurity ensures the pipeline never stalls.

**New records:** domain KS records include `historical_data` for each domain.
Non-cybersecurity domain KS entries ship `active: false` so operators can
review and enable deliberately.

**Seeding:** `db/seeds/domain_ks.rb` (run with `rails runner`) is safe on
live systems — uses `find_or_initialize_by` and only sets attributes on new
records. `db/seeds.rb` loads it for fresh installs.

**UI:** `/knowledge_sources` shows domain tab bar (Cybersecurity / Netops /
Medical / Financial). Dashboard KS Performance table and Control Panel KS
Processing card both scope to the active domain. Edit page shows a read-only
domain field (domain must not be reassigned — it breaks the fallback chain).
