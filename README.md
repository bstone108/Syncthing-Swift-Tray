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

Pull requests compile unsigned Release on **both** runners (`CODE_SIGNING_ALLOWED=NO`) and fail if either dedicated slice is missing. The `macos-15` job also compiles universal and fails if either arch is missing. PRs do not sign, notarize, or consume a date.build number.

After this workflow is merged, cut a GitHub Release with either:

1. **Actions → macOS Release → Run workflow** (`workflow_dispatch`), which assigns the next `YYYY.M.D.N` in America/Chicago (unpadded month/day) and tags `v{version}`, or
2. Push a `v*` tag (`vYYYY.M.D.N`) to package that version.

Do not publish from a push to `main`. Never `macos-latest` or self-hosted.
