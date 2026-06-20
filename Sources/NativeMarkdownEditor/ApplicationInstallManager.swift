import AppKit
import Foundation

enum ApplicationInstallManager {
    static let skippedPromptKey = "MoyeSkippedMoveToApplicationsPrompt"

    static func applicationsDirectoryURL(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .applicationDirectory, in: .localDomainMask).first
            ?? URL(fileURLWithPath: "/Applications", isDirectory: true)
    }

    static func destinationURL(
        for bundleURL: URL = Bundle.main.bundleURL,
        applicationsDirectory: URL = applicationsDirectoryURL()
    ) -> URL {
        applicationsDirectory.appendingPathComponent(bundleURL.lastPathComponent, isDirectory: true)
    }

    static func shouldOfferMoveToApplications(
        bundleURL: URL = Bundle.main.bundleURL,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier,
        applicationsDirectory: URL = applicationsDirectoryURL()
    ) -> Bool {
        guard bundleURL.pathExtension == "app" else {
            return false
        }
        guard bundleIdentifier != "org.moyesource.moye.dev" else {
            return false
        }
        return !isInsideApplications(bundleURL: bundleURL, applicationsDirectory: applicationsDirectory)
    }

    static func isInsideApplications(bundleURL: URL, applicationsDirectory: URL) -> Bool {
        let appPath = bundleURL.standardizedFileURL.path
        let applicationsPath = applicationsDirectory.standardizedFileURL.path
        return appPath == applicationsPath || appPath.hasPrefix(applicationsPath + "/")
    }

    static func installToApplications(
        bundleURL: URL = Bundle.main.bundleURL,
        applicationsDirectory: URL = applicationsDirectoryURL(),
        fileManager: FileManager = .default
    ) throws -> URL {
        let destination = destinationURL(for: bundleURL, applicationsDirectory: applicationsDirectory)
        let temporaryDestination = applicationsDirectory
            .appendingPathComponent(".\(bundleURL.deletingPathExtension().lastPathComponent)-installing-\(UUID().uuidString).app", isDirectory: true)

        if fileManager.fileExists(atPath: temporaryDestination.path) {
            try fileManager.removeItem(at: temporaryDestination)
        }
        try fileManager.copyItem(at: bundleURL, to: temporaryDestination)

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporaryDestination, to: destination)
        return destination
    }

    @MainActor
    static func offerMoveToApplicationsIfNeeded(language: AppLanguage) {
        guard shouldOfferMoveToApplications() else {
            return
        }
        guard !UserDefaults.standard.bool(forKey: skippedPromptKey) else {
            return
        }

        let strings = InstallPromptStrings(language: language)
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = strings.title
        alert.informativeText = strings.message
        alert.addButton(withTitle: strings.moveButton)
        alert.addButton(withTitle: strings.laterButton)

        guard alert.runModal() == .alertFirstButtonReturn else {
            UserDefaults.standard.set(true, forKey: skippedPromptKey)
            return
        }

        do {
            let installedURL = try installToApplications()
            relaunchInstalledApp(at: installedURL)
        } catch {
            showInstallFailure(error: error, language: language)
        }
    }

    @MainActor
    private static func relaunchInstalledApp(at url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            NSApp.terminate(nil)
        }
    }

    @MainActor
    private static func showInstallFailure(error: Error, language: AppLanguage) {
        let strings = InstallPromptStrings(language: language)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = strings.failureTitle
        alert.informativeText = "\(strings.failureMessage)\n\n\(error.localizedDescription)"
        alert.addButton(withTitle: strings.okButton)
        alert.runModal()
    }
}

struct InstallPromptStrings {
    let title: String
    let message: String
    let moveButton: String
    let laterButton: String
    let failureTitle: String
    let failureMessage: String
    let okButton: String

    init(language: AppLanguage) {
        switch language {
        case .chinese:
            title = "移动到“应用程序”文件夹？"
            message = "建议将墨页移动到“应用程序”文件夹。这样以后可以从启动台、Finder 和自动更新流程中正常打开。"
            moveButton = "移动并重新打开"
            laterButton = "稍后"
            failureTitle = "无法移动到“应用程序”"
            failureMessage = "请确认你有权限写入“应用程序”文件夹，或手动将墨页拖入“应用程序”。"
            okButton = "好"
        case .english:
            title = "Move to Applications Folder?"
            message = "Moye works best from the Applications folder. This keeps Launchpad, Finder, and future update flows consistent."
            moveButton = "Move and Relaunch"
            laterButton = "Later"
            failureTitle = "Could Not Move to Applications"
            failureMessage = "Make sure you have permission to write to the Applications folder, or move Moye there manually."
            okButton = "OK"
        }
    }
}
