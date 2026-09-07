# MobileSAM CoreML — PR 1 artifact

## Pin

- **Artifact id:** `mobilesam-coreml-v1`
- **Why first:** ready Apache-2.0 CoreML conversion (maturity/license), not a permanent quality verdict (ADR 0005).
- **Upstream model:** [ChaoningZhang/MobileSAM](https://github.com/ChaoningZhang/MobileSAM)
- **Runtime + zip:** [john-rocky/SamKit](https://github.com/john-rocky/SamKit) `v1.0.0` `MobileSAM.zip` (Apache-2.0)
  - `mobile_sam_encoder.mlpackage` → compiled `mobile_sam_encoder.mlmodelc`
  - `mobile_sam_decoder.mlpackage` → compiled `mobile_sam_decoder.mlmodelc`
  - `mobile_sam_prompt_encoder_weights.json`

## Delivery

- Download once → Application Support `LaughPlayer/SelectionModels/mobilesam-coreml-v1/`
- `SelectionModelStore.ensureAvailable` downloads, unzips, compiles `.mlpackage` → `.mlmodelc`, then promotes
- First accurate Auto Select: blocking download + cancel → Vision matte fallback
- Wi‑Fi idle prefetch: optional optimization only

## Provider

- `MobileSAMSelectionProvider` — class-blind; `SelectionPrompt` in → `SelectionMask` out
- Boundary stage: `SelectionMattePrecision` CI polish only (no second neural head in PR 1)

## Addendum — per-person prompting (implementation refinement, not a new decision)

PR 1 scoped Vision as the prompt source for one subject: Vision matte → points + one box →
one SAM call. On a group photo that box spans everyone, so SAM returns one merged blob and
fills whatever sits between the subjects. `VNGeneratePersonInstanceMaskRequest` (macOS 14+)
already separates individuals, so the prompt strategy became N prompts instead of 1. The
boundary stays where ADR 0005 put it — Vision supplies prompts, SAM owns the matte.

- `PersonInstanceSegmenting` → `VisionPersonSelectionProvider.personInstanceMasks`: one
  Vision matte per person. `[]` on older systems or an empty result.
- `SelectionPersonPromptAssist.buildInstancePlans`: per person, a tight box and interior
  positives from *that* person's matte, plus the other people as negative points.
- `MobileSAMSelectionProvider.select(in:prompts:)` (`BatchPromptSelecting`): one image
  encode, N decodes. Measured 228ms vs 344ms for 2 prompts; the gap widens with resolution
  because the encoder is the fixed cost.
- Matting runs per person (inside the provider) and the occluder gate uses that person's own
  Vision matte, so two adjacent people never reach the boundary stage as one ambiguous edge.
- `SelectionPersonInstances`: instances stay addressable; the union is a view over them, for
  the later "3 people detected, tap to pick one" picker.
- `ImageSelectionSession` prefers this route and falls back to the single group-wide prompt
  when Vision returns no instances.

**Occlusion order (heuristic, needs real-photo validation):** instances are ordered by matte
footprint, nearest (largest) last, so later instances win pixels two people both claim.
Vision reports confidence per observation, not per instance, so there is no per-person score
to sort on. The union is unaffected by order; this only matters once per-pixel ownership is
exposed. Re-check on a real family photo where someone stands behind another.

## Revisit

- EfficientSAM3 when CoreML export ships
- SAM2 CoreML if MobileSAM measurement disappoints

## Measurement

```bash
./scripts/measure-selection.sh           # Vision baseline
./scripts/measure-selection.sh mobilesam # requires cached weights (no download in harness)
```

Swap providers by adding a `SelectionMeasurementTests` case; diff `[SEL-MEASURE] summary` lines.

