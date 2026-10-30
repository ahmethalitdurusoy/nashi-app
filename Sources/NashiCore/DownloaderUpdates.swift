import Foundation

/// Sites change their pages often, so a fixed yt-dlp stops working within
/// months. The copy UForge installed is kept current with yt-dlp's own
/// updater, which downloads the official GitHub release and checks it against
/// that release's SHA2-256SUMS before replacing the file. Only the managed
/// copy is touched: a Homebrew or bundled yt-dlp belongs to someone else.
public enum DownloaderUpdates {
    static let checkedKey = "downloaderLastUpdateCheck"
    static let interval: TimeInterval = 7 * 24 * 3600
    private static let lock = NSLock()

    /// The yt-dlp that downloads actually use, when it is the managed copy.
    static var managedCopy: URL? {
        guard let managed = ExternalToolSetup.executable("yt-dlp"),
              let used = try? Dependencies.executable("yt-dlp"),
              used.resolvingSymlinksInPath() == managed.resolvingSymlinksInPath() else { return nil }
        return managed
    }

    /// The weekly check, run in the background at launch.
    public static func refreshIfDue(now: Date = Date(), defaults: UserDefaults = .standard) {
        if let last = defaults.object(forKey: checkedKey) as? Date, now.timeIntervalSince(last) < interval { return }
        _ = refresh(defaults: defaults)
    }

    /// Updates the managed yt-dlp. Returns true when a newer version was
    /// installed; false when it was already current, not managed by UForge,
    /// another update was running, or the update failed (the old copy stays).
    @discardableResult
    public static func refresh(defaults: UserDefaults = .standard, token: CancellationToken = .init()) -> Bool {
        guard let executable = managedCopy, lock.try() else { return false }
        defer { lock.unlock() }
        let before = version(executable, token: token)
        guard (try? WebDownloadProcess.run(executable, ["--ignore-config", "--no-plugin-dirs", "--update-to", "stable"], token: token, timeout: 180)) != nil else { return false }
        defaults.set(Date(), forKey: checkedKey)
        let after = version(executable, token: token)
        return after != nil && after != before
    }

    static func version(_ executable: URL, token: CancellationToken) -> String? {
        (try? WebDownloadProcess.run(executable, ["--version"], token: token, timeout: 30)).map { String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    /// Runs a yt-dlp step; when it fails for a reason other than cancellation
    /// or an unsupported link, updates yt-dlp once and, if a newer version was
    /// installed, tries again (a broken extractor is the usual cause).
    static func retryingAfterUpdate<T>(token: CancellationToken, _ operation: () async throws -> T) async throws -> T {
        do { return try await operation() } catch {
            if token.isCancelled || error is CancellationError { throw error }
            if case NashiError.unsupported = error { throw error }
            if case NashiError.invalidInput = error { throw error }
            let updated = await Task.detached { refresh(token: token) }.value
            try token.check(); try Task.checkCancellation()
            guard updated else { throw error }
            return try await operation()
        }
    }
}
