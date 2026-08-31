# Reynard Browser 简体中文说明

Reynard 是面向 iOS 15 及更高版本的 Gecko 浏览器。本分支保留原有 Gecko、JIT、应用扩展、
标签页和侧载架构，并加入简体中文（`zh-Hans`）、下载安全修复、私密会话保护和源码构建
未签名 IPA 的 GitHub Actions 流程。

已成功的 `main`、手动和 `v*` 标签构建会由 `github-actions[bot]` 自动发布到本仓库的
[Releases](https://github.com/xytxg/reynard-browser-zh/releases) 页面，并附带 IPA 与 SHA-256
校验文件。普通分支和 Pull Request 不具备发布权限。

## 上游同步状态

当前维护代码已合并原作者仓库截至 `0bfe06fda73842ff8f01a7e371854ee89f5e045a`
（2026-08-30）的 0.11.0 更新，Gecko 为 `FIREFOX_154_0_1_RELEASE`，固定源码提交为
`9cd094dbc3eac5df87a24e7a871e52880cb8cd42`。在上游代码基础上保留中文分支的下载安全、
私密会话保护、iOS 15 最低版本、iOS 27 SDK 编译验证与未签名 IPA 构建。

本轮包括下载暂停/继续、关闭来源标签后下载卡住、键盘焦点/Shift 键、底部工具栏、
崩溃后工具栏恢复、合成器布局崩溃及多进程扩展清理。另修复下载重启恢复、清理任务保护、
扩展下载临时路径、下载错误提示漏译和文件夹上传提示无法命中翻译的问题。

具体基线见 `.github/upstream-sync.json`，改动和验证记录见
`docs/UPDATE_REPORT_2026-08-28.md`。文档中的“已合并代码”不代表 IPA 已构建成功；
请以对应 GitHub Actions 运行结果和真实产物为准。

## 简体中文

当 iOS 的首选语言为“简体中文”时，Reynard 会自动使用中文；英文资源仍然保留。
主应用、OpenIn 扩展、Reynard Helper 扩展和附加组件界面都包含中文资源。可以运行
`tools/tests/run-static-tests.sh` 检查主界面、附加组件和设置的缺失翻译、源码中的本地化键及格式化占位符。

## 未签名 IPA 是什么

GitHub Actions 产物没有 Apple 开发证书、分发证书或 Provisioning Profile，不能直接安装。
安装前必须使用兼容方式重新签名，例如 AltStore、SideStore、个人开发证书，或在兼容系统上
使用 TrollStore。重新签名和安装时必须保留以下扩展：

- `PlugIns/OpenIn.appex`
- `PlugIns/Reynard Helper.appex`

扩展丢失会导致打开文件、Gecko 进程或其他浏览器能力失效。LiveContainer 受其进程和应用扩展
模型限制，不属于受支持方案；使用分发证书重签也存在 entitlement 和扩展兼容限制。

## 默认浏览器与外部链接

Reynard 已注册 `http`、`https` URL Scheme，并同时处理冷启动和运行中的外部链接。收到链接后会
直接在普通/私密浏览模式当前所选模式中打开网页；`reynard://` 包装链接只允许最终目标为有效的
HTTP/HTTPS 地址，不允许借此打开本地文件或脚本协议。应用内可进入
**设置 → 通用 → 默认浏览器**：iOS 18.3 及以上会直接打开“默认 App”设置，iOS 15–18.2
会打开 Reynard 的应用设置。

能否出现在系统“浏览器 App”列表，最终取决于安装签名中是否真的含有 Apple 管理的
`com.apple.developer.web-browser` 权限：

- 源码的标准 entitlement 已声明该权限，使用获 Apple 批准且包含该权限的 Provisioning Profile
  签名后可供系统识别；申请和要求见 Apple 的
  [默认浏览器准备说明](https://developer.apple.com/documentation/xcode/preparing-your-app-to-be-the-default-browser)与
  [entitlement 参考](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.web-browser)。
- 本仓库发布的未签名 IPA 没有任何签名 entitlement；重新签名时必须由签名环境注入获准权限。
- AltStore、SideStore 或普通个人开发证书不能自行创造 Apple 管理权限。此类签名仍可通过分享菜单、
  `reynard://` 或其他明确交付方式打开链接，但 Reynard 不会出现在系统默认浏览器列表中。
- 使用 TrollStore/越狱签名时，可通过 `Reynard.private.entitlements` 保留相应声明；系统是否接受仍取决于
  iOS 版本和安装方式，不能仅靠修改 `Info.plist` 保证。

若设置行显示“需要兼容签名”，表示当前实际安装的 App 签名里没有该权限；这不是界面开关能够绕过的限制。

## 检测和下载更新

进入 **设置 → App 更新 → 检测更新**，Reynard 会请求本仓库公开的 GitHub Releases API，
同时识别正式版和更新的 `main` 构建。更新器只接受
`github.com/xytxg/reynard-browser-zh/releases/download/` 下、名称符合 Reynard 规则的 IPA；下载前
读取 Release 附带的 `.sha256`，下载后同时核对文件大小和 SHA-256，通过后才会打开共享菜单。

普通 iOS App 无权静默安装或覆盖自身，未签名 IPA 也不能直接执行。因此 AltStore、SideStore、
个人证书等安装方式会在校验完成后打开共享菜单，需要手动选择原签名工具重新签名安装。若当前通过
TrollStore 安装，且对应 Release 另附 `.tipa`，更新按钮会优先唤起 TrollStore；只有未签名 IPA 时
仍会走“校验后分享”。这项限制来自 iOS 代码签名模型，不能通过浏览器代码绕过。

## 在 GitHub Actions 从源码构建

1. 打开本仓库的 **Actions** 页面。
2. 选择 **Build unsigned IPA from source**。
3. 点击 **Run workflow**。
4. 工作流成功后，可在 **Releases** 下载 bot 自动发布的 IPA，也可在该次运行的
   **Artifacts** 下载 `Reynard-source-unsigned-<运行编号>`。

工作流会按顺序执行：

1. 校验中文资源并运行不依赖 Gecko 的纯 Swift 下载安全测试。
2. 根据 `engine/release.txt` 下载指定 Firefox 源码并应用 `patches/`。
3. 从源码构建 idevice 静态库和 iOS Gecko。
4. 使用真实 `Reynard` Scheme 构建 `Reynard.app`，并设置
   `CODE_SIGNING_ALLOWED=NO`、`CODE_SIGNING_REQUIRED=NO` 和
   `AD_HOC_CODE_SIGNING_ALLOWED=NO`。
5. 检查主程序、`Info.plist`、两个应用扩展、GeckoView、`XUL.dylib` 和 Frameworks 后，生成标准
   `Payload/Reynard.app` IPA。

打包会检查 Mach-O 的 arm64 架构、残留签名、主应用与扩展构建号、中文资源和 ZIP 完整性。
`CFBundleVersion` 使用数字构建号，源码短 SHA 保留在产物文件名和构建日志中。正式构建最低
系统版本固定为 iOS 15.0，并另用 Xcode 27 / iOS 27 SDK 编译和检查 Mach-O 链接版本。

IPA 文件名格式为 `Reynard-<版本>-<提交短 SHA>-unsigned.ipa`。推送到 `main` 或手动运行时，
成功产物通常创建 `build-<运行编号>` 预发行版；推送 `v*` 标签时创建同名正式 Release。
维护者明确标记 `[formal release]` 的主分支提交也会在真实 IPA 校验通过后发布中文版正式版。
发行说明会明确标记未签名限制。Pull Request 默认只运行快速检查；需要按需验证完整包时，可在
PR 标题中加入 `[build ipa]`，但 PR 构建不会创建发行版，以防未合并代码取得发布权限。
旧的上游 AltStore 元数据刷新工作流只允许手动运行，不会再被每个中文构建发行版触发，也不会
干扰 IPA 的自动发布状态。

iOS 27 会在应用代码运行前严格校验 XUL 动态库签名。打包脚本会把上游无扩展名的 `XUL`
规范化为 `XUL.dylib` 并重写加载路径，方便 SideStore、AltStore、E-Sign 等工具递归重签名。
IPA 本身仍然未签名；安装工具必须使用同一证书重新签署主程序、扩展、GeckoView 和所有 dylib。

## 本地源码构建

需要 macOS、Xcode、Python 3、Rust/Cargo、`cbindgen`、支持
`wasm32-wasi` 的 LLVM/Clang 与 LLD（Apple Clang 不包含该目标时可使用 Homebrew LLVM/LLD）、
以及足够的磁盘空间。构建按上游成功配置使用 LLVM/LLD、Rust stable 和 Python 3.12；
Gecko 的 `--enable-bootstrap` 自动选择匹配的 Mozilla/WASI 工具链，不再手工混用 LLVM 版本。
克隆仓库后运行：

```bash
git clone --recursive https://github.com/xytxg/reynard-browser-zh.git
cd reynard-browser-zh
./tools/development/update-gecko.sh
./tools/development/apply-patches.sh
./tools/development/build-idevice.sh
./tools/development/build-gecko.sh
./tools/release/build-unsigned-app.sh
version="$(awk -F ' = ' '/^CURRENT_VERSION = / { print $2; exit }' browser/Configuration/Reynard.xcconfig)"
sha="$(git rev-parse --short=7 HEAD)"
./tools/release/create-unsigned-ipa.sh dist/Reynard.app "dist/Reynard-${version}-${sha}-unsigned.ipa"
```

正常的开发签名构建仍可直接在 Xcode 中打开 `browser/Reynard.xcodeproj`，选择 `Reynard`
Scheme。源码构建脚本不会读取或上传 Apple ID、证书、Provisioning Profile 或密码。

## JIT 与安装方式

Gecko 的正常性能依赖当前安装环境允许 JIT。TrollStore 和部分越狱环境可提供更稳定的 JIT；
AltStore、SideStore 或个人证书安装是否能启用 JIT，取决于 iOS 版本、配对服务和当前权限。
“已经安装”不等于“JIT 已启用”，请以应用内 JIT 状态为准。

## 下载与隐私改进

- 按日期清理只删除命中日期范围的已完成下载，不会清空全部记录或删除进行中的任务。
- 服务器文件名会移除路径分隔符、控制字符和双向文本控制符，限制 UTF-8 长度，并验证最终
  路径仍在 Downloads 目录中。
- 下载失败会显示网络、HTTP 响应、空间不足、权限或文件保存错误；普通 URLSession 下载可以重试。
- 普通和 Gecko 捕获下载可在当前进程存活期间暂停/继续；重启后的中断任务标为失败，支持的任务可重试。
- 仅删除已完成记录拥有的文件；清理记录不删除正在下载、暂停的任务或用户手动放入目录的文件。
- 下载确认会显示文件名、来源域名、大小和 MIME 类型；未知大小会明确显示。
- 下载进度界面合并为约 350 毫秒一次刷新，完成和失败仍立即更新。
- favicon 请求会合并同一站点的并发任务、拒绝非 Web URL，并限制压缩图片解码后的最大尺寸。
- 私密标签页、选择状态、导航历史和缩略图不写入会话数据库；升级后会清理旧版遗留的私密
  标签数据。
- “设置 → 主页 → 恢复上次浏览”关闭后会移除已保存的普通标签和导航状态。

## 当前限制

- Gecko 捕获下载使用上游新的暂停/继续接口，不是持久化 Resume Data；应用退出后的 Gecko 下载仍需
  网页重新发起。扩展下载仅在底层提供控制接口时显示暂停操作。
- 当前普通下载仍使用前台 `URLSession`。在没有验证任务重关联、目标路径恢复和 Gecko 捕获
  兼容性前，不会声称支持系统终止后的后台续传。
- GitHub 托管 macOS Runner 首次构建 Gecko 会很慢，并可能因磁盘、六小时任务上限、上游下载
  或缓存大小失败。工作流会保留实际日志，不会生成空 IPA；编译使用 sccache，成功的 Gecko 分发文件按源码和工具链精确缓存。若持续超过托管 Runner 限制，建议
  使用至少 100 GB 可用空间的 self-hosted macOS Runner。
- Gecko 对部分网站权限或 iOS 能力没有可用接口时，Reynard 不会提供无效开关。

## 常见构建失败

- Firefox 标签下载失败：检查 `engine/release.txt` 和上游网络状态。
- 补丁冲突：查看 `dist/logs/apply-patches.log`；CI 会直接失败，不会等待交互输入。
- Gecko 构建超时或磁盘不足：查看 `disk-*.log`，清理 DerivedData/对象缓存或改用 self-hosted Runner。
- Xcode 构建找不到 XUL/GeckoView：确认 `build-gecko.sh` 已成功完成且对象目录没有混用不同 Xcode。
- IPA 校验失败：检查 `Reynard.app/PlugIns`、`Frameworks` 和签名元数据；脚本不会上传不完整或
  带签名的包。
