# ADR 0001: Incremental codec rollout with manual verification

## Status

Accepted (2026-05-28)

## Context

LaughPlayer aims for broad playback (near-VLC) but native macOS decoding cannot cover all container/codec profiles (for example HEVC 10-bit in Matroska). Expanding a fourcc list in app code does not add decode capability. Users still need reliable, honest support claims.

## Decision

1. **Product goal:** Near-VLC breadth over time, not “native checklist growth.”
2. **Rollout rule:** **IncrementalCodecRollout** — one **VerifiedPlaybackPath** per change; no bulk matrix updates.
3. **Verification:** **PlaybackVerificationRecord** required (fixture clip + manual play + Cmd+Shift+D snapshot in commit/PR notes).
4. **Engine split:** **NativePlaybackEngine** (**SystemDecodeStack** via AVFoundation) stays try-then-fail on what macOS provides; new profiles that fail natively go to **AlternateDecoder** (**CompatibilityRemux** via bundled FFmpeg on direct builds) only after the same verification bar.

## Consequences

- SUPPORT.md grows slowly and accurately; Baraka-style failures remain “not verified” until Phase 2 covers that profile.
- Phase 2 work is serial and test-driven; higher upfront cost per format, fewer false “supported” claims.
- Automated playback smoke tests are deferred; manual verification is the gate until paths stabilize.

## Alternatives considered

- **Longer native fourcc list:** Does not fix OS decode limits; rejected as primary strategy.
- **Big-bang FFmpeg integration then document:** Hard to triage regressions; rejected.
- **Automated smoke tests first:** Valuable later; not the initial gate per team preference.
- **Direct VideoToolbox decode pipeline:** Does not add demux/container coverage beyond AVFoundation; high engineering cost; rejected in favor of **CompatibilityRemux** then replay through **SystemDecodeStack** (see ADR 0003).
