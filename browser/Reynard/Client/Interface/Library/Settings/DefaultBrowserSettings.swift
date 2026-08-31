//
//  DefaultBrowserSettings.swift
//  Reynard
//
//  Created by OpenAI Codex on 29/8/26.
//

import UIKit

enum DefaultBrowserSettings {
    private static let entitlement = "com.apple.developer.web-browser"

    static var hasRequiredEntitlement: Bool {
        return getEntitlementValue(entitlement)
    }

    static var statusText: String {
        guard #available(iOS 14.0, *) else {
            return localized("Requires iOS 14 or later")
        }

        return hasRequiredEntitlement ?
        localized("Open iOS Settings") :
        localized("Compatible signature required")
    }

    static func open() {
        guard #available(iOS 14.0, *) else {
            AlertPresenter.show(
                title: localized("Default Browser Unavailable"),
                message: localized("iOS 14 or later is required to choose a third-party default browser.")
            )
            return
        }

        guard hasRequiredEntitlement else {
            AlertPresenter.show(
                title: localized("Default Browser Permission Required"),
                message: localized(
                    "This installation does not contain Apple's managed default-browser entitlement. Reynard can open incoming links, but it will not appear in the system browser list until it is signed with that entitlement."
                ),
                buttons: [
                    AlertPresenter.Button(
                        title: NSLocalizedString("Cancel", comment: ""),
                        style: .cancel
                    ),
                    AlertPresenter.Button(title: localized("Open Settings Anyway")) {
                        openSystemSettings()
                    },
                ]
            )
            return
        }

        openSystemSettings()
    }

    private static func openSystemSettings() {
        let settingsURLString: String
        if #available(iOS 18.3, *) {
            settingsURLString = UIApplication.openDefaultApplicationsSettingsURLString
        } else {
            settingsURLString = UIApplication.openSettingsURLString
        }

        guard let settingsURL = URL(string: settingsURLString) else {
            return
        }
        UIApplication.shared.open(settingsURL)
    }

    private static func localized(_ key: String) -> String {
        return NSLocalizedString(key, tableName: "SettingsLocalizable", comment: "")
    }
}
