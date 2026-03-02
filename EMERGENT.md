# EMERGENT NOTES (2026-02-26)

## Context
- We observed repeated alerts for clearly benign hypotheses (for example: "Normal system activity").
- This was unexpected but important: the system is coherent, but optimizing the wrong semantic target in part of the pipeline.

## What Happened
- The pipeline treated high hypothesis confidence as alert-worthiness, even when the hypothesis content described non-threat behavior.
- In several cases, proposer output included non-threat labels (for example `none`, `normal_system_activity`) and benign descriptions.
- Verifier then "supported" those statements (truth-of-statement), which increased confidence.
- Alerting logic escalated based on confidence/status, not threat polarity.

## Confirmed Examples
- Hypothesis `#6503`
  - `attack_type: none`
  - Description: "Normal system activity"
  - Reached `alerted`, produced open alert.
- Hypothesis `#6548`
  - `attack_type: none`
  - Description: "Normal system activity"
  - Reached `alerted`, produced open critical alert.
- Hypothesis `#6563`
  - `attack_type: normal_system_activity`
  - Description explicitly normal/routine operations
  - Reached `alerted`, produced open critical alert.

## Key Insight
- Current `confidence` is epistemic ("how true is this statement?"), not adversarial ("how likely is threat?").
- This creates semantic inversion:
  - "It is normal activity" can be highly true,
  - and then incorrectly promoted to high-confidence alert.

## Why This Is Interesting
- The model is producing a stable second class of outputs:
  1. Threat hypotheses (intended lane)
  2. Normality/operations hypotheses (emergent lane)
- This appears patterned and repeatable, not random drift.
- Potentially useful if intentionally routed into a separate "normal ops insight" channel.

## Current Prompt Snapshot (Proposer KS)
- Live proposer system prompt asks for attack hypotheses, but does not strictly enforce:
  - "benign/normal => return []"
  - "only allowed threat taxonomy values"
- Runtime prompt template does say "Return [] if no clear attack patterns", but model still emitted benign hypotheses in practice.

## Discussion Outcomes
- Team preference: do not hard-block with code guardrails yet; explore implications first.
- Prompt-only mitigation is preferred initially.
- We acknowledged prompt-only changes usually improve behavior, but are not deterministic.

## Proposed Prompt-Level Mitigation (No Hard Blocking)
- Strengthen proposer contract:
  - Only malicious/adversarial/policy-violating hypotheses in threat lane.
  - Benign/normal/maintenance/routine findings must return `[]`.
  - Restrict attack_type to explicit taxonomy values.
  - Add explicit negative examples:
    - Cron jobs, service restarts, routine daemon logs -> `[]`.

## Recursive Learning Idea (Adaptive, Human-First)
- Add a feedback loop that appends learned prompt addenda from reviewed false positives.
- Workflow:
  1. Auto-flag candidate "no-threat issue" cases.
  2. Human labels (`false_positive`, `true_positive`, `uncertain`).
  3. Store concise "lesson" entries.
  4. Append recent/high-quality lessons to proposer prompt (token-capped).
  5. Periodically distill lessons to avoid prompt bloat.

## Candidate Auto-Flag Signals
- Alerted hypothesis with non-taxonomy attack_type (`none`, `normal_system_activity`, etc.).
- Benign-language patterns in description/summary:
  - "normal", "routine", "expected", "cron", "service startup", "maintenance".
- High confidence + benign semantics + alert escalation (contradiction signal).

## Suggested Longer-Term Architecture
- Split conceptual lanes:
  1. Threat lane (existing)
  2. Normality/ops-insight lane (new)
- Route proposer outputs by polarity, not just confidence.
- Keep human-in-loop for truth labels; automate triage, not final truth.

## Important Session Decision
- A guardrail patch was prototyped locally and then fully reverted on request.
- No guardrail changes from that experiment remain in the working tree.

## Open Questions For Next Session
- Do we formalize a separate Normality Insight artifact/table now, or first do prompt revision only?
- Where should human labeling UI live (Hypothesis page, Alert page, both)?
- How many prompt lessons to include at runtime before context quality degrades?
- Should learning be domain-specific (`netops` lessons only for `netops`)?

