# ADR 0002: Dual Distribution Codec Strategy

## Status

Accepted

## Context

LaughPlayer targets both:

- direct download users who expect broad codec compatibility out of the box
- Mac App Store users where bundled codec stacks can be constrained

Native AVFoundation playback is stable and deeply integrated with macOS UI, but codec/container coverage is narrower than VLC/IINA for edge profiles (for example `hev1` rendering failures where audio plays but frames do not render).

## Decision

Adopt a dual strategy:

1. **Direct distribution**
   - Use AVFoundation as primary path.
   - Enable bundled codec helper tools under `Sources/LaughPlayer/codec-tools/bin`.
   - Use fallback conversion path automatically on confirmed render failures.

2. **App Store distribution**
   - Keep native AVFoundation decoder path only.
   - Keep compatibility messaging explicit when native decode fails.

## Consequences

- Direct users get stronger compatibility without asking users to install external dependencies.
- Build/release process now needs separate scripts and QA passes for direct vs App Store.
- App Store build may still fail on codecs unsupported by AVFoundation; UX must communicate this clearly.
