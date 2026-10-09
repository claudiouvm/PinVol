import AppKit

#if SNAPSHOT
/// Solo desarrollo: traza a un archivo (el registro unificado oculta los textos dinámicos).
func devLog(_ s: String) {
    let line = "\(getpid()) \(s)\n"
    let path = ProcessInfo.processInfo.environment["PV_LOG"] ?? "/tmp/pinvol-dev.log"
    if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(Data(line.utf8)); h.closeFile() }
    else { try? line.write(toFile: path, atomically: false, encoding: .utf8) }
}

// MARK: - Solo desarrollo: renderiza la ventana a un PNG
// `--snapshot out.png [--dark] [--tab apps|settings|about] [--assigned id1,id2,…] [--level x1,x2,…] [--on]
//                     [--status kind --text t] [--update available|uptodate|failed]`

final class StaticBackend: Backend {
    var state: AppState
    var onState: ((AppState, Bool) -> Void)?
    init(state: AppState) { self.state = state }
    func assign(_ id: String) {}
    func remove(_ id: String) {}
    func setLevel(_ id: String, _ v: Float) {}
    func setEnabled(_ on: Bool) {}
    func setShowDock(_ on: Bool) {}
    func setShowMenuBar(_ on: Bool) {}
    func setCheckUpdates(_ on: Bool) {}
    func checkForUpdates() {}
    func quit() {}
}

final class SnapshotDelegate: NSObject, NSApplicationDelegate {
    private var settings: SettingsWindow?

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let args = CommandLine.arguments
        func opt(_ k: String) -> String? { args.firstIndex(of: k).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
        var st = AppState()
        let ids = opt("--assigned")?.split(separator: ",").map { String($0) } ?? []
        let levels = opt("--level")?.split(separator: ",").compactMap { Float($0) } ?? []
        let status = opt("--status").map { EngineStatus(kind: EngineStatus.Kind(rawValue: $0) ?? .idle, text: opt("--text") ?? $0) }
        for (i, id) in ids.enumerated() {
            var app = PinnedApp(id: id, level: i < levels.count ? levels[i] : (levels.last ?? 0.5))
            if let status { app.status = status }
            st.apps.append(app)
        }
        st.enabled = args.contains("--on")
        switch opt("--update") {
        case "available": st.update = UpdateState(kind: .available, latest: "9.9.9", url: "https://example.com")
        case "uptodate": st.update = UpdateState(kind: .upToDate, latest: UpdateChecker.currentVersion)
        case "failed": st.update = UpdateState(kind: .failed, message: "Sin conexión")
        default: break
        }
        let s = SettingsWindow(backend: StaticBackend(state: st))
        settings = s
        s.select(opt("--tab") ?? "apps")
        s.window.alphaValue = 0
        s.window.appearance = NSAppearance(named: args.contains("--dark") ? .darkAqua : .aqua)
        s.show()
        let out = opt("--snapshot")!
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let v = s.window.contentView!.superview!
            v.layoutSubtreeIfNeeded()
            // A 2x, como una pantalla retina: así las capturas del README se ven nítidas.
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int((v.bounds.width * 2).rounded()),
                                       pixelsHigh: Int((v.bounds.height * 2).rounded()), bitsPerSample: 8,
                                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            rep.size = v.bounds.size
            v.cacheDisplay(in: v.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
            NSApp.terminate(nil)
        }
    }
}
#endif
