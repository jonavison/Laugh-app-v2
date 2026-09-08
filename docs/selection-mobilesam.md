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

### Addendum: what a real group photo broke (W3-08c)

A 4288×2848 three-person photo produced marching ants that cut through a face and enclosed a
plant. Three defects, all found by replaying the pipeline stage by stage on that photo:

**Prompt geometry scaled to the frame, not the subject.** Three sampling radii were derived
from the image dimensions, which only holds for a subject that fills the frame.

- Positive points required a `min(w,h)/80` neighbourhood on-mask, which a hair mass passes.
  Scanning row-major then put every positive in the hair at the top of the person, and hair
  positives make SAM return an edge-ish region that drops the face: **47% of one subject's
  interior went unselected**. Positives now come from the deepest ring test the shape
  supports (30% of the subject's short side, stepping down until enough samples appear),
  which lands them in the torso. Interior miss fell to 1.3%, and fixture edge agreement
  roughly tripled (studio 0.050 → 0.154) — the bug was costing precision on every photo, not
  just this one.
- The occluder-negative scan needed a 71px clear radius on a 4288px frame, so an occluder
  *surrounded* by the subject could never qualify for a negative. Now 3% of the subject box.
- The prior gate's closing and slack radii were 171px and 214px, wide enough to close over
  an occluder. `subjectBox` now sets the scale.

**Per-instance negatives starved the occluder budget.** One shared pool let neighbouring
people take the points, leaving a plant in front of a subject with no negative on it at all.
The budget is now split explicitly (neighbours ≤2, occluders ≥half).

**Instances say who, the merged matte says where.** `VNGeneratePersonInstanceMaskRequest`
returned 2 instances for 3 people — at both qualities — and its masks are soft, covering the
plant at ~0.5. Mid-grey reads as subject to every consumer downstream, so the negative
sampler skipped the plant and the gate passed it. Two corrections, same principle:

- `SelectionPersonInstances.narrowed`: each instance is intersected with the merged
  `VNGeneratePersonSegmentationRequest` matte, which is crisp about the same pixels.
  Occluder pixels in the selection fell from 40.6% to 13.3%.
- `SelectionPersonInstances.residualSubject`: whatever the merged matte covers that no
  instance claims (opened, ≥0.4% of frame) becomes its own plan, which recovered the third
  person. Without it the instance route silently loses people the old route selected.

### Addendum: narrating the wait

Auto Select on a group photo is several seconds of Vision segmentation, one encode, N decodes
and N mattes, and the panel used to show one static line for all of it. The pipeline now
reports the step it is on and the panel narrates it:

- `ImageSelectionSession.Stage`: `preparing` → `findingPeople` → `cuttingOut(completed:total:)`
  → `refining`. Set optimistically on the click so the panel reacts before the first hop.
- `BatchPromptSelecting.select(in:prompts:quality:onProgress:)`: the provider reports each
  finished person. Matting is the per-person part (the encode is shared), so progress moves
  as mattes land. The default implementation reports once at the end, so a provider that
  only offers the plain batch entry still works.
- Stage updates carry the run's generation and are dropped when it no longer owns the
  session, so a late callback cannot re-arm the spinner after a run finishes or is superseded.
- `SelectionBusyStatus` maps phase → caption, with a bar fraction only for the model
  download. Select stages have no honest percentage, so they get a spinner instead of a bar
  that would have to invent its own movement.

## Revisit

- EfficientSAM3 when CoreML export ships
- SAM2 CoreML if MobileSAM measurement disappoints

## Measurement

```bash
./scripts/measure-selection.sh           # Vision baseline
./scripts/measure-selection.sh mobilesam # requires cached weights (no download in harness)
```

Swap providers by adding a `SelectionMeasurementTests` case; diff `[SEL-MEASURE] summary` lines.

