import AppKit
import ServiceManagement

// MARK: - Ventana de ajustes
//
// Tres pestañas: Apps (zona de arrastre, lista y nivel de cada app), Ajustes y Acerca de.
// La ventana se redimensiona sola al cambiar de pestaña o al añadir y quitar apps, sin mover su esquina superior izquierda.

final class SettingsWindow: NSObject, NSWindowDelegate {
    private static let positionKey = "windowTopLeft"
    private static let width: CGFloat = 360

    private enum Tab: Int, CaseIterable {
        case apps, settings, about
        var title: String {
            switch self {
            case .apps: return "Apps"
            case .settings: return "Ajustes"
            case .about: return "Acerca de"
            }
        }
    }

    private let backend: Backend
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 480),
                          styleMask: [.titled, .closable, .fullSizeContentView],
                          backing: .buffered, defer: true)
    private let root = NSStackView()
    private let header = NSStackView()
    private let updateBanner = NSButton()
    private let tabs = NSSegmentedControl(labels: Tab.allCases.map { $0.title }, trackingMode: .selectOne,
                                          target: nil, action: nil)
    private let appsPage = NSStackView()
    private let settingsPage = NSStackView()
    private let aboutPage = NSStackView()
    private let panel = AppsPanel()
    private let enableSwitch = NSSwitch()
    private let dockSwitch = NSSwitch()
    private let menuBarSwitch = NSSwitch()
    private let loginSwitch = NSSwitch()
    private let updatesSwitch = NSSwitch()
    private let updateDetail = makeLabel("", size: 11, color: .secondaryLabelColor)
    private let updateButton = NSButton(title: "Buscar", target: nil, action: nil)
    private let statusDot = NSImageView()
    private let statusLabel = makeLabel("", size: 12, color: .secondaryLabelColor)
    private var tab = Tab.apps
    private var sized = false
    private var flashItem: DispatchWorkItem?
    var onClose: (() -> Void)?

    init(backend: Backend) {
        self.backend = backend
        super.init()
        buildUI()
        sync()
        // El tamaño final se fija antes de colocar la ventana (ver restorePosition).
        root.layoutSubtreeIfNeeded()
        window.setContentSize(root.fittingSize)
        sized = true
        restorePosition()
        window.delegate = self
        backend.onState = { [weak self] state, full in
            if full { self?.sync() } else { self?.applyStatuses(state) }
        }
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()   // delante de otras ventanas aunque macOS no conceda la activación
    }

    /// Elige la pestaña inicial por nombre (apps, settings, about). Solo desarrollo y capturas.
    func select(_ name: String) {
        switch name {
        case "settings": showTab(.settings, animated: false)
        case "about": showTab(.about, animated: false)
        default: showTab(.apps, animated: false)
        }
    }

    func windowWillClose(_ notification: Notification) {
        savePosition()
        UserDefaults.standard.synchronize()   // esta instancia termina enseguida: asegura que se escriba
        onClose?()
    }

    func windowDidMove(_ notification: Notification) { savePosition() }

    // MARK: Posición y tamaño

    /// Se guarda la esquina superior izquierda: no depende de la altura de la ventana.
    private func savePosition() {
        let p = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        UserDefaults.standard.set(NSStringFromPoint(p), forKey: Self.positionKey)
    }

    /// Debe llamarse con el tamaño final ya aplicado; si no, la ventana crece hacia abajo al mostrarse.
    private func restorePosition() {
        if let s = UserDefaults.standard.string(forKey: Self.positionKey) {
            let p = NSPointFromString(s)
            let titleBar = NSRect(x: p.x, y: p.y - 40, width: 80, height: 40)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(titleBar) }) {   // ¿sigue habiendo pantalla ahí?
                window.setFrameTopLeftPoint(p)
                return
            }
        }
        window.center()
    }

    /// Ajusta la altura de la ventana al contenido actual, manteniendo fija su esquina superior izquierda.
    private func fitWindow(animated: Bool) {
        guard sized, let content = window.contentView else { return }
        root.layoutSubtreeIfNeeded()
        let dh = root.fittingSize.height - content.frame.height
        guard abs(dh) > 0.5 else { return }
        var frame = window.frame
        frame.size.height += dh
        frame.origin.y -= dh
        window.setFrame(frame, display: true, animate: animated && window.isVisible)
    }

    // MARK: Interfaz

    /// Apila `views` en vertical, todas del ancho de `stack`.
    private func fill(_ stack: NSStackView, with views: [NSView], spacing: CGFloat = 14) {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        for v in views {
            stack.addArrangedSubview(v)
            v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private func buildUI() {
        // Cabecera (la pestaña «Acerca de» la reemplaza por un logo grande)
        let appIcon = NSImageView(image: NSApp.applicationIconImage)
        appIcon.widthAnchor.constraint(equalToConstant: 48).isActive = true
        appIcon.heightAnchor.constraint(equalToConstant: 48).isActive = true
        let titles = NSStackView(views: [
            makeLabel("PinVol", size: 20, weight: .semibold),
            makeLabel("Mantén fijo el volumen de tus apps", size: 12, color: .secondaryLabelColor),
        ])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 1
        header.addArrangedSubview(appIcon)
        header.addArrangedSubview(titles)
        header.alignment = .centerY
        header.spacing = 12

        // Aviso de versión nueva
        updateBanner.bezelStyle = .rounded
        updateBanner.controlSize = .small
        updateBanner.image = symbol("arrow.down.circle.fill", size: 12)
        updateBanner.imagePosition = .imageLeading
        updateBanner.target = self
        updateBanner.action = #selector(openUpdate)
        updateBanner.isHidden = true

        // Pestañas
        tabs.target = self
        tabs.action = #selector(tabChanged)
        tabs.segmentDistribution = .fillEqually
        tabs.selectedSegment = Tab.apps.rawValue

        // Interruptores
        for (sw, title, action) in [(enableSwitch, "Mantener nivel fijo", #selector(enabledChanged)),
                                    (dockSwitch, "Mostrar en el Dock", #selector(dockChanged)),
                                    (menuBarSwitch, "Mostrar en la barra de menús", #selector(menuBarChanged)),
                                    (loginSwitch, "Abrir al iniciar sesión", #selector(loginChanged)),
                                    (updatesSwitch, "Buscar actualizaciones", #selector(updatesChanged))] {
            sw.target = self
            sw.action = action
            sw.setAccessibilityLabel(title)
        }

        // Pestaña Apps
        panel.onDrop = { [weak self] urls in self?.dropped(urls) }
        panel.onRemove = { [weak self] id in self?.removeApp(id) }
        panel.onLevel = { [weak self] id, v in self?.backend.setLevel(id, v) }
        let enableCard = Card(rows: [
            formRow("Mantener nivel fijo", detail: "Compensa el volumen general del Mac", control: enableSwitch),
        ])
        fill(appsPage, with: [panel, enableCard])

        // Pestaña Ajustes
        let presence = Card(rows: [
            formRow("Mostrar en el Dock", control: dockSwitch),
            formRow("Mostrar en la barra de menús", control: menuBarSwitch),
            formRow("Abrir al iniciar sesión", control: loginSwitch),
        ])
        let updates = Card(rows: [
            formRow("Buscar actualizaciones", detail: "Consulta GitHub una vez al día", control: updatesSwitch),
        ])
        fill(settingsPage, with: [presence, updates])

        // Pestaña Acerca de
        buildAbout()

        // Pie: estado + salir
        statusDot.image = symbol("circle.fill", size: 8)
        statusDot.contentTintColor = .tertiaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let quit = NSButton(title: "Salir", target: self, action: #selector(quitTapped))
        quit.bezelStyle = .rounded
        quit.controlSize = .small
        quit.toolTip = "Cierra PinVol por completo: la app deja de controlar el volumen"
        let footer = NSStackView(views: [statusDot, statusLabel, spacer(), quit])
        footer.alignment = .centerY
        footer.distribution = .fill
        footer.spacing = 6

        // Ensamblado
        let sections: [NSView] = [header, updateBanner, tabs, appsPage, settingsPage, aboutPage, footer]
        for v in sections { root.addArrangedSubview(v) }
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.setCustomSpacing(18, after: header)
        root.edgeInsets = NSEdgeInsets(top: 44, left: 20, bottom: 18, right: 20)
        for v in sections { v.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -40).isActive = true }
        root.widthAnchor.constraint(equalToConstant: SettingsWindow.width).isActive = true

        let vc = NSViewController()
        vc.view = root
        window.contentViewController = vc
        window.title = "PinVol"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        showTab(.apps, animated: false)
    }

    private func buildAbout() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let channel = (info?["PinVolReleaseChannel"] as? String).map { "\($0) " } ?? ""

        let logo = NSImageView(image: NSApp.applicationIconImage)
        logo.imageScaling = .scaleProportionallyUpOrDown
        logo.widthAnchor.constraint(equalToConstant: 112).isActive = true
        logo.heightAnchor.constraint(equalToConstant: 112).isActive = true
        let name = makeLabel("PinVol", size: 24, weight: .semibold)
        let versionLabel = makeLabel("Versión \(channel)\(version) (\(build))", size: 12, color: .secondaryLabelColor)
        let madeIn = makeLabel("Made in Chile by Claudiouvm and Claude <3", size: 12)

        updateButton.bezelStyle = .rounded
        updateButton.controlSize = .small
        updateButton.target = self
        updateButton.action = #selector(updateButtonTapped)
        updateDetail.lineBreakMode = .byTruncatingTail
        let updateCard = Card(rows: [formRow("Actualizaciones", detailLabel: updateDetail, control: updateButton)])

        let github = NSButton(title: "Código fuente en GitHub", target: self, action: #selector(openGitHub))
        github.isBordered = false
        github.contentTintColor = .linkColor
        github.font = .systemFont(ofSize: 12)

        let aboutViews: [NSView] = [logo, name, versionLabel, madeIn, updateCard, github]
        for v in aboutViews { aboutPage.addArrangedSubview(v) }
        aboutPage.orientation = .vertical
        aboutPage.alignment = .centerX
        aboutPage.spacing = 4
        aboutPage.setCustomSpacing(12, after: logo)
        aboutPage.setCustomSpacing(14, after: versionLabel)
        aboutPage.setCustomSpacing(22, after: madeIn)
        aboutPage.setCustomSpacing(10, after: updateCard)
        updateCard.widthAnchor.constraint(equalTo: aboutPage.widthAnchor).isActive = true
    }

    private func showTab(_ t: Tab, animated: Bool) {
        tab = t
        tabs.selectedSegment = t.rawValue
        appsPage.isHidden = t != .apps
        settingsPage.isHidden = t != .settings
        aboutPage.isHidden = t != .about
        header.isHidden = t == .about
        refreshBanner()
        fitWindow(animated: animated)
    }

    /// Refleja en los controles lo que dice el estado.
    private func sync() {
        let st = backend.state
        panel.update(apps: st.apps, full: true)
        enableSwitch.state = st.enabled ? .on : .off
        dockSwitch.state = st.showDock ? .on : .off
        menuBarSwitch.state = st.showMenuBar ? .on : .off
        updatesSwitch.state = st.checkUpdates ? .on : .off
        loginSwitch.state = SMAppService.mainApp.status == .enabled ? .on : .off
        applyUpdate(st.update)
        apply(st.summary)
        fitWindow(animated: true)
    }

    private func applyStatuses(_ st: AppState) {
        panel.update(apps: st.apps, full: false)
        apply(st.summary)
    }

    func apply(_ s: EngineStatus) {
        statusLabel.stringValue = s.text
        statusLabel.toolTip = s.detail ?? s.text
        statusDot.contentTintColor = statusColor(s.kind)
    }

    /// Mensaje breve en el pie; a los 3 s vuelve el estado normal.
    private func flash(_ text: String, kind: EngineStatus.Kind = .warning, detail: String? = nil) {
        apply(EngineStatus(kind: kind, text: text, detail: detail))
        flashItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.apply(self.backend.state.summary)
        }
        flashItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: item)
    }

    // MARK: Actualizaciones

    private func applyUpdate(_ u: UpdateState) {
        let current = UpdateChecker.currentVersion
        var color = NSColor.secondaryLabelColor
        switch u.kind {
        case .idle:
            updateDetail.stringValue = "Versión \(current)"
            updateButton.title = "Buscar"
        case .checking:
            updateDetail.stringValue = "Buscando…"
            updateButton.title = "Buscar"
        case .upToDate:
            updateDetail.stringValue = "Estás al día · \(current)"
            updateButton.title = "Buscar"
        case .available:
            updateDetail.stringValue = "Nueva versión \(u.latest ?? "")"
            updateButton.title = "Descargar"
        case .failed:
            updateDetail.stringValue = u.message ?? "No se pudo comprobar"
            updateButton.title = "Reintentar"
            color = .systemOrange
        }
        updateButton.isEnabled = u.kind != .checking
        updateDetail.textColor = color
        updateDetail.toolTip = updateDetail.stringValue
        updateBanner.title = "Nueva versión \(u.latest ?? "") disponible · Descargar"
        refreshBanner()
    }

    /// El aviso se muestra en todas las pestañas salvo «Acerca de», que ya tiene su propia fila de actualizaciones.
    private func refreshBanner() {
        updateBanner.isHidden = backend.state.update.kind != .available || tab == .about
    }

    @objc private func openUpdate() {
        if let s = backend.state.update.url, let url = URL(string: s) { NSWorkspace.shared.open(url) }
    }

    @objc private func updateButtonTapped() {
        if backend.state.update.kind == .available {
            openUpdate()
        } else {
            backend.checkForUpdates()
            applyUpdate(backend.state.update)
        }
    }

    @objc private func openGitHub() { NSWorkspace.shared.open(UpdateChecker.repoURL) }

    // MARK: Acciones

    private func dropped(_ urls: [URL]) {
        var known = Set(backend.state.apps.map { $0.id })
        var added = 0, repeated = 0, unreadable = 0, overflow = 0
        for url in urls {
            guard let id = Bundle(url: url)?.bundleIdentifier else { unreadable += 1; continue }
            if known.contains(id) { repeated += 1; continue }
            if known.count >= maxPinnedApps { overflow += 1; continue }
            known.insert(id)
            backend.assign(id)   // la residente responde con el estado completo (nivel inicial, interruptor)
            added += 1
        }
        if overflow > 0 {
            flash("Máximo \(maxPinnedApps) apps: quita una para añadir otra")
        } else if added == 0 && unreadable > 0 {
            flash("No se pudo leer esa app", kind: .error)
        } else if added == 0 && repeated > 0 {
            flash("Esa app ya está en la lista")
        }
    }

    private func removeApp(_ id: String) {
        backend.remove(id)
        sync()
    }

    @objc private func tabChanged() { showTab(Tab(rawValue: tabs.selectedSegment) ?? .apps, animated: true) }
    @objc private func enabledChanged() { backend.setEnabled(enableSwitch.state == .on) }
    @objc private func dockChanged() { backend.setShowDock(dockSwitch.state == .on) }
    @objc private func menuBarChanged() { backend.setShowMenuBar(menuBarSwitch.state == .on) }
    @objc private func updatesChanged() { backend.setCheckUpdates(updatesSwitch.state == .on) }

    @objc private func quitTapped() {
        backend.quit()
        NSApp.terminate(nil)
    }

    @objc private func loginChanged() {
        do {
            if loginSwitch.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            loginSwitch.state = SMAppService.mainApp.status == .enabled ? .on : .off
            flash("No se pudo cambiar el inicio de sesión", kind: .error, detail: error.localizedDescription)
        }
    }
}
