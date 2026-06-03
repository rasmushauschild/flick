# Release signing and notarization setup

One-time setup before your first signed release or GitHub Actions run.

## Apple Developer

1. Enroll in the [Apple Developer Program](https://developer.apple.com/programs/).
2. In [Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources):
   - Confirm App ID **com.xolo.Flick** exists.
   - Create and install a **Developer ID Application** certificate.
3. In Xcode, open the Flick target → **Signing & Capabilities**:
   - Select your **Team**.
   - Keep **Automatically manage signing** enabled.

Set your Team ID for command-line builds (optional if Xcode already has it):

```bash
export DEVELOPMENT_TEAM="XXXXXXXXXX"   # 10-character Team ID from developer.apple.com
```

## Notarization (pick one)

### Option A — App Store Connect API key (recommended for CI)

1. Create an API key with **Developer** role in App Store Connect → Users and Access → Integrations.
2. Download the `.p8` file once.
3. Store these as GitHub Actions secrets:
   - `APPLE_API_KEY_ID`
   - `APPLE_API_ISSUER_ID`
   - `APPLE_API_KEY_P8` (full contents of the `.p8` file)

### Option B — Apple ID + app-specific password

```bash
xcrun notarytool store-credentials "flick-notary" \
  --apple-id "you@example.com" \
  --team-id "$DEVELOPMENT_TEAM" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

Use `--keychain-profile "flick-notary"` in `scripts/release.sh` instead of API key env vars.

## Sparkle update signing

Generate EdDSA keys once (from a Sparkle release checkout or SPM DerivedData `Sparkle/bin/generate_keys`):

```bash
./generate_keys
```

- **Private key** → never commit. Save as GitHub secret `SPARKLE_PRIVATE_KEY` (file contents).
- **Public key** → in [`Flick/Info.plist`](../Flick/Info.plist) as `SUPublicEDKey`.

To export the private key for GitHub Actions:

```bash
build/sparkle/bin/generate_keys -x /tmp/sparkle-ed25519-private-key
# Paste contents into GitHub secret SPARKLE_PRIVATE_KEY, then delete the file.
```

To regenerate keys, update the public key in the Flick target build settings and replace the secret.

## GitHub Actions secrets

| Secret | Purpose |
|--------|---------|
| `APPLE_CERTIFICATE_P12` | Base64-encoded `.p12` export of Developer ID cert + private key |
| `APPLE_CERTIFICATE_PASSWORD` | Password for the `.p12` |
| `APPLE_TEAM_ID` | 10-character Team ID |
| `APPLE_API_KEY_ID` | Notary API key ID |
| `APPLE_API_ISSUER_ID` | Notary issuer ID |
| `APPLE_API_KEY_P8` | Notary `.p8` contents |
| `SPARKLE_PRIVATE_KEY` | Sparkle `ed25519` private key file contents |

Export the certificate for CI:

```bash
# Keychain Access → My Certificates → Developer ID Application → Export → .p12
base64 -i Certificates.p12 | pbcopy   # paste into APPLE_CERTIFICATE_P12
```

## Local release

```bash
export DEVELOPMENT_TEAM="XXXXXXXXXX"
./scripts/release.sh v1.0.0
```

Requires `gh` CLI authenticated to `rasmushauschild/flick`.
