import SwiftUI
import AppKit

// MARK: - Notes

struct NotesTab: View {
    @ObservedObject var model: IslandModel
    @ObservedObject var notes: NotesStore
    @ViewState private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.yellow)
                TextField("New note or to-do…", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .focused($focused)
                    .onSubmit(add)
                if !draft.isEmpty {
                    Button("Add", action: add)
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.yellow)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(focused ? 0.12 : 0.08)))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: draft.isEmpty)
            .onTapGesture { AppDelegate.shared.focusIsland(); focused = true }

            if notes.notes.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "note.text").font(.system(size: 24)).foregroundStyle(.yellow.opacity(0.7))
                    Text("Jot things down right from your notch")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 4) {
                        ForEach(notes.sorted) { n in
                            NoteRow(note: n, notes: notes)
                                .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                                        removal: .scale(scale: 0.8).combined(with: .opacity)))
                        }
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.75), value: notes.notes)
                }
                HStack {
                    Text("\(notes.openCount) open · \(notes.notes.count - notes.openCount) done")
                    Spacer()
                    if notes.notes.contains(where: \.done) {
                        Button("Clear done") { withAnimation(.spring) { notes.clearDone() } }.buttonStyle(.plain)
                    }
                }
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .onChange(of: focused) { _, f in model.isEditing = f }
        .onChange(of: model.focusNotes) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { AppDelegate.shared.focusIsland(); focused = true }
        }
        .onAppear {
            if model.focusNotes > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { AppDelegate.shared.focusIsland(); focused = true }
            }
        }
    }

    private func add() {
        guard !draft.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { notes.add(draft) }
        draft = ""
        model.confirm("note.text", "Note saved")
    }
}

private struct NoteRow: View {
    let note: Note
    @ObservedObject var notes: NotesStore
    @ViewState private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            Button { withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { notes.toggle(note) } } label: {
                Image(systemName: note.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15))
                    .foregroundStyle(note.done ? Color.green : .white.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            Text(note.text)
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(note.done ? 0.35 : 0.9))
                .strikethrough(note.done, color: .white.opacity(0.4))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            if note.pinned || hover {
                Button { notes.togglePin(note) } label: {
                    Image(systemName: note.pinned ? "pin.fill" : "pin")
                        .font(.system(size: 11))
                        .foregroundStyle(note.pinned ? .yellow : .white.opacity(0.5))
                }.buttonStyle(.plain)
            }
            if hover {
                Button { notes.copy(note) } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                }.buttonStyle(.plain)
                Button { withAnimation(.spring) { notes.delete(note) } } label: {
                    Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(.red.opacity(0.8))
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(note.pinned ? Color.yellow.opacity(0.1) : .white.opacity(hover ? 0.07 : 0.03)))
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: hover)
    }
}

// MARK: - Clipboard

struct ClipboardTab: View {
    @ObservedObject var clipboard: ClipboardStore
    @ObservedObject var model: IslandModel

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Label("Clipboard", systemImage: "doc.on.clipboard.fill")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text("Kept in memory only")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.35))
                if !clipboard.items.isEmpty {
                    Button("Clear") { withAnimation(.spring) { clipboard.clear() } }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            if clipboard.items.isEmpty {
                Text("Copy something and it'll show up here")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 3) {
                        ForEach(clipboard.items) { item in
                            ClipRow(item: item) {
                                clipboard.copy(item)
                                model.confirm("doc.on.clipboard", "Copied")
                            } remove: { clipboard.remove(item) }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }
}

private struct ClipRow: View {
    let item: ClipItem
    let copy: () -> Void
    let remove: () -> Void
    @ViewState private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            Text(item.text.replacingOccurrences(of: "\n", with: " "))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(item.date, style: .relative)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.3))
                .lineLimit(1)
                .frame(width: 70, alignment: .trailing)
            if hover {
                Button(action: remove) { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.white.opacity(hover ? 0.09 : 0.04)))
        .contentShape(Rectangle())
        .onTapGesture(perform: copy)
        .onHover { hover = $0 }
        .help("Click to copy")
    }
}

// MARK: - Mirror

struct MirrorTab: View {
    @ObservedObject var camera: MirrorCamera

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                if camera.authorized {
                    CameraPreview(session: camera.session)
                        .opacity(camera.running ? 1 : 0)
                        .animation(.easeIn(duration: 0.4), value: camera.running)
                    if !camera.running { ProgressView().controlSize(.small) }
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "video.slash.fill").font(.system(size: 22))
                        Text("Allow camera access\nin System Settings")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(width: 250, height: 168)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text("Mirror")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Quick check before a call. The camera turns off as soon as the island closes.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                if camera.running {
                    Label("Camera on", systemImage: "circle.fill")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                        .symbolEffect(.pulse)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 22)
        .padding(.top, 6)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }
}

// MARK: - Calls

struct CompactCallView: View {
    @ObservedObject var calls: CallMonitor
    let notch: CGSize

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            Wings(notch: notch) {
                HStack(spacing: 5) {
                    Image(systemName: calls.call?.symbol ?? "phone.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.green)
                        .symbolEffect(.pulse)
                    if calls.micMuted {
                        Image(systemName: "mic.slash.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.red)
                    }
                }
                .padding(.leading, 12)
            } right: {
                Text(Self.duration(from: calls.call?.startedAt ?? ctx.date, to: ctx.date))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .padding(.trailing, 12)
            }
        }
    }

    static func duration(from: Date, to: Date) -> String {
        let s = max(0, Int(to.timeIntervalSince(from)))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }
}

struct CallTab: View {
    @ObservedObject var calls: CallMonitor
    @ViewState private var ring = false

    var body: some View {
        if let c = calls.call {
            HStack(spacing: 16) {
                ZStack {
                    if c.kind == .incoming {
                        Circle().stroke(.green.opacity(0.5), lineWidth: 2)
                            .scaleEffect(ring ? 1.5 : 1)
                            .opacity(ring ? 0 : 1)
                    }
                    Circle().fill(LinearGradient(colors: [Color(white: 0.55), Color(white: 0.35)],
                                                 startPoint: .top, endPoint: .bottom))
                    Text(Self.initials(c.title))
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(width: 58, height: 58)
                .onAppear {
                    withAnimation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)) { ring = true }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(c.kind == .incoming ? c.subtitle : c.subtitle)
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(c.title)
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if c.kind == .active {
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            Text(CompactCallView.duration(from: c.startedAt, to: ctx.date))
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.green)
                                .monospacedDigit()
                        }
                    } else {
                        Text("Incoming call…")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.green)
                        if !calls.canAnswer {
                            Button("Allow answering from here") { PermissionCenter.shared.request(.accessibility) }
                                .buttonStyle(.plain)
                                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.55))
                                .underline()
                        }
                    }
                }
                Spacer()
                if c.kind == .incoming {
                    roundButton("phone.down.fill", .red, "Decline") { calls.declineCall() }
                    roundButton(c.isVideo ? "video.fill" : "phone.fill", .green, "Accept") { calls.acceptCall() }
                        .symbolEffect(.bounce, options: .repeating, value: ring)
                } else {
                    roundButton(calls.micMuted ? "mic.slash.fill" : "mic.fill",
                                calls.micMuted ? .white : Color(white: 0.25), calls.micMuted ? "Unmute" : "Mute",
                                fg: calls.micMuted ? .black : .white) { calls.toggleMute() }
                    roundButton("arrow.up.forward.app.fill", Color(white: 0.25), "Open app") { calls.openCallApp() }
                    roundButton("phone.down.fill", .red, "End") { calls.endCall() }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
        }
    }

    private func roundButton(_ icon: String, _ bg: Color, _ help: String, fg: Color = .white,
                             _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(fg)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 48, height: 48)
                .background(Circle().fill(bg))
        }
        .buttonStyle(PressableStyle(hoverFill: .clear))
        .help(help)
    }

    static func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").filter { $0.first?.isLetter == true }
        let s = parts.prefix(2).compactMap { $0.first }.map(String.init).joined()
        return s.isEmpty ? "📞" : s.uppercased()
    }
}
