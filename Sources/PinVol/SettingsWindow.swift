import AppKit
import ServiceManagement
import UniformTypeIdentifiers

// MARK: - Ventana de ajustes
//
// Tres pestañas: Apps (zona de arrastre, lista y nivel de cada app), Ajustes y Acerca de.
// La ventana se redimensiona sola al cambiar de pestaña o al añadir y quitar apps, sin mover su esquina superior izquierda.

final class SettingsWindow: NSObject, NSWindowDelegate {
    private static let positionKey = "windowTopLeft"
    private static let tabKey = "lastTab"
    private static let minWidth: CGFloat = 360
    private static let maxWidth: CGFloat = 900
    /// Página de Ko-fi a la que lleva el botón «Buy me a coffee!» de Acerca de (se abre en el navegador).
    static let donateURL = URL(string: "https://ko-fi.com/claudiouvm")!

    private enum Tab: Int, CaseIterable {
        case apps, settings, about
        var title: String {
            switch self {
            case .apps: return L("Apps")
            case .settings: return L("Settings")
            case .about: return L("About")
            }
        }
    }

    private let backend: Backend
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: max(360, scaled(360)), height: 480),
                          styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: true)
    private let scroll = NSScrollView()
    private let root = NSStackView()
    private let header = NSStackView()
    private let updateBanner = PillButton(title: "")
    private let tabs = TabBar(titles: Tab.allCases.map { $0.title })
    private let appsPage = NSStackView()
    private let settingsPage = NSStackView()
    private let aboutPage = NSStackView()
    private let panel = AppsPanel()
    private let enableSwitch = NSSwitch()
    private let loginSwitch = NSSwitch()
    private let updatesSwitch = NSSwitch()
    private let updateDetail = makeLabel("", size: 11, color: .secondaryLabelColor)
    private let updateButton = PillButton(title: L("Check"))
    private let updateProgress = NSProgressIndicator()
    private let statusDot = NSImageView()
    private let statusLabel = makeLabel("", size: 12, color: .secondaryLabelColor)
    private var tab = Tab.apps
    private var sized = false
    private var flashItem: DispatchWorkItem?
    private var suppressAnnouncement = false
    private var announcedKind: EngineStatus.Kind?
    private var announcedText = ""
    private var announcedUpdateKind: UpdateState.Kind?
    private var lastAnnouncedPercent = -1
    private var userAskedUpdate = false
    private var lastRemoved: (id: String, level: Float)?
    private var lastAlertedMessage: String?
    private var resizeTimer: Timer?
    private var resizeTarget: CGFloat = 0
    private var fittingWindow = false
    private var lastFittedHeight: CGFloat = 0
    private var lastFittedWidth: CGFloat = 0
    private var ignoreResize = false
    private var docMinHeight: NSLayoutConstraint!
    private static let resizeDuration: TimeInterval = 0.25
    var onClose: (() -> Void)?

    init(backend: Backend) {
        self.backend = backend
        super.init()
        buildUI()
        sync()
        // El tamaño final se fija con la página de apps visible (la más alta) y antes de colocar la ventana.
        // Después se abre la pestaña guardada sin volver a ajustar el alto: cambiar de pestaña no redimensiona.
        sized = true
        fitWindow(animated: false)
        showTab(Tab(rawValue: UserDefaults.standard.integer(forKey: Self.tabKey)) ?? .apps, animated: false)
        restorePosition()
        window.delegate = self
        backend.onState = { [weak self] state, full in
            if full { self?.sync() } else { self?.applyStatuses(state) }
        }
        NotificationCenter.default.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.window.contentView?.needsDisplay = true
            self?.sync()
        }
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()   // delante de otras ventanas aunque macOS no conceda la activación
        if window.initialFirstResponder == nil {
            window.initialFirstResponder = panel.firstFocusable
            window.makeFirstResponder(window.initialFirstResponder)
        }
    }

    /// Elige la pestaña por nombre (apps, settings, about). Sin `animated` es la pestaña inicial (y la de las capturas).
    func select(_ name: String, animated: Bool = false) {
        switch name {
        case "settings": showTab(.settings, animated: animated)
        case "about": showTab(.about, animated: animated)
        default: showTab(.apps, animated: animated)
        }
    }

    func windowWillClose(_ notification: Notification) {
        savePosition()
        UserDefaults.standard.synchronize()   // esta instancia termina enseguida: asegura que se escriba
        onClose?()
    }

    func windowDidMove(_ notification: Notification) { if resizeTimer == nil { savePosition() } }

    /// Al cambiar el ancho, el contenido cambia de alto: la ventana se reajusta (el alto lo decide el contenido).
    /// El aviso que llega después de un cambio de alto propio se ignora para no entrar en un bucle de layout.
    func windowDidResize(_ notification: Notification) {
        guard sized, !fittingWindow, !ignoreResize, resizeTimer == nil, tab == .apps else { return }
        let width = window.contentView?.frame.width ?? 0
        if abs(window.frame.height - lastFittedHeight) < 0.5, abs(width - lastFittedWidth) < 0.5 { return }
        fitWindow(animated: false)
    }

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

    /// El tamaño de la ventana lo decide el código, no el Auto Layout del contenido: si el contenido nuevo es más alto,
    /// AppKit agrandaría la ventana de golpe, sin animación. Por eso `root` cuelga de un contenedor sin restricción inferior.
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Alto máximo de la ventana: el contenido que no quepa se desplaza dentro de la ventana.
    private var maxWindowHeight: CGFloat {
        #if SNAPSHOT
        if let v = ProcessInfo.processInfo.environment["PV_MAX_HEIGHT"].flatMap(Double.init) { return CGFloat(v) }
        #endif
        return max(320, (window.screen?.visibleFrame.height ?? 900) - 24)
    }

    /// Alto de cada página; la ventana usa el mayor para que cambiar de pestaña no la redimensione.
    private func pageHeights() -> [CGFloat] { [appsPage, settingsPage, aboutPage].map { $0.fittingSize.height } }

    private var currentPageHeight: CGFloat {
        switch tab {
        case .apps: return appsPage.fittingSize.height
        case .settings: return settingsPage.fittingSize.height
        case .about: return aboutPage.fittingSize.height
        }
    }

    /// Ajusta la altura de la ventana al contenido, manteniendo fija su esquina superior izquierda.
    /// La altura es la de la pestaña más alta para todas: cambiar de pestaña no redimensiona.
    private func fitWindow(animated: Bool) {
        guard sized, let content = window.contentView else { return }
        root.layoutSubtreeIfNeeded()
        // Con el alto mínimo del documento activo, el contenido se estira hasta la ventana y su altura
        // ya no es la natural: se mide con esa restricción desactivada.
        docMinHeight.isActive = false
        root.layoutSubtreeIfNeeded()
        let natural = root.fittingSize.height
        let tallest = pageHeights().max() ?? currentPageHeight
        docMinHeight.isActive = true
        let chrome = window.frame.height - content.frame.height
        let desired = natural + max(0, tallest - currentPageHeight) + chrome
        let target = min(desired, maxWindowHeight)
        scroll.hasVerticalScroller = desired > maxWindowHeight + 0.5
        if resizeTimer != nil, abs(target - resizeTarget) < 0.5 { return }   // ya va hacia ahí
        resizeTimer?.invalidate()
        resizeTimer = nil
        let from = window.frame.height
        guard abs(target - from) > 0.5 else { return }
        guard animated, window.isVisible, !reduceMotion else { return setWindowHeight(target) }

        resizeTarget = target
        let start = ProcessInfo.processInfo.systemUptime
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] t in
            guard let self else { return t.invalidate() }
            let p = min((ProcessInfo.processInfo.systemUptime - start) / SettingsWindow.resizeDuration, 1)
            let eased = p < 0.5 ? 4 * p * p * p : 1 - pow(-2 * p + 2, 3) / 2   // ease in-out cúbica
            self.setWindowHeight(from + (target - from) * CGFloat(eased))
            if p >= 1 {
                t.invalidate()
                self.resizeTimer = nil
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        resizeTimer = timer
    }

    private func setWindowHeight(_ h: CGFloat) {
        fittingWindow = true
        var f = window.frame
        f.origin.y = f.maxY - h
        f.size.height = h
        ignoreResize = true
        window.setFrame(f, display: true)
        lastFittedHeight = h
        lastFittedWidth = window.contentView?.frame.width ?? 0
        fittingWindow = false
        DispatchQueue.main.async { [weak self] in self?.ignoreResize = false }
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
        window.contentMinSize = NSSize(width: Self.minWidth, height: 240)
        window.contentMaxSize = NSSize(width: Self.maxWidth, height: 3000)
        // Cabecera
        let appIcon = NSImageView(image: NSApp.applicationIconImage)
        appIcon.setAccessibilityElement(false)
        appIcon.widthAnchor.constraint(equalToConstant: 48).isActive = true
        appIcon.heightAnchor.constraint(equalToConstant: 48).isActive = true
        let titles = NSStackView(views: [
            makeLabel("PinVol", size: 20, weight: .semibold),
            makeLabel(L("Keep your apps' volume fixed"), size: 12, color: .secondaryLabelColor),
        ])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 1
        header.addArrangedSubview(appIcon)
        header.addArrangedSubview(titles)
        header.alignment = .centerY
        header.spacing = 12

        // Aviso de versión nueva
        updateBanner.image = symbol("arrow.down.circle.fill", size: scaled(12))
        updateBanner.imagePosition = .imageLeading
        updateBanner.target = self
        updateBanner.action = #selector(updateAction)
        updateBanner.isHidden = true

        // Pestañas
        tabs.onSelect = { [weak self] index in self?.showTab(Tab(rawValue: index) ?? .apps, animated: true) }
        tabs.select(Tab.apps.rawValue)

        // Interruptores
        for (sw, title, action) in [(enableSwitch, L("Keep levels fixed"), #selector(enabledChanged)),
                                    (loginSwitch, L("Open at login"), #selector(loginChanged)),
                                    (updatesSwitch, L("Check for updates"), #selector(updatesChanged))] {
            sw.target = self
            sw.action = action
            sw.setAccessibilityLabel(title)
        }

        // Pestaña Apps
        panel.onDrop = { [weak self] urls in self?.dropped(urls) }
        panel.onAdd = { [weak self] in self?.addApp() }
        panel.onRemove = { [weak self] id in self?.removeApp(id) }
        panel.onRetry = { [weak self] id in self?.backend.retry(id) }
        panel.onOpenSettings = { [weak self] _ in self?.openAudioSettings() }
        panel.onLevel = { [weak self] id, v in self?.backend.setLevel(id, v) }
        let enableCard = Card(rows: [
            formRow(L("Keep levels fixed"), detail: L("Each app stays at its own level"), control: enableSwitch),
        ])
        fill(appsPage, with: [panel, enableCard])

        // Pestaña Ajustes
        let presence = Card(rows: [
            formRow(L("Open at login"), control: loginSwitch),
        ])
        let updates = Card(rows: [
            formRow(L("Check for updates"), detail: L("Checks GitHub once a day"), control: updatesSwitch),
        ])
        fill(settingsPage, with: [presence, updates])

        // Pestaña Acerca de
        buildAbout()

        // Pie: estado + salir, al final del contenido. Si la ventana es más alta que la página, un
        // separador flexible lo empuja al fondo; si la página es más alta, se desplaza con ella.
        statusDot.image = symbol("circle.fill", size: scaled(8))
        statusDot.contentTintColor = .tertiaryLabelColor
        statusDot.setAccessibilityElement(false)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let quit = PillButton(title: L("Quit PinVol"))
        quit.target = self
        quit.action = #selector(quitTapped)
        quit.identifier = NSUserInterfaceItemIdentifier("quit")
        quit.toolTip = L("Quits PinVol completely: the app stops controlling the volume")
        let footer = NSStackView(views: [statusDot, statusLabel, spacer(), updateBanner, quit])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.distribution = .fill
        footer.spacing = 6

        let flexible = NSView()
        flexible.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .vertical)
        flexible.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(1), for: .vertical)

        // Ensamblado: cabecera, pestañas, página visible y pie. Todo dentro del scroll; el separador
        // flexible absorbe el alto sobrante para que el pie quede abajo.
        let sections: [NSView] = [header, tabs, appsPage, settingsPage, aboutPage, flexible, footer]
        for v in sections { root.addArrangedSubview(v) }
        root.orientation = .vertical
        root.alignment = .leading
        root.distribution = .fill
        root.spacing = 14
        root.setCustomSpacing(18, after: header)
        root.setCustomSpacing(0, after: flexible)
        root.edgeInsets = NSEdgeInsets(top: scaled(32), left: 20, bottom: 8, right: 20)
        for v in sections { v.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -40).isActive = true }

        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        root.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: document.topAnchor),
            root.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            root.bottomAnchor.constraint(equalTo: document.bottomAnchor),
        ])
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        scroll.documentView = document
        window.contentView = scroll
        docMinHeight = document.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor)
        docMinHeight.isActive = true
        NSLayoutConstraint.activate([
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])
        window.title = "PinVol"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.closeButton)?.setAccessibilityHelp(L("Closes the window; PinVol keeps running in the menu bar"))
        showTab(.apps, animated: false)
    }

    private func buildAbout() {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let channel = (info?["PinVolReleaseChannel"] as? String).map { "\($0) " } ?? ""

        // Mismo esqueleto que Ajustes: la cabecera de la ventana ya muestra el ícono y el nombre; aquí van
        // la versión (en la fila de actualizaciones), la autoría y los enlaces, alineados como el resto.
        let madeIn = makeLabel(L("Made in Chile by Claudiouvm and Claude ♥"), size: 12, color: .secondaryLabelColor)

        updateButton.target = self
        updateButton.action = #selector(updateAction)
        updateDetail.lineBreakMode = .byWordWrapping
        updateDetail.maximumNumberOfLines = 2
        updateProgress.style = .bar
        updateProgress.isIndeterminate = false
        updateProgress.minValue = 0
        updateProgress.maxValue = 1
        updateProgress.controlSize = .small
        updateProgress.isHidden = true
        updateProgress.setAccessibilityLabel(L("Download progress"))
        let updateTitles = NSStackView(views: [makeLabel(L("Updates")), updateDetail, updateProgress])
        updateTitles.orientation = .vertical
        updateTitles.alignment = .leading
        updateTitles.spacing = 2
        updateTitles.setCustomSpacing(4, after: updateDetail)
        let updateRow = NSView()
        for v in [updateTitles, updateButton] { v.translatesAutoresizingMaskIntoConstraints = false; updateRow.addSubview(v) }
        NSLayoutConstraint.activate([
            updateTitles.leadingAnchor.constraint(equalTo: updateRow.leadingAnchor, constant: 14),
            updateTitles.centerYAnchor.constraint(equalTo: updateRow.centerYAnchor),
            updateButton.trailingAnchor.constraint(equalTo: updateRow.trailingAnchor, constant: -14),
            updateButton.centerYAnchor.constraint(equalTo: updateRow.centerYAnchor),
            updateButton.leadingAnchor.constraint(greaterThanOrEqualTo: updateTitles.trailingAnchor, constant: 10),
            updateRow.heightAnchor.constraint(equalToConstant: scaled(64)),
            updateProgress.widthAnchor.constraint(equalTo: updateTitles.widthAnchor),
        ])
        let updateCard = Card(rows: [updateRow])

        let github = NSButton(title: L("Source code on GitHub"), target: self, action: #selector(openGitHub))
        github.isBordered = false
        github.contentTintColor = .linkColor
        // Subrayado: el enlace no puede distinguirse solo por el color (WCAG 1.4.1).
        github.attributedTitle = NSAttributedString(string: L("Source code on GitHub"), attributes: [
            .font: scaledFont(12),
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ])
        github.setAccessibilityLabel(L("Source code on GitHub"))

        let coffee = PillButton(title: L("Buy me a coffee!"))
        coffee.image = symbol("cup.and.saucer.fill", size: scaled(12))
        coffee.target = self
        coffee.action = #selector(openDonate)
        coffee.imagePosition = .imageLeading
        coffee.toolTip = L("Support PinVol on Ko-fi")

        let links = NSStackView(views: [github, spacer(), coffee])
        links.orientation = .horizontal
        links.alignment = .centerY
        links.spacing = 12

        let aboutViews: [NSView] = [madeIn, updateCard, links]
        for v in aboutViews {
            aboutPage.addArrangedSubview(v)
            v.widthAnchor.constraint(equalTo: aboutPage.widthAnchor).isActive = true
        }
        aboutPage.orientation = .vertical
        aboutPage.alignment = .leading
        aboutPage.spacing = 10
        aboutPage.setCustomSpacing(18, after: updateCard)
    }

    private func showTab(_ t: Tab, animated: Bool) {
        let changed = t != tab
        tab = t
        tabs.select(t.rawValue)
        let pages = [appsPage, settingsPage, aboutPage]
        for (i, page) in pages.enumerated() {
            page.isHidden = i != t.rawValue
            page.alphaValue = 1
        }
        if changed { UserDefaults.standard.set(t.rawValue, forKey: Self.tabKey) }
        refreshBanner()
        if animated && changed && sized && !reduceMotion {   // la página nueva aparece con un fundido
            let incoming = pages[t.rawValue]
            incoming.alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = SettingsWindow.resizeDuration
                incoming.animator().alphaValue = 1
            }
        }
    }

    /// Refleja en los controles lo que dice el estado.
    private func sync() {
        let st = backend.state
        panel.update(apps: st.apps, full: true)
        enableSwitch.state = st.enabled ? .on : .off
        updatesSwitch.state = st.checkUpdates ? .on : .off
        loginSwitch.state = SMAppService.mainApp.status == .enabled ? .on : .off
        applyUpdate(st.update)
        apply(st.summary)
        if window.initialFirstResponder == nil { window.initialFirstResponder = panel.firstFocusable }
        // El alto solo se recalcula con la página de apps delante: al cambiar de pestaña no se redimensiona.
        if tab == .apps { fitWindow(animated: true) }
    }

    private func applyStatuses(_ st: AppState) {
        panel.update(apps: st.apps, full: false)
        apply(st.summary)
    }

    func apply(_ s: EngineStatus, announceChange: Bool = true) {
        statusLabel.stringValue = s.text
        statusLabel.toolTip = s.detail ?? s.text
        statusDot.contentTintColor = statusColor(s.kind)

        let kindChanged = s.kind != announcedKind
        let newDetail = (s.kind == .error || s.kind == .warning) && s.text != announcedText
        announcedKind = s.kind
        announcedText = s.text
        guard announceChange, !suppressAnnouncement, window.isVisible, kindChanged || newDetail else { return }
        let message = [s.text, s.detail].compactMap { $0 }.joined(separator: ". ")
        announce(message, priority: s.kind == .error ? .high : .medium)
    }

    /// Mensaje breve en el pie; a los 3 s vuelve el estado normal.
    private func flash(_ text: String, kind: EngineStatus.Kind = .warning, detail: String? = nil) {
        suppressAnnouncement = true
        apply(EngineStatus(kind: kind, text: text, detail: detail))
        suppressAnnouncement = false
        announce([text, detail].compactMap { $0 }.joined(separator: ". "), priority: kind == .error ? .high : .medium)
        flashItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.suppressAnnouncement = true
            self.apply(self.backend.state.summary)
            self.suppressAnnouncement = false
        }
        flashItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: item)
    }

    // MARK: Actualizaciones

    private func applyUpdate(_ u: UpdateState) {
        let current = UpdateChecker.currentVersion
        let latest = u.latest ?? ""
        let percent = percentText(Float(u.progress ?? 0))
        var color = NSColor.secondaryLabelColor
        var enabled = true
        switch u.kind {
        case .idle:
            updateDetail.stringValue = L("Version %@", current)
            updateButton.title = L("Check")
        case .checking:
            updateDetail.stringValue = L("Checking…")
            updateButton.title = L("Check")
            enabled = false
        case .upToDate:
            updateDetail.stringValue = L("Up to date · %@", current)
            updateButton.title = L("Check")
        case .available:   // tras una descarga fallida, el motivo ocupa el sitio de la versión
            updateDetail.stringValue = u.message ?? L("New version %@", latest)
            updateButton.title = L("Download")
            if u.message != nil { color = .systemOrange }
        case .downloading:
            updateDetail.stringValue = L("Downloading… %@", percent)
            updateButton.title = L("Download")
            enabled = false
        case .ready:
            updateDetail.stringValue = u.message ?? L("Ready to install · %@", latest)
            updateButton.title = L("Install")
            if u.message != nil { color = .systemOrange }
        case .installing:
            updateDetail.stringValue = L("Installing…")
            updateButton.title = L("Install")
            enabled = false
        case .failed:
            updateDetail.stringValue = u.message ?? L("Couldn't check")
            updateButton.title = L("Retry")
            color = .systemOrange
        }
        updateButton.isEnabled = enabled
        updateButton.invalidateIntrinsicContentSize()
        switch u.kind {
        case .available: updateButton.setAccessibilityLabel(L("Download update"))
        case .ready: updateButton.setAccessibilityLabel(L("Install update"))
        case .failed: updateButton.setAccessibilityLabel(L("Retry the update"))
        default: updateButton.setAccessibilityLabel(L("Check for updates"))
        }
        updateDetail.textColor = color
        updateDetail.toolTip = updateDetail.stringValue
        updateProgress.isHidden = u.kind != .downloading
        updateProgress.doubleValue = u.progress ?? 0
        updateProgress.setAccessibilityValueDescription(percentText(Float(u.progress ?? 0)))
        if u.kind == .downloading {
            let step = Int(((u.progress ?? 0) * 10).rounded(.down)) * 10
            if step != lastAnnouncedPercent, window.isVisible {
                lastAnnouncedPercent = step
                announce(L("Downloading… %@", percent))
            }
        } else {
            lastAnnouncedPercent = -1
        }
        if window.isVisible, u.kind != announcedUpdateKind,
           [.available, .ready, .failed, .upToDate].contains(u.kind) {
            announce(updateDetail.stringValue, priority: u.kind == .failed ? .high : .medium)
        }
        announcedUpdateKind = u.kind

        // Un fallo de una acción que pidió el usuario se muestra en una alerta, no solo en una etiqueta de 11 pt.
        if userAskedUpdate {
            if let message = u.message, u.kind != .downloading, message != lastAlertedMessage {
                lastAlertedMessage = message
                userAskedUpdate = false
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.alertStyle = .warning
                    alert.messageText = L("Couldn't update")
                    alert.informativeText = message
                    alert.addButton(withTitle: L("OK"))
                    alert.runModal()
                }
            } else if u.kind == .upToDate || (u.kind == .available && u.message == nil) || u.kind == .ready {
                userAskedUpdate = false
            }
        }

        switch u.kind {
        case .available:
            updateBanner.title = L("Update")
            updateBanner.toolTip = L("Version %@ available · Download", latest)
            updateBanner.setAccessibilityLabel(L("Version %@ available · Download", latest))
        case .downloading:
            updateBanner.title = percent
            updateBanner.toolTip = L("Downloading… %@", percent)
            updateBanner.setAccessibilityLabel(L("Downloading… %@", percent))
        case .ready:
            updateBanner.title = L("Install")
            updateBanner.toolTip = L("Version %@ ready · Install and restart", latest)
            updateBanner.setAccessibilityLabel(L("Version %@ ready · Install and restart", latest))
        case .installing:
            updateBanner.title = L("Installing…")
            updateBanner.toolTip = updateDetail.stringValue
            updateBanner.setAccessibilityLabel(L("Installing…"))
        default: break
        }
        updateBanner.isEnabled = u.kind == .available || u.kind == .ready
        updateBanner.invalidateIntrinsicContentSize()
        refreshBanner()
    }

    private static let bannerKinds: Set<UpdateState.Kind> = [.available, .downloading, .ready, .installing]

    /// El aviso se muestra en todas las pestañas salvo «Acerca de», que ya tiene su propia fila de actualizaciones.
    private func refreshBanner() {
        updateBanner.isHidden = !Self.bannerKinds.contains(backend.state.update.kind) || tab == .about
    }

    /// Lo que piden el botón de Acerca de y el aviso de arriba según el estado: descargar, instalar o buscar.
    @objc private func updateAction() {
        userAskedUpdate = true
        switch backend.state.update.kind {
        case .available: backend.downloadUpdate()
        case .ready: backend.installUpdate()
        case .checking, .downloading, .installing: break
        default: backend.checkForUpdates()
        }
        applyUpdate(backend.state.update)
    }

    @objc private func openGitHub() { NSWorkspace.shared.open(UpdateChecker.repoURL) }

    @objc private func openDonate() { NSWorkspace.shared.open(Self.donateURL) }

    // MARK: Añadir y quitar sin ratón

    /// Abre el panel para elegir apps, igual que soltarlas en la ventana. Es la vía accesible (⌘O).
    func addApp() {
        let picker = NSOpenPanel()
        picker.canChooseFiles = true
        picker.canChooseDirectories = false
        picker.allowsMultipleSelection = true
        picker.treatsFilePackagesAsDirectories = false
        picker.allowedContentTypes = [.applicationBundle]
        picker.prompt = L("Pin")
        picker.message = L("Choose the app to pin")
        if picker.runModal() == .OK { dropped(picker.urls) }
    }

    /// Quita la app de la fila que tiene el foco (tecla Supr o menú «Quitar app»).
    func removeFocusedApp() {
        guard let row = focusedRow() else { return }
        removeApp(row.id)
    }

    private func focusedRow() -> AppRow? {
        var responder: NSResponder? = window.firstResponder
        while let r = responder {
            if let row = r as? AppRow { return row }
            responder = r.nextResponder
        }
        return nil
    }

    private func openAudioSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Acciones

    private func dropped(_ urls: [URL]) {
        let wasEnabled = backend.state.enabled
        var known = Set(backend.state.apps.map { $0.id })
        var added = 0, repeated = 0, unreadable = 0, overflow = 0, notApp = 0
        for url in urls {
            guard url.pathExtension.lowercased() == "app" else { notApp += 1; continue }
            guard let id = Bundle(url: url)?.bundleIdentifier else { unreadable += 1; continue }
            if known.contains(id) { repeated += 1; continue }
            if known.count >= maxPinnedApps { overflow += 1; continue }
            known.insert(id)
            backend.assign(id, level: nil)   // la residente responde con el estado completo (nivel inicial, interruptor)
            added += 1
        }
        if overflow > 0 {
            flash(L("Maximum %ld apps: remove one to add another", maxPinnedApps))
        } else if added > 0 && !wasEnabled {
            flash(L("Fixed levels are on now"))
        } else if added == 0 && notApp > 0 {
            flash(L("Only .app bundles can be pinned"))
        } else if added == 0 && unreadable > 0 {
            flash(L("Couldn't read that app"), kind: .error)
        } else if added == 0 && repeated > 0 {
            flash(L("That app is already in the list"))
        }
    }

    private func removeApp(_ id: String) {
        let removed = backend.state.apps.first { $0.id == id }
        backend.remove(id)
        sync()
        if let removed { lastRemoved = (removed.id, removed.level) }
    }

    /// ⌘Z: vuelve a añadir la última app quitada, con su nivel.
    func undoRemove() {
        guard let removed = lastRemoved else { return }
        lastRemoved = nil
        backend.assign(removed.id, level: removed.level)
        sync()
        flash(L("App added back"))
    }

    @objc private func enabledChanged() { backend.setEnabled(enableSwitch.state == .on) }
    @objc private func updatesChanged() { backend.setCheckUpdates(updatesSwitch.state == .on) }

    @objc private func quitTapped() {
        if backend.state.enabled && !backend.state.apps.isEmpty {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L("Quit PinVol?")
            alert.informativeText = L("The apps you pinned will follow the Mac's volume again.")
            alert.addButton(withTitle: L("Quit PinVol"))
            alert.addButton(withTitle: L("Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        backend.quit()
        NSApp.terminate(nil)
    }

    @objc private func loginChanged() {
        do {
            if loginSwitch.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            loginSwitch.state = SMAppService.mainApp.status == .enabled ? .on : .off
            flash(L("Couldn't change the login setting"), kind: .error, detail: error.localizedDescription)
        }
    }
}
