//
//  AddonPermissions.swift
//  Reynard
//
//  Created by Minh Ton on 23/5/26.
//

import Foundation

public struct AddonLocalizedPermission {
    public let name: String
    public let localizedName: String
    public let granted: Bool
    
    public init(name: String, localizedName: String, granted: Bool) {
        self.name = name
        self.localizedName = localizedName
        self.granted = granted
    }
}

public struct AddonHostPermissions {
    public let allUrls: String?
    public let wildcards: [String]
    public let sites: [String]
    
    public init(allUrls: String?, wildcards: [String], sites: [String]) {
        self.allUrls = allUrls
        self.wildcards = wildcards
        self.sites = sites
    }
}

private enum AddonHostPermissionKind: Equatable {
    case allUrls
    case domain(String)
    case site(String)
}

public enum AddonPermissionSupport {
    public static let allowForAllSitesTitle = "允许所有网站"
    public static let allowForAllSitesSubtitle = "如果你信任此扩展，可以授予它在所有网站上的权限。"
    public static let noPermissionsRequiredDescription = "此扩展不需要任何权限。"
    public static let noDataCollectionRequiredDescription = "开发者表示此扩展不需要收集数据。"
    public static let userScriptsWarning = "未经验证的脚本可能带来安全和隐私风险。仅运行来自可信扩展或来源的脚本。"
    
    private static let permissionDescriptions = [
        "<all_urls>": "访问你在所有网站上的数据",
        "bookmarks": "Read and modify bookmarks",
        "browserSettings": "读取和修改浏览器设置",
        "browsingData": "清除最近的浏览历史、Cookie 和相关数据",
        "clipboardRead": "读取剪贴板数据",
        "clipboardWrite": "写入剪贴板数据",
        "declarativeNetRequest": "阻止任意页面上的内容",
        "declarativeNetRequestFeedback": "读取你的浏览历史",
        "devtools": "扩展开发者工具以访问打开标签页中的数据",
        "downloads": "Download files and read and modify the browser's download history",
        "downloads.open": "打开已下载到设备的文件",
        "find": "读取所有打开标签页的文本",
        "geolocation": "访问你的位置",
        "history": "访问浏览历史",
        "management": "监控扩展使用情况并管理主题",
        "nativeMessaging": "与本应用以外的应用交换消息",
        "notifications": "向你显示通知",
        "pkcs11": "提供加密认证服务",
        "privacy": "读取和修改隐私设置",
        "proxy": "控制浏览器代理设置",
        "sessions": "访问最近关闭的标签页",
        "tabHide": "隐藏和显示浏览器标签页",
        "tabs": "访问浏览器标签页",
        "topSites": "访问浏览历史",
        "trialML": "在设备上下载并运行 AI 模型",
        "userScripts": "允许未经验证的第三方脚本访问你的数据",
        "webNavigation": "访问导航期间的浏览器活动",
    ]
    
    private static let dataCollectionShortDescriptions = [
        "authenticationInfo": "authentication information",
        "bookmarksInfo": "bookmarks",
        "browsingActivity": "browsing activity",
        "financialAndPaymentInfo": "financial and payment information",
        "healthInfo": "health information",
        "locationInfo": "location",
        "personalCommunications": "personal communications",
        "personallyIdentifyingInfo": "personally identifying information",
        "searchTerms": "search terms",
        "technicalAndInteraction": "technical and interaction data",
        "websiteActivity": "website activity",
        "websiteContent": "website content",
    ]
    
    private static let dataCollectionLongDescriptions = [
        "authenticationInfo": "Share authentication information with extension developer",
        "bookmarksInfo": "Share bookmarks information with extension developer",
        "browsingActivity": "Share browsing activity with extension developer",
        "financialAndPaymentInfo": "Share financial and payment information with extension developer",
        "healthInfo": "Share health information with extension developer",
        "locationInfo": "Share location information with extension developer",
        "personalCommunications": "Share personal communications with extension developer",
        "personallyIdentifyingInfo": "Share personally identifying information with extension developer",
        "searchTerms": "Share search terms with extension developer",
        "technicalAndInteraction": "Share technical and interaction data with extension developer",
        "websiteActivity": "Share website activity with extension developer",
        "websiteContent": "Share website content with extension developer",
    ]
    
    public static func localizePermissions(_ permissions: [String], forUpdate: Bool = false) -> [String] {
        var localizedUrlAccessPermissions: [String] = []
        let requireAllUrlsAccess = permissions.contains("<all_urls>")
        var notFoundPermissions: [String] = []
        
        let localizedNormalPermissions = permissions.compactMap { permission -> String? in
            guard let localizedPermission = localizedPermissionDescription(for: permission, forUpdate: forUpdate) else {
                notFoundPermissions.append(permission)
                return nil
            }
            
            return localizedPermission
        }
        
        if !requireAllUrlsAccess && !notFoundPermissions.isEmpty {
            localizedUrlAccessPermissions = localizeURLAccessPermissions(notFoundPermissions, forUpdate: forUpdate)
        }
        
        return localizedNormalPermissions + localizedUrlAccessPermissions
    }
    
    public static func localizeOptionalPermissions(
        _ permissions: [String],
        grantedPermissions: [String]
    ) -> [AddonLocalizedPermission] {
        let granted = Set(grantedPermissions)
        var localizedPermissions: [AddonLocalizedPermission] = []
        var unresolved: [String] = []
        var allUrlsFound = false
        
        permissions.forEach { permission in
            guard let localizedName = localizedPermissionDescription(for: permission, forUpdate: false) else {
                unresolved.append(permission)
                return
            }
            
            if permission == "<all_urls>" {
                allUrlsFound = true
            }
            
            localizedPermissions.append(
                AddonLocalizedPermission(name: permission, localizedName: localizedName, granted: granted.contains(permission))
            )
        }
        
        if !allUrlsFound {
            unresolved.forEach { permission in
                guard let localizedName = localizeHostPermission(permission, forUpdate: false) else {
                    return
                }
                
                localizedPermissions.append(
                    AddonLocalizedPermission(name: permission, localizedName: localizedName, granted: granted.contains(permission))
                )
            }
        }
        
        return localizedPermissions
    }
    
    public static func localizeOptionalOrigins(
        _ origins: [String],
        grantedOrigins: [String]
    ) -> [AddonLocalizedPermission] {
        let granted = Set(grantedOrigins)
        var localizedOrigins: [AddonLocalizedPermission] = []
        var seen = Set<String>()
        
        origins.forEach { origin in
            guard !seen.contains(origin),
                  let localizedName = localizeHostPermission(origin, forUpdate: false) else {
                return
            }
            
            seen.insert(origin)
            localizedOrigins.append(
                AddonLocalizedPermission(name: origin, localizedName: localizedName, granted: granted.contains(origin))
            )
        }
        
        return localizedOrigins
    }
    
    public static func localizeDataCollectionPermissions(_ permissions: [String]) -> [String] {
        permissions.compactMap { dataCollectionShortDescriptions[$0] }
    }
    
    public static func localizeOptionalDataCollectionPermissions(
        _ permissions: [String],
        grantedPermissions: [String]
    ) -> [AddonLocalizedPermission] {
        let granted = Set(grantedPermissions)
        return permissions.compactMap { permission in
            guard let localizedName = dataCollectionLongDescriptions[permission] else {
                return nil
            }
            
            return AddonLocalizedPermission(name: permission, localizedName: localizedName, granted: granted.contains(permission))
        }
    }
    
    public static func formatLocalizedDataCollectionPermissions(_ localizedPermissions: [String]) -> String {
        ListFormatter.localizedString(byJoining: localizedPermissions)
    }
    
    public static func requiredDataCollectionDescription(for permissions: [String]) -> String? {
        if permissions.count == 1, permissions.contains("none") {
            return noDataCollectionRequiredDescription
        }
        
        let localizedPermissions = localizeDataCollectionPermissions(permissions)
        guard !localizedPermissions.isEmpty else {
            return nil
        }
        
        return "The developer says this extension collects: \(formatLocalizedDataCollectionPermissions(localizedPermissions))"
    }
    
    public static func optionalDataCollectionDescription(for permissions: [String]) -> String? {
        let localizedPermissions = localizeDataCollectionPermissions(permissions)
        guard !localizedPermissions.isEmpty else {
            return nil
        }
        
        return "The developer says the extension wants to collect: \(formatLocalizedDataCollectionPermissions(localizedPermissions))"
    }
    
    public static func updateDataCollectionDescription(for permissions: [String]) -> String? {
        let localizedPermissions = localizeDataCollectionPermissions(permissions)
        guard !localizedPermissions.isEmpty else {
            return nil
        }
        
        return "New required data collection: The developer says the extension will collect \(formatLocalizedDataCollectionPermissions(localizedPermissions))."
    }
    
    public static func updatePermissionDescription(for permissions: [String]) -> String? {
        let localizedPermissions = localizePermissions(permissions, forUpdate: true)
        guard !localizedPermissions.isEmpty else {
            return nil
        }
        
        return "New required permissions: \(localizedPermissions.joined(separator: " "))"
    }
    
    public static func permissionsListContainsAllUrls(_ permissions: [String]) -> Bool {
        permissions.contains { hostPermissionKind(for: $0) == .allUrls }
    }
    
    public static func allSiteOriginPermissions(_ origins: [String]) -> [String] {
        origins.filter { hostPermissionKind(for: $0) == .allUrls }
    }
    
    public static func classifyOriginPermissions(_ origins: [String]) -> AddonHostPermissions {
        var allUrls: String?
        var wildcards: [String] = []
        var sites: [String] = []
        
        origins.forEach { permission in
            if permission == "<all_urls>" {
                if allUrls == nil {
                    allUrls = permission
                }
                return
            }
            
            guard let translation = hostPermissionKind(for: permission) else {
                return
            }
            
            switch translation {
            case .allUrls:
                if allUrls == nil {
                    allUrls = permission
                }
            case .domain(let host):
                if !wildcards.contains(host) {
                    wildcards.append(host)
                }
            case .site(let host):
                if !sites.contains(host) {
                    sites.append(host)
                }
            }
        }
        
        return AddonHostPermissions(allUrls: allUrls, wildcards: wildcards, sites: sites)
    }
    
    public static func localizeHostPermission(_ permission: String, forUpdate: Bool) -> String? {
        switch hostPermissionKind(for: permission) {
        case .allUrls:
            return forUpdate ? "访问你在所有网站上的数据。" : "访问你在所有网站上的数据"
        case .domain(let host):
            let description = "访问你在 \(host) 域名下网站的数据"
            return forUpdate ? description + "." : description
        case .site(let host):
            let description = "访问你在 \(host) 上的数据"
            return forUpdate ? description + "." : description
        case nil:
            return nil
        }
    }
    
    private static func localizedPermissionDescription(for permission: String, forUpdate: Bool) -> String? {
        guard let description = permissionDescriptions[permission] else {
            return nil
        }
        
        return forUpdate ? description + "." : description
    }
    
    private static func localizeURLAccessPermissions(_ accessPermissions: [String], forUpdate: Bool) -> [String] {
        var permissionsToTranslations: [(String, AddonHostPermissionKind)] = []
        var seenPermissions = Set<String>()
        
        accessPermissions.forEach { permission in
            guard !seenPermissions.contains(permission),
                  let translation = hostPermissionKind(for: permission) else {
                return
            }
            
            seenPermissions.insert(permission)
            permissionsToTranslations.append((permission, translation))
        }
        
        if permissionsToTranslations.contains(where: { _, translation in
            if case .allUrls = translation {
                return true
            }
            return false
        }) {
            return [forUpdate ? "访问你在所有网站上的数据。" : "访问你在所有网站上的数据"]
        }
        
        return formatURLAccessPermissions(permissionsToTranslations, forUpdate: forUpdate)
    }
    
    private static func formatURLAccessPermissions(
        _ permissionsToTranslations: [(String, AddonHostPermissionKind)],
        forUpdate: Bool
    ) -> [String] {
        let maxShownPermissionsEntries = forUpdate ? 2 : 4
        var localizedSiteAccessPermissions: [String] = []
        var domainCount = 0
        var siteCount = 0
        
        for (_, translation) in permissionsToTranslations {
            switch translation {
            case .allUrls:
                continue
            case .domain(let host):
                domainCount += 1
                guard domainCount <= maxShownPermissionsEntries else {
                    continue
                }
                let description = "访问你在 \(host) 域名下网站的数据"
                localizedSiteAccessPermissions.append(forUpdate ? description + "." : description)
            case .site(let host):
                siteCount += 1
                guard siteCount <= maxShownPermissionsEntries else {
                    continue
                }
                let description = "访问你在 \(host) 上的数据"
                localizedSiteAccessPermissions.append(forUpdate ? description + "." : description)
            }
        }
        
        if domainCount > maxShownPermissionsEntries {
            if domainCount - maxShownPermissionsEntries == 1 {
                localizedSiteAccessPermissions.append(forUpdate ? "访问你在另一个域名上的数据。" : "访问你在另一个域名上的数据")
            } else {
                localizedSiteAccessPermissions.append(forUpdate ? "访问你在其他域名上的数据。" : "访问你在其他域名上的数据")
            }
        }
        
        if siteCount > maxShownPermissionsEntries {
            if siteCount - maxShownPermissionsEntries == 1 {
                localizedSiteAccessPermissions.append(forUpdate ? "访问你在另一个网站上的数据。" : "访问你在另一个网站上的数据")
            } else {
                localizedSiteAccessPermissions.append(forUpdate ? "访问你在其他网站上的数据。" : "访问你在其他网站上的数据")
            }
        }
        
        return localizedSiteAccessPermissions
    }
    
    private static func hostPermissionKind(for urlAccess: String) -> AddonHostPermissionKind? {
        if urlAccess == "<all_urls>" {
            return .allUrls
        }
        
        guard let schemeRange = urlAccess.range(of: "://") else {
            return nil
        }
        
        let scheme = urlAccess[..<schemeRange.lowerBound]
        if scheme != "*" && scheme != "http" && scheme != "https" && scheme != "ws" && scheme != "wss" && scheme != "file" {
            return nil
        }
        
        let hostAndPath = urlAccess[schemeRange.upperBound...]
        let parts = hostAndPath.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        let host = parts.first.map(String.init) ?? ""
        let path = parts.count > 1 ? "/" + parts[1] : ""
        
        switch true {
        case host == "*":
            return .allUrls
        case host.isEmpty || path.isEmpty:
            return nil
        case host.hasPrefix("*."):
            return .domain(String(host.dropFirst(2)))
        default:
            return .site(host)
        }
    }
}
