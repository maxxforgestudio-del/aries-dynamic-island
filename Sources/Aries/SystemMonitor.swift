import AppKit
import Combine
import CoreAudio
import CoreMediaIO
import IOKit.ps

struct MicClient: Equatable {
    let bundleID: String
    let name: String
}

enum SystemEvent {
    case chargingStarted(Int)
    case lowBattery(Int)
    case micStarted(String?)
    case cameraStarted
}

/// Watches microphone, camera and battery state.
final class SystemMonitor: ObservableObject {
    @Published private(set) var micActive = false
    @Published private(set) var micApp: String?
    /// Every process currently recording (bundle id, display name).
    @Published private(set) var micClients: [MicClient] = []
    /// Set by the Mirror tab so Aries doesn't flag its own camera use.
    var ownCameraInUse = false
    @Published private(set) var cameraActive = false
    @Published private(set) var batteryLevel: Int?
    @Published private(set) var isCharging = false

    let events = PassthroughSubject<SystemEvent, Never>()

    private var timer: Timer?
    private var started = false
    private var lastLowWarning = 101
    private let queue = DispatchQueue(label: "aries.system", qos: .utility)

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in self?.poll() }
    }

    private func poll() {
        queue.async { [weak self] in
            let clients = Self.micClients()
            let mic: (Bool, String?) = (!clients.isEmpty, clients.first?.name)
            let cam = Self.cameraInUse()
            let battery = Self.battery()
            DispatchQueue.main.async {
                guard let self else { return }
                if self.micClients != clients { self.micClients = clients }
                self.apply(mic: mic, cam: cam && !self.ownCameraInUse, battery: battery)
            }
        }
    }

    private func apply(mic: (Bool, String?), cam: Bool, battery: (Int, Bool)?) {
        let first = !started
        started = true

        if mic.0 != micActive {
            micActive = mic.0
            if mic.0 && !first { events.send(.micStarted(mic.1)) }
        }
        if micApp != mic.1 { micApp = mic.1 }
        if cam != cameraActive {
            cameraActive = cam
            if cam && !first { events.send(.cameraStarted) }
        }
        if let (level, charging) = battery {
            if charging && !isCharging && !first { events.send(.chargingStarted(level)) }
            if !charging, level <= 20, level < lastLowWarning, [20, 10, 5].contains(where: { level <= $0 && lastLowWarning > $0 }) {
                if !first { events.send(.lowBattery(level)) }
                lastLowWarning = level
            }
            if charging { lastLowWarning = 101 }
            if batteryLevel != level { batteryLevel = level }
            if isCharging != charging { isCharging = charging }
        }
    }

    static func batterySymbol(level: Int, charging: Bool) -> String {
        if charging { return "battery.100percent.bolt" }
        switch level {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    // MARK: Microphone (per-process, macOS 14+)

    private static let ignoredMicProcesses = ["corespeech", "siri", "assistant", "voicecontrol", "audiomxd", "dictation", "aries"]

    private static func micClients() -> [MicClient] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let sys = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(sys, &addr, 0, nil, &size) == noErr, size > 0 else {
            return deviceInputRunning() ? [MicClient(bundleID: "", name: "An app")] : []
        }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(sys, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        var out: [MicClient] = []

        for id in ids {
            var a = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningInput,
                                               mScope: kAudioObjectPropertyScopeGlobal,
                                               mElement: kAudioObjectPropertyElementMain)
            var running: UInt32 = 0
            var s = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(id, &a, 0, nil, &s, &running) == noErr, running != 0 else { continue }

            var bundle = ""
            a.mSelector = kAudioProcessPropertyBundleID
            var ref: Unmanaged<CFString>?
            s = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            if AudioObjectGetPropertyData(id, &a, 0, nil, &s, &ref) == noErr, let r = ref {
                bundle = r.takeRetainedValue() as String
            }
            a.mSelector = kAudioProcessPropertyPID
            var pid: pid_t = 0
            s = UInt32(MemoryLayout<pid_t>.size)
            AudioObjectGetPropertyData(id, &a, 0, nil, &s, &pid)
            if pid == ProcessInfo.processInfo.processIdentifier { continue }

            let app = NSRunningApplication(processIdentifier: pid)
            let ident = (bundle + " " + (app?.executableURL?.lastPathComponent ?? "")).lowercased()
            if ignoredMicProcesses.contains(where: { ident.contains($0) }) { continue }
            out.append(MicClient(bundleID: bundle.isEmpty ? (app?.bundleIdentifier ?? ident) : bundle,
                                 name: app?.localizedName ?? (bundle.isEmpty ? "An app" : bundle)))
        }
        return out
    }

    /// Fallback for older systems: any input-capable device running.
    private static func deviceInputRunning() -> Bool {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var dev = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr else { return false }
        addr.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &running) == noErr && running != 0
    }

    // MARK: Camera

    private static func cameraInUse() -> Bool {
        var addr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        let sys = CMIOObjectID(kCMIOObjectSystemObject)
        guard CMIOObjectGetPropertyDataSize(sys, &addr, 0, nil, &size) == 0, size > 0 else { return false }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(sys, &addr, 0, nil, size, &used, &ids) == 0 else { return false }

        for id in ids {
            var a = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
            var running: UInt32 = 0
            var u: UInt32 = 0
            if CMIOObjectGetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &u, &running) == 0, running != 0 {
                return true
            }
        }
        return false
    }

    // MARK: Battery

    private static func battery() -> (Int, Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            let onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let charging = (d[kIOPSIsChargingKey] as? Bool) ?? false
            return (Int((Double(cur) / Double(Swift.max(max, 1)) * 100).rounded()), charging || (onAC && cur >= max))
        }
        return nil
    }
}
