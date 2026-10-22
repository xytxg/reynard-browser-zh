#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "../..");

function read(relativePath) {
  return fs.readFileSync(path.join(root, relativePath), "utf8");
}

function requireText(value, fragment, message) {
  if (!value.includes(fragment)) {
    throw new Error(message);
  }
}

function rejectText(value, fragment, message) {
  if (value.includes(fragment)) {
    throw new Error(message);
  }
}

const workflow = read(".github/workflows/build-unsigned-ipa.yml");
if ((workflow.match(/- name: Require a real IPA artifact/g) ?? []).length !== 1) {
  throw new Error("PR pipeline does not verify a real IPA pair");
}
requireText(workflow, "uses: ./.github/workflows/build.yml", "PR builds bypass resumable Gecko pipeline");
requireText(workflow, 'checkout_ref: ${{ github.event.pull_request.head.sha || github.sha }}', "PR builds must check out the reviewed commit");
requireText(workflow, "build_normal_ipa: true", "PR build omits normal IPA");
requireText(workflow, "build_trollstore_tipa: true", "PR build omits TrollStore TIPA");
requireText(workflow, "build_jailbroken_ipa: false", "PR build wastes resources on a second Gecko flavor");
requireText(workflow, "stage_ios27_input: true", "PR build does not pass inputs to Xcode 27");
requireText(workflow, "name: Reynard-ios27-input\n", "PR Xcode 27 job expects obsolete artifact name");
requireText(workflow, "name: Reynard.ipa", "PR IPA artifact must be verified");
requireText(workflow, "name: Reynard-TrollStore.tipa", "PR TIPA artifact must be verified");
requireText(workflow, "runs-on: xcode-27", "PR lacks Xcode 27 compatibility");
requireText(workflow, 'REYNARD_DEPLOYMENT_TARGET_OVERRIDE: "15.0"', "iOS 27 SDK compatibility minimum missing");
requireText(workflow, "Verify the shipping project still targets iOS 13", "Shipping iOS 13 check is missing");
requireText(workflow, 'test "$minimum_os" = "15.0"', "Linked iOS minimum not verified");
requireText(workflow, "xcrun vtool -show-build", "iOS SDK Mach-O version not verified");
requireText(workflow, "firefox/toolkit/mozapps/extensions/default-theme", "Gecko default theme omitted");
rejectText(workflow, "SCCACHE_GHA_ENABLED", "PR source build should not use per-object sccache cloud backend");
rejectText(workflow, "timeout-minutes: 360", "A monolithic Gecko job still reaches the six-hour limit");
rejectText(workflow, "gh release create", "PR workflow must never publish stable releases");
rejectText(workflow, "gh release upload", "PR workflow must never modify release artifacts");
if (/(?:curl|wget)[^\\n]*releases\\/download/i.test(workflow)) {
  throw new Error("PR builds may not use release binaries as source");
}
for (const match of workflow.matchAll(/uses:\\s+[^@\\s]+@([^\\s#]+)/g)) {
  if (!/^[a-f0-9]{40}$/.test(match[1])) {
    throw new Error("Workflow action is not pinned: " + match[0]);
  }
}

const unsignedBuild = read("tools/release/build-unsigned-app.sh");
requireText(unsignedBuild, "CODE_SIGNING_ALLOWED=NO", "unsigned app build does not disable signing");
requireText(unsignedBuild, "AD_HOC_CODE_SIGNING_ALLOWED=NO", "unsigned app build allows ad-hoc signing");
requireText(
  unsignedBuild,
  "REYNARD_DEPLOYMENT_TARGET_OVERRIDE",
  "unsigned app build does not support the isolated Xcode 27 deployment override"
);

const buildConfiguration = read("browser/Configuration/Reynard.xcconfig");
const currentVersion = buildConfiguration.match(/^CURRENT_VERSION = (\d+\.\d+\.\d+)$/m)?.[1];
if (!currentVersion) {
  throw new Error("Xcode project has no valid release version");
}
const releaseTag = read(".github/release-tag").trim();
// A rebuild of the same app version gets the next -zh.N suffix; the updater
// orders such releases by the build number written into the release notes.
if (!new RegExp(`^v${currentVersion.replace(/\./g, "\\.")}-zh\\.[1-9][0-9]*$`).test(releaseTag)) {
  throw new Error("Release tag does not match the Xcode app version");
}
const formalReleaseWorkflow = read(".github/workflows/build-release.yml");
requireText(
  formalReleaseWorkflow,
  'title="Reynard Browser 中文版 ${VERSION}"',
  "Release title is not derived from the validated release tag"
);
requireText(
  formalReleaseWorkflow,
  "does not match CURRENT_VERSION",
  "Release workflow does not verify the tag against the Xcode app version before building"
);
requireText(
  read(`.github/release-notes/${releaseTag}.md`),
  `# Reynard Browser 中文版 ${currentVersion}`,
  "Release notes do not match the Xcode app version"
);
requireText(
  buildConfiguration,
  "IPHONEOS_DEPLOYMENT_TARGET = 13.0",
  "Xcode deployment target is not iOS 13"
);
const projectConfiguration = read("browser/Reynard.xcodeproj/project.pbxproj");
rejectText(
  projectConfiguration,
  "IPHONEOS_DEPLOYMENT_TARGET = 15.0",
  "an Xcode target still overrides the iOS 13 deployment target with iOS 15"
);
const geckoBuild = read("tools/development/build-gecko.sh");
requireText(geckoBuild, "--enable-ios-target=13.0", "Gecko deployment target is not iOS 13");
requireText(
  geckoBuild,
  "libclang_rt.ios.a",
  "Gecko does not link the compiler runtime required by iOS availability guards"
);
const ideviceBuild = read("tools/development/build-idevice.sh");
requireText(ideviceBuild, 'DEPLOYMENT_TARGET="13.0"', "idevice deployment target is not iOS 13");

const unsignedPackage = read("tools/release/create-unsigned-ipa.sh");
requireText(
  unsignedPackage,
  "codesign --remove-signature",
  "unsigned IPA packaging does not strip embedded Mach-O signatures"
);
requireText(
  unsignedPackage,
  "embedded.mobileprovision",
  "unsigned IPA packaging does not reject provisioning profiles"
);
requireText(
  unsignedPackage,
  "@rpath/XUL.dylib",
  "unsigned IPA packaging does not normalize XUL for recursive signing tools"
);

const infoPlist = read("browser/Reynard/Resources/Info.plist");
requireText(infoPlist, "<string>http</string>", "the app does not register the HTTP URL scheme");
requireText(infoPlist, "<string>https</string>", "the app does not register the HTTPS URL scheme");
requireText(
  infoPlist,
  "<string>apple-magnifier</string>",
  "the TrollStore install URL scheme is not declared for canOpenURL"
);

const appEntitlements = read("browser/Reynard/Entitlements/Reynard.entitlements");
requireText(
  appEntitlements,
  "<key>com.apple.developer.web-browser</key>",
  "the standard app entitlement file does not request default-browser access"
);

const incomingBrowserURL = read("browser/Reynard/Client/Shared/IncomingBrowserURL.swift");
requireText(
  incomingBrowserURL,
  "URLUtils.isWebURL(wrappedURL)",
  "custom-scheme browser URLs are not restricted to HTTP and HTTPS"
);

const sceneDelegate = read("browser/Reynard/SceneDelegate.swift");
requireText(
  sceneDelegate,
  "IncomingBrowserURL.firstResolvedURL",
  "scene URL delivery does not use the validated incoming-browser URL resolver"
);

const defaultBrowserSettings = read(
  "browser/Reynard/Client/Interface/Library/Settings/DefaultBrowserSettings.swift"
);
requireText(
  defaultBrowserSettings,
  "UIApplication.openDefaultApplicationsSettingsURLString",
  "settings do not open the iOS Default Apps panel on supported systems"
);
requireText(
  defaultBrowserSettings,
  "UIApplication.openSettingsURLString",
  "settings do not provide a fallback for older supported systems"
);
requireText(
  defaultBrowserSettings,
  'getEntitlementValue(entitlement)',
  "settings do not report whether the installed signature has default-browser access"
);

const browserUpdates = read("browser/Reynard/Client/Startup/BrowserUpdates.swift");
requireText(
  browserUpdates,
  "api.github.com/repos/xytxg/reynard-browser-zh/releases",
  "the updater does not check this repository's releases"
);
requireText(
  browserUpdates,
  "BoundedURLDataLoader",
  "the update release feed is not loaded through the bounded network loader"
);
requireText(
  browserUpdates,
  "BrowserUpdatePolicy.isAllowedReleaseDownloadURL",
  "release package URLs are not restricted to this repository"
);
rejectText(browserUpdates, "Data(contentsOf:", "the updater performs an unbounded synchronous network read");
rejectText(
  browserUpdates,
  "minh-ton/reynard-browser/releases/download/0.0.1-a1/source.json",
  "the updater still uses the obsolete upstream feed"
);

const updateSettings = read(
  "browser/Reynard/Client/Interface/Library/Settings/Sections/Updates/UpdatesSettingsSection.swift"
);
requireText(
  updateSettings,
  "UpdatePackageVerifier.verify",
  "downloaded updates are not verified before sharing"
);
requireText(
  updateSettings,
  "BrowserUpdatePolicy.checksum",
  "the updater does not parse the release SHA-256 sidecar"
);

const boundedURLDataLoader = read("browser/Reynard/Client/Shared/BoundedURLDataLoader.swift");
requireText(
  boundedURLDataLoader,
  "URLSessionConfiguration.ephemeral",
  "small untrusted responses do not use an isolated network session"
);
requireText(
  boundedURLDataLoader,
  "maximumByteCount - receivedData.count",
  "small untrusted responses are not capped while streaming"
);

// PR builds are test artifacts only; signed release metadata is controlled by build-release.yml.
const releaseWorkflow = formalReleaseWorkflow;
requireText(releaseWorkflow, "reynard-update-build:", "formal release body omits build number");
requireText(releaseWorkflow, 'cat "$NOTES"', "formal release omits curated notes");
requireText(releaseWorkflow, "## SHA-256 校验", "formal release notes omit checksums");
requireText(releaseWorkflow, "dist/Reynard.ipa.sha256", "formal release lacks IPA checksum sidecar");
rejectText(workflow, "gh release edit", "PR workflow must never edit releases");
const changelog = read("CHANGELOG.md");
const latestChangelogHeading = changelog.match(/^## (.+)$/m)?.[1] ?? "";
if (!latestChangelogHeading.startsWith(`${currentVersion} `)) {
  throw new Error("the newest CHANGELOG.md section does not match the Xcode app version");
}
requireText(changelog, "f25792a", "project changelog does not record the audited upstream baseline");

const tabStore = read("browser/Reynard/Client/Stores/TabManagementStore.swift");
requireText(tabStore, "privateTabs: []", "private tabs can be returned from persistent storage");
requireText(tabStore, "selectedPrivateTabID: nil", "private tab selection can be persisted");
requireText(tabStore, "purgePersistedPrivateTabsLocked", "legacy private tab records are not purged");
rejectText(tabStore, "insertTabsLocked(persistedPrivateTabs", "private tabs are written to SQLite");
requireText(
  tabStore,
  "guard !isPrivate else",
  "private tab thumbnails can still be written to disk"
);
requireText(
  tabStore,
  "purgePersistedHistories(keeping:",
  "orphaned private navigation histories are not purged on startup"
);
requireText(
  tabStore,
  "pendingPersistWorkItem.perform()",
  "background session flushing does not execute the delayed tab-state write"
);

const addressBar = read(
  "browser/Reynard/Client/Interface/Chrome/AddressBar/AddressBar.swift"
);
requireText(
  addressBar,
  ".resolvedColor(with: traitCollection)",
  "address-bar border does not refresh its dynamic color after appearance changes"
);
requireText(
  addressBar,
  "updateBorderColor()",
  "address-bar border color refresh hook is missing"
);

const navigationHistoryStore = read("browser/Reynard/Client/Stores/NavigationHistoryStore.swift");
requireText(
  navigationHistoryStore,
  "nonPersistentTabIDs.contains(tabID)",
  "private navigation histories are not excluded from persistence"
);
requireText(
  navigationHistoryStore,
  "pendingHistories.removeAll(keepingCapacity: false)",
  "clearing navigation history leaves pending disk writes behind"
);

const browserPreferences = read("browser/Reynard/Client/Preferences/BrowserPreferences.swift");
requireText(
  browserPreferences,
  "static var openingScreen: HomepageOpeningScreen",
  "homepage opening-screen preference is missing"
);

const tabManager = read("browser/Reynard/Client/TabManagement/TabManagerImpl.swift");
requireText(tabManager, "guard !tab.isPrivate", "private navigation state is not protected from persistence");
requireText(
  tabManager,
  "setNavigationHistoryPersistenceEnabled(!tab.isPrivate",
  "private tabs are not registered for in-memory-only navigation history"
);
requireText(
  tabManager,
  "persistThumbnail(image, for: tab.id, isPrivate: tab.isPrivate)",
  "thumbnail persistence does not carry the tab privacy mode"
);
requireText(
  tabManager,
  "func createInitialTab(openingScreen: HomepageOpeningScreen)",
  "session restore preference is not passed into initial-tab creation"
);
requireText(tabManager, "case .lastTab:", "last-session startup mode is not handled");
requireText(tabManager, "restoreTabsIfNeeded()", "last-session startup mode does not restore persisted tabs");

const downloadStore = read("browser/Reynard/Client/Stores/DownloadStore.swift");
requireText(downloadStore, "DownloadCleanupPolicy.partition", "date-based download cleanup does not use the tested policy");
rejectText(downloadStore, "self.persistedDownloads.removeAll()", "download cleanup still contains the original unconditional clear");

const addonCoordinator = read("browser/Reynard/Client/Interface/Addons/AddonCoordinator.swift");
const browserTabManager = read("browser/Reynard/Client/Interface/BrowserViewController+TabManager.swift");
requireText(
  addonCoordinator,
  "func confirmExternalResponse(_ response: ExternalResponseInfo) async -> Bool",
  "add-on package downloads are not confirmed before installation"
);
requireText(
  browserTabManager,
  "return await addonCoordinator.confirmExternalResponse(response)",
  "the external-response delegate does not call the add-on confirmation API"
);
rejectText(
  browserTabManager,
  "addonCoordinator.handleExternalResponse(response)",
  "the external-response delegate calls the removed add-on coordinator API"
);

const autofillHandler = read("browser/GeckoView/Session/GeckoAutofillHandler.swift");
rejectText(
  autofillHandler,
  'fatalError("Unimplemented")',
  "optional autofill bridge selectors still crash when unavailable"
);

const geckoSession = read("browser/GeckoView/Session/GeckoSession.swift");
rejectText(
  geckoSession,
  'fatalError("GeckoView window has no view")',
  "missing Gecko view still crashes the browser"
);

const faviconStore = read("browser/Reynard/Client/Stores/FaviconStore.swift");
rejectText(
  faviconStore,
  "SafariSharedUI",
  "favicon rendering still calls a private Safari framework"
);
requireText(
  faviconStore,
  "?? fileManager.temporaryDirectory",
  "favicon cache initialization can still crash when Application Support is unavailable"
);
requireText(
  faviconStore,
  "CGImageSourceCopyPropertiesAtIndex",
  "favicon decoding does not validate image dimensions before UIKit decoding"
);
requireText(
  faviconStore,
  "URLUtils.isWebURL(requestedURL)",
  "favicon metadata requests allow non-web URL schemes"
);

// Upstream removed the experimental native picture-in-picture implementation
// (800fb571). Make sure no stale file or reference survives a later sync.
for (const removedPath of [
  "browser/GeckoView/Delegates/PictureInPictureDelegate.swift",
  "browser/Reynard/Client/SessionManagement/Media/PictureInPictureCoordinator.swift",
]) {
  if (fs.existsSync(path.join(root, removedPath))) {
    throw new Error("removed picture-in-picture source was reintroduced: " + removedPath);
  }
}
rejectText(
  read("browser/Reynard.xcodeproj/project.pbxproj"),
  "PictureInPicture",
  "the Xcode project still references removed picture-in-picture sources"
);

const siteMetadataStore = read("browser/Reynard/Client/Stores/SiteMetadataStore.swift");
requireText(
  siteMetadataStore,
  "BoundedURLDataLoader",
  "site metadata responses are not capped while streaming"
);
requireText(
  siteMetadataStore,
  "ImageUtils.prepareJPEGImage",
  "Open Graph images are not downsampled before UIKit decoding"
);

requireText(
  faviconStore,
  "BoundedURLDataLoader",
  "favicon and manifest responses are not capped while streaming"
);
requireText(
  faviconStore,
  "maxFetchedCandidateCount",
  "a page can trigger an unbounded number of favicon requests"
);

const searchCompletion = read("browser/Reynard/Client/Search/SearchCompletion.swift");
requireText(
  searchCompletion,
  "BoundedURLDataLoader",
  "search suggestion responses are not capped while streaming"
);
requireText(
  searchCompletion,
  "maximumSuggestionCount",
  "search providers can return an unbounded number of suggestions"
);

const mediaSession = read(
  "browser/Reynard/Client/SessionManagement/Media/SystemMediaSession.swift"
);
requireText(mediaSession, "BoundedURLDataLoader", "media artwork responses are not bounded");
requireText(mediaSession, "artworkRequestID", "stale media artwork requests can overwrite current metadata");

const imagePreviewLoader = read(
  "browser/Reynard/Client/Interface/ContextMenu/ImagePreview/ImagePreviewLoader.swift"
);
requireText(imagePreviewLoader, "fetchImageData", "image previews no longer use Gecko networking");
requireText(
  imagePreviewLoader,
  "data.count <= maximumSourceDataSize",
  "image previews fetched through Gecko are not size capped"
);
requireText(
  read("patches/mobile/shared/actors/GeckoViewContentChild.sys.mjs.patch"),
  "MAX_FETCH_IMAGE_BYTES",
  "the content process does not cap context menu image fetches before base64 encoding"
);
requireText(imagePreviewLoader, "maximumPreviewPixelSize", "image previews are not downsampled");

const zipArchiveReader = read("browser/Reynard/Client/Utilities/ZipArchiveReader.swift");
requireText(zipArchiveReader, "maximumEntryCount", "add-on ZIP entry counts are not capped");
requireText(zipArchiveReader, "maximumEntrySize", "add-on ZIP inflation output is not capped");
requireText(zipArchiveReader, "containsBytes", "add-on ZIP offsets are not bounds checked");

const addonPackageSafety = read(
  "browser/Reynard/Client/Interface/Addons/AddonPackageSafety.swift"
);
requireText(addonPackageSafety, "maximumPackageSize", "add-on package files are not size limited");
requireText(addonPackageSafety, "validateZip", "add-on packages need central-directory validation");
requireText(addonPackageSafety, "maximumUnpackedSize", "add-on ZIP inflation is not bounded");
requireText(addonPackageSafety, 'name == "manifest.json"', "add-on ZIP files must contain a root manifest");
requireText(
  read("browser/Reynard/Client/Stores/SitePermissionStore.swift"),
  "migrateLegacyHostPermissionsLocked",
  "legacy host-only site permissions are not isolated"
);
requireText(
  read("browser/Reynard/Client/Shared/URLUtils.swift"),
  "permissionOrigin(from rawURI:",
  "web permissions are not normalized to complete origins"
);

const svgRenderer = read("browser/Reynard/Client/Utilities/SVGIconRenderer.swift");
requireText(svgRenderer, "isSafeSVGDocument", "untrusted SVG icons are not screened before private parsing");
requireText(svgRenderer, "maximumDataSize", "untrusted SVG icon data is not capped");

const ddiManager = read("browser/Reynard/JIT/RPPairing/DDIManager.swift");
requireText(
  ddiManager,
  "6eae353ae694bda1c421d4a3eee5459ae59c99a1",
  "Developer Disk Images are not pinned to an audited revision"
);
rejectText(ddiManager, "refs/heads/main", "Developer Disk Images still download from a mutable branch");
requireText(ddiManager, "expectedSHA256", "Developer Disk Images are not SHA-256 verified");
requireText(ddiManager, "expectedByteCount", "Developer Disk Image size is not verified");
requireText(
  ddiManager,
  "05fd807da5e19f030fa4941f24800c965c6c77982ab572dd5d1ef778fb69f9ca",
  "the personalized Developer Disk Image (iOS < 26.4) is not SHA-256 pinned"
);
requireText(ddiManager, "if #available(iOS 26.4, *)", "cryptex DDI mounting is not limited to iOS 26.4+");
requireText(
  read("browser/Reynard/Bridging/UIKit+Private.h"),
  "API_AVAILABLE(ios(14.0))\n@interface _UIContextMenuStyle",
  "the private _UIContextMenuStyle class is a hard launch dependency on iOS 13"
);
const contextMenuCoordinator = read("browser/Reynard/Client/Interface/ContextMenu/ContextMenuCoordinator.swift");
requireText(
  contextMenuCoordinator,
  'NSClassFromString("_UIContextMenuStyle")',
  "context menu style is used without checking the private class exists"
);
requireText(
  contextMenuCoordinator,
  "#selector(setter: _UIContextMenuStyle._preferredAnchor)",
  "context menu anchor is set without checking the private setter exists"
);
requireText(
  read("browser/Reynard/Client/Interface/ContentView/WebContent/SelectionActionMenu/SelectionActionMenuHostView.swift"),
  "responds(to: selectionViewSelector)",
  "the private selectionView selector is called without a responds(to:) check"
);
const webContentErrorView = read("browser/Reynard/Client/Interface/ContentView/WebContentErrorView.swift");
rejectText(webContentErrorView, "as! String", "the error page force-casts the app display name");
requireText(
  webContentErrorView,
  "linkRange.location != NSNotFound",
  "the crash page link can raise when a translation drops the link text"
);
rejectText(webContentErrorView, "minh-ton/reynard-browser/issues", "crash reports from this build go to the upstream tracker");
requireText(
  read("patches/widget/uikit/nsWindow.mm.patch"),
  "!topWindow || !topWindow->DocumentPrincipal()",
  "HTTPS-only exceptions can hit IPC_FAIL (content process kill) when called directly"
);

const jitSettings = read(
  "browser/Reynard/Client/Interface/Library/Settings/Sections/JIT/JITSettingsSection.swift"
);
requireText(
  jitSettings,
  "PropertyListSerialization.propertyList",
  "imported pairing files are not validated as property lists"
);
requireText(jitSettings, "fileSize <= 4 * 1024 * 1024", "pairing file size is not capped");

const jitEnabler = read("browser/Reynard/JIT/JITEnabler.m");
requireText(jitEnabler, "NSUUID.UUID.UUIDString", "the root JIT helper uses a predictable temporary path");
requireText(jitEnabler, "NSFilePosixPermissions: @0700", "the temporary JIT helper directory is not protected");

const eventDispatcher = read("browser/GeckoView/Events/EventDispatcher.swift");
rejectText(eventDispatcher, "message as!", "malformed Gecko event payloads can still force-cast crash");

const developerPreferences = read(
  "browser/Reynard/Client/Interface/Library/Settings/Sections/Advanced/Developer/DeveloperPreferencesViewController.swift"
);
requireText(
  developerPreferences,
  'URL(string: "https://libimobiledevice.org")',
  "remote debugging documentation link is not an absolute HTTPS URL"
);
rejectText(
  developerPreferences,
  "URL(string: urlString)!",
  "remote debugging instructions still force-unwrap a relative URL"
);
if ((developerPreferences.match(/location != NSNotFound/g) ?? []).length < 2) {
  throw new Error("remote debugging localization ranges are not checked before applying attributes");
}

const filePicker = read("browser/Reynard/Client/Interface/ContentView/WebContent/FilePicker/FilePicker.swift");
requireText(
  filePicker,
  "nonisolated static let imageCompressionQuality",
  "file-picker compression settings can trigger strict-concurrency diagnostics"
);
const filePickerStaging = read(
  "browser/Reynard/Client/Interface/ContentView/WebContent/FilePicker/FilePickerStaging.swift"
);
requireText(
  filePickerStaging,
  "private nonisolated static func preferredMediaFileName",
  "file-provider callbacks cross the main actor for media filenames"
);

const userDataMigrationPath = path.join(
  root,
  "browser/Reynard/Client/Startup/UserDataMigration.swift"
);
if (fs.existsSync(userDataMigrationPath)) {
  throw new Error("obsolete startup data migration is still present");
}
rejectText(
  read("browser/Reynard/main.swift"),
  "UserDataMigration",
  "startup still invokes the obsolete data migration"
);
const mainSource = read("browser/Reynard/main.swift");
requireText(
  mainSource,
  "configureUnsandboxedAppDataDirectories",
  "iOS 13 unsandboxed builds do not configure Gecko app-data directories"
);
requireText(
  mainSource,
  "if #unavailable(iOS 14.0)",
  "iOS 13 Gecko app-data compatibility is not runtime-gated"
);
rejectText(
  mainSource,
  "obsoleted: 14.0",
  "iOS 13 Gecko app-data helper cannot be type-checked by newer deployment targets"
);

// Firefox 157 integration moved the decoder/encoder guards into upstream patches.
const ios13AvailabilityPatch = [
  "patches/zz-compat/iOS13RuntimeAvailability.patch",
  "patches/dom/media/platforms/apple/AppleVTDecoder.cpp.patch",
  "patches/dom/media/platforms/apple/AppleVTEncoder.cpp.patch",
  "patches/widget/uikit/ScreenHelperUIKit.mm.patch",
].map(read).join("\n");
const decoderAvailabilityPatch = read(
  "patches/dom/media/platforms/apple/AppleVTDecoder.cpp.patch"
);
const encoderAvailabilityPatch = read(
  "patches/dom/media/platforms/apple/AppleVTEncoder.cpp.patch"
);
for (const [fragment, message] of [
  ["__builtin_available(macOS 11.0, iOS 14.0, *)", "HDR color-space APIs are not guarded for iOS 13"],
  ["__builtin_available(iOS 17.0, *)", "VideoToolbox decoder APIs are not guarded for iOS 13"],
  ["__builtin_available(iOS 17.4, *)", "VideoToolbox encoder APIs are not guarded for iOS 13"],
  ["__builtin_available(macos 13.0, iOS 16.0, *)", "constant-bitrate APIs are not guarded for iOS 13"],
]) {
  requireText(ios13AvailabilityPatch, fragment, message);
}
requireText(
  decoderAvailabilityPatch,
  "if (__builtin_available(iOS 17.0, *)) {\n+    const void* specKeys[]",
  "VideoToolbox decoder key reference is outside its iOS 17 availability scope"
);
requireText(
  encoderAvailabilityPatch,
  "if (__builtin_available(iOS 17.4, *)) {\n+    const void* keys[]",
  "VideoToolbox encoder key reference is outside its iOS 17.4 availability scope"
);
rejectText(
  ios13AvailabilityPatch,
  "\n+  if ([aScreen respondsToSelector:@selector(potentialEDRHeadroom)",
  "selector probing does not satisfy iOS availability checking for EDR APIs"
);

// Release pipeline and updater hardening.
requireText(browserUpdates, "!release.prerelease", "the updater offers prereleases as updates");
rejectText(
  releaseWorkflow,
  'tags: ["v*"]',
  "the unsigned IPA workflow still publishes tags alongside build-release.yml"
);
requireText(formalReleaseWorkflow, "- 'v*'", "build-release.yml does not limit formal releases to v* tags");
requireText(formalReleaseWorkflow, ".sha256", "formal releases do not publish SHA-256 sidecars for the updater");
requireText(formalReleaseWorkflow, "reynard-update-build:", "formal releases do not expose their build number");
const nightlyWorkflow = read(".github/workflows/build-nightly.yml");
requireText(nightlyWorkflow, "should_build", "nightly builds do not skip unchanged commits");
requireText(nightlyWorkflow, "## Nightly skipped", "skipped nightlies are not reported in the run summary");
const threeIpaTriggers = read(".github/workflows/build-three-ipa.yml").split("\njobs:")[0];
if (/^\s*-\s*main\s*$/m.test(threeIpaTriggers)) {
  throw new Error("build-three-ipa.yml rebuilds every main push in addition to nightly and release builds");
}
requireText(threeIpaTriggers, "- sync/**", "build-three-ipa.yml no longer builds sync branches before merge");
for (const workflowName of fs.readdirSync(path.join(root, ".github/workflows"))) {
  if (!workflowName.endsWith(".yml")) {
    continue;
  }
  const workflowText = read(`.github/workflows/${workflowName}`);
  const checkoutCount = (workflowText.match(/uses: actions\/checkout@/g) ?? []).length;
  const persistedCount = (workflowText.match(/persist-credentials: false/g) ?? []).length;
  if (checkoutCount !== persistedCount) {
    throw new Error(`${workflowName} has a checkout that persists the GitHub token`);
  }
  // Reusable workflows inherit the caller's concurrency group.
  const reusableOnly = /^on:\n  workflow_call:\n/m.test(workflowText);
  if (!reusableOnly && !workflowText.includes("\nconcurrency:\n")) {
    throw new Error(`${workflowName} has no concurrency group`);
  }
}
// Gecko is compiled once per flavor, stays inside the 6 hour job limit, and
// its compiler cache stays below the repository's 10 GB Actions cache quota.
const sharedBuildWorkflow = read(".github/workflows/build.yml");
const geckoWorkflow = read(".github/workflows/build-gecko.yml");
for (const caller of [formalReleaseWorkflow, nightlyWorkflow, read(".github/workflows/build-three-ipa.yml")]) {
  requireText(caller, "uses: ./.github/workflows/build.yml", "a release, nightly or three-variant build no longer uses the shared build pipeline");
}
for (const flavor of ["standard", "nojemalloc"]) {
  for (const pass of [1, 2, 3, 4]) {
    requireText(sharedBuildWorkflow, `  gecko-${flavor}-p${pass}:\n`, `build.yml has no gecko-${flavor}-p${pass} job`);
  }
  // Resume passes must reuse pass 1's exact compilers, or cargo and make
  // would rebuild everything the earlier passes produced.
  requireText(
    sharedBuildWorkflow,
    `rust_toolchain: \${{ needs.gecko-${flavor}-p1.outputs.rust_toolchain }}`,
    `resume passes of ${flavor} do not pin pass 1's Rust toolchain`
  );
  requireText(
    sharedBuildWorkflow,
    `xcode_version: \${{ needs.gecko-${flavor}-p1.outputs.xcode_version }}`,
    `resume passes of ${flavor} do not pin pass 1's Xcode`
  );
  requireText(
    sharedBuildWorkflow,
    `needs.gecko-${flavor}-p4.outputs.complete == 'true'`,
    `packaging ignores the last ${flavor} pass`
  );
}
if ((sharedBuildWorkflow.match(/uses: \.\/\.github\/workflows\/build-gecko\.yml/g) ?? []).length !== 8) {
  throw new Error("build.yml must build each Gecko flavor through build-gecko.yml in at most four passes");
}
if ((sharedBuildWorkflow.match(/final_pass: true/g) ?? []).length !== 2) {
  throw new Error("each Gecko flavor needs exactly one final pass that fails instead of resuming");
}
rejectText(sharedBuildWorkflow, "tools/development/build-gecko.sh", "packaging jobs compile Gecko again instead of using the Gecko artifact");
requireText(sharedBuildWorkflow, "name: gecko-dist-${{ matrix.variant }}", "packaging jobs do not consume the Gecko artifact");
requireText(sharedBuildWorkflow, "--disable-jemalloc --use-sccache --auto-clobber", "the jailbroken Gecko flavor lost --disable-jemalloc");
requireText(geckoWorkflow, "timeout-minutes: 355", "Gecko jobs can run into GitHub's 6 hour limit");
{
  const passMinutes = Number(geckoWorkflow.match(/GECKO_PASS_MINUTES: (\d+)/)?.[1]);
  // The job timeout must leave time to stop, archive and upload the pass.
  if (!(passMinutes >= 240 && passMinutes <= 325)) {
    throw new Error("Gecko passes do not stop early enough to save their object directory");
  }
}
requireText(geckoWorkflow, "        timeout-minutes: 330\n", "the Gecko compile step has no backstop timeout");
requireText(geckoWorkflow, "build-gecko-pass.sh run", "Gecko passes are not stopped cleanly at their time budget");
requireText(
  read("tools/development/build-gecko-pass.sh"),
  'optional = {"L10NBASEDIR"}',
  "the never-created l10n directory still forces a reconfigure on every resumed pass"
);
requireText(geckoWorkflow, "build-gecko-pass.sh normalize-sources", "resumed Gecko builds would treat restored objects as stale");
requireText(geckoWorkflow, "build-gecko-pass.sh save", "Gecko passes do not keep their object directory for the next pass");
requireText(geckoWorkflow, "build-gecko-pass.sh restore", "Gecko resume passes do not restore the previous object directory");
requireText(geckoWorkflow, "name: gecko-objdir-${{ inputs.flavor }}-p${{ inputs.pass }}", "the object directory artifact is not per flavor and pass");
requireText(geckoWorkflow, "SCCACHE_CACHE_SIZE:", "the local sccache directory is not size capped");
requireText(geckoWorkflow, "uses: actions/cache/save@", "Gecko jobs do not save their compiler cache");
requireText(geckoWorkflow, "key: gecko-dist-v3-", "Gecko jobs do not reuse an identical prebuilt Gecko");
// sccache is saved only from a finished build: saving the directory while
// the killed build's compilers still wrote into it made `tar` fail.
const sccacheSave = geckoWorkflow.split("- name: Save sccache directory\n")[1]?.split("\n      - name:")[0] ?? "";
requireText(sccacheSave, "steps.verify.outcome == 'success'", "sccache is saved from an unfinished or still running build");
const geckoPass = read("tools/development/build-gecko-pass.sh");
requireText(geckoPass, "--stop-server", "the pass script archives sccache while its server can still write");
requireText(geckoPass, "-newer \"$marker\"", "the pass script keeps outputs that were being written when it stopped");
requireText(geckoPass, "RESUMABLE=75", "the pass script does not report a resumable stop separately from a build failure");
// configure records absolute tool paths; a resume pass on a fresh runner
// must get the same toolchains at the same paths (run 39025087956 failed
// with "sccache: cannot find binary path" because ~/.mozbuild was missing).
requireText(geckoPass, 'mozbuild.tar.zst', "the object directory artifact does not carry the bootstrapped toolchains");
requireText(geckoPass, "location_file", "a resume pass does not verify it builds at the same checkout and home paths");
requireText(geckoPass, "config.status.json", "a resume pass does not check the tool paths configure recorded");
requireText(geckoPass, 'rm -f "$OBJDIR/config.status"', "missing toolchains do not trigger a reconfigure and bootstrap");
requireText(geckoPass, "\tcheck_toolchain\n", "the pass does not check recorded tool paths before building");
const sccacheSetup = geckoWorkflow.split("- name: Set up sccache\n")[1]?.split("\n      - name:")[0] ?? "";
if (!/version: v\d+\.\d+\.\d+/.test(sccacheSetup)) {
  throw new Error("sccache is not pinned; its recorded path would change between passes");
}
requireText(geckoWorkflow, "toolchain: ${{ steps.rust.outputs.toolchain }}", "pass 1 installs Rust under a moving channel name");
const depsSave = geckoWorkflow.split("- name: Save Gecko dependency cache\n")[1]?.split("\n      - name:")[0] ?? "";
requireText(depsSave, "steps.bootstrap.outputs.ready == 'true'", "~/.mozbuild is not saved once its toolchains are bootstrapped");
rejectText(depsSave, "steps.verify.outcome", "~/.mozbuild is only saved after a finished build");
requireText(geckoBuild, 'touch -t "$GECKO_SOURCE_MTIME" "$MOZCONFIG"', "a regenerated mozconfig would force resumed builds to reconfigure");
for (const workflowText of [sharedBuildWorkflow, geckoWorkflow]) {
  rejectText(workflowText, "SCCACHE_GHA_ENABLED", "the per-object sccache Actions backend is back and floods the cache quota");
}
if (/name: Reynard[^\n]*gecko/i.test(geckoWorkflow)) {
  throw new Error("Gecko artifacts must not match build-release.yml's Reynard*.*ipa download pattern");
}
rejectText(
  unsignedPackage,
  "| grep -Fq '@rpath/XUL '",
  "the stale @rpath/XUL check is defeated by pipefail and grep -q"
);
const ipaPackaging = read("tools/release/create-ipa.sh");
requireText(
  ipaPackaging,
  'SIGNED_IPA_SHA256="567282427ffa56bf897aa786ff3e16beb6098c31b7880b309d94f6f2f58d5a8b"',
  "the downloaded signed libswift_Concurrency source IPA is not pinned"
);
requireText(
  read("tools/release/build-app.sh"),
  '/usr/bin/codesign --force --sign - --verbose "$SWIFT_CONCURRENCY_PATH"',
  "libswift_Concurrency.dylib is not re-signed after bitcode_strip"
);
requireText(
  read("browser/Reynard/Client/Interface/Addons/AddonCoordinator.swift"),
  "failedIconKeys.insert(failureKey)",
  "failed add-on icon loads are retried in a refresh loop"
);
requireText(
  read("browser/Reynard/Client/Interface/Library/Settings/Sections/Privacy/ClearBrowsingData/ClearBrowsingDataViewController.swift"),
  "TabManagementStore.shared.clearPersistedSession()",
  "clearing opened tabs leaves restorable recently closed tabs and tab sessions"
);
rejectText(
  read("browser/Reynard/JIT/Services/BackgroundAudioManager.swift"),
  "if !startEngine() {\n                stop()",
  "background audio keep-alive stops permanently after one failed recovery"
);

console.log("Project safety validation passed");
