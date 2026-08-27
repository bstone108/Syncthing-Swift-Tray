# Syncthing Swift Tray

macOS menu-bar app for Syncthing (`com.brandonstone.syncthingtray`). Requires macOS 14+.

## Local unsigned build

Needs Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
./scripts/build-app.sh
```

That produces `build/Syncthing Tray.app` without Developer ID signing.

## Release (signed, notarized, stapled)

GitHub Actions on `macos-15` builds one universal `Syncthing Tray.app` (`arm64` + `x86_64`), Developer ID-signs it, notarizes, staples the `.app`, then ships a zip of that stapled app plus a stapled `.dmg`.

Pull requests only compile Release with `CODE_SIGNING_ALLOWED=NO`. They do not sign, notarize, or consume a date.build number.

After this workflow is merged, cut a GitHub Release with either:

1. **Actions → macOS Release → Run workflow** (`workflow_dispatch`), which assigns the next `YYYY.M.D.N` in America/Chicago (unpadded month/day) and tags `v{version}`, or
2. Push a `v*` tag (`vYYYY.M.D.N`) to package that version.

Do not publish from a push to `main`.
