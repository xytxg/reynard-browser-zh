# Security and stability review — 2026-10-21

Target: `xytxg/reynard-browser-zh` based on `a99a63c3`. Attribution to upstream `minh-ton/reynard-browser` and existing fork authors remains intact.

## Included in review branch

1. **Origin isolation:** persistent and in-memory permission choices now use normalized `scheme://hostname[:port]` instead of only the hostname. Default ports are canonicalized, and IPv6 is bracketed. Unparseable origins fail closed to the configured default action. Tests compare HTTP, HTTPS, and custom ports.
2. **Legacy database safety:** existing hostname-only permission rows cannot reliably be assigned to a single origin. They are copied into `legacy_site_permissions` within a transaction and made inactive. Users may be asked to approve affected website permissions again. The preserved old records remain in the same SQLite database for recovery or debugging; no grant is silently broadened.
3. **Media uploads:** large movies require file-backed NSItemProvider staging. The fallback data representation is limited to images and rejects representations beyond 16 MiB; note that NSItemProvider allocates the data before this size check, so the preferred defense is the initial file-backed API. Large-photo and memory-pressure device tests are still needed.
4. **Extension ZIP preflight:** validate the central directory, expected entry bounds, supported compression methods, path traversal, total expanded size, and root `manifest.json` before forwarding a package to Gecko. This is **not** a WebExtension signature check or complete sandbox audit. Unit tests cover accepted and rejected archives.
5. **Localization workflow:** scheduled/manual upstream comparison produces a report for human review. It never machine-translates strings or pushes changes without inspection.

## Verification checklist

- [x] macOS CI: static/Swift tests and compiler parsing — [PR #15 run](https://github.com/xytxg/reynard-browser-zh/actions/runs/39718816406), success on 2026-10-22.
- [x] Native Gecko/iOS build, standard IPA and TrollStore TIPA — packages and SHA-256 checks verified in the same successful run.
- [x] iOS 27 SDK compatibility — native compatibility job succeeded in the same run (not a substitute for on-device verification).
- [x] Jailbroken IPA successfully **built and packaged** from main in [Nightly #39856424428](https://github.com/xytxg/reynard-browser-zh/actions/runs/39856424428), completed 2026-10-23; not yet device-tested.
- [ ] Jailbroken IPA on-device installation and core browsing functionality
- [ ] On-device: legacy site-permission migration and new grants
- [ ] On-device: camera, microphone, location, autoplay on scheme/port variants
- [ ] On-device: existing AMO add-on installs and malformed ZIP rejection
- [ ] On-device: large video and high-resolution photo upload under memory pressure
- [ ] On-device: no private tabs/history persisted after force quit

## Follow-up engineering work

- **Low-memory tab suspension:** needs device telemetry, Gecko session lifecycle design, and session restoration tests, especially on iOS 13. Do not ship a storage-changing heuristic without those checks.
- **Release authenticity:** detached SHA-256 files from the same release catch accidental corruption but do not prove independent authenticity. Signing requires a protected signing key and an auditable trust-rotation plan; do not embed a private key in the repository.
- **Gecko CI time:** retain pinned toolchain and exact cache keys; first measure cache-hit behavior and expensive compilation steps before changing the release pipeline.

**No claim of a full codebase security audit or device verification is made.** Nightly outputs are test artifacts. A stable release incorporating this change set should wait until essential on-device checks above are satisfied.

## Merge and release status (2026-10-22)

The changes were merged in [PR #15](https://github.com/xytxg/reynard-browser-zh/pull/15) (merge commit `e41236be`). Both main-branch static CI and the PR's standard/TrollStore native builds passed. This does **not** certify on-device behavior or a complete security audit. A stable release incorporating this change set has not been produced as part of PR #15; the on-device items above remain release verification gates.
