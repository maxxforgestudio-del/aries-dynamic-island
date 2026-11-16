import AppKit
import SwiftUI

/// Transparent, non-activating panel that sits over the notch.
final class IslandPanel: NSPanel {
    /// Becomes key only when a text field needs typing (notes, search), without activating the app.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class IslandPanelController {
    let model: IslandModel
    let panel: IslandPanel
    /// Big enough for the expanded island plus the music-note particles around it.
    static let canvasSize = CGSize(width: 820, height: 340)

    private var monitors: [Any] = []
    private var screenObserver: NSObjectProtocol?
    private var fallbackTimer: Timer?
    private var screenFrame: NSRect = .zero

    init(model: IslandModel) {
        self.model = model
        panel = IslandPanel(
            contentRect: NSRect(origin: .zero, size: Self.canvasSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true

        let host = NSHostingView(rootView: IslandRootView(model: model, music: model.music))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: Self.canvasSize)
        panel.contentView = host

        model.onLayoutChange = { [weak self] in self?.updateMouse() }
        model.onCollapse = { [weak self] in
            guard let self, self.panel.isKeyWindow else { return }
            self.panel.resignKey()
            NSWorkspace.shared.frontmostApplication?.activate()
        }
    }

    func show() {
        reposition()
        panel.orderFrontRegardless()

        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            self?.updateMouse()
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .mouseExited, .leftMouseUp]) { [weak self] e in
            self?.updateMouse(); return e
        } as Any)
        // Two-finger swipe on the island = next/previous song; scroll on the closed island = volume.
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] e in
            guard let self, e.window === self.panel else { return e }
            return self.handleScroll(e) ? nil : e
        } as Any)
        // Click anywhere else closes the island (like iPhone).
        monitors.append(NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.model.isExpanded, !self.isInside(NSEvent.mouseLocation, margin: 14) else { return }
            if self.model.calls.call?.kind == .incoming { return }
            self.model.collapse()
        } as Any)
        // Safety net for cases where no mouse event arrives (spaces switching, sleep, etc).
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.updateMouse()
            self?.updateFullscreenVisibility()
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.reposition() }
    }

    private func targetScreen() -> NSScreen {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens[0]
    }

    func reposition() {
        let screen = targetScreen()
        screenFrame = screen.frame
        model.updateNotch(for: screen)
        let size = Self.canvasSize
        panel.setFrame(NSRect(x: screenFrame.midX - size.width / 2,
                              y: screenFrame.maxY - size.height,
                              width: size.width, height: size.height), display: true)
    }

    private var swipeX: CGFloat = 0
    private var swipeY: CGFloat = 0
    private var swipeFired = false

    /// Returns true when the scroll was used as a gesture.
    private func handleScroll(_ e: NSEvent) -> Bool {
        guard Prefs.bool(Prefs.gestures), model.music.track != nil else { return false }
        let expandedMusic = model.isExpanded && model.tab == .music && model.musicPanel == .player
        guard !model.isExpanded || expandedMusic else { return false }

        if e.phase == .began || (e.phase.isEmpty && e.momentumPhase.isEmpty && !e.hasPreciseScrollingDeltas) {
            swipeX = 0; swipeY = 0; swipeFired = false
        }
        guard e.momentumPhase.isEmpty else { return true }
        let k: CGFloat = e.hasPreciseScrollingDeltas ? 1 : 8
        swipeX += e.scrollingDeltaX * k
        swipeY += e.scrollingDeltaY * k

        if !swipeFired, abs(swipeX) > 70, abs(swipeX) > abs(swipeY) * 1.6 {
            swipeFired = true
            model.swipe(next: swipeX < 0)
            return true
        }
        if !model.isExpanded, abs(swipeY) > abs(swipeX) * 1.4, abs(swipeY) > 12 {
            let step = Int((swipeY / 12).rounded(.towardZero))
            swipeY -= CGFloat(step) * 12
            model.scrollVolume(by: step * 3)
            return true
        }
        if e.phase == .ended || e.phase == .cancelled { swipeX = 0; swipeY = 0 }
        return swipeFired
    }

    func focus() {
        panel.makeKey()
    }

    private var fullscreenTick = 0
    private func updateFullscreenVisibility() {
        fullscreenTick += 1
        guard fullscreenTick % 3 == 0 else { return }
        let hide = Prefs.bool(Prefs.hideInFullscreen) && Self.frontAppIsFullscreen(on: screenFrame)
            && model.calls.call == nil && !model.isExpanded
        let target: CGFloat = hide ? 0 : 1
        if panel.alphaValue != target {
            NSAnimationContext.runAnimationGroup { $0.duration = 0.25; panel.animator().alphaValue = target }
        }
    }

    /// A normal-layer window of the frontmost app covering the whole screen = full-screen app.
    private static func frontAppIsFullscreen(on frame: NSRect) -> Bool {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        for w in list where (w[kCGWindowOwnerPID as String] as? pid_t) == pid && (w[kCGWindowLayer as String] as? Int) == 0 {
            if let b = w[kCGWindowBounds as String] as? [String: CGFloat],
               b["Width"] ?? 0 >= frame.width, b["Height"] ?? 0 >= frame.height { return true }
        }
        return false
    }

    private func isInside(_ p: NSPoint, margin: CGFloat) -> Bool {
        let size = model.totalSize
        return NSRect(x: screenFrame.midX - size.width / 2 - margin, y: screenFrame.maxY - size.height - margin,
                      width: size.width + margin * 2, height: size.height + margin + 2).contains(p)
    }

    /// Only accept mouse events while the cursor is over the island itself,
    /// so the rest of the (transparent) panel never blocks the menu bar.
    func updateMouse() {
        let p = NSEvent.mouseLocation
        let size = model.totalSize
        let dragging = NSEvent.pressedMouseButtons & 1 != 0
        let margin: CGFloat = dragging ? 40 : (model.isExpanded ? 14 : 3)
        let rect = NSRect(x: screenFrame.midX - size.width / 2 - margin,
                          y: screenFrame.maxY - size.height - margin,
                          width: size.width + margin * 2,
                          height: size.height + margin + 2)
        var inside = rect.contains(p)
        if model.secondary != nil {
            let d = model.notchSize.height
            let bubble = NSRect(x: screenFrame.midX + size.width / 2 + 4, y: screenFrame.maxY - d - 3, width: d + 10, height: d + 4)
            inside = inside || bubble.contains(p)
        }
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        model.setHovering(inside)
    }
}
