# ADR 0002: Dual Distribution Codec Strategy

## Status

Accepted

## Context

LaughPlayer targets both:

- direct download users who expect broad codec compatibility out of the box
- Mac App Store users where bundled codec stacks can be constrained

Native AVFoundation playback (**SystemDecodeStack**) is stable and deeply integrated with macOS UI, but codec/container coverage is narrower than VLC/IINA for edge profiles (for example `hev1` rendering failures where audio plays but frames do not render). A custom VideoToolbox-only path does not close that gap without a separate demuxer.

## Decision

Adopt a dual strategy:

1. **Direct distribution**
   - Use **SystemDecodeStack** (AVFoundation / AVPlayer) as the primary playback path.
   - Enable bundled codec helper tools under `Sources/LaughPlayer/codec-tools/bin`.
   - On confirmed **CompatibilityFailure**, run **CompatibilityRemux** (FFmpeg stream-copy to a temporary MP4, then replay through **SystemDecodeStack**). See ADR 0003.

2. **App Store distribution**
   - Keep **SystemDecodeStack** only (no bundled FFmpeg remux).
   - Keep compatibility messaging explicit when native decode fails.

## Consequences

- Direct users get stronger compatibility without asking users to install external dependencies.
- Build/release process now needs separate scripts and QA passes for direct vs App Store.
- App Store build may still fail on codecs unsupported by AVFoundation; UX must communicate this clearly.
