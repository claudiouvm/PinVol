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
//                     [--status kind [--text t]] [--gains dB1,dB2,…] [--update available|uptodate|failed] [--force]`
// Con `--status active`, `--gains` pone en cada app la ganancia que mostraría («Active · +11.9 dB»). Con `waiting` y `error`,
// sin `--text`, salen los textos reales del motor. El idioma se elige como en cualquier app: `-AppleLanguages "(es)"`.
// Si algún ícono de app aún no está generado sale con código 3 sin escribir nada; `--force` captura igual.

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

/// Imagen de `size` puntos a 2x, como una pantalla retina: así las capturas del README se ven nítidas.
private func makeRep(_ size: NSSize) -> NSBitmapImageRep? {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int((size.width * 2).rounded()),
                               pixelsHigh: Int((size.height * 2).rounded()), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
    rep?.size = size
    return rep
}

/// En macOS 26 el servicio de íconos genera bajo demanda (y por separado para claro y oscuro) los de las apps recién
/// instaladas, y hasta entonces la ventana dibuja un cuadro punteado casi liso; el ícono real mezcla al menos dos tonos.
/// Con la ventana ya mostrada, devuelve los ids de las apps cuyo ícono aún es ese cuadro. Cada ícono se dibuja por
/// separado, por el mismo camino y a la misma resolución que la captura, y sobre gris medio para que la transparencia
/// no cuente como contraste. Dibujarlos también le pide al sistema que los genere: la siguiente captura ya los tiene.
private func iconsNotReady(in root: NSView) -> [String] {
    func descendants(_ v: NSView) -> [NSView] { v.subviews.flatMap { [$0] + descendants($0) } }
    var pending: [String] = []
    for case let row as AppRow in descendants(root)
    where !row.isHiddenOrHasHiddenAncestor && NSWorkspace.shared.urlForApplication(withBundleIdentifier: row.id) != nil {
        guard let icon = descendants(row).first(where: { $0 is NSImageView && abs($0.frame.width - 32) < 1 }),
              let rep = makeRep(icon.bounds.size) else { continue }
        icon.cacheDisplay(in: icon.bounds, to: rep)
        var lo: CGFloat = 1, hi: CGFloat = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let luma = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
                let shown = c.alphaComponent * luma + (1 - c.alphaComponent) * 0.5
                lo = min(lo, shown)
                hi = max(hi, shown)
            }
        }
        if hi - lo < 0.3 { pending.append(row.id) }
    }
    return pending
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
        let gains = opt("--gains")?.split(separator: ",").compactMap { Float($0) } ?? []
        let kind = opt("--status").flatMap { EngineStatus.Kind(rawValue: $0) }
        let text = opt("--text")
        func status(for i: Int) -> EngineStatus? {
            guard let kind else { return nil }
            if let text { return EngineStatus(kind: kind, text: text) }
            switch kind {
            case .active: return .active(gain: i < gains.count ? gains[i] : 0)
            case .waiting: return .waiting
            case .error: return .captureFailed(-1)
            default: return EngineStatus(kind: kind, text: "")
            }
        }
        for (i, id) in ids.enumerated() {
            var app = PinnedApp(id: id, level: i < levels.count ? levels[i] : (levels.last ?? 0.5))
            if let s = status(for: i) { app.status = s }
            st.apps.append(app)
        }
        st.enabled = args.contains("--on")
        switch opt("--update") {
        case "available": st.update = UpdateState(kind: .available, latest: "9.9.9", url: "https://example.com")
        case "uptodate": st.update = UpdateState(kind: .upToDate, latest: UpdateChecker.currentVersion)
        case "failed": st.update = UpdateState(kind: .failed, message: UpdateError.rateLimited.message)
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
            if !args.contains("--force") {
                let pending = iconsNotReady(in: v)
                if !pending.isEmpty {
                    FileHandle.standardError.write(Data("íconos sin generar: \(pending.joined(separator: ", "))\n".utf8))
                    exit(3)
                }
            }
            let rep = makeRep(v.bounds.size)!
            v.cacheDisplay(in: v.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
            NSApp.terminate(nil)
        }
    }
}
#endif
