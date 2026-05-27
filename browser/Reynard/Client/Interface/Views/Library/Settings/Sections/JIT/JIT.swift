//
//  JIT.swift
//  Reynard
//
//  Created by Minh Ton on 11/4/26.
//

import UIKit
import UniformTypeIdentifiers
import MobileCoreServices

extension SettingsRootViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        importPairingFile(from: url)
    }
    
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {}
}

extension SettingsRootViewController {
    func makeJITFooterView() -> UIView {
        let footerView = UITableViewHeaderFooterView(reuseIdentifier: nil)
        footerView.contentView.preservesSuperviewLayoutMargins = true
        
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 4
        
        let footerPointSize = UIFont.preferredFont(forTextStyle: .footnote).pointSize
        let statusBoldFont = UIFontMetrics(forTextStyle: .footnote)
            .scaledFont(for: UIFont.systemFont(ofSize: footerPointSize, weight: .semibold))
        
        if isJITLessModeActive {
            let statusLabel = UILabel()
            statusLabel.numberOfLines = 0
            statusLabel.font = statusBoldFont
            statusLabel.adjustsFontForContentSizeCategory = true
            statusLabel.textColor = .systemOrange
            statusLabel.text = "\u{25B2} 当前已启用无 JIT 模式"
            stack.addArrangedSubview(statusLabel)
        }
        
        let detailLabel = UILabel()
        detailLabel.numberOfLines = 0
        detailLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textColor = .secondaryLabel
        detailLabel.text = "启用 JIT 可以显著提升性能，并且是 WebAssembly 等功能所必需的。"
        stack.addArrangedSubview(detailLabel)
        
        // if on 16.6 to 17.3.1, show warning about JIT
        if #available(iOS 16.6, *) {
            if #unavailable(iOS 17.4) {
                let warningLabel = UILabel()
                warningLabel.numberOfLines = 0
                warningLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
                warningLabel.adjustsFontForContentSizeCategory = true
                warningLabel.textColor = .systemRed
                warningLabel.text = "基于配对文件的 JIT 启用方式在你当前的系统版本上可能无法正常工作。你可以在不启用 JIT 的情况下使用浏览器；如果你的 iOS/iPadOS 版本支持 TrollStore，也可以考虑使用 TrollStore 版 IPA。"
                stack.addArrangedSubview(warningLabel)
            }
        }
        
        footerView.contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: footerView.contentView.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: footerView.contentView.layoutMarginsGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: footerView.contentView.layoutMarginsGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: footerView.contentView.layoutMarginsGuide.bottomAnchor),
        ])
        
        return footerView
    }
    
    func presentPairingFilePicker() {
        let picker: UIDocumentPickerViewController
        if #available(iOS 14.0, *) {
            let types = allowedPairingFileTypes()
            picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        } else {
            picker = UIDocumentPickerViewController(documentTypes: allowedPairingDocumentTypeIdentifiers(), in: .import)
        }
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }
    
    func importPairingFile(from url: URL) {
        backgroundQueue.async { [weak self] in
            guard let self else { return }
            do {
                try installPairingFile(from: url)
                DispatchQueue.main.async { self.refreshControls() }
            } catch {
                DispatchQueue.main.async {
                    self.presentAlert(title: "导入失败", message: error.localizedDescription)
                }
            }
        }
    }
    
    @objc func jitSwitchChanged(_ sender: UISwitch) {
        Prefs.JITSettings.isJITEnabled = sender.isOn
        guard sender.isOn else { presentJITRestartAlert(); return }
        guard !DDIManager.shared.hasRequiredDDIFiles() else { presentJITRestartAlert(); return }
        presentDDIDownloadAlert(for: sender)
    }
    
    @objc func handleJITLessModeActivated(_ notification: Notification) {
        refreshControls()
        tableView.reloadData()
    }
    
    func presentDDIDownloadAlert(for sender: UISwitch) {
        sender.isEnabled = false
        let alert = UIAlertController(
            title: "正在准备 JIT",
            message: "这是你第一次启用 JIT，Reynard 需要下载并挂载开发者磁盘镜像。这是 JIT 正常工作所必需的。",
            preferredStyle: .alert
        )
        let progressView = UIProgressView(progressViewStyle: .default)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.progress = 0
        let token = UUID()
        activeDDIDownloadToken = token
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in
            self?.cancelDDIDownload(for: sender, token: token)
        })
        present(alert, animated: true) { [weak self] in
            self?.attachProgressView(progressView, to: alert)
            self?.startDDIDownload(for: sender, alert: alert, progressView: progressView, token: token)
        }
    }
    
    func attachProgressView(_ progressView: UIProgressView, to alert: UIAlertController) {
        guard let messageText = alert.message,
              let messageLabel = alert.view.firstDescendantLabel(withText: messageText) else { return }
        alert.view.addSubview(progressView)
        let cancelAnchorView: UIView? = {
            if let button = alert.view.firstDescendantButton(withTitle: "取消") { return button }
            return alert.view.firstDescendantView(containingLabelText: "取消")
        }()
        var constraints = [
            progressView.widthAnchor.constraint(equalTo: messageLabel.widthAnchor),
            progressView.centerXAnchor.constraint(equalTo: messageLabel.centerXAnchor),
            progressView.topAnchor.constraint(greaterThanOrEqualTo: messageLabel.bottomAnchor, constant: 12),
        ]
        if let cancelAnchorView {
            let verticalGuide = UILayoutGuide()
            alert.view.addLayoutGuide(verticalGuide)
            constraints.append(contentsOf: [
                verticalGuide.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 16),
                verticalGuide.bottomAnchor.constraint(equalTo: cancelAnchorView.topAnchor, constant: -16),
                progressView.centerYAnchor.constraint(equalTo: verticalGuide.centerYAnchor),
            ])
        } else {
            constraints.append(progressView.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 20))
        }
        NSLayoutConstraint.activate(constraints)
    }
    
    func startDDIDownload(for sender: UISwitch, alert: UIAlertController, progressView: UIProgressView, token: UUID) {
        DDIManager.shared.ensureRequiredDDIFiles(
            progress: { [weak self] value in
                guard let self, self.activeDDIDownloadToken == token else { return }
                progressView.setProgress(Float(value), animated: true)
            },
            completion: { [weak self] result in
                guard let self, self.activeDDIDownloadToken == token else { return }
                self.activeDDIDownloadToken = nil
                sender.isEnabled = Prefs.JITSettings.hasPairingFile
                switch result {
                case .success:
                    self.dismissAlertIfPresented(alert) { self.presentJITRestartAlert() }
                case .failure(let error):
                    Prefs.JITSettings.isJITEnabled = false
                    sender.setOn(false, animated: true)
                    self.dismissAlertIfPresented(alert) {
                        self.presentAlert(title: "下载失败", message: error.localizedDescription)
                    }
                }
            }
        )
    }
    
    func cancelDDIDownload(for sender: UISwitch, token: UUID) {
        guard activeDDIDownloadToken == token else { return }
        activeDDIDownloadToken = nil
        DDIManager.shared.cancelActiveDownload()
        Prefs.JITSettings.isJITEnabled = false
        sender.setOn(false, animated: true)
        sender.isEnabled = Prefs.JITSettings.hasPairingFile
    }
    
    func dismissAlertIfPresented(_ alert: UIAlertController, completion: @escaping () -> Void) {
        guard presentedViewController === alert else { completion(); return }
        alert.dismiss(animated: true, completion: completion)
    }
    
    func presentJITRestartAlert() {
        let alert = UIAlertController(
            title: "需要重启",
            message: "应用即将关闭，以便 JIT 设置生效。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(1)) {
                exit(EXIT_SUCCESS)
            }
        })
        present(alert, animated: true)
    }
}

@available(iOS 14.0, *)
func allowedPairingFileTypes() -> [UTType] {
    var types = [UTType.propertyList]
    ["mobiledevicepairing", "mobiledevicepair", "plist"].forEach { ext in
        if let type = UTType(filenameExtension: ext), !types.contains(type) {
            types.append(type)
        }
    }
    return types
}

func allowedPairingDocumentTypeIdentifiers() -> [String] {
    var identifiers = [kUTTypePropertyList as String]
    ["mobiledevicepairing", "mobiledevicepair", "plist"].forEach { ext in
        if let uti = UTTypeCreatePreferredIdentifierForTag(
            kUTTagClassFilenameExtension,
            ext as CFString,
            nil
        )?.takeRetainedValue() as String?,
           !identifiers.contains(uti) {
            identifiers.append(uti)
        }
    }
    return identifiers
}
func installPairingFile(from sourceURL: URL) throws {
    let fileManager = FileManager.default
    let destinationURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("pairingFile.plist", isDirectory: false)
    try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    
    let normalizedSourceURL = sourceURL.standardizedFileURL
    let normalizedDestinationURL = destinationURL.standardizedFileURL
    
    guard normalizedSourceURL != normalizedDestinationURL else {
        Prefs.JITSettings.isJITEnabled = false
        return
    }
    
    if fileManager.fileExists(atPath: normalizedDestinationURL.path) {
        try fileManager.removeItem(at: normalizedDestinationURL)
    }
    
    try fileManager.copyItem(at: normalizedSourceURL, to: normalizedDestinationURL)
    Prefs.JITSettings.isJITEnabled = false
}
