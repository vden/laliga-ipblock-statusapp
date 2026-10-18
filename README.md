# HayFutbol

A menu bar icon showing whether LaLiga's IP blocks are on right now, according to
[hayahora.futbol](https://hayahora.futbol).

Download the DMG from [Releases](https://github.com/vden/laliga-ipblock-status/releases).
It is signed and notarized, runs on Apple silicon and Intel, macOS 13 or later.

- Plain ball: no blocking.
- Red ball: blocking is on. The menu shows how many IPs each ISP is blocking.
- Dimmed: no answer yet, or the latest check failed and the status is stale.

Checks every 10 minutes and after the Mac wakes. *Check Now* forces a refresh.

A notification says when blocking starts and when it ends; clicking it opens the
site. *Notify When Blocking Starts or Ends* in the menu switches them off and on.
The last verdict is remembered across launches, so a Mac switched on mid-match
still gets told.

## How the status is decided

The site's headline is computed in the browser from `estado/data.json`, about
5.6 MB of history. The app uses the per-ISP lists in `estado/blocked-*.txt`
instead, a few KB each, and applies the same rule the page's JS uses: blocked
when more than 10 Cloudflare IPs are blocked on more than 2 ISPs, or when both
188.114.96.5 and 188.114.97.5 are blocked. Replayed over two months of history
at 10-minute steps, it agreed with the page on every sample. See
`Sources/BlockStatus.swift`.

## Building

Needs Xcode 16 or later (Swift 6).

```sh
./test.sh             # offline checks of the verdict rule and parsing
./build.sh            # signed build in build/
./build.sh install    # also copy to /Applications and launch
./package.sh 1.0.0    # notarized, stapled DMG in build/
```

Without a Developer ID certificate, `CODESIGN_IDENTITY=- ./build.sh` signs ad hoc.
`swift tools/make-icon.swift` regenerates `Resources/AppIcon.icns`.

## Releasing

CI tests and builds every push and pull request. Pushing a `v*` tag runs
`.github/workflows/release.yml`, which signs and notarizes the DMG and attaches it
to a draft release:

```sh
git tag v1.2.0 && git push origin v1.2.0
```

The release workflow needs these repository secrets:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE` | Developer ID Application certificate with its private key, as base64 of a `.p12` |
| `MACOS_CERTIFICATE_PWD` | Password of that `.p12` (leave unset if it has none) |
| `KEYCHAIN_PASSWORD` | Any random string; protects the runner's temporary keychain |
| `SIGNING_IDENTITY` | e.g. `Developer ID Application: Name (TEAMID)`; optional |
| `TEAM_ID` | Apple developer team ID |
| `APPLE_ID` | Apple ID used for notarization |
| `APP_PASSWORD` | App-specific password for that Apple ID, from appleid.apple.com |
