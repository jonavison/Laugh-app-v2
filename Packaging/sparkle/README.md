# Sparkle (in-app updates)

LaughPlayer uses [Sparkle 2](https://sparkle-project.org) like Smile.

| Item | Value |
|------|--------|
| Feed | `https://avison-soft.com/laugh/appcast.xml` |
| Public key | `public-ed-key.txt` (committed) |
| Private key | Login Keychain on the release Mac (same Avison key as Smile unless overridden) |

## One-time setup

```bash
./scripts/sparkle-generate-keys.sh
```

If a Sparkle key already exists in Keychain (e.g. from Smile), this writes that public key into `public-ed-key.txt`. Commit it.

Optional private key file for CI:

```bash
LAUGH_SPARKLE_EXPORT_PRIVATE_KEY=1 ./scripts/sparkle-generate-keys.sh
```

Add `Packaging/release-env.local` (gitignored):

```bash
LAUGH_SPARKLE_PRIVATE_KEY_FILE=/secure/path/ed25519-private-key.pem
```

## Ship an update

```bash
OUT_DIR=.build ./scripts/create-app-bundle.sh   # embeds Sparkle + SUFeedURL
./scripts/build-macos-sparkle-zip.sh
./scripts/generate-laugh-appcast.sh
# Copy .build/sparkle-releases/appcast.xml + LaughPlayer <ver>.zip
# → advision-web/public/laugh/
```
