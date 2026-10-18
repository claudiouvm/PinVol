import AppKit
import Foundation

#if SNAPSHOT
// MARK: - Solo desarrollo y CI: prueba de la instalación de actualizaciones
//
// `PinVol --selftest-install <dmg> <app instalada> <bundle id> <versión del dmg> <versión instalada>`
// Prueba en un macOS de verdad (lo ejecuta tools/test-install.sh en el CI) el análisis de la release, la descarga con huella y
// la instalación, incluidos los casos que deben fallar. Instala sobre la app que se le da: hay que pasarle una copia.
// Sale con 0 si todo pasa, con 1 si algo falla y con 2 si los argumentos no son los esperados.

func runInstallSelfTest(_ args: [String]) -> Never {
    guard args.count == 5 else {
        print("uso: PinVol --selftest-install <dmg> <app instalada> <bundle id> <versión del dmg> <versión instalada>")
        exit(2)
    }
    let dmg = URL(fileURLWithPath: args[0])
    let target = URL(fileURLWithPath: args[1])
    let bundleID = args[2], version = args[3], current = args[4]
    let fm = FileManager.default
    var failures = 0

    func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print("\(ok ? "ok   " : "FALLA") \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        if !ok { failures += 1 }
    }
    // Se lee el Info.plist del disco: `Bundle` guarda en memoria el de la primera lectura y no vería el cambio.
    func installedVersion() -> String? {
        guard let data = try? Data(contentsOf: target.appendingPathComponent("Contents/Info.plist")),
              let info = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { return nil }
        return info["CFBundleShortVersionString"] as? String
    }
    func wait(_ done: () -> Bool) {
        let limit = Date(timeIntervalSinceNow: 60)
        while !done() && Date() < limit { RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05)) }
    }

    // Instalar borra el .dmg que recibe: cada prueba usa su copia.
    let work = fm.temporaryDirectory.appendingPathComponent("pinvol-selftest-\(UUID().uuidString)")
    try? fm.createDirectory(at: work, withIntermediateDirectories: true)
    func copyOfDMG(_ name: String) -> URL {
        let copy = work.appendingPathComponent(name)
        try? fm.copyItem(at: dmg, to: copy)
        return copy
    }

    // 1. Lo que dice la API de GitHub
    let sample: [String: Any] = [
        "tag_name": "v9.9.9",
        "html_url": "https://github.com/claudiouvm/PinVol/releases/tag/v9.9.9",
        "assets": [
            ["name": "Otro.zip", "browser_download_url": "https://example.com/Otro.zip"],
            ["name": "PinVol.dmg", "browser_download_url": "https://example.com/PinVol.dmg", "digest": "sha256:ABCDEF0123"],
        ],
    ]
    let release = UpdateChecker.parseRelease(sample)
    check("release: versión sin la v", release?.version == "9.9.9")
    check("release: dirección del .dmg", release?.assetURL?.absoluteString == "https://example.com/PinVol.dmg")
    check("release: huella en minúsculas", release?.sha256 == "abcdef0123")
    check("release sin adjuntos", UpdateChecker.parseRelease(["tag_name": "v1.0"])?.assetURL == nil)
    check("respuesta sin tag", UpdateChecker.parseRelease([:]) == nil)

    // 2. Descarga (de un archivo local) con la huella buena y con una mala
    let sha = try? UpdateInstaller.sha256(of: dmg)
    check("huella SHA-256 de 64 cifras", sha?.count == 64)
    var outcome: Result<URL, InstallError>?
    UpdateInstaller.download(dmg, to: work.appendingPathComponent("bajado.dmg"), sha256: sha, progress: { _ in }) { outcome = $0 }
    wait { outcome != nil }
    if case .success(let file)? = outcome {
        check("descarga con la huella buena", fm.fileExists(atPath: file.path))
    } else {
        check("descarga con la huella buena", false, String(describing: outcome))
    }
    outcome = nil
    UpdateInstaller.download(dmg, to: work.appendingPathComponent("malo.dmg"), sha256: String(repeating: "0", count: 64),
                             progress: { _ in }) { outcome = $0 }
    wait { outcome != nil }
    if case .failure(.checksum)? = outcome {
        check("descarga con la huella mala se rechaza", !fm.fileExists(atPath: work.appendingPathComponent("malo.dmg").path))
    } else {
        check("descarga con la huella mala se rechaza", false, String(describing: outcome))
    }

    // 3. Instalaciones que deben fallar sin tocar la app instalada
    func mustFail(_ name: String, into: URL, id: String, version v: String, current c: String, _ expected: (InstallError) -> Bool) {
        do {
            try UpdateInstaller.install(dmg: copyOfDMG("\(name).dmg"), into: into, bundleID: id, version: v, currentVersion: c)
            check(name, false, "no falló")
        } catch let e as InstallError {
            check(name, expected(e) && installedVersion() == current, "\(e)")
        } catch {
            check(name, false, "\(error)")
        }
    }
    func isInvalid(_ e: InstallError) -> Bool { if case .invalid = e { return true } else { return false } }
    func isNotWritable(_ e: InstallError) -> Bool { if case .notWritable = e { return true } else { return false } }
    mustFail("otro identificador de bundle", into: target, id: "com.example.otra", version: version, current: current, isInvalid)
    mustFail("otra versión que la esperada", into: target, id: bundleID, version: "0.0.9", current: current, isInvalid)
    mustFail("versión que no es más nueva", into: target, id: bundleID, version: version, current: version, isInvalid)
    mustFail("carpeta sin permiso de escritura", into: URL(fileURLWithPath: "/System/Applications/PinVol.app"), id: bundleID,
             version: version, current: current, isNotWritable)

    // 4. La instalación buena
    let good = copyOfDMG("bueno.dmg")
    do {
        try UpdateInstaller.install(dmg: good, into: target, bundleID: bundleID, version: version, currentVersion: current)
        check("instalación: la app instalada es la nueva", installedVersion() == version, installedVersion() ?? "sin versión")
    } catch {
        check("instalación", false, "\(error)")
    }
    check("instalación: se borra el .dmg", !fm.fileExists(atPath: good.path))
    let leftovers = (try? fm.contentsOfDirectory(atPath: target.deletingLastPathComponent().path))?.filter { $0.hasPrefix(".PinVol-update-") } ?? []
    check("instalación: sin restos junto a la app", leftovers.isEmpty, leftovers.joined(separator: ", "))

    try? fm.removeItem(at: work)
    print(failures == 0 ? "OK: todo pasó" : "\(failures) prueba(s) fallaron")
    exit(failures == 0 ? 0 : 1)
}

// MARK: - Solo desarrollo y CI: contraste y accesibilidad
//
// `PinVol --selftest-contrast` resuelve los colores propios en claro y oscuro y aplica la fórmula WCAG.
// `PinVol --selftest-a11y` construye la ventana en sus estados y comprueba nombres accesibles, imágenes
// decorativas, tamaños de los botones sin texto y foco inicial. `tools/test-a11y.sh` ejecuta los dos y, además,
// el segundo con PV_TEXT_SCALE=1.5. Salen con 0 si todo pasa y con 1 si algo falla.

func runContrastSelfTest() -> Never {
    /// Aplana `color` sobre `background` en la apariencia dada y devuelve el color RGB resultante.
    /// Se dibuja en un bitmap de 1×1 porque algunos colores del sistema son de escala de grises y
    /// `redComponent` falla en ellos; así se mide lo que se ve, con su transparencia ya compuesta.
    func resolved(_ color: NSColor, _ appearance: NSAppearance, over background: NSColor) -> NSColor {
        var out = background
        appearance.performAsCurrentDrawingAppearance {
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8,
                                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                             colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            background.setFill()
            NSRect(x: 0, y: 0, width: 1, height: 1).fill()
            color.setFill()
            NSRect(x: 0, y: 0, width: 1, height: 1).fill()
            NSGraphicsContext.restoreGraphicsState()
            if let c = rep.colorAt(x: 0, y: 0)?.usingColorSpace(.sRGB) { out = c }
        }
        return out
    }
    func luminance(_ c: NSColor) -> CGFloat {
        func f(_ v: CGFloat) -> CGFloat { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * f(c.redComponent) + 0.7152 * f(c.greenComponent) + 0.0722 * f(c.blueComponent)
    }
    func ratio(_ a: NSColor, _ b: NSColor) -> CGFloat {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    var failures = 0
    func check(_ name: String, _ foreground: NSColor, _ background: NSColor, minimum: CGFloat) {
        let value = ratio(foreground, background)
        print("\(name): \(String(format: "%.2f", value)):1 (mínimo \(minimum):1)")
        if value < minimum {
            failures += 1
            print("  FALLA")
        }
    }

    // Fondo real de las tarjetas: blanco en claro; en oscuro, el velo blanco al 7 % sobre la ventana.
    let cases: [(String, NSAppearance, NSColor)] = [
        ("claro", NSAppearance(named: .aqua)!, NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)),
        ("oscuro", NSAppearance(named: .darkAqua)!, NSColor(srgbRed: 0.19, green: 0.19, blue: 0.19, alpha: 1)),
    ]
    for (appearanceName, appearance, background) in cases {
        for kind in [EngineStatus.Kind.active, .waiting, .warning, .error] {
            check("\(appearanceName): estado \(kind.rawValue)",
                  resolved(PinVolPalette.status(kind), appearance, over: background), background, minimum: 3)
        }
        check("\(appearanceName): quitar y borde de la zona de arrastre",
              resolved(PinVolPalette.controlOutline, appearance, over: background), background, minimum: 3)
        check("\(appearanceName): texto",
              resolved(.labelColor, appearance, over: background), background, minimum: 4.5)
        let track = resolved(PinVolPalette.sliderTrack, appearance, over: background)
        check("\(appearanceName): track del slider", track, background, minimum: 3)
        check("\(appearanceName): knob del slider",
              resolved(PinVolPalette.knobFill, appearance, over: track), track, minimum: 3)
    }
    // El texto blanco del segmento seleccionado de las pestañas: el acento se oscurece hasta 4,5:1.
    for (appearanceName, appearance) in [("claro", NSAppearance(named: .aqua)!), ("oscuro", NSAppearance(named: .darkAqua)!)] {
        check("\(appearanceName): texto de la pestaña seleccionada",
              NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
              PinVolPalette.accessibleAccent(for: appearance), minimum: 4.5)
    }
    print(failures == 0 ? "OK: contraste" : "\(failures) problema(s) de contraste")
    exit(failures == 0 ? 0 : 1)
}

final class AccessibilitySelfTestDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        DispatchQueue.main.async { [weak self] in self?.run() }
    }

    private func run() -> Never {
        var problems: [String] = []

        func makeState(_ apps: [(String, Float, EngineStatus)], update: UpdateState = UpdateState()) -> AppState {
            var state = AppState()
            state.apps = apps.map { var app = PinnedApp(id: $0.0, level: $0.1); app.status = $0.2; return app }
            state.enabled = !apps.isEmpty
            state.update = update
            return state
        }

        let active = EngineStatus.active(gain: 1)
        let waiting = EngineStatus(kind: .waiting, text: L("Waiting for the app's audio…"))
        let error = EngineStatus.captureFailed(-1)
        let five = ["com.apple.Music", "com.apple.Safari", "com.apple.Mail", "com.apple.Notes", "com.apple.Calendar"]
            .map { ($0, Float(0.5), active) }

        let cases: [(String, AppState, String, NSAppearance)] = [
            ("vacío", makeState([]), "apps", NSAppearance(named: .aqua)!),
            ("una app activa", makeState([("com.apple.Music", 0.45, active)]), "apps", NSAppearance(named: .aqua)!),
            ("una app en espera", makeState([("com.apple.Music", 0.45, waiting)]), "apps", NSAppearance(named: .aqua)!),
            ("una app con error", makeState([("com.apple.Music", 0.45, error)]), "apps", NSAppearance(named: .aqua)!),
            ("cinco apps", makeState(five), "apps", NSAppearance(named: .aqua)!),
            ("ajustes", makeState([]), "settings", NSAppearance(named: .aqua)!),
            ("acerca de", makeState([]), "about", NSAppearance(named: .aqua)!),
            ("actualización", makeState([("com.apple.Music", 0.45, active)],
                                        update: UpdateState(kind: .available, latest: "9.9.9")), "apps",
             NSAppearance(named: .aqua)!),
            ("ventana oscura", makeState([("com.apple.Music", 0.45, active)]), "apps", NSAppearance(named: .darkAqua)!),
        ]

        for (name, state, tab, appearance) in cases {
            let settings = SettingsWindow(backend: StaticBackend(state: state))
            settings.select(tab)
            settings.window.appearance = appearance
            settings.show()
            settings.window.layoutIfNeeded()
            problems += inspect(settings.window, context: name)
            let expectedWidth = max(360, scaled(360))
            if abs(settings.window.frame.width - expectedWidth) > 1 {
                problems.append("\(name): la ventana se ensancha a \(Int(settings.window.frame.width)) pt")
            }
            settings.window.orderOut(nil)
        }

        // Cambiar de pestaña no debe redimensionar la ventana, y el pie tiene que quedar dentro.
        let oneApp = makeState([("com.apple.Music", 0.45, active)])
        let layout = SettingsWindow(backend: StaticBackend(state: oneApp))
        layout.select("apps")
        layout.show()
        layout.window.layoutIfNeeded()
        var heights: [CGFloat] = []
        for tabName in ["apps", "settings", "about"] {
            layout.select(tabName)
            layout.window.layoutIfNeeded()
            heights.append(layout.window.frame.height)
            if let quit = findQuitButton(in: layout.window) {
                let frame = quit.convert(quit.bounds, to: nil)
                if !layout.window.contentView!.bounds.intersects(frame) {
                    problems.append("el pie queda fuera de la ventana en la pestaña \(tabName)")
                }
            } else {
                problems.append("no se encuentra el botón de salir en la pestaña \(tabName)")
            }
        }
        if (heights.max() ?? 0) - (heights.min() ?? 0) > 0.5 {
            problems.append("cambiar de pestaña redimensiona la ventana: \(heights.map { Int($0) })")
        }
        layout.window.orderOut(nil)

        if problems.isEmpty {
            print("OK: accesibilidad (\(cases.count) estados, escala \(String(format: "%.2f", textScale)))")
            exit(0)
        }
        for problem in problems { print("FALLA \(problem)") }
        print("\(problems.count) problema(s) de accesibilidad")
        exit(1)
    }

    private func findQuitButton(in window: NSWindow) -> NSButton? {
        func walk(_ view: NSView) -> NSButton? {
            if let button = view as? NSButton, button.identifier?.rawValue == "quit" { return button }
            for sub in view.subviews { if let found = walk(sub) { return found } }
            return nil
        }
        guard let root = window.contentView else { return nil }
        return walk(root)
    }

    private func inspect(_ window: NSWindow, context: String) -> [String] {
        var problems: [String] = []
        guard let root = window.contentView else { return ["\(context): ventana sin contenido"] }
        if window.initialFirstResponder == nil { problems.append("\(context): sin foco inicial") }
        if let minimize = window.standardWindowButton(.miniaturizeButton), minimize.isHidden || !minimize.isEnabled {
            problems.append("\(context): el botón de minimizar no está disponible")
        }

        func walk(_ view: NSView, depth: Int) {
            if !view.isHiddenOrHasHiddenAncestor {
                let label = (view.accessibilityLabel() ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if let button = view as? NSButton {
                    let title = button.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    if label.isEmpty && title.isEmpty {
                        problems.append("\(context): botón sin nombre")
                    }
                    // Los botones que son solo un ícono necesitan un objetivo de 24×24 pt como mínimo.
                    if title.isEmpty && (button.frame.width < 24 || button.frame.height < 24) {
                        problems.append("\(context): botón sin texto de \(Int(button.frame.width))×\(Int(button.frame.height)) pt")
                    }
                    if !title.isEmpty && button.intrinsicContentSize.width > button.frame.width + 2 {
                        problems.append("\(context): botón recortado «\(title)»")
                    }
                } else if view is NSSlider {
                    if label.isEmpty { problems.append("\(context): slider sin nombre") }
                } else if view is NSSwitch {
                    if label.isEmpty { problems.append("\(context): interruptor sin nombre") }
                } else if let image = view as? NSImageView {
                    if image.isAccessibilityElement() && label.isEmpty {
                        problems.append("\(context): imagen sin descripción")
                    }
                } else if view is NSProgressIndicator {
                    if label.isEmpty { problems.append("\(context): progreso sin nombre") }
                }
            }
            view.subviews.forEach { walk($0, depth: depth + 1) }
        }
        walk(root, depth: 0)
        return problems
    }
}
#endif
