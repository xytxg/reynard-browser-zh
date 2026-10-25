# Reynard Browser 简体中文分支说明 · Simplified Chinese Fork Notes

[![Build Release](https://github.com/xytxg/reynard-browser-zh/actions/workflows/build-release.yml/badge.svg)](https://github.com/xytxg/reynard-browser-zh/actions/workflows/build-release.yml)
[![Unsigned IPA checks (main)](https://github.com/xytxg/reynard-browser-zh/actions/workflows/build-unsigned-ipa.yml/badge.svg?branch=main)](https://github.com/xytxg/reynard-browser-zh/actions/workflows/build-unsigned-ipa.yml?query=branch%3Amain)
[![Build Nightly](https://github.com/xytxg/reynard-browser-zh/actions/workflows/build-nightly.yml/badge.svg)](https://github.com/xytxg/reynard-browser-zh/actions/workflows/build-nightly.yml)
[![Latest release](https://img.shields.io/github/v/release/xytxg/reynard-browser-zh?display_name=tag)](https://github.com/xytxg/reynard-browser-zh/releases/latest)
[![License: GPL-3.0](https://img.shields.io/github/license/xytxg/reynard-browser-zh)](../LICENSE)

[中文](#中文) · [English](#english)

---

## 中文

本仓库 [xytxg/reynard-browser-zh](https://github.com/xytxg/reynard-browser-zh) 是
[minh-ton/reynard-browser](https://github.com/minh-ton/reynard-browser)（Reynard，基于 Gecko 的 iOS 浏览器）的
简体中文维护分支。浏览器本身的设计、Gecko 移植和绝大部分代码来自上游作者 Minh Ton；本分支只做汉化、
修复与加固、CI 与发布流程。本文只列出能在本仓库文件或提交中核对的内容；文中提交号均为本仓库 `main` 上的提交。

各徽章含义：**Build Release** 是唯一的正式发布流水线（推送 `v*` 标签触发；`main` 的普通推送会被跳过）；
**Unsigned IPA checks** 是每次推送 `main` 与每个 PR 都会运行的快速检查（本地化、项目安全检查、纯 Swift 测试与语法解析）；
**Build Nightly** 是每日定时构建（无新提交时跳过，不创建 Release）。

### 1. 同步方式与当前基线

本分支与上游**没有共享 Git 历史**。每次同步把上游新提交用 `git format-patch` 导出，再以 `git am -3`
应用到同步分支（`sync/upstream-*`），保留上游作者与提交信息；需要本分支改动的提交在提交信息末尾加
`[reynard-browser-zh]` 注记。同步分支先由 **Build three unsigned IPA variants** 完整构建三个安装包，
通过后经 Pull Request 合并到 `main`，再推送 `vX.Y.Z-zh.N` 标签由 **Build Release** 发布。

当前基线记录在 [`.github/upstream-sync.json`](../.github/upstream-sync.json)：

| 字段 | 值 |
| --- | --- |
| 上游仓库 | `https://github.com/minh-ton/reynard-browser` |
| 已合并到的上游提交 | `e52764023970c20d6a7e4d0c949a78ad1196f91e`（Reynard 0.18.0） |
| 上一次基线 | `6e84bfca9c16b2204dc64c93d2089b5410039897` |
| Gecko | `FIREFOX_158_0_1_RELEASE`，固定提交 `9378fbc58660847fbc02c3486a0ecd6049978e25` |
| 合并日期 | 2026-10-25（同步分支 `sync/upstream-158.0.1`，经 PR #16 合并） |
| 方式 | `6114ed61..25aa6da1`、`25aa6da1..55919a66`、`55919a66..860bb6f4`、`860bb6f4..6e84bfca`、`6e84bfca..e5276402` 五段 `git format-patch` + `git am -3` |

各版本的同步内容见 [`CHANGELOG.md`](../CHANGELOG.md)。

### 2. 汉化

当 iOS 首选语言为简体中文时自动使用中文，英文资源保留。数字由
`node tools/tests/validate-localizations.js` 输出，并与上游同一基线（`e5276402`）的同名字符串表逐键比对得出
（统计时本仓库为同步分支提交 `28989203`；上游表中值为空的 `zh-Hans` 按“缺少中文”计）。校验脚本会检查每个键都有 `zh-Hans` 译文、占位符一致，
以及源码中 `NSLocalizedString` 的键都已收录。

| 范围 | 文件 | 条数 | 其中来自本分支 |
| --- | --- | --- | --- |
| 应用界面 | `browser/Reynard/Resources/Localizable.xcstrings` | 579（全部有中文） | 新增中文 142 条（57 条为上游目录中没有的键，85 条为上游缺少中文的键，其中 51 条是本次同步的数据管理等新文字），并修订上游中文 15 条；其余 422 条沿用上游中文 |
| 附加组件 | `browser/Reynard/Client/Interface/Addons/AddonLocalizable.xcstrings` | 72 | 0（上游自带中文，本分支只做校验） |
| 设置 | `browser/Reynard/Client/Interface/Library/Settings/SettingsLocalizable.xcstrings` | 50 | 9（均为上游目录中没有的键） |
| 网页错误页 | `browser/Reynard/Client/Interface/ContentView/WebContentErrorLocalizable.xcstrings` | 69 | 0（上游 `6c8ca44d`，即本仓库 `de6f0ef1`，随错误页一同带来 Firefox 中文译文；本分支在 `e769b573` 中把该表纳入校验） |
| 系统权限说明与显示名 | 3 个 `zh-Hans.lproj/InfoPlist.strings`（主应用 6 条、OpenIn 扩展 1 条、Helper 扩展 1 条） | 8 | 8（上游没有这些文件） |

四个字符串表合计 770 条，`InfoPlist.strings` 另有 8 条。本分支的中文工作量以“来自本分支”一列为准，
不应把上游已提供的中文计入。

### 3. 修复与加固

以下为本分支在上游之外加入的改动（文件路径相对仓库根目录）。

**更新与下载**

1. 应用内更新只请求本仓库的 Releases API，忽略草稿与预发行版（如手动运行产生的 `build-N`），只接受
   `github.com/xytxg/reynard-browser-zh/releases/download/` 下符合命名规则的安装包；下载前读取 `.sha256`，
   下载后同时核对大小与 SHA-256。
   文件：`browser/Reynard/Client/Startup/BrowserUpdates.swift`、`BrowserUpdatePolicy.swift`、`UpdatePackageVerifier.swift`；
   提交：`0fca4e07`、`23abe1c2`；测试：`Tests/BrowserUpdatePolicyTests.swift`。
2. TrollStore 安装时 `.tipa` 走同一校验流程，校验后再交给 TrollStore；只保留最新的更新包，防止重复点击。
   文件：`browser/Reynard/Client/Interface/Library/Settings/Sections/Updates/UpdatesSettingsSection.swift`；提交：`23abe1c2`。
3. 下载文件名清理（路径分隔符、控制字符、双向文本控制符、UTF-8 长度）、最终路径限制在 Downloads 目录内、
   不可信 `Content-Length` 不再导致进度溢出。
   文件：`browser/Reynard/Client/Stores/DownloadSafety.swift`；提交：`41c84d88`、`e58f70ee`；测试：`Tests/DownloadSafetyTests.swift`。
4. 附加组件安装包限制 128 MiB，并在交给 Gecko 前预检 ZIP 中央目录：条目数、解压后累计大小（≤512 MiB）、压缩方式、路径穿越与根目录 `manifest.json`（不替代 Gecko 的签名与权限检查）。
   文件：`browser/Reynard/Client/Interface/Addons/AddonPackageSafety.swift`；提交：`0fca4e07`、`633c0cf8`；测试：`Tests/AddonPackageSafetyTests.swift`。
5. 外部链接与 `reynard://` 包装链接只允许最终目标为 HTTP/HTTPS。
   文件：`browser/Reynard/Client/Shared/IncomingBrowserURL.swift`；提交：`0fca4e07`；测试：`Tests/IncomingBrowserURLTests.swift`。
6. 上下文菜单图片在内容进程内限制为 20 MiB，避免超大图片耗尽内存。
   文件：`patches/mobile/shared/actors/GeckoViewContentChild.sys.mjs.patch`；提交：`5a8156b8`。

**隐私与稳定性**

7. 私密标签页、选择状态、导航历史和缩略图不写入会话数据库，并清理旧版遗留的私密数据。
   文件：`browser/Reynard/Client/Stores/TabManagementStore.swift`、`NavigationHistoryStore.swift`、
   `browser/Reynard/Client/SessionManagement/SessionManager.swift` 等；提交：`41c84d88`、`b29693c0`、`49fb7ef1`。
8. 清除已打开标签页时一并清除最近关闭的标签与持久化会话/缩略图；`BoundedURLDataLoader` 加锁消除竞态；
   附加组件图标加载失败不再循环刷新；`ZipArchiveReader` 修复悬空指针（该文件已随上游改用 ZIPFoundation 删除，限制见第 13 条）；后台音频保活失败后按指数退避重试。
   提交：`23abe1c2`。
9. 系统代理 PAC 条目缺少 URL 或脚本时按直连处理，不再崩溃。
   文件：`patches/toolkit/system/iosproxy/nsIOSSystemProxySettings.mm.patch`；提交：`20d6979d`。
10. 修复 iOS 27 上 RemoteIO 音频线程自我 join 导致的崩溃。
    文件：`patches/media/libcubeb/src/cubeb_audiounit.cpp.patch`；提交：`4be69e0f`。
11. 上游 `6e84bfca` 审查修复：`selectionView` 私有接口先检查再调用；错误页显示名不再强制转换，崩溃页链接文字缺失时不抛异常；
    HTTPS-Only 例外在调用前校验 URI 与顶层主体，避免 `IPC_FAIL` 强杀内容进程。
    文件：`SelectionActionMenuHostView.swift`、`WebContentErrorView.swift`、`patches/widget/uikit/nsWindow.mm.patch`；提交：`980335dc`。
12. 网站权限按完整来源（`scheme://host[:port]`，默认端口规范化、IPv6 加方括号）保存，旧的仅域名记录备份到 `legacy_site_permissions` 并停用；
    照片/视频上传优先使用文件型表示，图片数据回退限制 16 MiB。
    文件：`browser/Reynard/Client/Stores/SitePermissionStore.swift`、`browser/Reynard/Client/Shared/URLUtils.swift`、`FilePickerStaging.swift` 等；提交：`e50e632c`；测试：`Tests/IncomingBrowserURLTests.swift`。
13. 上游改用 ZIPFoundation 0.9.20 后，`BoundedZipArchive` 在其上限制条目数、单项与累计解压大小，解压超过声明大小立即中止，并校验 CRC-32 与条目路径；
    附加组件图标（XPI）沿用原 `ZipArchiveReader` 的限制（≤128 MiB、≤4096 条目、单项 ≤8 MiB）。
    文件：`browser/Reynard/Client/Utilities/BoundedZipArchive.swift`、`AddonIconLoader.swift`；提交：`d4831742`；测试：`Tests/BoundedZipArchiveTests/`（`d342c6ca`）。
14. 数据导入（上游 `2e504a80`）按不可信输入处理：ZIP 流式解压（单项 ≤512 MiB、累计 ≤1 GiB、可导入文件 ≤64 个）、书签 HTML ≤64 MiB、
    单条历史 JSON 值 ≤16 MiB、插件数据 ≤16 MiB；导入时会自动接受插件安装提示，因此只从 `addons.mozilla.org` 下载安装包。
    文件：`browser/Reynard/Client/UserData/` 下的 `UserDataImporter.swift`、`BookmarkHTMLParser.swift`、`HistoryJSONReader.swift`、`AddonDataFile.swift`、`AddonCatalog.swift`；提交：`e3c210d2`。

所有上述约束由 `tools/tests/validate-project-safety.js` 做静态断言，PR 与 `main` 推送时运行。

### 4. 与上游的差异

| 方面 | 本分支的做法 | 文件 / 提交 |
| --- | --- | --- |
| iOS 13 兼容 | 发布包最低系统 iOS 13.0。额外的运行时可用性补丁：`NativeLayerCA.mm` 的 iOS 14/15 接口加 `@available` 保护；Firefox 156 起使用的 iOS 14 HDR 色彩空间常量加保护；Gecko 链接时显式加入 `libclang_rt.ios.a`，使可用性检查在新 SDK 下正常工作；私有类 `_UIContextMenuStyle` 改为弱链接（`API_AVAILABLE(ios(14.0))`）。 | `patches/zz-compat/iOS13RuntimeAvailability.patch`（`46a3d127`、`44387bc9`、`e967e530`）；`tools/development/build-gecko.sh`（`0fca4e07`）；`browser/Reynard/Bridging/UIKit+Private.h`（`980335dc`） |
| iOS 27 SDK 检查 | 发布包保持 iOS 13 目标，另用 Xcode 27 单独编译并检查 iOS 27 SDK 加载命令；打包时把无扩展名的 `XUL` 规范化为 `XUL.dylib`。 | `06d0c4ed`、`74e4a986`；`tools/release/create-unsigned-ipa.sh`、`tools/release/verify-unsigned-ipa.py` |
| AppleVT（VideoToolbox） | 把 iOS 17 解码器键与 iOS 17.4 编码器键的引用放进对应的运行时可用性分支，不再在 iOS 13 上引用。 | `patches/dom/media/platforms/apple/AppleVTDecoder.cpp.patch`、`AppleVTEncoder.cpp.patch`（`bba67053`） |
| JIT 开发者磁盘映像（DDI） | 上游从 `github.com/doronz88/DeveloperDiskImage/raw/refs/heads/main` 下载且不校验哈希；本分支固定到 `doronz88/DeveloperDiskImage` 修订 `6eae353ae694bda1c421d4a3eee5459ae59c99a1`，只允许 `raw.githubusercontent.com`，Cryptex（iOS 26.4+，5 个文件）与 Personalized（iOS 26.4 以下，3 个文件）均校验大小与 SHA-256，失败即清理。 | `browser/Reynard/JIT/RPPairing/DDIManager.swift`（`e967e530`、`23abe1c2`、`3b69b2eb`） |
| ZIP 读取 | 上游用 ZIPFoundation（`exactVersion` 0.9.20）读取附加组件图标与导入文件；本分支所有不可信 ZIP 都经 `BoundedZipArchive` 读取（见第 3 节第 13、14 条），项目安全检查断言 ZIPFoundation 固定版本。上游从 `Reynard.xcconfig` 删除 `SWIFT_OBJC_BRIDGING_HEADER` 不影响本分支：6 个 Swift 目标配置在工程文件中仍各自设置桥接头（含 `UIKit+Private.h`），并由安全检查断言。 | `BoundedZipArchive.swift`（`d4831742`、`e3c210d2`）、`tools/tests/validate-project-safety.js` |
| 越狱包依赖 | 打包时下载的上游 0.10.0 IPA 及从中取出的 `libswift_Concurrency.dylib` 均固定 SHA-256。 | `tools/release/create-ipa.sh`（`3a9aa1c2`） |
| 更新 / 下载 | 见第 3 节 1–6 条。 | 同上 |
| CI：Gecko 分段续编 | 冷编译的 Gecko 每种变体最多 4 段（`p1`–`p4`）；每段在作业开始 320 分钟后停止，把整个对象目录、`~/.mozbuild` 引导工具链与 sccache 上传为 artifact，下一段在相同路径与相同 Rust/Xcode/sccache 版本下续编，续编前校验 configure 记录的工具路径。 | `.github/workflows/build-gecko.yml`、`tools/development/build-gecko-pass.sh`（`a101aa5a`、`5125b199`、`3b92b753`、`6f968111`） |
| CI：三种 IPA 变体 | 与上游相同的三个包：`Reynard.ipa`、`Reynard-TrollStore.tipa`（共用 standard Gecko）与 `Reynard-Jailbroken.ipa`（关闭 jemalloc 的独立 Gecko）。全部未签名，打包后检查架构、残留签名、构建号、中文资源与 ZIP 完整性。 | `.github/workflows/build.yml`、`build-three-ipa.yml`、`tools/release/verify-unsigned-ipa.py` |
| CI：发布 | `build-release.yml` 是唯一的正式发布流水线：只响应 `v*` 标签、`main` 上带 `[release]` 的提交或手动重建；构建前校验标签格式、版本号与 `CURRENT_VERSION` 一致、已存在的标签必须指向同一提交；发布三个包及各自 `.sha256`。上游的官方 AltStore 源（`.github/source.json`）及其更新工作流（`update_source.yml`、`update_source.py`）已删除。 | `.github/workflows/build-release.yml`（`3a9aa1c2`） |
| 版本号 | 标签格式 `vX.Y.Z-zh.N`：`X.Y.Z` 必须等于 `browser/Configuration/Reynard.xcconfig` 的 `CURRENT_VERSION`，同一上游版本重新发布时 `N` 递增（如 `v0.18.0-zh.1` → `v0.18.0-zh.2`）。安装包 `CFBundleVersion` 为发布运行号，Release 正文带 `<!-- reynard-update-build: N -->`，应用内更新据此比较同版本的新旧。 | `build-release.yml`、`BrowserUpdatePolicy.swift`、`tools/tests/validate-project-safety.js`（`980335dc`） |
| 链接 | 应用内更新、关于页、错误页崩溃报告、性能建议页的 TrollStore 下载均指向本仓库；手动启用 JIT 的教程仍指向上游 Wiki。 | `BrowserUpdates.swift`、`BrowserUpdatePolicy.swift`、`AboutSettingsSection.swift`、`WebContentErrorView.swift`、`PerformanceRecommendationViewController.swift` |

### 5. 安装包与校验

正式安装包在 [Releases](https://github.com/xytxg/reynard-browser-zh/releases) 发布，均为**未签名**，
需自行用 AltStore、SideStore、TrollStore 等方式签名安装。每个安装包附带 `.sha256` 文件，可用
`shasum -a 256 -c Reynard.ipa.sha256` 校验。能否安装、能否启用 JIT 取决于 iOS 版本与签名方式；
构建成功不等于已在真机上验证。

### 6. 许可证与致谢

- 本仓库沿用上游的 [GPL-3.0](../LICENSE) 许可证；Firefox / Gecko 相关代码适用 [MPL-2.0](../LICENSE.firefox)。
- 感谢上游作者 [Minh Ton](https://github.com/minh-ton) 与 [Reynard](https://github.com/minh-ton/reynard-browser) 的所有贡献者，
  以及 Mozilla Firefox / Gecko 项目。附加组件与错误页中文译文来自上游随附的 Firefox 本地化。

---

## English

[xytxg/reynard-browser-zh](https://github.com/xytxg/reynard-browser-zh) is the Simplified Chinese maintenance fork of
[minh-ton/reynard-browser](https://github.com/minh-ton/reynard-browser) (Reynard, a Gecko-based browser for iOS).
The browser's design, the Gecko port and most of the code come from the upstream author, Minh Ton; this fork adds
localization, fixes and hardening, and its own CI and release pipeline. Everything below can be checked against a file
or a commit in this repository; commit hashes refer to this repository's `main`.

What the badges mean: **Build Release** is the only formal release pipeline (it runs for pushed `v*` tags; ordinary
pushes to `main` are skipped); **Unsigned IPA checks** is the quick check run on every push to `main` and every pull
request (localization, project safety, pure Swift tests and syntax parsing); **Build Nightly** is the scheduled daily
build (skipped when there are no new commits; it never creates a release).

### 1. How upstream is synced, and the current baseline

The fork **does not share Git history** with upstream. Each sync exports the new upstream commits with
`git format-patch` and applies them with `git am -3` on a sync branch (`sync/upstream-*`), keeping upstream authorship
and messages; commits that needed fork changes carry a `[reynard-browser-zh]` note at the end of the message. The sync
branch is first built in full by **Build three unsigned IPA variants**, then merged into `main` through a pull request,
and a `vX.Y.Z-zh.N` tag is pushed for **Build Release** to publish.

The current baseline is recorded in [`.github/upstream-sync.json`](../.github/upstream-sync.json):

| Field | Value |
| --- | --- |
| Upstream repository | `https://github.com/minh-ton/reynard-browser` |
| Upstream commit merged up to | `e52764023970c20d6a7e4d0c949a78ad1196f91e` (Reynard 0.18.0) |
| Previous baseline | `6e84bfca9c16b2204dc64c93d2089b5410039897` |
| Gecko | `FIREFOX_158_0_1_RELEASE`, pinned commit `9378fbc58660847fbc02c3486a0ecd6049978e25` |
| Integration date | 2026-10-25 (sync branch `sync/upstream-158.0.1`, merged in PR #16) |
| Method | `git format-patch` + `git am -3` in five ranges: `6114ed61..25aa6da1`, `25aa6da1..55919a66`, `55919a66..860bb6f4`, `860bb6f4..6e84bfca`, `6e84bfca..e5276402` |

What each sync brought in is listed in [`CHANGELOG.md`](../CHANGELOG.md) (in Chinese).

### 2. Localization

The app switches to Simplified Chinese when it is the preferred iOS language; English resources are kept. The numbers
come from `node tools/tests/validate-localizations.js` and from a key-by-key comparison with the same string tables at the
upstream baseline (`e5276402`), counted on this repository's sync branch at `28989203` (an empty upstream `zh-Hans` value counts as missing). The script checks that every key has a
`zh-Hans` value with matching placeholders and that every `NSLocalizedString` key used in the source is in a table.

| Scope | File | Entries | Contributed by this fork |
| --- | --- | --- | --- |
| App UI | `browser/Reynard/Resources/Localizable.xcstrings` | 579 (all translated) | 142 new Chinese entries (57 keys not in the upstream table, 85 upstream keys without Chinese, 51 of them the new data-management strings of this sync) and 15 revised upstream translations; the other 422 use upstream's Chinese |
| Add-ons | `browser/Reynard/Client/Interface/Addons/AddonLocalizable.xcstrings` | 72 | 0 (upstream ships Chinese; the fork only validates it) |
| Settings | `browser/Reynard/Client/Interface/Library/Settings/SettingsLocalizable.xcstrings` | 50 | 9 (all keys not in the upstream table) |
| Web error pages | `browser/Reynard/Client/Interface/ContentView/WebContentErrorLocalizable.xcstrings` | 69 | 0 (upstream `6c8ca44d`, `de6f0ef1` in this repository, brought Firefox's Chinese with the error pages; the fork added the table to validation in `e769b573`) |
| Permission prompts and display names | three `zh-Hans.lproj/InfoPlist.strings` (app 6, OpenIn extension 1, Helper extension 1) | 8 | 8 (upstream has no such files) |

The four string tables hold 770 entries, plus 8 in `InfoPlist.strings`. The fork's own translation work is the
"Contributed by this fork" column; Chinese already provided upstream should not be counted as the fork's.

### 3. Fixes and hardening

Changes this fork adds on top of upstream (paths are relative to the repository root).

**Updates and downloads**

1. The in-app updater only queries this repository's Releases API, ignores drafts and prereleases (such as manual
   `build-N` runs), and only accepts correctly named packages under
   `github.com/xytxg/reynard-browser-zh/releases/download/`; it reads the `.sha256` before downloading and checks both size
   and SHA-256 afterwards.
   Files: `browser/Reynard/Client/Startup/BrowserUpdates.swift`, `BrowserUpdatePolicy.swift`, `UpdatePackageVerifier.swift`;
   commits `0fca4e07`, `23abe1c2`; tests: `Tests/BrowserUpdatePolicyTests.swift`.
2. TrollStore installs download the `.tipa` through the same verified flow before handing it to TrollStore; only the newest
   package is kept and repeated taps are rejected.
   File: `browser/Reynard/Client/Interface/Library/Settings/Sections/Updates/UpdatesSettingsSection.swift`; commit `23abe1c2`.
3. Download file names are sanitized (path separators, control and bidi characters, UTF-8 length), the final path is kept
   inside Downloads, and an untrusted `Content-Length` can no longer overflow progress.
   File: `browser/Reynard/Client/Stores/DownloadSafety.swift`; commits `41c84d88`, `e58f70ee`; tests: `Tests/DownloadSafetyTests.swift`.
4. Add-on packages are limited to 128 MiB, and their ZIP central directory is checked before Gecko sees them: entry count,
   total expanded size (≤512 MiB), compression methods, path traversal and a root `manifest.json` (this does not replace
   Gecko's signature and permission checks).
   File: `browser/Reynard/Client/Interface/Addons/AddonPackageSafety.swift`; commits `0fca4e07`, `633c0cf8`; tests: `Tests/AddonPackageSafetyTests.swift`.
5. External links and `reynard://` wrapper links must resolve to HTTP/HTTPS.
   File: `browser/Reynard/Client/Shared/IncomingBrowserURL.swift`; commit `0fca4e07`; tests: `Tests/IncomingBrowserURLTests.swift`.
6. Context-menu image fetches are capped at 20 MiB in the content process so a huge image cannot exhaust memory.
   File: `patches/mobile/shared/actors/GeckoViewContentChild.sys.mjs.patch`; commit `5a8156b8`.

**Privacy and stability**

7. Private tabs, selection state, navigation history and thumbnails are not written to the session database, and private
   data left by older versions is removed.
   Files: `browser/Reynard/Client/Stores/TabManagementStore.swift`, `NavigationHistoryStore.swift`,
   `browser/Reynard/Client/SessionManagement/SessionManager.swift` and others; commits `41c84d88`, `b29693c0`, `49fb7ef1`.
8. Clearing open tabs also clears recently closed tabs and persisted sessions/thumbnails; `BoundedURLDataLoader` is locked
   against a cancel/finish race; failed add-on icon loads no longer cause a refresh loop; a dangling pointer in
   `ZipArchiveReader` is fixed (the file was removed when upstream moved to ZIPFoundation; see item 13); background-audio keep-alive retries with exponential backoff. Commit `23abe1c2`.
9. PAC entries without a URL or script resolve to no proxy instead of crashing.
   File: `patches/toolkit/system/iosproxy/nsIOSSystemProxySettings.mm.patch`; commit `20d6979d`.
10. Fixes a RemoteIO audio thread self-join crash on iOS 27.
    File: `patches/media/libcubeb/src/cubeb_audiounit.cpp.patch`; commit `4be69e0f`.
11. Review fixes for upstream `6e84bfca`: the private `selectionView` call is checked first; the error page no longer
    force-casts the display name or throws when the crash-page link text is missing; the HTTPS-Only exception checks the URI
    and top-level principal first, so `IPC_FAIL` cannot kill the content process.
    Files: `SelectionActionMenuHostView.swift`, `WebContentErrorView.swift`, `patches/widget/uikit/nsWindow.mm.patch`; commit `980335dc`.
12. Site permissions are stored per full origin (`scheme://host[:port]`, default ports canonicalized, IPv6 bracketed); old
    host-only rows are copied to `legacy_site_permissions` and deactivated. Photo/video uploads prefer file-backed
    representations, and the image data fallback is capped at 16 MiB.
    Files: `browser/Reynard/Client/Stores/SitePermissionStore.swift`, `browser/Reynard/Client/Shared/URLUtils.swift`, `FilePickerStaging.swift` and others; commit `e50e632c`; tests: `Tests/IncomingBrowserURLTests.swift`.
13. Upstream switched to ZIPFoundation 0.9.20; `BoundedZipArchive` adds entry-count, per-entry and total expanded-size limits on
    top of it, stops a deflate stream that grows beyond its declared size, and checks CRC-32 and entry paths. Add-on icons
    (XPI) keep the former `ZipArchiveReader` limits (≤128 MiB, ≤4096 entries, ≤8 MiB per entry).
    Files: `browser/Reynard/Client/Utilities/BoundedZipArchive.swift`, `AddonIconLoader.swift`; commit `d4831742`; tests: `Tests/BoundedZipArchiveTests/` (`d342c6ca`).
14. Data import (upstream `2e504a80`) treats files as untrusted: ZIP entries are streamed (≤512 MiB each, ≤1 GiB total, ≤64
    importable files), bookmark HTML ≤64 MiB, a single history JSON value ≤16 MiB, add-on data ≤16 MiB; because the import
    accepts the add-on install prompt automatically, packages are only downloaded from `addons.mozilla.org`.
    Files under `browser/Reynard/Client/UserData/`: `UserDataImporter.swift`, `BookmarkHTMLParser.swift`, `HistoryJSONReader.swift`, `AddonDataFile.swift`, `AddonCatalog.swift`; commit `e3c210d2`.

These constraints are asserted statically by `tools/tests/validate-project-safety.js`, which runs on pull requests and
pushes to `main`.

### 4. Differences from upstream

| Area | What this fork does | Files / commits |
| --- | --- | --- |
| iOS 13 compatibility | Shipping packages target iOS 13.0. Extra runtime-availability patches: `@available` guards for iOS 14/15 APIs in `NativeLayerCA.mm`; a guard for the iOS 14 HDR color-space constants used since Firefox 156; `libclang_rt.ios.a` linked explicitly into Gecko so availability checks work with newer SDKs; the private `_UIContextMenuStyle` class weak-linked (`API_AVAILABLE(ios(14.0))`). | `patches/zz-compat/iOS13RuntimeAvailability.patch` (`46a3d127`, `44387bc9`, `e967e530`); `tools/development/build-gecko.sh` (`0fca4e07`); `browser/Reynard/Bridging/UIKit+Private.h` (`980335dc`) |
| iOS 27 SDK checks | Packages keep the iOS 13 target; a separate Xcode 27 build checks the iOS 27 SDK load commands; packaging renames the extensionless `XUL` to `XUL.dylib`. | `06d0c4ed`, `74e4a986`; `tools/release/create-unsigned-ipa.sh`, `tools/release/verify-unsigned-ipa.py` |
| AppleVT (VideoToolbox) | References to the iOS 17 decoder key and iOS 17.4 encoder keys are moved inside their runtime-availability branches, so iOS 13 never touches them. | `patches/dom/media/platforms/apple/AppleVTDecoder.cpp.patch`, `AppleVTEncoder.cpp.patch` (`bba67053`) |
| JIT Developer Disk Image (DDI) | Upstream downloads from `github.com/doronz88/DeveloperDiskImage/raw/refs/heads/main` without hash checks; this fork pins `doronz88/DeveloperDiskImage` at revision `6eae353ae694bda1c421d4a3eee5459ae59c99a1`, allows only `raw.githubusercontent.com`, and verifies size and SHA-256 of both the Cryptex set (iOS 26.4+, 5 files) and the Personalized set (below iOS 26.4, 3 files), deleting them on failure. | `browser/Reynard/JIT/RPPairing/DDIManager.swift` (`e967e530`, `23abe1c2`, `3b69b2eb`) |
| ZIP reading | Upstream reads add-on icons and imported files with ZIPFoundation (`exactVersion` 0.9.20); in this fork every untrusted ZIP goes through `BoundedZipArchive` (items 13 and 14 in section 3), and the project safety check asserts the pinned version. Upstream removing `SWIFT_OBJC_BRIDGING_HEADER` from `Reynard.xcconfig` does not affect the fork: the 6 Swift target configurations still set the bridging header (which imports `UIKit+Private.h`) in the project file, which the safety check asserts. | `BoundedZipArchive.swift` (`d4831742`, `e3c210d2`), `tools/tests/validate-project-safety.js` |
| Jailbroken package dependency | The upstream 0.10.0 IPA downloaded at packaging time and the `libswift_Concurrency.dylib` extracted from it are pinned by SHA-256. | `tools/release/create-ipa.sh` (`3a9aa1c2`) |
| Updates / downloads | See items 1–6 in section 3. | As above |
| CI: multi-pass Gecko | A cold Gecko build runs in up to 4 passes per flavor (`p1`–`p4`). Each pass stops 320 minutes after its job starts and uploads the whole object directory, the `~/.mozbuild` bootstrap toolchain and sccache as an artifact; the next pass resumes at the same paths with the same Rust/Xcode/sccache versions and first verifies the tool paths recorded by configure. | `.github/workflows/build-gecko.yml`, `tools/development/build-gecko-pass.sh` (`a101aa5a`, `5125b199`, `3b92b753`, `6f968111`) |
| CI: three IPA variants | The same three packages as upstream: `Reynard.ipa` and `Reynard-TrollStore.tipa` (sharing the standard Gecko) and `Reynard-Jailbroken.ipa` (a separate Gecko with jemalloc disabled). All are unsigned; packaging checks architecture, leftover signatures, build numbers, Chinese resources and ZIP integrity. | `.github/workflows/build.yml`, `build-three-ipa.yml`, `tools/release/verify-unsigned-ipa.py` |
| CI: releases | `build-release.yml` is the only formal release pipeline: it runs for `v*` tags, `[release]` commits on `main`, or manual rebuilds; before building it checks the tag format, that the version equals `CURRENT_VERSION`, and that an existing tag points at the same commit; it publishes the three packages and a `.sha256` for each. Upstream's official AltStore source (`.github/source.json`) and its update workflow (`update_source.yml`, `update_source.py`) are removed. | `.github/workflows/build-release.yml` (`3a9aa1c2`) |
| Version numbers | Tags are `vX.Y.Z-zh.N`: `X.Y.Z` must equal `CURRENT_VERSION` in `browser/Configuration/Reynard.xcconfig`, and `N` increases when the same upstream version is released again (e.g. `v0.18.0-zh.1` → `v0.18.0-zh.2`). `CFBundleVersion` is the release run number, and the release notes carry `<!-- reynard-update-build: N -->`, which the updater uses to order releases of the same version. | `build-release.yml`, `BrowserUpdatePolicy.swift`, `tools/tests/validate-project-safety.js` (`980335dc`) |
| Links | The updater, the About page, the error page's crash report link and the TrollStore download on the performance recommendation page point to this repository; the manual JIT guide still points to the upstream wiki. | `BrowserUpdates.swift`, `BrowserUpdatePolicy.swift`, `AboutSettingsSection.swift`, `WebContentErrorView.swift`, `PerformanceRecommendationViewController.swift` |

### 5. Packages and verification

Formal packages are published on [Releases](https://github.com/xytxg/reynard-browser-zh/releases). They are **unsigned** and
must be signed with AltStore, SideStore, TrollStore or a similar method. Each package has a `.sha256` file; verify with
`shasum -a 256 -c Reynard.ipa.sha256`. Whether a package installs and whether JIT is available depend on the iOS version and
signing method; a successful build is not the same as on-device verification.

### 6. License and credits

- This repository keeps upstream's [GPL-3.0](../LICENSE) license; Firefox / Gecko code is under [MPL-2.0](../LICENSE.firefox).
- Thanks to the upstream author [Minh Ton](https://github.com/minh-ton) and all contributors to
  [Reynard](https://github.com/minh-ton/reynard-browser), and to the Mozilla Firefox / Gecko project. The Chinese strings for
  add-ons and error pages come from the Firefox localization shipped upstream.
