import AppKit
import SwiftUI

/// Patch notes that update remotely, without shipping a new version of the app.
///
/// The notes live in `docs/patch-notes.json` in the GitHub repo, which GitHub Pages serves at
/// `patchNotesURL`. Edit that file and push, and every copy of Aries picks up the new notes within
/// a few hours (or right away with Refresh). A copy is kept on disk so they work offline too.
final class PatchNotes: ObservableObject {
    static let shared = PatchNotes()
    static let feedURL = URL(string: "https://maxxforgestudio-del.github.io/aries-dynamic-island/patch-notes.json")!

    struct Item: Codable, Hashable, Identifiable {
        var id: String { type + text }
        let type: String          // new | improved | fixed | security | known
        let text: String

        var label: String {
            switch type {
            case "new": return "NEW"
            case "improved": return "IMPROVED"
            case "fixed": return "FIXED"
            case "security": return "SECURITY"
            default: return type.uppercased()
            }
        }
        var color: Color {
            switch type {
            case "new": return .blue
            case "improved": return .purple
            case "fixed": return .green
            case "security": return .orange
            default: return .gray
            }
        }
        var icon: String {
            switch type {
            case "new": return "sparkles"
            case "improved": return "arrow.up.circle.fill"
            case "fixed": return "wrench.and.screwdriver.fill"
            case "security": return "lock.shield.fill"
            default: return "circle.fill"
            }
        }
    }

    struct Entry: Codable, Hashable, Identifiable {
        var id: String { version + date }
        let version: String
        let date: String          // yyyy-MM-dd
        let title: String?
        let items: [Item]
    }

    struct Feed: Codable, Equatable {
        let updated: String       // yyyy-MM-dd — bump it whenever the notes change
        let schedule: String?
        let knownIssues: [String]?
        let entries: [Entry]
        /// Optional: where Help and Report a Bug send people (an https link).
        let supportURL: String?
    }

    @Published private(set) var feed: Feed?
    @Published private(set) var loading = false
    @Published private(set) var lastError: String?
    /// True when the notes changed since you last opened Patch Notes.
    @Published private(set) var hasUnread = false

    /// Called when new notes arrive in a background check (to show a little toast).
    var onNew: ((String) -> Void)?
    private var timer: Timer?
    private static let seenKey = "patchNotesSeen"

    private static var cacheFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Aries Dynamic Island/patch-notes.json")
    }

    init() {
        if let d = try? Data(contentsOf: Self.cacheFile), let f = try? JSONDecoder().decode(Feed.self, from: d) {
            feed = f
            hasUnread = f.updated > (UserDefaults.standard.string(forKey: Self.seenKey) ?? "")
        }
    }

    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in self?.refresh(background: true) }
        timer = Timer.scheduledTimer(withTimeInterval: 4 * 3600, repeats: true) { [weak self] _ in
            self?.refresh(background: true)
        }
    }

    func refresh(background: Bool = false) {
        guard !loading else { return }
        loading = true
        var req = URLRequest(url: Self.feedURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.setValue("AriesDynamicIsland/\(Updater.currentVersion)", forHTTPHeaderField: "User-Agent")
        Task {
            let result = try? await URLSession.shared.data(for: req)
            let ok = (result?.1 as? HTTPURLResponse)?.statusCode == 200
            let f = ok ? result.flatMap { try? JSONDecoder().decode(Feed.self, from: $0.0) } : nil
            await MainActor.run {
                self.loading = false
                guard let f, let data = result?.0 else {
                    if !background { self.lastError = "Couldn't load patch notes. Showing the last saved copy." }
                    return
                }
                self.lastError = nil
                let changed = f != self.feed
                self.feed = f
                try? FileManager.default.createDirectory(at: Self.cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: Self.cacheFile, options: .atomic)
                let seen = UserDefaults.standard.string(forKey: Self.seenKey)
                if seen == nil {
                    // First run: nothing is "new" yet.
                    UserDefaults.standard.set(f.updated, forKey: Self.seenKey)
                } else if f.updated > seen! {
                    self.hasUnread = true
                    if background && changed && Prefs.bool(Prefs.patchNotesToast) { self.onNew?(f.entries.first?.version ?? "") }
                }
            }
        }
    }

    func markRead() {
        guard let f = feed else { return }
        UserDefaults.standard.set(f.updated, forKey: Self.seenKey)
        hasUnread = false
    }

    /// The MAXX FORGE STUDIO help page (or wherever the patch notes feed says), with the app and
    /// macOS version attached so the site can fill them in. Nothing personal is sent.
    static func supportURL(topic: String? = nil) -> URL {
        var base = Brand.defaultSupport
        if let s = shared.feed?.supportURL, let u = URL(string: s), u.scheme == "https" { base = u }
        var c = URLComponents(url: base, resolvingAgainstBaseURL: false) ?? URLComponents(url: Brand.defaultSupport, resolvingAgainstBaseURL: false)!
        let v = ProcessInfo.processInfo.operatingSystemVersion
        var q = c.queryItems ?? []
        q += [.init(name: "app", value: "aries"), .init(name: "version", value: Updater.currentVersion),
              .init(name: "macos", value: "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)")]
        if let topic { q.append(.init(name: "topic", value: topic)) }
        c.queryItems = q
        return c.url ?? base
    }

    static var reportBugURL: URL { supportURL(topic: "bug") }

    static func prettyDate(_ ymd: String) -> String {
        let p = DateFormatter(); p.dateFormat = "yyyy-MM-dd"; p.locale = Locale(identifier: "en_US_POSIX")
        guard let d = p.date(from: ymd) else { return ymd }
        return d.formatted(date: .abbreviated, time: .omitted)
    }
}

// MARK: - Settings pane

struct PatchNotesPane: View {
    @ObservedObject var notes: PatchNotes
    @AppStorage(Prefs.patchNotesToast) private var toast = true

    var body: some View {
        Form {
            Section {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 22)).foregroundStyle(.teal)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("You're on Aries \(Updater.currentVersion)").font(.system(size: 13.5, weight: .semibold))
                        Text(notes.feed?.schedule ?? "New patch notes are posted every 1–2 weeks.")
                            .font(.caption).foregroundStyle(.secondary)
                        if let u = notes.feed?.updated {
                            Text("Last updated \(PatchNotes.prettyDate(u))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if notes.loading { ProgressView().controlSize(.small) }
                    Button("Refresh") { notes.refresh() }.controlSize(.small)
                }
                if let e = notes.lastError {
                    Label(e, systemImage: "wifi.exclamationmark").font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    Button { NSWorkspace.shared.open(PatchNotes.reportBugURL) } label: {
                        Label("Report a Bug", systemImage: "ladybug.fill")
                    }
                    Button { NSWorkspace.shared.open(PatchNotes.supportURL()) } label: {
                        Label("Get Help", systemImage: "questionmark.circle.fill")
                    }
                    Button { NSWorkspace.shared.open(URL(string: "https://github.com/\(Updater.repo)/releases")!) } label: {
                        Label("All Releases", systemImage: "arrow.up.right.square")
                    }
                    Spacer()
                    Toggle("Tell me about new notes", isOn: $toast).toggleStyle(.switch).controlSize(.small)
                }
            }

            if let issues = notes.feed?.knownIssues, !issues.isEmpty {
                Section {
                    ForEach(issues, id: \.self) { i in
                        Label { Text(i) } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow) }
                    }
                } header: {
                    Text("Known issues")
                } footer: {
                    Text("We're working on these. If something else is wrong, tap Report a Bug — it opens the MAXX FORGE STUDIO help page.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if let entries = notes.feed?.entries, !entries.isEmpty {
                ForEach(entries) { e in
                    Section {
                        ForEach(e.items) { it in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(it.label)
                                    .font(.system(size: 9.5, weight: .heavy)).tracking(0.5)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6).padding(.vertical, 2.5)
                                    .background(Capsule().fill(it.color))
                                    .frame(width: 78, alignment: .leading)
                                Text(it.text).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    } header: {
                        HStack {
                            Text("Version \(e.version)\(e.title.map { " — \($0)" } ?? "")")
                            Spacer()
                            Text(PatchNotes.prettyDate(e.date)).foregroundStyle(.secondary)
                        }
                    }
                }
            } else if !notes.loading {
                Section { Text("Patch notes will show up here.").foregroundStyle(.secondary) }
            }
        }
        .onAppear {
            notes.refresh()
            notes.markRead()
        }
    }
}
