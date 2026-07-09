import AppKit
import Sparkle

@MainActor
final class UpdateController: NSObject, SPUUserDriver, SPUUpdaterDelegate {
    private let state: AppState
    private lazy var updater = SPUUpdater(
        hostBundle: Bundle.main,
        applicationBundle: Bundle.main,
        userDriver: self,
        delegate: self
    )

    private var updateReply: ((SPUUserUpdateChoice) -> Void)?
    private var readyReply: ((SPUUserUpdateChoice) -> Void)?
    private var cancelDownload: (() -> Void)?
    private var expectedDownloadLength: UInt64 = 0
    private var receivedDownloadLength: UInt64 = 0

    init(state: AppState) {
        self.state = state
        super.init()
        state.onCheckForUpdates = { [weak self] in self?.checkForUpdates() }
        state.onInstallUpdate = { [weak self] in self?.installUpdate() }
        state.onDismissUpdate = { [weak self] in self?.dismissUpdate() }
        state.onSkipUpdate = { [weak self] in self?.skipUpdate() }
        state.onRestartForUpdate = { [weak self] in self?.restartForUpdate() }
    }

    func start() {
        do {
            try updater.start()
            if updater.automaticallyChecksForUpdates {
                updater.checkForUpdatesInBackground()
            }
        } catch {
            state.setUpdateError("更新器启动失败：\(error.localizedDescription)")
        }
    }

    @objc func checkForUpdates() {
        guard updater.canCheckForUpdates else {
            state.openUpdateDialog()
            return
        }
        updater.checkForUpdates()
    }

    private func installUpdate() {
        if let readyReply {
            state.setUpdateInstalling()
            self.readyReply = nil
            readyReply(.install)
            return
        }
        guard let updateReply else { return }
        state.setUpdateDownloadProgress(0)
        self.updateReply = nil
        updateReply(.install)
    }

    private func dismissUpdate() {
        if let readyReply {
            self.readyReply = nil
            readyReply(.dismiss)
        } else if let updateReply {
            self.updateReply = nil
            updateReply(.dismiss)
        }
        cancelDownload = nil
        state.clearUpdate()
    }

    private func skipUpdate() {
        if let readyReply {
            self.readyReply = nil
            readyReply(.skip)
        } else if let updateReply {
            self.updateReply = nil
            updateReply(.skip)
        }
        cancelDownload = nil
        state.clearUpdate()
    }

    private func restartForUpdate() {
        guard let readyReply else { return }
        state.setUpdateInstalling()
        self.readyReply = nil
        readyReply(.install)
    }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, automaticUpdateDownloading: false, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        state.setUpdateChecking()
        state.openUpdateDialog()
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state updateState: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        updateReply = reply
        readyReply = nil
        let notes = plainNotes(from: appcastItem.itemDescription)
        state.setUpdateAvailable(
            version: appcastItem.displayVersionString,
            title: appcastItem.title ?? "Todo Capsule \(appcastItem.displayVersionString)",
            notes: notes
        )
        if updateState.userInitiated {
            state.openUpdateDialog()
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        state.setUpdateError("当前已经是最新版本。")
        state.openUpdateDialog()
        acknowledgement()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        state.setUpdateError(error.localizedDescription)
        state.openUpdateDialog()
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        cancelDownload = cancellation
        expectedDownloadLength = 0
        receivedDownloadLength = 0
        state.setUpdateDownloadProgress(0)
        state.openUpdateDialog()
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedDownloadLength = expectedContentLength
        receivedDownloadLength = 0
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedDownloadLength += length
        guard expectedDownloadLength > 0 else { return }
        state.setUpdateDownloadProgress(Double(receivedDownloadLength) / Double(expectedDownloadLength))
    }

    func showDownloadDidStartExtractingUpdate() {
        state.setUpdateDownloadProgress(1)
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        state.setUpdateDownloadProgress(progress)
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        readyReply = reply
        state.setUpdateReady()
        state.openUpdateDialog()
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        state.setUpdateInstalling()
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func dismissUpdateInstallation() {
        if state.updateInfo?.phase != .readyToRestart {
            cancelDownload = nil
        }
    }

    func showUpdateInFocus() {
        state.openUpdateDialog()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        state.setUpdateError(error.localizedDescription)
    }

    private func plainNotes(from raw: String?) -> String {
        guard var text = raw, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "这个版本包含改进和修复。"
        }
        text = text.replacingOccurrences(of: "<br>", with: "\n")
        text = text.replacingOccurrences(of: "<br/>", with: "\n")
        text = text.replacingOccurrences(of: "<br />", with: "\n")
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
