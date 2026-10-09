import AppKit

// MARK: - Zona de arrastre
//
// Una sola zona que se adapta a cuántas apps hay:
//  · sin apps: tarjeta grande con instrucciones (140 pt);
//  · con 1 a 4 apps: franja compacta bajo la lista (44 pt);
//  · con 5 apps: se oculta y la lista ocupa su sitio.
// Así la ventana crece o se encoge de forma pareja (≈ 58 pt por app) y nunca pasa de cinco filas.

final class DropCard: NSView {
    var highlighted = false { didSet { needsDisplay = true } }
    private let bigStack = NSStackView()
    private let compactStack = NSStackView()
    private let compactLabel = makeLabel("", size: 12, color: .secondaryLabelColor)
    private var heightConstraint: NSLayoutConstraint!
    private var compact = false { didSet { needsDisplay = true } }

    init() {
        super.init(frame: .zero)

        let icon = NSImageView(image: symbol("arrow.down.app", size: 38, weight: .light) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor
        icon.imageScaling = .scaleProportionallyUpOrDown
        let title = makeLabel("Arrastra una app aquí", size: 13, weight: .semibold)
        title.alignment = .center
        let caption = makeLabel("Su volumen quedará fijo · hasta \(maxPinnedApps) apps", size: 11, color: .secondaryLabelColor)
        caption.alignment = .center
        for v in [icon, title, caption] { bigStack.addArrangedSubview(v) }
        bigStack.orientation = .vertical
        bigStack.alignment = .centerX
        bigStack.spacing = 3
        bigStack.setCustomSpacing(10, after: icon)

        let plus = symbolView("plus.circle", size: 14, color: .secondaryLabelColor)
        for v in [plus, compactLabel] { compactStack.addArrangedSubview(v) }
        compactStack.orientation = .horizontal
        compactStack.alignment = .centerY
        compactStack.spacing = 6

        for s in [bigStack, compactStack] {
            s.translatesAutoresizingMaskIntoConstraints = false
            addSubview(s)
            NSLayoutConstraint.activate([
                s.centerXAnchor.constraint(equalTo: centerXAnchor),
                s.centerYAnchor.constraint(equalTo: centerYAnchor),
                s.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 14),
                s.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            ])
        }
        icon.widthAnchor.constraint(equalToConstant: 56).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 56).isActive = true
        heightConstraint = heightAnchor.constraint(equalToConstant: 140)
        heightConstraint.isActive = true
        configure(count: 0)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(count: Int) {
        compact = count > 0
        bigStack.isHidden = compact
        compactStack.isHidden = !compact
        heightConstraint.constant = compact ? 44 : 140
        compactLabel.stringValue = "Arrastra otra app aquí · \(count) de \(maxPinnedApps)"
        toolTip = "Suelta aquí el archivo .app cuyo volumen quieres mantener fijo (hasta \(maxPinnedApps) apps)"
        isHidden = count >= maxPinnedApps
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius: CGFloat = compact ? 10 : 14
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: radius, yRadius: radius)
        if highlighted {
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            path.fill()
        }
        (highlighted ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor).setStroke()
        path.lineWidth = highlighted ? 2 : 1
        path.setLineDash([6, 4], count: 2, phase: 0)
        path.stroke()
    }
}

// MARK: - Fila de una app

/// Ícono, nombre, estado, slider de nivel y botón para quitarla.
final class AppRow: NSView {
    let id: String
    var onLevel: ((Float) -> Void)?
    var onRemove: (() -> Void)?
    private let nameLabel = makeLabel("", size: 13, weight: .medium)
    private let dot = NSImageView(image: symbol("circle.fill", size: 7) ?? NSImage())
    private let caption = makeLabel("", size: 11, color: .secondaryLabelColor)
    private let slider = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let percent = makeLabel("", size: 11, color: .secondaryLabelColor)
    private var dragging = false

    init(id: String) {
        self.id = id
        super.init(frame: .zero)
        let info = appLookup(id)

        let icon = NSImageView(image: info.icon)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 32).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 32).isActive = true
        icon.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        nameLabel.stringValue = info.name
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        caption.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        dot.contentTintColor = .tertiaryLabelColor
        let top = NSStackView(views: [nameLabel, spacer(), dot, caption])
        top.alignment = .centerY
        top.spacing = 5

        slider.target = self
        slider.action = #selector(sliderMoved)
        slider.isContinuous = true
        slider.controlSize = .small
        slider.setAccessibilityLabel("Nivel fijo de \(info.name)")
        slider.toolTip = "Volumen al que sonará \(info.name), en la misma escala que el volumen del sistema"
        percent.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        percent.alignment = .right
        percent.widthAnchor.constraint(equalToConstant: 36).isActive = true
        percent.setContentHuggingPriority(.required, for: .horizontal)
        let bottom = NSStackView(views: [slider, percent])
        bottom.alignment = .centerY
        bottom.spacing = 8

        let mid = NSStackView(views: [top, bottom])
        mid.orientation = .vertical
        mid.alignment = .leading
        mid.spacing = 3
        mid.setContentHuggingPriority(.defaultLow, for: .horizontal)
        top.widthAnchor.constraint(equalTo: mid.widthAnchor).isActive = true
        bottom.widthAnchor.constraint(equalTo: mid.widthAnchor).isActive = true

        let remove = NSButton(image: symbol("xmark.circle.fill", size: 15) ?? NSImage(), target: self, action: #selector(removeTapped))
        remove.isBordered = false
        remove.contentTintColor = .tertiaryLabelColor
        remove.toolTip = "Dejar de controlar \(info.name)"
        remove.setAccessibilityLabel("Quitar \(info.name)")
        remove.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        let row = NSStackView(views: [icon, mid, remove])
        row.alignment = .centerY
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 10)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    /// `updateLevel` es falso en las actualizaciones de estado, para no pisar el slider mientras se arrastra.
    func configure(_ app: PinnedApp, updateLevel: Bool) {
        if updateLevel && !dragging { slider.floatValue = app.level }
        percent.stringValue = "\(Int((slider.floatValue * 100).rounded())) %"
        let s = app.status
        caption.stringValue = Self.caption(for: s)
        dot.isHidden = caption.stringValue.isEmpty
        dot.contentTintColor = statusColor(s.kind)
        caption.toolTip = s.detail ?? s.text
        dot.toolTip = s.detail ?? s.text
    }

    /// Texto corto para la fila: «Activo · +6.2 dB» pasa a «+6.2 dB»; en reposo no se muestra nada.
    private static func caption(for s: EngineStatus) -> String {
        switch s.kind {
        case .idle: return ""
        case .active:
            if let r = s.text.range(of: "· ") { return String(s.text[r.upperBound...]) }
            return s.text
        default: return s.text
        }
    }

    @objc private func sliderMoved() {
        let t = NSApp.currentEvent?.type
        dragging = t == .leftMouseDown || t == .leftMouseDragged
        percent.stringValue = "\(Int((slider.floatValue * 100).rounded())) %"
        onLevel?(slider.floatValue)
    }

    @objc private func removeTapped() { onRemove?() }

    override func menu(for event: NSEvent) -> NSMenu? {
        let m = NSMenu()
        m.addItem(withTitle: "Quitar app", action: #selector(removeTapped), keyEquivalent: "").target = self
        return m
    }
}

// MARK: - Panel de apps

/// Lista de apps fijadas (hasta `maxPinnedApps`) más la zona de arrastre. Acepta soltar `.app` sobre todo el panel.
final class AppsPanel: NSView {
    var onDrop: (([URL]) -> Void)?
    var onRemove: ((String) -> Void)?
    var onLevel: ((String, Float) -> Void)?
    private let drop = DropCard()
    private let list = Card()
    private var rows: [String: AppRow] = [:]
    private var shownIDs: [String] = []

    init() {
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
        let stack = NSStackView(views: [list, drop])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        for v in [list, drop] { v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        list.isHidden = true
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(apps: [PinnedApp], full: Bool) {
        let ids = apps.map { $0.id }
        if full && ids != shownIDs {
            for id in Array(rows.keys) where !ids.contains(id) { rows[id] = nil }
            let ordered = apps.map { app -> AppRow in
                if let r = rows[app.id] { return r }
                let r = AppRow(id: app.id)
                r.onLevel = { [weak self] v in self?.onLevel?(app.id, v) }
                r.onRemove = { [weak self] in self?.onRemove?(app.id) }
                rows[app.id] = r
                return r
            }
            list.setRows(ordered)
            shownIDs = ids
        }
        for app in apps { rows[app.id]?.configure(app, updateLevel: full) }
        list.isHidden = apps.isEmpty
        drop.configure(count: apps.count)
    }

    // MARK: Arrastrar y soltar

    private func appURLs(_ info: NSDraggingInfo) -> [URL] {
        let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                       options: [.urlReadingFileURLsOnly: true]) as? [URL]
        return (urls ?? []).filter { $0.pathExtension == "app" }
    }

    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation {
        guard shownIDs.count < maxPinnedApps, !appURLs(s).isEmpty else { return [] }
        drop.highlighted = true
        return .copy
    }
    override func draggingExited(_ s: NSDraggingInfo?) { drop.highlighted = false }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        drop.highlighted = false
        let urls = appURLs(s)
        guard !urls.isEmpty else { return false }
        onDrop?(urls)
        return true
    }
}
