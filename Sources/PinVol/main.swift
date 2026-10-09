import AppKit
import ServiceManagement

// MARK: - Estilo

/// Relleno de las tarjetas: blanco en claro, velo translúcido en oscuro (como Ajustes del Sistema).
private let cardFill = NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.07) : .white
}

private func makeLabel(_ text: String = "", size: CGFloat = 13, weight: NSFont.Weight = .regular,
                       color: NSColor = .labelColor) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = .systemFont(ofSize: size, weight: weight)
    l.textColor = color
    l.lineBreakMode = .byTruncatingTail
    return l
}

private func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: size, weight: weight))
}

private func symbolView(_ name: String, size: CGFloat, color: NSColor) -> NSImageView {
    let v = NSImageView(image: symbol(name, size: size) ?? NSImage())
    v.contentTintColor = color
    return v
}

private func spacer() -> NSView {
    let v = NSView()
    v.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
    return v
}

// MARK: - Tarjeta agrupada

final class Separator: NSView {
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 1) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        NSRect(x: 14, y: 0, width: max(bounds.width - 14, 0), height: 0.5).fill()
    }
}

/// Filas separadas por líneas finas dentro de un rectángulo redondeado.
final class Card: NSView {
    init(rows: [NSView]) {
        super.init(frame: .zero)
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        for (i, row) in rows.enumerated() {
            if i > 0 {
                let sep = Separator()
                stack.addArrangedSubview(sep)
                sep.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        cardFill.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

/// Fila de ajustes: título (y detalle opcional) a la izquierda, control a la derecha.
private func formRow(_ title: String, detail: String? = nil, control: NSView) -> NSView {
    let titleLabel = makeLabel(title)
    let left: NSView
    if let detail {
        let d = makeLabel(detail, size: 11, color: .secondaryLabelColor)
        let v = NSStackView(views: [titleLabel, d])
        v.orientation = .vertical
        v.alignment = .leading
        v.spacing = 1
        left = v
    } else {
        left = titleLabel
    }
    let row = NSView()
    for v in [left, control] { v.translatesAutoresizingMaskIntoConstraints = false; row.addSubview(v) }
    NSLayoutConstraint.activate([
        left.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
        left.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        control.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -14),
        control.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        left.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -10),
        row.heightAnchor.constraint(equalToConstant: detail == nil ? 44 : 54),
    ])
    return row
}

// MARK: - Zona de arrastre

final class DropCard: NSView {
    var onDrop: ((URL) -> Void)?
    var onRemove: (() -> Void)?
    private let icon = NSImageView()
    private let title = makeLabel("", size: 13, weight: .semibold)
    private let caption = makeLabel("", size: 11, color: .secondaryLabelColor)
    private var assigned = false { didSet { needsDisplay = true } }
    private var highlighted = false { didSet { needsDisplay = true } }

    init() {
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
        icon.imageScaling = .scaleProportionallyUpOrDown
        title.alignment = .center
        caption.alignment = .center

        let stack = NSStackView(views: [icon, title, caption])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 3
        stack.setCustomSpacing(10, after: icon)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            icon.widthAnchor.constraint(equalToConstant: 56),
            icon.heightAnchor.constraint(equalToConstant: 56),
            heightAnchor.constraint(equalToConstant: 140),
        ])
        show(appURL: nil, name: nil, assigned: false)
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(appURL: URL?, name: String?, assigned: Bool) {
        self.assigned = assigned
        if assigned {
            icon.image = appURL.map { NSWorkspace.shared.icon(forFile: $0.path) }
                ?? symbol("app.dashed", size: 40, weight: .light)
            icon.contentTintColor = appURL == nil ? .secondaryLabelColor : nil
            title.stringValue = name ?? appURL?.deletingPathExtension().lastPathComponent ?? ""
            title.textColor = .labelColor
            caption.stringValue = "Doble clic o ⌘-clic para quitar"
            toolTip = "Doble clic, ⌘-clic o clic derecho para dejar de controlar esta app"
        } else {
            icon.image = symbol("arrow.down.app", size: 38, weight: .light)
            icon.contentTintColor = .secondaryLabelColor
            title.stringValue = "Arrastra una app aquí"
            title.textColor = .labelColor
            caption.stringValue = "Su volumen quedará fijo"
            toolTip = "Suelta aquí el archivo .app cuyo volumen quieres mantener fijo"
        }
    }

    private func appURL(_ info: NSDraggingInfo) -> URL? {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                       options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return urls?.first { $0.pathExtension == "app" }
    }

    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation {
        guard appURL(s) != nil else { return [] }
        highlighted = true
        return .copy
    }
    override func draggingExited(_ s: NSDraggingInfo?) { highlighted = false }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        highlighted = false
        guard let u = appURL(s) else { return false }
        onDrop?(u)
        return true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if assigned, event.clickCount >= 2 || event.modifierFlags.contains(.command) { onRemove?() }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard assigned else { return nil }
        let m = NSMenu()
        m.addItem(withTitle: "Quitar app", action: #selector(removeTapped), keyEquivalent: "").target = self
        return m
    }
    @objc private func removeTapped() { onRemove?() }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 14, yRadius: 14)
        if highlighted {
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            path.fill()
        } else if assigned {
            cardFill.setFill()
            path.fill()
        }
        (highlighted ? NSColor.controlAccentColor : assigned ? NSColor.separatorColor : NSColor.tertiaryLabelColor).setStroke()
        path.lineWidth = highlighted ? 2 : 1
        if !assigned { path.setLineDash([6, 4], count: 2, phase: 0) }
        path.stroke()
    }
}

#if SNAPSHOT
/// Solo desarrollo: traza a un archivo (el registro unificado oculta los textos dinámicos).
func devLog(_ s: String) {
    let line = "\(getpid()) \(s)\n"
    let path = ProcessInfo.processInfo.environment["PV_LOG"] ?? "/tmp/pinvol-dev.log"
    if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(Data(line.utf8)); h.closeFile() }
    else { try? line.write(toFile: path, atomically: false, encoding: .utf8) }
}
#endif

// MARK: - Estado y mensajería entre procesos
//
// PinVol corre como dos instancias de la misma app:
//  · la residente (Dock/barra de menú + motor de audio), siempre viva y pequeña;
//  · la de interfaz (`--ui`), que muestra la ventana y termina al cerrarla.
// Así la memoria que AppKit reserva para dibujar la ventana se devuelve al sistema al cerrarla.

struct AppState {
    var bundleID: String?
    var level: Float = 0.5
    var enabled = false
    var showDock = true
    var showMenuBar = true
    var status = EngineStatus(kind: .idle, text: "")

    init() {}

    init(_ d: [AnyHashable: Any]) {
        bundleID = d["bundleID"] as? String
        level = Float(d["level"] as? Double ?? 0.5)
        enabled = d["enabled"] as? Bool ?? false
        showDock = d["showDock"] as? Bool ?? true
        showMenuBar = d["showMenuBar"] as? Bool ?? true
        status = EngineStatus(kind: EngineStatus.Kind(rawValue: d["kind"] as? String ?? "") ?? .idle,
                              text: d["text"] as? String ?? "", detail: d["detail"] as? String)
    }

    func dictionary(full: Bool) -> [String: Any] {
        var d: [String: Any] = ["level": Double(level), "enabled": enabled, "showDock": showDock, "showMenuBar": showMenuBar,
                                "kind": status.kind.rawValue, "text": status.text, "full": full]
        if let id = bundleID { d["bundleID"] = id }
        if let detail = status.detail { d["detail"] = detail }
        return d
    }
}

enum IPC {
    // Los nombres derivan del identificador del bundle: dos variantes de la app (p. ej. una de desarrollo) no se mezclan.
    private static let prefix = Bundle.main.bundleIdentifier ?? "com.claudiouvm.pinvol"
    static let toResident = Notification.Name(prefix + ".toResident")
    static let toUI = Notification.Name(prefix + ".toUI")

    static func post(_ name: Notification.Name, _ info: [String: Any]) {
        DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: info, deliverImmediately: true)
    }
}

/// Escucha un tipo de mensaje del otro proceso. Se entrega siempre, aunque la app esté en segundo plano.
final class IPCObserver: NSObject {
    private let handler: ([AnyHashable: Any]) -> Void

    init(_ name: Notification.Name, handler: @escaping ([AnyHashable: Any]) -> Void) {
        self.handler = handler
        super.init()
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(received(_:)), name: name, object: nil,
                                                            suspensionBehavior: .deliverImmediately)
    }

    deinit { DistributedNotificationCenter.default().removeObserver(self) }

    @objc private func received(_ n: Notification) { handler(n.userInfo ?? [:]) }
}

/// Lo que la ventana necesita del resto de la app (en producción, hablar con la instancia residente).
protocol Backend: AnyObject {
    var state: AppState { get }
    var onState: ((AppState, Bool) -> Void)? { get set }   // (estado, ¿completo?)
    func assign(_ id: String)
    func removeApp()
    func setLevel(_ v: Float)
    func setEnabled(_ on: Bool)
    func setShowDock(_ on: Bool)
    func setShowMenuBar(_ on: Bool)
    func quit()
}

// MARK: - Instancia residente: ajustes guardados + motor

final class Controller {
    let defaults: UserDefaults
    let engine = Engine()
    private(set) var status = EngineStatus(kind: .idle, text: "")
    private(set) var level: Float
    private(set) var enabled: Bool
    private(set) var showDock: Bool
    private(set) var showMenuBar: Bool
    private var uiActive = false
    private var observer: IPCObserver?
    var onStatus: ((EngineStatus) -> Void)?
    var onPresence: (() -> Void)?
    var onShow: (() -> Void)?

    var state: AppState {
        var s = AppState()
        s.bundleID = engine.bundleID
        s.level = level
        s.enabled = enabled
        s.showDock = showDock
        s.showMenuBar = showMenuBar
        s.status = status
        return s
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        level = defaults.object(forKey: "level") as? Float ?? 0.5
        enabled = defaults.bool(forKey: "enabled")
        showDock = defaults.object(forKey: "showDock") as? Bool ?? true
        showMenuBar = defaults.object(forKey: "showMenuBar") as? Bool ?? true
        engine.onStatus = { [weak self] s in
            self?.status = s
            self?.onStatus?(s)
            self?.broadcast(full: false)
        }
        observer = IPCObserver(IPC.toResident) { [weak self] in self?.handle($0) }
    }

    /// Arranca el motor con lo guardado.
    func start() {
        engine.level = level
        engine.bundleID = defaults.string(forKey: "bundleID")
        engine.enabled = enabled
        engine.reconcile()
    }

    private func broadcast(full: Bool) {
        if uiActive { IPC.post(IPC.toUI, state.dictionary(full: full)) }
    }

    private func handle(_ m: [AnyHashable: Any]) {
        #if SNAPSHOT
        devLog("residente recibió op=\(String(describing: m["op"]))")
        #endif
        switch m["op"] as? String {
        case "hello": uiActive = true; broadcast(full: true)
        case "bye": uiActive = false
        case "assign": if let id = m["id"] as? String { assign(id) }
        case "remove": removeApp()
        case "level": if let v = m["value"] as? Double { setLevel(Float(v)) }
        case "enabled": if let v = m["value"] as? Bool { setEnabled(v) }
        case "dock": if let v = m["value"] as? Bool { setShowDock(v) }
        case "menubar": if let v = m["value"] as? Bool { setShowMenuBar(v) }
        case "show": onShow?()
        case "quit": NSApp.terminate(nil)
        default: break
        }
    }

    /// Asigna una app. El nivel inicial es el volumen actual del sistema.
    private func assign(_ id: String) {
        defaults.set(id, forKey: "bundleID")
        engine.bundleID = id
        if let dev = defaultOutputDevice(), let m = MasterVolume(device: dev) { setLevel(m.scalar) }
        setEnabled(true)
    }

    /// Deja de controlar la app: se destruye el tap y su audio vuelve a sonar normal.
    private func removeApp() {
        defaults.removeObject(forKey: "bundleID")
        engine.bundleID = nil
        broadcast(full: true)
    }

    private func setLevel(_ v: Float) {
        level = v
        defaults.set(v, forKey: "level")
        engine.level = v
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        defaults.set(on, forKey: "enabled")
        engine.enabled = on
        broadcast(full: true)
    }

    // Siempre debe quedar al menos una vía de acceso (Dock o barra de menús); si no, la app sería inalcanzable.
    private func setShowDock(_ on: Bool) {
        if on || showMenuBar {
            showDock = on
            defaults.set(on, forKey: "showDock")
            onPresence?()
        }
        broadcast(full: true)
    }

    private func setShowMenuBar(_ on: Bool) {
        if on || showDock {
            showMenuBar = on
            defaults.set(on, forKey: "showMenuBar")
            onPresence?()
        }
        broadcast(full: true)
    }
}

// MARK: - Instancia de interfaz: habla con la residente

final class RemoteBackend: Backend {
    private(set) var state = AppState()
    var onState: ((AppState, Bool) -> Void)?
    var onShow: (() -> Void)?
    private var observer: IPCObserver?

    init() {
        observer = IPCObserver(IPC.toUI) { [weak self] d in
            guard let self else { return }
            if d["bye"] != nil { return NSApp.terminate(nil) }
            if d["show"] != nil { return self.onShow?() ?? () }
            let incoming = AppState(d)
            let full = d["full"] as? Bool ?? true
            #if SNAPSHOT
            devLog("interfaz recibió estado full=\(full) texto=\(incoming.status.text)")
            #endif
            if full { self.state = incoming } else { self.state.status = incoming.status }   // no pisar el slider mientras se arrastra
            self.onState?(self.state, full)
        }
    }

    func connect() { IPC.post(IPC.toResident, ["op": "hello"]) }
    func disconnect() { IPC.post(IPC.toResident, ["op": "bye"]) }
    func assign(_ id: String) { IPC.post(IPC.toResident, ["op": "assign", "id": id]) }
    func removeApp() { state.bundleID = nil; IPC.post(IPC.toResident, ["op": "remove"]) }
    func setLevel(_ v: Float) { state.level = v; IPC.post(IPC.toResident, ["op": "level", "value": Double(v)]) }
    func setEnabled(_ on: Bool) { state.enabled = on; IPC.post(IPC.toResident, ["op": "enabled", "value": on]) }
    func setShowDock(_ on: Bool) { IPC.post(IPC.toResident, ["op": "dock", "value": on]) }
    func setShowMenuBar(_ on: Bool) { IPC.post(IPC.toResident, ["op": "menubar", "value": on]) }
    func quit() { IPC.post(IPC.toResident, ["op": "quit"]) }
}

// MARK: - Ventana de ajustes

final class SettingsWindow: NSObject, NSWindowDelegate {
    private static let positionKey = "windowTopLeft"

    private let backend: Backend
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 340, height: 480),
                          styleMask: [.titled, .closable, .fullSizeContentView],
                          backing: .buffered, defer: true)
    private let drop = DropCard()
    private let enableSwitch = NSSwitch()
    private let dockSwitch = NSSwitch()
    private let menuBarSwitch = NSSwitch()
    private let loginSwitch = NSSwitch()
    private let slider = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let valueLabel = makeLabel("", color: .secondaryLabelColor)
    private let statusDot = NSImageView()
    private let statusLabel = makeLabel("", size: 12, color: .secondaryLabelColor)
    var onClose: (() -> Void)?

    init(backend: Backend) {
        self.backend = backend
        super.init()
        UserDefaults.standard.removeObject(forKey: "NSWindow Frame PinVolWindow")   // clave antigua del guardado automático
        buildUI()
        sync()
        apply(backend.state.status)
        backend.onState = { [weak self] state, full in
            self?.apply(state.status)
            if full { self?.sync() }
        }
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()   // delante de otras ventanas aunque macOS no conceda la activación
    }

    func windowWillClose(_ notification: Notification) {
        savePosition()
        UserDefaults.standard.synchronize()   // esta instancia termina enseguida: asegura que se escriba
        onClose?()
    }

    func windowDidMove(_ notification: Notification) { savePosition() }

    // MARK: Posición

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

    // MARK: Interfaz

    private func buildUI() {
        // Cabecera
        let appIcon = NSImageView(image: NSApp.applicationIconImage)
        appIcon.widthAnchor.constraint(equalToConstant: 48).isActive = true
        appIcon.heightAnchor.constraint(equalToConstant: 48).isActive = true
        let titles = NSStackView(views: [
            makeLabel("PinVol", size: 20, weight: .semibold),
            makeLabel("Mantén fijo el volumen de una app", size: 12, color: .secondaryLabelColor),
        ])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 1
        let header = NSStackView(views: [appIcon, titles])
        header.alignment = .centerY
        header.spacing = 12

        // Zona de arrastre
        drop.onDrop = { [weak self] url in self?.dropped(url) }
        drop.onRemove = { [weak self] in self?.removeApp() }

        // Interruptores
        for (sw, title, action) in [(enableSwitch, "Mantener nivel fijo", #selector(enabledChanged)),
                                    (dockSwitch, "Mostrar en el Dock", #selector(dockChanged)),
                                    (menuBarSwitch, "Mostrar en la barra de menús", #selector(menuBarChanged)),
                                    (loginSwitch, "Abrir al iniciar sesión", #selector(loginChanged))] {
            sw.target = self
            sw.action = action
            sw.setAccessibilityLabel(title)
        }

        slider.target = self
        slider.action = #selector(levelChanged)
        slider.isContinuous = true
        slider.setAccessibilityLabel("Nivel fijo")
        slider.toolTip = "Volumen al que sonará la app, en la misma escala que el volumen del sistema"
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)

        let levelHeader = NSStackView(views: [makeLabel("Nivel fijo"), spacer(), valueLabel])
        let levelSlider = NSStackView(views: [
            symbolView("speaker.fill", size: 11, color: .secondaryLabelColor),
            slider,
            symbolView("speaker.wave.3.fill", size: 11, color: .secondaryLabelColor),
        ])
        levelSlider.spacing = 8
        let levelStack = NSStackView(views: [levelHeader, levelSlider])
        levelStack.orientation = .vertical
        levelStack.alignment = .leading
        levelStack.spacing = 8
        levelStack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 14, right: 14)
        for v in [levelHeader, levelSlider] { v.widthAnchor.constraint(equalTo: levelStack.widthAnchor, constant: -28).isActive = true }

        let level = Card(rows: [
            formRow("Mantener nivel fijo", detail: "Compensa el volumen general del Mac", control: enableSwitch),
            levelStack,
        ])
        let presence = Card(rows: [
            formRow("Mostrar en el Dock", control: dockSwitch),
            formRow("Mostrar en la barra de menús", control: menuBarSwitch),
            formRow("Abrir al iniciar sesión", control: loginSwitch),
        ])

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
        let sections = [header, drop, level, presence, footer]
        let root = NSStackView(views: sections)
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.setCustomSpacing(18, after: header)
        root.edgeInsets = NSEdgeInsets(top: 44, left: 20, bottom: 18, right: 20)
        for v in sections { v.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -40).isActive = true }
        root.widthAnchor.constraint(equalToConstant: 340).isActive = true

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
        // El tamaño final se fija antes de colocar la ventana (ver restorePosition).
        root.layoutSubtreeIfNeeded()
        window.setContentSize(root.fittingSize)
        restorePosition()
        window.delegate = self
    }

    /// Refleja en los controles lo que dice el estado.
    private func sync() {
        let st = backend.state
        if let id = st.bundleID {
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
            let name = url.flatMap { Bundle(url: $0) }.flatMap {
                $0.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? $0.object(forInfoDictionaryKey: "CFBundleName") as? String
            }
            drop.show(appURL: url, name: name ?? id, assigned: true)
        } else {
            drop.show(appURL: nil, name: nil, assigned: false)
        }
        slider.floatValue = st.level
        valueLabel.stringValue = "\(Int((st.level * 100).rounded())) %"
        enableSwitch.state = st.enabled ? .on : .off
        dockSwitch.state = st.showDock ? .on : .off
        menuBarSwitch.state = st.showMenuBar ? .on : .off
        loginSwitch.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    func apply(_ s: EngineStatus) {
        statusLabel.stringValue = s.text
        statusLabel.toolTip = s.detail ?? s.text
        switch s.kind {
        case .idle: statusDot.contentTintColor = .tertiaryLabelColor
        case .waiting, .warning: statusDot.contentTintColor = .systemOrange
        case .active: statusDot.contentTintColor = .systemGreen
        case .error: statusDot.contentTintColor = .systemRed
        }
    }

    private func dropped(_ url: URL) {
        guard let id = Bundle(url: url)?.bundleIdentifier else {
            return apply(EngineStatus(kind: .error, text: "No se pudo leer esa app"))
        }
        backend.assign(id)   // la residente responde con el estado completo (nivel inicial, interruptor)
    }

    private func removeApp() {
        backend.removeApp()
        sync()
    }

    @objc private func levelChanged() {
        backend.setLevel(slider.floatValue)
        valueLabel.stringValue = "\(Int((slider.floatValue * 100).rounded())) %"
    }

    @objc private func enabledChanged() { backend.setEnabled(enableSwitch.state == .on) }
    @objc private func dockChanged() { backend.setShowDock(dockSwitch.state == .on) }
    @objc private func menuBarChanged() { backend.setShowMenuBar(menuBarSwitch.state == .on) }

    @objc private func quitTapped() {
        backend.quit()
        NSApp.terminate(nil)
    }

    @objc private func loginChanged() {
        do {
            if loginSwitch.state == .on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            loginSwitch.state = SMAppService.mainApp.status == .enabled ? .on : .off
            apply(EngineStatus(kind: .error, text: "No se pudo cambiar el inicio de sesión", detail: error.localizedDescription))
        }
    }
}

// MARK: - Menú principal compartido

private func installMainMenu(quitAction: Selector, quitTitle: String, extra: [NSMenuItem] = []) {
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
        model.onStatus = { [weak self] in self?.statusChanged($0) }
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

    private func statusChanged(_ s: EngineStatus) {
        let active = s.kind == .active
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
        let st = model.status
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

#if SNAPSHOT
// MARK: - Solo desarrollo: renderiza la ventana a un PNG
// `--snapshot out.png [--dark] [--assigned id] [--level x] [--on] [--status kind --text t]`

final class StaticBackend: Backend {
    var state: AppState
    var onState: ((AppState, Bool) -> Void)?
    init(state: AppState) { self.state = state }
    func assign(_ id: String) {}
    func removeApp() {}
    func setLevel(_ v: Float) {}
    func setEnabled(_ on: Bool) {}
    func setShowDock(_ on: Bool) {}
    func setShowMenuBar(_ on: Bool) {}
    func quit() {}
}

final class SnapshotDelegate: NSObject, NSApplicationDelegate {
    private var settings: SettingsWindow?

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let args = CommandLine.arguments
        func opt(_ k: String) -> String? { args.firstIndex(of: k).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
        var st = AppState()
        st.bundleID = opt("--assigned")
        st.level = opt("--level").flatMap(Float.init) ?? 0.5
        st.enabled = args.contains("--on")
        if let k = opt("--status") { st.status = EngineStatus(kind: EngineStatus.Kind(rawValue: k) ?? .idle, text: opt("--text") ?? k) }
        let s = SettingsWindow(backend: StaticBackend(state: st))
        settings = s
        s.window.alphaValue = 0
        s.window.appearance = NSAppearance(named: args.contains("--dark") ? .darkAqua : .aqua)
        s.show()
        let out = opt("--snapshot")!
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let v = s.window.contentView!.superview!
            v.layoutSubtreeIfNeeded()
            let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds)!
            v.cacheDisplay(in: v.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
            NSApp.terminate(nil)
        }
    }
}
#endif

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
