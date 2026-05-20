# Synthetic-data autoresearch campaign and evolution UI pattern

Use this reference when an autoresearch loop is being designed for synthetic-data generation or other simulation-heavy benchmarks where quality can be gamed by a single metric.

Session source: BruxSynth/OpenJaw campaign planning, 2026-05-12.

## Core lesson

Do not optimize a single synthetic-data "quality score". Use a multi-objective ladder and require each pass to make one bounded, attributable improvement. Accept a pass only if it improves a named axis or adds a missing measurement without weakening reproducibility, claim safety, or shortcut resistance.

## Recommended ladder for synthetic time-series / biosignal loops

- Reproducibility and package integrity: deterministic seed replay, checksums, command logs, generated artifact existence, forbidden-claim scan.
- Assumption fidelity: event duration, inter-event intervals, envelope morphology, RMS/MAV, zero-crossing, waveform length, PSD, bandpower, spectrogram snippets.
- Artifact-confusion resistance: false positives per minute/hour by artifact family, artifact-negative specificity, clean-control specificity, threshold-sensitivity curves, worst-family drilldown.
- Synthetic-domain utility: held-out synthetic subject/session, held-out artifact family, held-out severity, morphology shift, clean-control guardrail, montage-role checks, waveform tensor contract, optional learned-generator comparison.
- Diversity/coverage: severity/artifact/morphology/montage/seed coverage, sparse regions, near-duplicates, parameter-space heatmaps.
- Provenance/privacy: synthetic-only provenance now; real-derived privacy checks only after private real data exists.
- Expert/readiness: blinded snippet packet and answer-key hash; expert plausibility is not clinical proof.

## Campaign pass protocol

1. Snapshot start state: git SHA, scorecard, corpus manifest/checksums, current reports, UI snapshot, kanban card ID.
2. State one hypothesis: if we change X, metric/report Y should improve because Z.
3. Declare one primary axis and one primary metric.
4. Declare guardrails: no reproduction regression, no claim-safety regression, no clean-control or worst-artifact collapse.
5. Make exactly one bounded change or one measurement addition.
6. Regenerate reports and write commands to a run manifest.
7. Compare against previous accepted baseline; emit metrics-delta JSON/Markdown and verdict.
8. Accept/reject/park with reasons.
9. Preserve paths and learning in Kanban/wiki/repo docs.

## Real-reference vs synthetic-generator state labeling

When a campaign pivots from synthetic-only work to an open real-reference dataset, label the current method precisely before scheduling or implementing work:

- **TRTR** means train on real data and test on held-out real data. This is an evaluation/reference baseline, not synthetic generation.
- **TSTR** means train on synthetic data and test on real data. This is the first transfer-utility gate for a synthetic generator.
- **TRTS** means train on real data and test on synthetic data. This can expose coverage/fidelity gaps but is not proof of real-world utility by itself.

Before saying "synthetic data was evaluated against reference data," verify that a synthetic generator actually exists and that the protocol is TSTR or another explicit synthetic-real comparison. If the current artifact is a real-data adapter plus handcrafted features/classifier baseline, say so plainly.

For biosignal pivots where real-reference evidence is scarce, prefer this sequence:

1. real-reference adapter and provenance/license gate;
2. subject-locked TRTR baseline with transparent features/classifier;
3. aggregate morphology/fidelity diagnostics on real data;
4. pre-registered first TSTR generator contract;
5. simplest auditable generator first, often parametric/physiology-inspired;
6. learned generators only after measurement surfaces and split locks exist.

## First-generator choice for biosignal reference lanes

Do not jump to GANs, diffusion, transformers, or other learned generators just because the long-term topic is synthetic data. For a new EMG/fatigue lane, a good first generator is often a deterministic or stochastic **parametric physiology-inspired simulator**: load-dependent amplitude/envelope, fatigue/time drift, median-frequency trend, subject-level variation, and explicit artifact/noise knobs. It is easier to audit, teach, and falsify than a learned generator, and it gives clear targets for later GAN/diffusion/transformer comparisons.

## Transparent learned-baseline protocol

When a campaign adds learned baselines for synthetic biosignal/time-series data, pre-register the protocol before implementing models. This prevents benchmark fishing and keeps results interpretable.

Minimum protocol:

- Freeze a split-lock artifact before training. Train may fit weights; validation may choose thresholds/hyperparameters; final test is read once per protocol version.
- Start with transparent baselines before deep models: always-negative, fixed threshold/rule baseline, logistic regression, and shallow random forest. Add a small 1D CNN only after transparent models and shortcut audits are report-backed.
- Report per-model and per-split sensitivity, specificity, precision, F1, confusion counts, calibration where applicable, and worst-split deltas.
- Include guardrails for clean-control specificity and artifact-family false positives; do not accept a model that improves average F1 by learning shortcuts or collapsing on a worst artifact family.
- Preserve feature importance or other explanation artifacts for transparent models, plus shortcut-audit verdicts and exact commands.
- Keep real TRTR/TSTR/TRTS rows explicitly pending until private real holdouts, consent/retention rules, and aligned labels exist.

## Good artifact layout

```text
artifacts/autoresearch/<campaign>/
  campaign-manifest.json
  accepted-baseline.json
  <run_id>/
    hypothesis.md
    start-state.json
    end-state.json
    commands.jsonl
    metrics-delta.json
    metrics-delta.md
    acceptance-verdict.md
    plots/
    ui-snapshot.json
```

## UI/evolution visualization pattern

The UI can visualize autoresearch progress, but only from shared manifests, reports, and sidecars. Do not let a Streamlit/browser UI own scientific state.

Useful panels:

- Campaign timeline: run ID, commit, kanban card, hypothesis, axis, metric, verdict, artifact directory.
- Scorecard evolution matrix: rows are axes, columns are accepted passes; no aggregate green score.
- Signal diff: before/after waveform, rectified envelope, PSD, spectrogram, event overlays; label same-seed vs nearest-comparable cases.
- Artifact lab: artifact-family heatmap over time, threshold curves from precomputed sidecars, false-positive example gallery.
- Split explorer: synthetic-domain split definitions, confusion matrix, worst examples; real-data rows stay pending until a private holdout exists.
- Parameter-space explorer: coverage/failure regions over generator factors.
- Provenance graph: config/preset/seed -> generated record/tensor -> detector/model -> report -> scorecard axis -> UI panel.
- Claim-safety panel: visible synthetic/pre-hardware/non-medical status and forbidden-claim scan.

## Kanban branch shape

For a campaign branch, seed an epic plus cards for:

1. manifest/pass schema freeze;
2. baseline snapshot + metrics-delta CLI;
3. no-generator-change dry pass;
4. worst-case artifact metric addition;
5. coverage/diversity report;
6. one measured generator-factor improvement;
7. transparent learned-baseline protocol;
8. learned-baseline implementation;
9. UI timeline/scorecard evolution;
10. UI signal diff/artifact lab;
11. UI parameter-space/provenance;
12. independent claims/evidence review;
13. preservation/wiki handoff.

## Pitfalls

- Do not call synthetic-domain performance real-world utility.
- Do not treat lower loss or higher average F1 as success if worst-family artifact false positives regress.
- Do not add a learned generator/model before measurement surfaces exist.
- Do not hide parameter changes or thresholds in UI state.
- Do not let pending real-data, hardware, privacy, or expert-review gates render as pass.
