# ADR 0005: Smart selection protocol — class-agnostic matting substrate

## Status

Accepted (2026-09-07); amended for matting-product + class-agnostic discipline.

## Context

Image Studio develop tools are display-only Core Image adjusts ([ADR 0004](0004-image-studio-develop-display-only.md)). Portrait **Face / Body**, Landscape **Adapt Sky / Adapt Rocks**, and later click-any-object tools all need selection mattes. Baking “person matte” (or any single class) into shared pathways would force rewrites at tool #4–#5.

Stock Vision covers a few fixed classes today. Exceptional precision and open-vocabulary subjects need CoreML (SAM-class / matting) providers. The API must not assume Vision types **or** that every mask has a semantic label.

## Decision

1. **`SelectionProvider` + `SelectionMask`.** Providers return a matte (`CGImage` / alpha) with optional `SemanticClass`, confidence, extent in image pixel space, and `SelectionSource`. Callers never talk to Vision / CoreML directly.

2. **Class-agnostic core (non-negotiable).** Shared pathways — refine, view compositing, cutout export, boolean compose, mask-scoped adjust — operate on alpha buffers only. They must not branch on `semanticClass`. Person / sky / rock / unlabeled brush / SAM click all use the identical pipeline.

3. **`SemanticClass` is optional metadata.** Useful for UI presets and suggestions; never required for select → refine → preview → export to function. An unlabeled mask (manual brush, anonymous SAM click) is a first-class citizen.

4. **Tool-specific behavior lives in tools.** `if class == .person` (or sky/rock) is allowed only inside a consuming tool or a suggestion layer — never inside `SelectionCompositor`, `SelectionRefineParameters.applying`, `ImageExportWriter` cutout, or boolean mask ops.

5. **New sources = new conformers.** Vision person, CoreML SAM/matting, text-prompt, geology fine-tune — each is a `SelectionProvider`. Adding one must not edit refine, compositor, cutout, or adjust-application code.

6. **Refine is class-blind.** `SelectionRefineParameters` (Smooth / Feather / Contrast / Shift Edge; later brush / decontam) applies identically to any matte. Per-content starting values are presets/hints, not branches inside `refine()`.

7. **`SelectionHint` (sanctioned smarts).** Optional, advisory struct a provider or classifier may attach (“looks like sky → suggest graduated tone + higher feather”). Lives outside the mask/refine/compose core so content-aware UX cannot leak into infrastructure.

8. **Multi-mask ready.** Future union / subtract / intersect / stacked mask layers compose as alpha ops without reading class labels.

9. **`ImageSelectionSession` is separate from `ImageAdjustSession`.** Selection does not invent a parallel develop effect system. Tools *combine* a `SelectionMask` with adjusts.

10. **Display-only.** Mattes feed Select-and-Mask view modes and optional cutout PNG export. Never rewrite the source file.

11. **Engines.** Accurate Auto Select uses a **SAM-class CoreML** `SelectionProvider` (one conformer, class-blind — it only receives prompts and returns masks). **Pipeline shape:** (1) coarse SAM-class mask, then (2) boundary-band matting. **PR 1 weights pin:** **MobileSAM** CoreML (known Apache-2.0–licensed `.mlpackage` conversion, ~19 MB download) — chosen for **availability + license maturity + interactive size**, not as a final verdict on model quality. Revisit EfficientSAM / EfficientSAM3 when their CoreML path ships; if MobileSAM quality disappoints on Laugh fixtures, next candidate is **SAM2 CoreML** (image segmentation). Download once and cache; measure before custom training.

12. **Two distinct Vision roles (do not conflate).**
    - **Accurate path (tool-layer prompt only):** For the person-shaped **Auto Select Person** tool, Vision’s rough person mask is used **only** to build a SAM prompt — confident **positive** interior points (torso/head, not edges), optional **negative** points just outside the rough mask, plus a coarse **box** as spatial constraint. Vision is **not** the matte source on this path; SAM+boundary owns the matte. This does not violate class-blind substrate: person-specificity lives in the tool’s prompt builder; a future Auto Select Sky tool would use its own detector the same way.
    - **Fallback path (different code path):** If SAM/CoreML is unavailable, Vision’s matte may be used **directly** as the selection — that is the only “Vision is the matte engine” role. Prompt-assist ≠ fallback.

13. **Weights delivery.** **MobileSAM** CoreML artifact (license-checked; download once and cache). **First-run UX:** accurate Auto Select triggers a **blocking download** with progress + cancel → Vision fallback for that attempt if cancelled or failed. **Optional optimization (not required PR 1 scope):** Wi‑Fi-only, idle, best-effort **opportunistic prefetch**. Bundling weights in the app re-litigates this lock unless explicitly amended. EfficientSAM-first deferred until a ready CoreML conversion exists; SAM2 CoreML is the measurement fallback if MobileSAM underperforms.

14. **Subject Select** is a **full matting product**, not Vision polish.

15. **Model freshness vs product polish.** Engine weights stay **swappable** behind `SelectionProvider`. PR 1 ships **MobileSAM** (mature artifact). **Watch list (named only):** EfficientSAM3 CoreML export status; SAM2 CoreML maturity (esp. temporal when relevant). **Cadence:** ~quarterly re-check + re-run a **checked-in measurement harness** on Laugh fixtures — not continuous AI-news monitoring. Custom conversion via coremltools is allowed when a promising model lacks a package. **Strategic watch:** Apple Vision gaining first-party promptable/general segmentation could change the need for third-party SAM — low near-term probability, high impact.

16. **Where “edge of technology” is allowed.** Core substrate (mask / provider / refine / compose) stays **boring**. Auto engine = **track edge, ship mature**. Differentiating edge bets (sequenced after still-image solid): open-vocabulary / text-prompt select + agent-local edits; later video/temporal matting (SAM2-class). Custom-trained heads only after a measured gap. One deliberate pre-1.0 bet per roadmap cycle, contained behind the protocol so a bad bet is cheap to rip out.

17. **PR 1 boundary stage:** coarse MobileSAM + thin class-blind **CI photo-edge / trimap polish** only (no second neural matting head). Neural boundary matting = follow-up once MobileSAM is measured.

- “Adapt sky” / “adapt rocks” = new adjust (or tool) over an existing mask — **zero** changes to `SelectionProvider` / `SelectionMask` / refine / compositor if the abstraction holds.
- Vision has **two roles**: (1) **tool-layer prompt builder** for Auto Select Person on the accurate path (rough mask → +/− points + box → SAM; SAM owns the matte); (2) **fallback matte engine** only when CoreML/SAM is unavailable. These are different code paths — prompt-assist must not be read as contradicting “SAM owns accurate mattes.”
- Accurate Auto Select = **one** SAM-class CoreML conformer with internal two-stage pipeline (coarse mask → boundary matting). Person-matting-only specialists rejected — they contradict class-blind “sky/rocks over any mask.”
- **Debt (W3-08d):** `ImageSelectionSession` still hardcodes person for the first UI tool. Sequence: **PR 1** = SAM conformer + coarse→boundary behind Auto Select (Vision prompt-assist; session may stay person-shaped). **PR 2 (immediately after)** = deperson session. Do **not** tune Refine Edge / decontam (W3-08b) against Vision mattes first.
- Face / Body / Sky / Rocks consume masks; they do not own selection infrastructure.
- Leak test: if adding a rock tool requires editing shared selection code, the boundary is wrong.
- Glossaries: `SelectionMask`, `SelectionProvider`, `SelectionRefineParameters`, `SelectionHint`, `ImageSelectionSession` in `CONTEXT.md`.

## Alternatives considered

- **Person-matte-only API / person-matting-only CoreML:** Rejected — contradicts class-blind substrate; sky/rocks would need a second model (= new selection infrastructure).
- **A-vs-C as competing engines:** Rejected — C is the pipeline shape *inside* the SAM-class conformer (coarse → boundary matting), not an alternative to A.
- **Folding selection into `ImageAdjustParameters`:** Rejected — breaks the shared develop graph and presets; selection is mask-scoped, not global.
- **Baking class switches into refine/compositor “for convenience”:** Rejected — fails the sky/rocks leak test.
- **EfficientSAM-first for PR 1:** Deferred — CoreML export still immature vs ready MobileSAM Apache-2.0 `.mlpackage`; not a rejection on eventual quality merits.
- **SAM2-first for PR 1:** Deferred — viable if MobileSAM measurement fails; larger/heavier than MobileSAM for interactive stills; no video win for PR 1 scope.
- **Bundle weights in installer (delivery C):** Rejected unless the download-once+cache lock is explicitly amended — not a first-run UX peer to A/B.
- **Unconditional background prefetch on Subject Select expand (plain B):** Rejected — surprise network/cellular use conflicts with privacy-forward positioning.
- **Grid-only / unprompted SAM for “Auto Select Person”:** Rejected for PR 1 — one-button person promise fails on busy scenes; class-blindness is substrate property, not a ban on tool-layer prompt helpers.
- **Neural boundary-matting head in PR 1:** Deferred until MobileSAM is measured; PR 1 uses CI photo-edge/trimap polish only.
- **Bleeding-edge everywhere:** Rejected — edge only in swappable engine freshness + later text/agent/temporal; substrate stays boring.
