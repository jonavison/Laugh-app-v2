# Image studio develop roadmap

Living checklist for **ImageMedia** edit tools. Product rules: [ADR 0004](adr/0004-image-studio-develop-display-only.md).

**How to use:** when adding a tool, (1) pick the row below, (2) set status → `in progress`, (3) ship UI in the listed **Edits section**, (4) extend `ImageAdjustParameters` + CI chain, (5) mark `done` and note the PR/commit.

**Status:** `done` · `partial` · `todo` · `later`

**Ease:** `S` small (hours) · `M` medium (days) · `L` large (multi-day / new UI paradigms)

---

## Already shipped (baseline)

| Tool | Section | Status | Notes |
|------|---------|--------|--------|
| Exposure | Develop | done | `CIExposureAdjust` |
| Brightness | Develop | done | `CIColorControls` |
| Contrast | Develop | done | `CIColorControls` |
| Highlights / Shadows | Develop | done | `CIHighlightShadowAdjust` |
| Saturation / Vibrance | Color | done | `CIColorControls` + `CIVibrance` |
| Temperature / Tint | Color | done | `CITemperatureAndTint` (WB lite) |
| Sharpness | Details | done | `CISharpenLuminance` |
| Definition (clarity-ish) | Details | done | `CIUnsharpMask` |
| Looks / Mood presets | Presets | done | Named `ImageAdjustPreset`s |
| Before / After | Meta bar | done | Identity vs current params |

---

## Wave 1 — easiest next (ship first)

Cheap Core Image filters or preset recipes. Same slider/card patterns we already have.

| ID | Tool | Edits section | Ease | Status | CI / approach |
|----|------|---------------|------|--------|----------------|
| W1-01 | Whites / Blacks | Develop | S | done | Soft `CIToneCurve` toe/shoulder anchors |
| W1-02 | Hue | Color | S | done | `CIHueAdjust` |
| W1-03 | Color balance (3-way lite) | Color | S | done | Mid cyan↔red via `CIColorMatrix` |
| W1-04 | Vignette | Vignette | S | done | `CIVignette` (center drag → Wave 2) |
| W1-05 | Black & White | Black & White | S | done | Saturation blend + mild contrast |
| W1-06 | High Key | Effects / Presets | S | done | Mood preset `highKey` |
| W1-07 | SuperContrast | Effects / Presets | S | done | Mood preset `superContrast` |
| W1-08 | Film stocks (expand) | Presets | S | done | Film tab: Portra / Fuji / Noir |
| W1-09 | Denoise | Denoise | S | done | `CINoiseReduction` before sharpen |
| W1-10 | Split toning | Color | M | done | Split hi/shadow + amount via `CIColorMatrix` |
| W1-11 | Structure (stronger clarity) | Details | S | done | Wider-radius `CIUnsharpMask` vs Definition |

**Suggested order inside Wave 1:** W1-02 Hue → W1-04 Vignette → W1-05 B&W → W1-01 Whites/Blacks → W1-09 Denoise → W1-06/07 presets → W1-08 film stocks → W1-11 Structure → W1-03 Color balance → W1-10 Split toning.

---

## Wave 2 — more structure (custom controls)

Needs richer UI or multi-control graphs; still display-only CI.

| ID | Tool | Edits section | Ease | Status | CI / approach |
|----|------|---------------|------|--------|----------------|
| W2-01 | Curves | Tone | M | todo | `CIToneCurve` + RGB/luma curve editor view |
| W2-02 | HSL per channel | HSL | M | todo | 6–8 color wheels; `CIColorCube` or channel masks |
| W2-03 | White Balance eyedropper | Color / WB | M | todo | Click image → sample neutral → solve temp/tint |
| W2-04 | Vignette center point | Effects | M | todo | Drag center on image + existing vignette |
| W2-05 | Sharpening (amount/radius/detail) | Detail | M | todo | Expand beyond single sharpness slider |
| W2-06 | Smart contrast | Light | M | todo | Auto from histogram + user strength |

---

## Wave 3 — hard / later

New interaction models, RAW pipeline, or ML.

| ID | Tool | Edits section | Ease | Status | Why later |
|----|------|---------------|------|--------|-----------|
| W3-01 | RAW/Develop ingest | Develop | L | later | Needs RAW decode path (e.g. Circum / LibRaw), not just JPEG/HEIC |
| W3-02 | Lens corrections / Optics | Optics | L | later | Distortion + CA need lens profiles or manual mesh |
| W3-03 | Crop + horizon straighten | Crop | L | partial | Toolbar crop mode: Free / Original / 1:1 / 4:5 / 16:9; display-only + Export. Straighten / AI still later |
| W3-04 | Crop AI compositions | Crop | L | later | Depends on W3-03 + vision heuristics/ML |
| W3-05 | Dodge & Burn | Retouch | L | partial | v1 = luminosity-range Amount/Range/Softness (no brush yet); painted D&B later |
| W3-06 | Full Develop (whites/blacks + WB + optics as suite) | Develop | L | later | Bundle after Waves 1–2; not a single filter |
| W3-07 | Selection foundation | Portrait / Select | M | done | `SelectionProvider` + `SelectionMask` + `ImageSelectionSession` (ADR 0005) |
| W3-08 | Vision person select | Portrait | M | done | Baseline UI: views + F + global refine + cutout export. Vision is fallback only — not the precision ceiling |
| W3-08a | Selection edge refine | Portrait | M | done | Smooth / Feather / Contrast / Shift Edge (polish after a strong matte) |
| W3-08b | Local refine + decontam | Portrait | L | done | Paint In/Out/Refine Edge + radius cursor ring + interior-pull decontam on cutout |
| W3-08c | SAM-class CoreML auto engine | Portrait / Select | L | done | **PR 1:** MobileSAM (SamKit) + Vision→+/−/box prompt + CI edge polish. Blocking download; cancel→Vision fallback. Quarterly watch: EfficientSAM3 CoreML, SAM2 CoreML |
| W3-08e | Measurement harness | Select | S | done | `SelectionMeasurementTests` + `scripts/measure-selection.sh` — `[SEL-MEASURE]` coverage/softness/timing; MobileSAM when cached |
| W3-11 | Point-prompt / text-prompt select | Select | L | partial | Click/box point-prompt shipped (Click Select); text-prompt later |
| W3-12 | Temporal / video matting | Select | L | later edge | SAM2-class when CoreML temporal is real; Mac differentiator |
| W3-08d | Deperson session | Select | S | done | Session APIs class-agnostic; person prompt assist at tool layer (`SelectionPersonPromptAssist`) |
| W3-09 | Face / Body AI tools | Portrait | L | later | Consume `SelectionMask` where `class == .person` (and face subregions when available) |
| W3-10 | CoreML semantic classes | Select | L | later | Optional class labels / hints only — not required for mask pipeline |
| W3-11 | Point-prompt select | Select | L | partial | Click Select (+/−/box) on MobileSAM; text later |

---

## Section map (UI structure)

**Edits** uses outline groups (**Essentials**, **Landscape**, **Creative**, **Portrait**, **Professional**). Each **ImageDevelopTool** is a row: available tools expand (one at a time); unfinished tools stay visible but grayed (“Coming soon”). Catalog: `ImageDevelopOutline`.

### v1 expandable tools (`ImageAdjustSection`)

| Tool | Symbol | Owns |
|------|--------|------|
| Develop | `sun.max.fill` | Exposure, brightness, contrast, highlights/shadows, whites/blacks |
| Color | `paintpalette.fill` | Saturation, vibrance, hue, temp/tint, color balance, split toning |
| Dramatic | `bolt.fill` | S-curve punch, local contrast, cool grade, vignette |
| Mood | `paintbrush.pointed.fill` | Soft nostalgic grade (curve + warm wash) |
| Toning | `circle.hexagongrid.fill` | Amount + highlight/shadow hue axes |
| Matte | `rectangle.dashed` | Lifted blacks / compressed whites print matte |
| Glow | `sparkle` | Orton-style bloom (amount + radius) |
| Soft focus (Blur) | `camera.filters` | Soft-focus blend (not flat gaussian) |
| Film Grain | `film` | Luma soft-light grain (amount + size) |
| Mystical | `sparkles` | Amount + haze + hue (violet↔teal ethereal grade) |
| High Key | `sun.haze.fill` | Amount + softness bloom |
| Supercontrast | `circle.righthalf.filled` | Amount + midtone clarity |
| Color Harmony | `paintpalette` | Amount + warm/cool balance |
| Sunrays | `sun.horizon.fill` | Amount + length + warmth (zoom-blur rays) |
| Landscape | `mountain.2.fill` | Amount + foliage + sky polish |
| Black & White | `circle.lefthalf.filled` | Amount + contrast + warmth |
| Details | `wand.and.stars` | Sharpness, definition, structure |
| Denoise | `waveform` | Denoise |
| Vignette | `circle.dashed` | Amount + midpoint |
| Dodge & Burn | `paintbrush.pointed` | Amount (−dodge/+burn) + tonal range + softness |

Coming-soon rows (Erase, Structure AI, Relight AI, Twilight/Atmosphere/Water AI, Portrait Face/Body/Bokeh AI, Clone, etc.) reserve IA slots without controls yet. **Subject Select** (Portrait) is available: Vision person matte, Select-and-Mask view modes (default Marching Ants + **F** cycle), edge refine (Smooth/Feather/Contrast/Shift Edge), and optional cutout PNG export.

**Presets** tab: Looks / Mood / Film / Saved — only recipes over `ImageAdjustParameters`, no separate engine. **ImageUserPreset**s are named snapshots from the sidebar footer.

**Preview performance:** slider drags emit `ImageAdjustRenderQuality.preview` (longest edge ≤ 1600) on a cached base `CIImage`; after ~140ms settle (and on presets/reset) emit `.full` on a background queue with generation cancellation.

---

## Implementation checklist (every tool)

When marking a tool `in progress` / `done`:

1. [ ] Row updated in this file (status + date optional)
2. [ ] Expandable tool row exists under the correct outline group (or Coming soon until implemented)
3. [ ] Fields on `ImageAdjustParameters` + CI apply in `applying(to:)`
4. [ ] Sliders/controls in `ImageAdjustControls` + Edits tab wiring
5. [ ] Per-tool eye/restore + Reset All + Before/After still correct
6. [ ] Optional: preset(s) if the tool is recipe-friendly
7. [ ] `CONTEXT.md` term touched only if the **product language** changed

---

## Mapping from the product wish-list

| Wish-list name | Roadmap IDs |
|----------------|-------------|
| Develop RAW – exposure, highlights, shadows, whites/blacks, WB, lens | W1-01, shipped light, W2-03, W3-01, W3-02 |
| Light – exposure, smart contrast, highlights, shadows | shipped + W2-06 |
| Color – sat, vibrance, hue, color balance | shipped + W1-02, W1-03 |
| HSL | W2-02 |
| Curves | W2-01 |
| White Balance + eyedropper | shipped temp/tint + W2-03 |
| Split Toning | W1-10 |
| Crop AI / horizon | W3-03, W3-04 |
| Optics | W3-02 |
| Clarity & Structure | partial (Definition) + W1-11 |
| Sharpening | shipped + W2-05 |
| Denoise | W1-09 |
| Vignette | W1-04, W2-04 |
| Black & White | W1-05 |
| High Key | W1-06 |
| Film Stocks / Presets | shipped + W1-08 |
| Dodge & Burn | W3-05 |
| SuperContrast | W1-07 |
