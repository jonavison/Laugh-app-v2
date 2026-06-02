---
name: commit-with-v
description: Bumps Smile’s marketing semver in Packaging/RELEASE_VERSION, aligns commits and optional git tags with macOS packaging. Use when the user says commit with v, bump version, release commit, RELEASE_VERSION, semver, tag release, or wants a versioned ship commit.
---

# commit-with-v

## Version model (this repo)

| Piece | Source | Ends up in |
|-------|--------|------------|
| Marketing / semver | [Packaging/RELEASE_VERSION](../../../Packaging/RELEASE_VERSION) (one line, e.g. `0.2.0`) or 1st arg to the script | `CFBundleShortVersionString`, `pkgbuild --version`, default `.pkg` name |
| Build number | `git rev-list --count HEAD` (or 2nd script arg) | `CFBundleVersion` |

Authoritative script: [scripts/build-macos-pkg.sh](../../../scripts/build-macos-pkg.sh) (header comments + generated `Info.plist`). Background: [0008-smile-packaging-versioning](../../../docs/adr/0008-smile-packaging-versioning.md).

Treat **RELEASE_VERSION** as the single source of truth for the user-visible string. **Commit it in git** so clones build with the same marketing version by default.

**Build number caveat:** `rev-list --count` can change after history rewrite (squash/rebase). If that bites, move to a CI counter or committed build file later.

## Semver bumps

- File contents: `MAJOR.MINOR.PATCH` only — **no** `v` prefix, one line, trim whitespace.
- Validate with: `^[0-9]+\.[0-9]+\.[0-9]+$` (reject pre-release strings unless you change house rules).

**Pre-1.0 (`0.y.z`):** patch = fixes; minor = features / user-visible behavior changes; major = reserve for eventual breaking or public-API redefinitions.

**From `1.0.0`:** major = breaking, minor = features, patch = fixes.

Do **not** reset to `0.0.0` unless deliberately restarting public history; prefer the **next** appropriate version so existing users and tags stay coherent.

## Workflow

1. **Gate:** Create a git **commit** only if the user **explicitly** asked (repo rule: never commit unprompted).
2. **Choose** patch / minor / major from what is shipping; agree the new triple with the user if unclear.
3. **Edit** only `Packaging/RELEASE_VERSION` to that triple.
4. **Stage** whatever belongs in this release: either **same commit** as feature/fix work, or a **version-only** commit after those changes — both are valid; be explicit about intent.
5. **Commit** per user rules:
   - Message via **HEREDOC** (`git commit -m "$(cat <<'EOF' ... EOF)"`).
   - **No** `--no-verify` / hook skips unless the user explicitly requests it.
   - Message should explain **why** this release matters, not only “bump version”.
   - Follow the **committing-changes-with-git** user rule: analyze diff, don’t commit secrets, don’t amend except under the rule’s narrow conditions, don’t push unless asked.
6. **Tag (optional, recommended when shipping):** after the commit, `git tag -a vX.Y.Z -m "..."` where `X.Y.Z` matches `RELEASE_VERSION` exactly. **Never** `git push` or push tags unless the user explicitly asks.
7. **Package:** `scripts/build-macos-pkg.sh` reads the file by default; see script usage for overrides.

## Quick checklist

- [ ] User explicitly requested a commit (if committing).
- [ ] Semver validated; no `v` in file.
- [ ] Staged files match intended release set.
- [ ] Commit message explains the release; HEREDOC; hooks respected.
- [ ] Tag only if cutting a release track; no push unless requested.
