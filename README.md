# Syncthing Swift Tray

macOS menu-bar app for Syncthing (`com.brandonstone.syncthingtray`). Requires macOS 14+.

## Local unsigned build

Needs Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
./scripts/build-app.sh
```

That produces `build/Syncthing Tray.app` without Developer ID signing.

## Release (signed, notarized, stapled)

GitHub Actions publishes **dedicated** Apple Silicon and Intel builds, plus a universal binary in addition:

| Artifact | Runner | `xcodebuild` |
| --- | --- | --- |
| `SyncthingTray-{version}-macos-arm64.{zip,dmg}` | `macos-15` | `ARCHS=arm64 ONLY_ACTIVE_ARCH=YES` |
| `SyncthingTray-{version}-macos-x86_64.{zip,dmg}` | `macos-15-intel` | `ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES` |
| `SyncthingTray-{version}-macos-universal.{zip,dmg}` | `macos-15` | `ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO` |

Each `.app` is Developer ID-signed, notarized via a temp zip (that zip is not a release asset), stapled, then shipped as the named zip. The `.dmg` is signed, notarized, and stapled separately. One GitHub Release attaches every zip+dmg plus `SHA256SUMS`.

## In-app updates (Sparkle 2)

The tray wrapper updates itself with [Sparkle 2](https://sparkle-project.org). That is separate from **Auto-check runtime updates**, which still only refreshes the bundled Syncthing *daemon* (`UpdateCoordinator`).

- About every two days Sparkle fetches `https://github.com/bstone108/Syncthing-Swift-Tray/releases/download/appcast/appcast.xml`.
- The feed lists dedicated `macos-arm64` and `macos-x86_64` zip enclosures. Universal extras are published but are not Sparkle targets.
- After the matching archive is staged, Sparkle offers **Install and Relaunch** or **Later**. Later installs on the next quit and does not nag that same version again.
- The popover **Check for Updates…** button runs a manual check.

Publish-only EdDSA signing writes `SPARKLE_ED_PRIVATE_KEY` to a mode-600 temp file, passes `-f` to the appcast generator (Sparkle `generate_keys -x` 32-byte seed), then deletes the file. `SUPublicEDKey` is committed in `Info.plist`. Do not generate a new keypair.

If `SPARKLE_ED_PRIVATE_KEY` is missing on a publish run, packaging still notarizes, but appcast generation is skipped and installed apps cannot verify updates.

Pull requests compile unsigned Release on **both** runners (`CODE_SIGNING_ALLOWED=NO`) and fail if either dedicated slice is missing. The `macos-15` job also compiles universal and fails if either arch is missing. PRs do not sign, notarize, or consume a date.build number.

After this workflow is merged, cut a GitHub Release with either:

1. **Actions → macOS Release → Run workflow** (`workflow_dispatch`), which assigns the next `YYYY.M.D.N` in America/Chicago (unpadded month/day) and tags `v{version}`, or
2. Push a `v*` tag (`vYYYY.M.D.N`) to package that version.

Do not publish from a push to `main`. Never `macos-latest` or self-hosted.
