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
requireText(workflow, "tools/development/build-gecko.sh", "IPA workflow does not build Gecko from source");
requireText(workflow, "tools/release/build-unsigned-app.sh", "IPA workflow does not build Reynard.app from source");
requireText(workflow, "runs-on: xcode-27", "IPA workflow does not compile against the iOS 27 SDK");
requireText(workflow, 'test "$minimum_os" = "15.0"', "iOS 27 compatibility job does not enforce iOS 15");
requireText(workflow, "xcrun vtool -show-build", "iOS 27 compatibility job does not inspect Mach-O load commands");
rejectText(workflow, "releases/download", "IPA workflow downloads a release binary");
rejectText(workflow, "source.ipa", "IPA workflow accepts a prebuilt IPA as its source");
for (const match of workflow.matchAll(/uses:\s+[^@\s]+@([^\s#]+)/g)) {
  if (!/^[a-f0-9]{40}$/.test(match[1])) {
    throw new Error("GitHub Actions dependency is not pinned to a full commit: " + match[0]);
  }
}

const unsignedBuild = read("tools/release/build-unsigned-app.sh");
requireText(unsignedBuild, "CODE_SIGNING_ALLOWED=NO", "unsigned app build does not disable signing");
requireText(unsignedBuild, "AD_HOC_CODE_SIGNING_ALLOWED=NO", "unsigned app build allows ad-hoc signing");

const buildConfiguration = read("browser/Configuration/Reynard.xcconfig");
requireText(
  buildConfiguration,
  "IPHONEOS_DEPLOYMENT_TARGET = 15.0",
  "Xcode deployment target is not iOS 15"
);
const geckoBuild = read("tools/development/build-gecko.sh");
requireText(geckoBuild, "--enable-ios-target=15.0", "Gecko deployment target is not iOS 15");
requireText(
  geckoBuild,
  "libclang_rt.ios.a",
  "Gecko does not link the compiler runtime required by iOS availability guards"
);
const ideviceBuild = read("tools/development/build-idevice.sh");
requireText(ideviceBuild, 'DEPLOYMENT_TARGET="15.0"', "idevice deployment target is not iOS 15");

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

const releaseWorkflow = read(".github/workflows/build-unsigned-ipa.yml");
requireText(
  releaseWorkflow,
  "reynard-update-build:",
  "release notes do not expose a machine-readable build number to the updater"
);

const tabStore = read("browser/Reynard/Client/Stores/TabManagementStore.swift");
requireText(tabStore, "privateTabs: []", "private tabs can be returned from persistent storage");
requireText(tabStore, "selectedPrivateTabID: nil", "private tab selection can be persisted");
requireText(tabStore, "purgePersistedPrivateTabsLocked", "legacy private tab records are not purged");
rejectText(tabStore, "insertTabsLocked(persistedPrivateTabs", "private tabs are written to SQLite");

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

const pictureInPictureDelegate = read("browser/GeckoView/Delegates/PictureInPictureDelegate.swift");
rejectText(
  pictureInPictureDelegate,
  "preconditionFailure",
  "an unavailable picture-in-picture candidate still crashes the browser"
);

const pictureInPictureCoordinator = read(
  "browser/Reynard/Client/SessionManagement/Media/PictureInPictureCoordinator.swift"
);
requireText(
  pictureInPictureCoordinator,
  "@available(iOS 15.0, *)",
  "picture-in-picture coordinator availability contract is missing"
);
requireText(
  pictureInPictureCoordinator,
  "deinit",
  "picture-in-picture coordinator does not define lifecycle cleanup"
);
requireText(
  pictureInPictureCoordinator,
  "observedSession?.pictureInPictureDelegate = nil",
  "picture-in-picture coordinator leaves the Gecko session delegate attached"
);
requireText(
  pictureInPictureCoordinator,
  "state.presentation?.controller.delegate = nil",
  "picture-in-picture coordinator leaves the AVKit controller delegate attached"
);
requireText(
  pictureInPictureCoordinator,
  "mediaSession.observer = nil",
  "picture-in-picture coordinator leaves the media observer attached"
);
requireText(
  pictureInPictureCoordinator,
  "sessionManager.applicationStateObserver = nil",
  "picture-in-picture coordinator leaves the application observer attached"
);
requireText(
  pictureInPictureCoordinator,
  "sessionManager.pictureInPictureHandler = nil",
  "picture-in-picture coordinator leaves the session handler attached"
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
requireText(imagePreviewLoader, "BoundedURLDataLoader", "image previews are not capped while streaming");
requireText(imagePreviewLoader, "maximumPreviewPixelSize", "image previews are not downsampled");

const zipArchiveReader = read("browser/Reynard/Client/Utilities/ZipArchiveReader.swift");
requireText(zipArchiveReader, "maximumEntryCount", "add-on ZIP entry counts are not capped");
requireText(zipArchiveReader, "maximumEntrySize", "add-on ZIP inflation output is not capped");
requireText(zipArchiveReader, "containsBytes", "add-on ZIP offsets are not bounds checked");

const addonPackageSafety = read(
  "browser/Reynard/Client/Interface/Addons/AddonPackageSafety.swift"
);
requireText(addonPackageSafety, "maximumPackageSize", "add-on package files are not size limited");
requireText(addonPackageSafety, "zipSignatures", "add-on packages are not checked for ZIP format");

const svgRenderer = read("browser/Reynard/Client/Utilities/SVGIconRenderer.swift");
requireText(svgRenderer, "isSafeSVGDocument", "untrusted SVG icons are not screened before private parsing");
requireText(svgRenderer, "maximumDataSize", "untrusted SVG icon data is not capped");

const ddiManager = read("browser/Reynard/JIT/RPPairing/DDIManager.swift");
requireText(
  ddiManager,
  "5423e4e955fbb3a9eef3e1212acfbfc6e7a26236",
  "Developer Disk Images are not pinned to an audited revision"
);
rejectText(ddiManager, "refs/heads/main", "Developer Disk Images still download from a mutable branch");
requireText(ddiManager, "expectedSHA256", "Developer Disk Images are not SHA-256 verified");
requireText(ddiManager, "expectedByteCount", "Developer Disk Image size is not verified");

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

const userDataMigration = read("browser/Reynard/Client/Startup/UserDataMigration.swift");
requireText(
  userDataMigration,
  "mergeDirectoryContents",
  "legacy migration can overwrite the active Application Support store"
);
rejectText(userDataMigration, 'fatalError("AppData migration failed")', "legacy migration still crashes on file errors");

const ios15AvailabilityPatch = read("patches/zz-compat/iOS15RuntimeAvailability.patch");
for (const [fragment, message] of [
  ["__builtin_available(macos 10.13, iOS 17.0, *)", "VideoToolbox decoder APIs are not guarded for iOS 15"],
  ["__builtin_available(macos 10.13, iOS 17.4, *)", "VideoToolbox encoder APIs are not guarded for iOS 15"],
  ["__builtin_available(macos 13.0, iOS 16.0, *)", "constant-bitrate APIs are not guarded for iOS 15"],
  ["@available(iOS 16.0, *)", "extended dynamic-range APIs are not guarded for iOS 15"],
]) {
  requireText(ios15AvailabilityPatch, fragment, message);
}
rejectText(
  ios15AvailabilityPatch,
  "\n+  if ([aScreen respondsToSelector:@selector(potentialEDRHeadroom)",
  "selector probing does not satisfy iOS availability checking for EDR APIs"
);

console.log("Project safety validation passed");
