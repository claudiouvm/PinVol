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
    let windowMenu = NSMenu(title: "Ventana")
    windowMenu.addItem(withTitle: "Cerrar", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
    windowItem.submenu = windowMenu
    NSApp.mainMenu = main
}

// MARK: - Instancia de interfaz (`--ui`)

final class UIDelegate: NSObject, NSApplicationDelegate {
    private let backend = RemoteBackend()
    private var settings: SettingsWindow?

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        installMainMenu(quitAction: #selector(quitAll), quitTitle: "Salir de PinVol")
        // La ventana se abre con el primer estado recibido (o a los 1,5 s si la residente no responde).
        backend.onState = { [weak self] _, _ in self?.open() }
        backend.onShow = { [weak self] in
            self?.settings?.show()
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
        s.onClose = { NSApp.terminate(nil) }
        settings = s
        s.show()
    }

    func applicationShouldHandleReopen(_ app: NSApplication, hasVisibleWindows: Bool) -> Bool {
        settings?.show()
        return true
    }

    func applicationWillTerminate(_ n: Notification) { backend.disconnect() }

    @objc private func quitAll() {
        backend.quit()
        NSApp.terminate(nil)
    }
}
