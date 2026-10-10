# ADR 0006: Per-image develop edit ownership (save / batch)

## Status

Accepted (2026-10-06); amended (2026-10-06) — leave-image prompts removed.

## Context

Develop tools today keep a sticky **ImageAdjustSession** across carousel switches (same look follows the user). That fights a Luminar-like workflow: grade one still, keep its look, batch-stamp siblings, export one or many, without rewriting sources (ADR 0004).

Modal **Save / Don’t Save** on every filmstrip step is too heavy for browsing. Users need free single-image navigation, a catalog of what has been edited, and a quit safety net.

## Decision

1. **Per-image ownership.** Each still has at most one saved **ImageDevelopEdit** (parameters + geometry) keyed by source path in an **in-app store** (v1 — no sidecar). **ImageAdjustSession** is only the live surface for the open **ImageMedia**.
2. **Working copies while browsing.** Leaving an image **stashes** unsaved work in a per-path working map (no modal). Re-opening restores working copy if present, else the saved document, else identity. Explicit **Save Develop** writes store + clears working for that path; **Discard Develop** drops working and reloads saved/identity.
3. **Quit prompt only.** Quitting while any working edits exist presents **Save All** / **Don’t Save** / **Cancel**. Leaving the image, opening video, or empty-surface does **not** prompt.
4. **Export ≠ Save.** **ImageExport** renders the live session of the open still (dirty OK, including an unedited photo) and does not auto-save. **BatchImageExport** writes one new file per still in the active set, each from that still’s own look (Dry/Wet mix when the batch is active). Both live on the right **ImageStudioCommitFooter**, not the Batch catalog. Neither overwrites a source file.
5. **Batch stamps params while the Batch tab is active.** **BatchLookApply** copies `ImageAdjustParameters` only into selected targets’ **saved** documents (clears working for those paths). No separate Apply Look button — entering Batch / growing the set / coalesced slider settle stamps. The open still **previews live**; the N-image store write waits until settle so large sets stay snappy. Each catalog row has a **Dry / Wet** mix against the look the still had when it joined the set. Crop / straighten / rotation stay per image. The **active batch session** (membership, shared wet look, per-image mix / dry bases) is persisted in-app so quit/relaunch restores the batch — not only flattened single-image documents.
6. **Left rail tabs.** **Info** | **Edits** | **Batch**. **Edits** lists **single-image** looks (saved and/or unsaved working copies). Stills in the active batch belong only to **Batch**, even once stamped. **Batch** is the develop set. Selecting 2+ in **ImageFolderCarousel** or **Edit as Batch** from the library grid/list opens the column and switches to Batch.
7. **Reset vs clear.** **Reset** (right footer) → session toward identity (working/unsaved). **Clear saved look** → **ImageEditsCatalog** hover trash deletes document + working (confirm). **Clear all** on that catalog removes every **single-image** look listed there (one confirm; batch membership unchanged). Carousel top-left edit icon: filled = saved, outline = unsaved working.

## Consequences

- Glossary terms live in `CONTEXT.md`.
- ADR 0004 display-only / export-new-file policy unchanged.
- Implementation must not session-sticky-carry adjusts across image switches.
- Selection mattes remain on **ImageSelectionSession** unless a later ADR folds them into **ImageDevelopEdit**.

## Alternatives considered

- **Session-sticky only:** Rejected; loses per-image grades.
- **Modal on every leave-image:** Rejected after use; blocks browsing (amended).
- **Silent auto-save on every leave:** Rejected; keeps explicit Save + working copies + quit Save All.
- **Live linked multi-image editing:** Rejected for v1; use **BatchLookApply**.
