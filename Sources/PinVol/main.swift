import AppKit
import os
import ServiceManagement

// MARK: - Instancia residente (por defecto)

final class ResidentDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = Controller(defaults: .standard)
    private var statusItem: NSStatusItem?
    private var uiApp: NSRunningApplication?
    private var launchingUI = false
    private var barActive = false
    private var markedAsLoginItem = false   // macOS marcó el evento de apertura como «elemento de inicio de sesión»
    private var quietStart = false          // arrancó sola al iniciar sesión y ya hay apps fijadas: sin ventana
    private let launchedAt = Date()
    private let launchLog = Logger(subsystem: "com.claudiouvm.pinvol", category: "launch")

    /// Al abrirse como elemento de inicio de sesión, macOS lo marca en el evento de apertura.
    private func openedAsLoginItem() -> Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        return event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == AEKeyword(keyAELaunchedAsLogInItem)
    }

    func applicationWillFinishLaunching(_ n: Notification) {
        markedAsLoginItem = openedAsLoginItem()   // según la versión de macOS, el evento está en este aviso o en el siguiente
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        let show = NSMenuItem(title: L("Show PinVol"), action: #selector(showWindow), keyEquivalent: "")
        show.target = self
        installMainMenu(quitAction: #selector(NSApplication.terminate(_:)), quitTitle: L("Quit PinVol"), extra: [show])
        model.onStatus = { [weak self] in self?.statusChanged() }
        model.onPresence = { [weak self] in self?.applyPresence() }
        model.onShow = { [weak self] in self?.showWindow() }
        model.start()
        applyPresence()
        #if SNAPSHOT
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            devLog("residente: dock=\(self?.model.showDock ?? false) barra=\(self?.statusItem != nil) política=\(NSApp.activationPolicy().rawValue)")
        }
        #endif
        // Al encender el Mac y abrirse sola (con «Abrir al iniciar sesión»), si ya hay apps fijadas pasa directo a la barra de
        // menús: la ventana solo estorba. Si el usuario abre la app, o mientras no haya nada fijado, se muestra como siempre.
        markedAsLoginItem = markedAsLoginItem || openedAsLoginItem()
        let bySession = !markedAsLoginItem && startedWithSession()
        quietStart = (markedAsLoginItem || bySession) && model.isConfigured
        launchLog.notice("inicio: evento=\(self.markedAsLoginItem, privacy: .public) sesión=\(bySession, privacy: .public) fijadas=\(self.model.apps.count, privacy: .public) → \(self.quietStart ? "barra de menús" : "ventana", privacy: .public)")
        if !quietStart { DispatchQueue.main.async { self.showWindow() } }
    }

    /// Respaldo para cuando macOS no marca el evento de apertura (no siempre lo hace con los elementos de inicio de sesión):
    /// la app arrancó pocos segundos después de empezar la sesión del usuario, que es lo que tardan en abrirse sus elementos
    /// de inicio. La sesión empieza con su proceso loginwindow. Con «Abrir al iniciar sesión» activado (SMAppService) el margen
    /// es de un minuto; si no, solo de 25 s, para no confundir con un arranque manual justo después de iniciar sesión.
    private func startedWithSession() -> Bool {
        let registered = SMAppService.mainApp.status == .enabled
        let limit: TimeInterval = registered ? 60 : 25
        let session = NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == "com.apple.loginwindow" }
            .flatMap { processStart($0.processIdentifier) ?? $0.launchDate }
        // Sin poder localizar la sesión, solo se acepta un Mac recién encendido y con el elemento de inicio activado.
        guard let session else { return registered && ProcessInfo.processInfo.systemUptime < 120 }
        return (0..<limit).contains(launchedAt.timeIntervalSince(session))
    }

    /// Cuándo empezó el proceso `pid`, o nil si el sistema no lo dice.
    private func processStart(_ pid: pid_t) -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let t = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: TimeInterval(t.tv_sec) + TimeInterval(t.tv_usec) / 1_000_000)
    }

    func applicationShouldHandleReopen(_ app: NSApplication, hasVisibleWindows: Bool) -> Bool {
        // Al encender el Mac, macOS puede mandar este aviso justo después de abrir la app: no es un clic del usuario.
        let justStarted = Date().timeIntervalSince(launchedAt) < 10
        if !(quietStart && justStarted) { showWindow() }   // clic en el ícono del Dock, o doble clic en la app
        return true
    }

    func applicationWillTerminate(_ n: Notification) {
        IPC.post(IPC.toUI, ["bye": true])
    }

    // MARK: Presencia: Dock y barra de menús

    /// El Dock es la vía de acceso fiable; la barra de menús depende de que macOS tenga sitio y la deje verse.
    private func applyPresence() {
        NSApp.setActivationPolicy(model.showDock ? .regular : .accessory)
        if model.showMenuBar {
            if statusItem == nil { buildStatusItem() }
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = menuBarImage(active: barActive)
        item.button?.toolTip = "PinVol"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu   // clic → menú desplegable, como cualquier ícono de la barra
        statusItem = item
    }

    /// Glifo propio derivado del ícono (lo genera tools/make-icon.py y build.sh lo copia a Resources);
    /// activo a opacidad completa, inactivo atenuado. Sin el recurso (p. ej. con `swift run`), cae al símbolo del sistema.
    private func menuBarImage(active: Bool) -> NSImage? {
        if let glyph = NSImage(named: NSImage.Name(active ? "MenuBarActiveTemplate" : "MenuBarIdleTemplate")) {
            glyph.isTemplate = true
            return glyph
        }
        let img = symbol(active ? "speaker.wave.2.fill" : "speaker.wave.2", size: 14, weight: .medium)
        img?.isTemplate = true
        return img
    }

    private func statusChanged() {
        let active = model.anyActive
        if active != barActive {
            barActive = active
            statusItem?.button?.image = menuBarImage(active: active)
        }
    }

    // MARK: Menús (barra de menús y Dock)

    func menuNeedsUpdate(_ menu: NSMenu) { fill(menu, includeQuit: true) }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let m = NSMenu()
        fill(m, includeQuit: false)   // el Dock añade "Salir" por su cuenta
        return m
    }

    private func fill(_ menu: NSMenu, includeQuit: Bool) {
        menu.removeAllItems()
        let st = model.summary
        let head = NSMenuItem(title: st.text, action: nil, keyEquivalent: "")
        head.image = dot(st.kind)
        menu.addItem(head)
        menu.addItem(.separator())
        let show = NSMenuItem(title: L("Show PinVol"), action: #selector(showWindow), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        let toggle = NSMenuItem(title: L("Keep levels fixed"), action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        toggle.state = model.enabled ? .on : .off
        menu.addItem(toggle)
        if model.update.kind == .available, let v = model.update.latest {
            let update = NSMenuItem(title: L("Download PinVol %@…", v), action: #selector(openUpdate), keyEquivalent: "")
            update.target = self
            menu.addItem(update)
        }
        if includeQuit {
            menu.addItem(.separator())
            menu.addItem(withTitle: L("Quit PinVol"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        }
    }

    private func dot(_ kind: EngineStatus.Kind) -> NSImage? {
        let color: NSColor
        switch kind {
        case .idle: color = .tertiaryLabelColor
        case .waiting, .warning: color = .systemOrange
        case .active: color = .systemGreen
        case .error: color = .systemRed
        }
        let cfg = NSImage.SymbolConfiguration(pointSize: 8, weight: .regular).applying(.init(paletteColors: [color]))
        return NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?.withSymbolConfiguration(cfg)
    }

    @objc private func toggleEnabled() { model.setEnabled(!model.enabled) }

    @objc private func openUpdate() {
        if let s = model.update.url, let url = URL(string: s) { NSWorkspace.shared.open(url) }
    }

    // MARK: Ventana (otra instancia)

    @objc private func showWindow() {
        if let ui = uiApp, !ui.isTerminated {
            raise(ui)
            return
        }
        guard !launchingUI else { return }
        launchingUI = true
        let cfg = NSWorkspace.OpenConfiguration()
        cfg.createsNewApplicationInstance = true
        cfg.activates = true
        cfg.arguments = ["--ui"]
        #if SNAPSHOT
        cfg.environment = ProcessInfo.processInfo.environment.filter { $0.key.hasPrefix("PV_") }
        #endif
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: cfg) { [weak self] app, _ in
            DispatchQueue.main.async {
                self?.uiApp = app
                self?.launchingUI = false
            }
        }
    }

    /// Trae al frente la ventana de la instancia de interfaz que ya está abierta.
    /// Desde macOS 14 una app no puede activar a otra por las buenas: primero debe estar activa ella misma
    /// (acaba de recibir un clic en el Dock o en el menú) y ceder la activación.
    private func raise(_ ui: NSRunningApplication) {
        NSApp.activate()
        NSApp.yieldActivation(to: ui)
        ui.activate()
        IPC.post(IPC.toUI, ["show": true])   // la propia ventana también se pone delante
    }
}

// MARK: - Arranque

private func makeDelegate() -> NSApplicationDelegate {
    #if SNAPSHOT
    if CommandLine.arguments.contains("--snapshot") { return SnapshotDelegate() }
    #endif
    return CommandLine.arguments.contains("--ui") ? UIDelegate() : ResidentDelegate()
}

let app = NSApplication.shared
let delegate = makeDelegate()
app.delegate = delegate
app.run()
