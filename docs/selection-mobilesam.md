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

## Revisit

- EfficientSAM3 when CoreML export ships
- SAM2 CoreML if MobileSAM measurement disappoints
