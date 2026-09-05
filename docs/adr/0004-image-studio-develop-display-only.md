# ADR 0004: Image studio develop tools — display-only Core Image stack

## Status

Accepted (2026-07-23)

## Context

**ImageMedia** already has a right **edit sidebar** with **ImageAdjustSettings** (outline groups of **ImageDevelopTool** rows) and a **Presets** tab. Users want a fuller “develop” toolset (RAW-style light, HSL, curves, crop, optics, dodge & burn, etc.).

We need a durable structure so each new tool lands in a known UI group, uses a known processing path, and is tracked by difficulty — without rewriting files on disk until an explicit export/save decision exists.

## Decision

1. **Display-only by default.** All develop tools adjust the on-screen **ImageMedia** presentation via a Core Image filter graph (`ImageAdjustParameters` → `ImageSurfaceView`). They do **not** rewrite the source file. **ImageExport** writes a new file; **ImageUserPreset** stores a named parameter snapshot.
2. **Outline tools + Presets tab.** Tools ship as expandable rows under outline groups on **Edits** (one tool open at a time); unfinished tools stay listed as Coming soon. Named looks stay on **Presets**. New tools get an outline id + SF Symbol in `ImageDevelopOutline` before UI work starts (see roadmap).
3. **Incremental rollout by ease.** Ship Wave 1 (cheap CI filters / presets) before Wave 2 (custom UI: curves, HSL, WB eyedropper) before Wave 3 (geometry brushes, RAW, AI crop, lens profiles). One tool (or small related cluster) per change; update the roadmap status when merged.
4. **Shared parameter model.** New sliders extend `ImageAdjustParameters` + the CI apply chain; presets map to the same struct. Avoid parallel “effect” systems.
5. **Before/After stays.** Meta-bar Before/After compares identity vs current parameters for any tool in the graph.

## Consequences

- Roadmap lives in `docs/image-studio-develop-roadmap.md` (source of truth for status / wave / section).
- Glossaries in `CONTEXT.md` describe the product terms; the roadmap tracks implementation status.
- RAW, brush tools, and AI crop are deferred until Waves 1–2 prove the graph and UI patterns.

## Alternatives considered

- **Destructive edit-in-place:** Rejected. **ImageExport** always writes a new file.
- **Big-bang Luminar-parity release:** Rejected; hard to review and regress.
- **Per-tool ad hoc filters outside `ImageAdjustParameters`:** Rejected; breaks presets and Before/After.
