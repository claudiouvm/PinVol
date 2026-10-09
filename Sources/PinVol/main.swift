import AppKit

// MARK: - Instancia residente (por defecto)

final class ResidentDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = Controller(defaults: .standard)
    private var statusItem: NSStatusItem?
    private var uiApp: NSRunningApplication?
    private var launchingUI = false
    private var barActive = false
    private var launchedAtLogin = false

    func applicationWillFinishLaunching(_ n: Notification) {
        // Al abrirse como elemento de inicio de sesión, la app arranca sin mostrar la ventana.
        let event = NSAppleEventManager.shared().currentAppleEvent
        launchedAtLogin = event?.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == AEKeyword(keyAELaunchedAsLogInItem)
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        let show = NSMenuItem(title: "Mostrar PinVol", action: #selector(showWindow), keyEquivalent: "")
        show.target = self
        installMainMenu(quitAction: #selector(NSApplication.terminate(_:)), quitTitle: "Salir de PinVol", extra: [show])
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
        if !launchedAtLogin { DispatchQueue.main.async { self.showWindow() } }
    }

    func applicationShouldHandleReopen(_ app: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showWindow()   // clic en el ícono del Dock, o doble clic en la app
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

    private func menuBarImage(active: Bool) -> NSImage? {
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
        let show = NSMenuItem(title: "Mostrar PinVol", action: #selector(showWindow), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        let toggle = NSMenuItem(title: "Mantener nivel fijo", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self
        toggle.state = model.enabled ? .on : .off
        menu.addItem(toggle)
        if model.update.kind == .available, let v = model.update.latest {
            let update = NSMenuItem(title: "Descargar PinVol \(v)…", action: #selector(openUpdate), keyEquivalent: "")
            update.target = self
            menu.addItem(update)
        }
        if includeQuit {
            menu.addItem(.separator())
            menu.addItem(withTitle: "Salir de PinVol", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
