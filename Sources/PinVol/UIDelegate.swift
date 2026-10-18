import AppKit

// MARK: - Menú principal compartido

func installMainMenu(quitAction: Selector, quitTitle: String, extra: [NSMenuItem] = []) {
    let main = NSMenu()
    let appItem = NSMenuItem()
    main.addItem(appItem)
    let appMenu = NSMenu()
    for item in extra { appMenu.addItem(item) }
    if !extra.isEmpty { appMenu.addItem(.separator()) }
    appMenu.addItem(withTitle: quitTitle, action: quitAction, keyEquivalent: "q")
    appItem.submenu = appMenu
    let windowItem = NSMenuItem()
    main.addItem(windowItem)
    let windowMenu = NSMenu(title: L("Window"))
    windowMenu.addItem(withTitle: L("Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    windowItem.submenu = windowMenu
    NSApp.mainMenu = main
}

// MARK: - Instancia de interfaz (`--ui`)

final class UIDelegate: NSObject, NSApplicationDelegate {
    private let backend = RemoteBackend()
    private var settings: SettingsWindow?
    /// Pestaña en que se abre la ventana: la que pidió la residente al lanzar esta instancia (`--ui --tab about`) o, si la
    /// ventana aún no existe, la de un aviso «show» que llegó antes.
    private var pendingTab: String? = {
        let args = CommandLine.arguments
        return args.firstIndex(of: "--tab").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
    }()

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installUIMainMenu()
        // La ventana se abre con el primer estado recibido (o a los 1,5 s si la residente no responde).
        backend.onState = { [weak self] _, _ in self?.open() }
        backend.onShow = { [weak self] tab in
            self?.show(tab: tab)
            #if SNAPSHOT
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                let w = self?.settings?.window
                devLog("UI recibió «show»: visible=\(w?.isVisible ?? false) clave=\(w?.isKeyWindow ?? false) activa=\(NSApp.isActive) sinOclusión=\(w?.occlusionState.contains(.visible) ?? false)")
            }
            #endif
        }
        backend.connect()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.open() }
        #if SNAPSHOT
        let env = ProcessInfo.processInfo.environment
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            devLog("UI abrió con frame=\(String(describing: self?.settings?.window.frame))")
            if let m = env["PV_MOVE"]?.split(separator: ",").compactMap({ Double($0) }), m.count == 2 {
                self?.settings?.window.setFrameOrigin(NSPoint(x: m[0], y: m[1]))
                devLog("UI movió a \(m)")
            }
        }
        if let t = env["PV_AUTOCLOSE"].flatMap(Double.init) {
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { [weak self] in
                devLog("UI cierra con frame=\(String(describing: self?.settings?.window.frame))")
                self?.settings?.window.performClose(nil)
            }
        }
        #endif
    }

    private func open() {
        guard settings == nil else { return }
        let s = SettingsWindow(backend: backend)
        if let tab = pendingTab { s.select(tab) }
        s.onClose = { NSApp.terminate(nil) }
        settings = s
        s.show()
    }

    /// La residente pide traer la ventana al frente, a veces en una pestaña concreta («Acerca de PinVol» del menú).
    private func show(tab: String?) {
        guard let settings else {
            if let tab { pendingTab = tab }   // la ventana aún no existe: se abrirá en esa pestaña
            return
        }
        if let tab { settings.select(tab, animated: true) }
        settings.show()
    }

    func applicationShouldHandleReopen(_ app: NSApplication, hasVisibleWindows: Bool) -> Bool {
        settings?.show()
        return true
    }

    func applicationWillTerminate(_ n: Notification) { backend.disconnect() }

    // MARK: Menú principal

    /// Las apps instaladas no tienen menú si no se crea: sin esto no hay ⌘O, ⌘, ni ⌘H, y el menú de la app
    /// solo ofrecería «Salir».
    private func installUIMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let app = NSMenu()
        app.addItem(menuItem(L("About PinVol"), #selector(showAbout), ""))
        app.addItem(.separator())
        app.addItem(menuItem(L("Settings…"), #selector(showSettings), ","))
        app.addItem(.separator())
        app.addItem(menuItem(L("Pin App…"), #selector(addApp), "o"))
        let remove = menuItem(L("Remove App"), #selector(removeFocusedApp), "\u{8}")
        remove.keyEquivalentModifierMask = []
        app.addItem(remove)
        app.addItem(.separator())
        app.addItem(menuItem(L("Check for updates…"), #selector(checkForUpdates), ""))
        app.addItem(.separator())
        app.addItem(chained(L("Hide PinVol"), #selector(NSApplication.hide(_:)), "h"))
        app.addItem(chained(L("Hide Others"), #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        app.addItem(chained(L("Show All"), #selector(NSApplication.unhideAllApplications(_:)), ""))
        app.addItem(.separator())
        app.addItem(withTitle: L("Quit PinVol"), action: #selector(quitAll), keyEquivalent: "q")
        appItem.submenu = app

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: L("Edit"))
        edit.addItem(menuItem(L("Undo Remove App"), #selector(undoRemove), "z"))
        editItem.submenu = edit

        let viewItem = NSMenuItem()
        main.addItem(viewItem)
        let view = NSMenu(title: L("View"))
        view.addItem(menuItem(L("Apps"), #selector(showApps), "1"))
        view.addItem(menuItem(L("Settings"), #selector(showSettings), "2"))
        view.addItem(menuItem(L("About"), #selector(showAbout), "3"))
        viewItem.submenu = view

        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let windowMenu = NSMenu(title: L("Window"))
        windowMenu.addItem(chained(L("Minimize"), #selector(NSWindow.performMiniaturize(_:)), "m"))
        windowMenu.addItem(chained(L("Zoom"), #selector(NSWindow.performZoom(_:)), ""))
        windowMenu.addItem(withTitle: L("Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(.separator())
        windowMenu.addItem(chained(L("Bring All to Front"), #selector(NSApplication.arrangeInFront(_:)), ""))
        windowItem.submenu = windowMenu

        let helpItem = NSMenuItem()
        main.addItem(helpItem)
        let help = NSMenu(title: L("Help"))
        help.addItem(menuItem(L("PinVol Help"), #selector(openHelp), "?"))
        helpItem.submenu = help

        NSApp.mainMenu = main
    }

    private func menuItem(_ title: String, _ action: Selector, _ key: String,
                          _ mask: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = mask
        item.target = self
        return item
    }

    /// Para las acciones que atiende NSApplication a través de la cadena de respondedores.
    private func chained(_ title: String, _ action: Selector, _ key: String,
                         _ mask: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = mask
        item.target = nil
        return item
    }

    @objc private func showAbout() { open(); settings?.select("about", animated: true); settings?.show() }
    @objc private func showSettings() { open(); settings?.select("settings", animated: true); settings?.show() }
    @objc private func showApps() { open(); settings?.select("apps", animated: true); settings?.show() }

    @objc private func checkForUpdates() {
        open()
        backend.checkForUpdates()
        settings?.select("about", animated: true)
        settings?.show()
    }

    @objc private func undoRemove() { settings?.undoRemove() }

    @objc private func openHelp() {
        guard let url = URL(string: "https://github.com/claudiouvm/PinVol#readme") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func quitAll() {
        backend.quit()
        NSApp.terminate(nil)
    }

    /// ⌘O: elegir apps con el panel del sistema (también cuando la ventana aún no existe).
    @objc private func addApp() {
        if settings == nil { open() }
        settings?.addApp()
    }

    /// ⌫: quitar la app de la fila que tiene el foco.
    @objc private func removeFocusedApp() { settings?.removeFocusedApp() }
}
