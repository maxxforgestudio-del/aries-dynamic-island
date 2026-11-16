import AppKit

struct DownloadItem: Identifiable, Equatable {
    let id: String          // path of the in-progress file
    var name: String
    var bytes: Int64
    var total: Int64?
    var progress: Double? { total.flatMap { $0 > 0 ? min(1, Double(bytes) / Double($0)) : nil } }
}

/// Watches ~/Downloads for files that are still downloading (Safari, Chrome, Edge,
/// Brave, Arc, Firefox, Opera) and reports progress and completion.
final class DownloadsMonitor: ObservableObject {
    @Published private(set) var active: [DownloadItem] = []
    var onFinished: ((URL) -> Void)?

    private let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var timer: Timer?
    private var known: [String: String] = [:]   // in-progress path → final name

    private static let partialExtensions = ["crdownload", "download", "part", "opdownload", "partial"]

    var current: DownloadItem? { active.first }

    func debugSet(_ items: [DownloadItem]) { active = items }

    func setEnabled(_ on: Bool) {
        on ? start() : stop()
    }

    private let io = DispatchQueue(label: "aries.downloads", qos: .utility)
    private var starting = false

    /// Opening ~/Downloads can show a macOS permission prompt and block until it's answered,
    /// so everything that touches the folder runs off the main thread.
    private func start() {
        guard source == nil, !starting else { return }
        starting = true
        io.async { [weak self] in
            guard let self else { return }
            let fd = open(self.dir.path, O_EVTONLY)
            DispatchQueue.main.async {
                self.starting = false
                guard fd >= 0, self.source == nil else { if fd >= 0 { close(fd) }; return }
                self.fd = fd
                let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
                s.setEventHandler { [weak owner = self] in owner?.scan() }
                s.setCancelHandler { close(fd) }
                s.resume()
                self.source = s
                self.timer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak owner = self] _ in
                    guard let owner, !owner.active.isEmpty else { return }
                    owner.scan()
                }
                self.scan()
            }
        }
    }

    private func stop() {
        source?.cancel(); source = nil
        timer?.invalidate(); timer = nil
        active = []; known = [:]
    }

    private var scanning = false

    private func scan() {
        guard !scanning else { return }
        scanning = true
        let known = self.known
        io.async { [weak self] in
            guard let self else { return }
            let (found, newKnown, finished) = self.collect(known: known)
            DispatchQueue.main.async {
                self.scanning = false
                self.known = newKnown
                finished.forEach { self.onFinished?($0) }
                if found != self.active { self.active = found }
            }
        }
    }

    private func collect(known startKnown: [String: String]) -> ([DownloadItem], [String: String], [URL]) {
        var known = startKnown
        var finished: [URL] = []
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey, .totalFileAllocatedSizeKey]) else { return ([], known, []) }
        var found: [DownloadItem] = []
        for url in entries where Self.partialExtensions.contains(url.pathExtension.lowercased()) {
            var name = url.deletingPathExtension().lastPathComponent
            var bytes: Int64 = 0
            var total: Int64?
            if url.pathExtension.lowercased() == "download" {
                // Safari keeps progress inside the .download bundle.
                let info = url.appendingPathComponent("Info.plist")
                if let d = NSDictionary(contentsOf: info) {
                    bytes = (d["DownloadEntryProgressBytesSoFar"] as? NSNumber)?.int64Value ?? 0
                    total = (d["DownloadEntryProgressTotalToLoad"] as? NSNumber)?.int64Value
                    if let p = d["DownloadEntryPath"] as? String { name = (p as NSString).lastPathComponent }
                }
            } else {
                bytes = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            }
            // Chrome names files "Unconfirmed 1234.crdownload" until the name is known.
            if name.hasPrefix("Unconfirmed ") { name = "Downloading…" }
            found.append(DownloadItem(id: url.path, name: name, bytes: bytes, total: total))
            known[url.path] = name
        }

        // Anything that was in progress and is gone now has finished (or was cancelled).
        let stillThere = Set(found.map(\.id))
        for (path, name) in known where !stillThere.contains(path) {
            known[path] = nil
            let final = dir.appendingPathComponent(name)
            if fm.fileExists(atPath: final.path) { finished.append(final) }
        }
        return (found, known, finished)
    }

    static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
