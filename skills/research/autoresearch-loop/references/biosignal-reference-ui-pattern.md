# Biosignal synthetic-data autoresearch UI: reference-signal pattern

Use this reference when an autoresearch campaign for synthetic biosignals (EMG/EXG/ECG/etc.) asks whether to show real/public reference signals in an interactive progress/quality UI.

## Core rule

Reference signals can be useful as orientation and morphology context, but they must not become validation proof unless a pre-registered, reviewed gate says exactly how they are used.

Good labels:
- Public reference orientation
- External morphology examples
- Reference context, not validation
- Different montage/task/population unless stated
- Private real holdout still pending

Avoid labels:
- Realism validated
- Clinical reference
- Hardware-ready
- Ground-truth bruxism reference
- Privacy-safe synthetic patient data

## Recommended UI panel shape

Add a distinct `Reference Context` panel rather than mixing public references into accepted-baseline evidence.

Sections:
1. Public reference snippets
   - source title/URL/DOI/license
   - local cached path and checksum if downloaded
   - task/montage/population/hardware/filtering summary
2. Synthetic-vs-reference views
   - raw waveform windows, normalized separately
   - rectified/RMS envelope
   - Welch PSD quartiles or bands
   - spectrogram thumbnail
   - feature table: MAV, RMS, waveform length, zero crossings, median frequency, spectral centroid, artifact-band energy ratio
3. Caveats always visible
   - different montage/task/population/hardware/filtering
   - no clinical/hardware/real-holdout/privacy/expert claim
   - no acceptance-verdict effect
4. Provenance
   - transform script/checksum
   - snippet selection rule
   - exact filter and normalization settings

## EMG/bruxism reference sources that fit this pattern

- PhysioNet CAP Sleep Database (`capslpdb`): open PSG dataset with EEG/EOG/ECG/respiration plus chin/submentalis and tibial EMG; includes `brux1`/`brux2`. Useful as sleep/PSG/chin-EMG context, not awake jaw-reference validation.
- KCL/UCL sEMG of Swallowing, Coughing and Speech: public 3-channel sEMG + labels for swallow/cough/speech/movement/baseline. Useful for functional-confound morphology, not bruxism proof.
- Bruxism masseter/24h EMG literature: useful for UI semantics such as muscle-work/duty-cycle versus simple event counts; often not reusable as raw public snippet data.
- Sleep bruxism montage studies: useful for caveats that chin/submental EMG is not equivalent to bilateral masseter/temporalis jaw EMG, especially in PSG/RMMA contexts.
- HD-sEMG datasets/validation literature: useful for generic signal-quality UI ideas (PSD summaries, cross-channel correlation, RMS/power outliers), not jaw-specific validation.

## Kanban branch shape

If reference-signal visualization becomes active, seed it as a new bounded branch rather than appending it informally to a completed generator-quality pass:
1. research/review card: source shortlist, licenses, montage/task limitations, non-claim copy
2. build card: local sidecar-backed reference context panel with no live web dependency
3. review card: claims/montage/privacy overclaim check
4. preserve card: docs/wiki update with exact sources and caveats

## Pitfalls

- Do not let public reference displays affect accepted-baseline status.
- Do not compare public chin/submental/sleep EMG as if it validates awake masseter/temporalis or a project-specific `jaw_reference` montage.
- Do not compute ad hoc UI metrics that alter verdicts; precompute sidecars and keep acceptance gates separate.
- Missing reference sidecars should render `pending`/`missing`, not silently disappear or imply no reference is needed.
- Keep current synthetic campaign metrics separate from future private real-holdout gates such as TRTR/TSTR/TRTS.