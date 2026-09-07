# Selection fixtures

Used by `ImageSelectionStressTests`, `SelectionMeasurementTests`, `scripts/stress-selection.sh`, and `scripts/measure-selection.sh`.

- `person-*` — positive person cases
- `negative-*` / `synthetic-silhouette` / `preview-*` / `luminar-*` / `stress-4k` — negatives & size stress

Load path is resolved from `#filePath` (not SPM resources).

## Measurement harness (W3-08e)

```bash
./scripts/measure-selection.sh           # Vision baseline (no network)
./scripts/measure-selection.sh mobilesam # MobileSAM when Application Support cache is ready
```

Compare `[SEL-MEASURE] summary` lines (`personCov`, `soft`, `personMs`, `negFP`) across providers.
