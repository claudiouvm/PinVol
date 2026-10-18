import AppKit

// MARK: - Zona de arrastre
//
// Una sola zona que se adapta a cuántas apps hay:
//  · sin apps: tarjeta grande con instrucciones y un botón «Añadir app…» (140 pt);
//  · con 1 a 4 apps: franja compacta bajo la lista, que es un botón (44 pt);
//  · con 5 apps: se oculta y la lista ocupa su sitio.
// Toda la tarjeta se puede pulsar, pero el control accesible es el botón: así se puede añadir una app
// con el teclado y con VoiceOver, sin depender de arrastrar.

final class DropCard: NSView {
    var highlighted = false { didSet { needsDisplay = true } }
    var onAdd: (() -> Void)?
    private let bigStack = NSStackView()
    private let addButton = NSButton(title: L("Add App…"), target: nil, action: nil)
    private let compactButton = NSButton(title: "", target: nil, action: nil)
    private var heightConstraint: NSLayoutConstraint!
    private var compact = false { didSet { needsDisplay = true } }

    /// Control que recibe el foco cuando no hay ninguna fila (la tarjeta vacía).
    var focusTarget: NSView { compact ? compactButton : addButton }

    init() {
        super.init(frame: .zero)

        let icon = NSImageView(image: symbol("arrow.down.app", size: 38, weight: .light) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityElement(false)
        let title = makeLabel(L("Drop an app here"), size: 13, weight: .semibold)
        title.alignment = .center
        let caption = makeLabel(L("Its volume will stay fixed · up to %ld apps", maxPinnedApps), size: 11, color: .secondaryLabelColor)
        caption.alignment = .center

        addButton.target = self
        addButton.action = #selector(addTapped)
        addButton.bezelStyle = .rounded
        addButton.controlSize = .small
        addButton.setAccessibilityHelp(L("Opens a panel to choose the app whose volume you want to keep fixed"))

        for v in [icon, title, caption, addButton] { bigStack.addArrangedSubview(v) }
        bigStack.orientation = .vertical
        bigStack.alignment = .centerX
        bigStack.spacing = 3
        bigStack.setCustomSpacing(10, after: icon)
        bigStack.setCustomSpacing(8, after: caption)

        compactButton.target = self
        compactButton.action = #selector(addTapped)
        compactButton.isBordered = false
        compactButton.image = symbol("plus.circle", size: 14, weight: .regular)
        compactButton.imagePosition = .imageLeading
        compactButton.contentTintColor = .secondaryLabelColor
        compactButton.font = .systemFont(ofSize: 12)
        compactButton.setAccessibilityHelp(L("Opens a panel to choose the app whose volume you want to keep fixed"))

        for v in [bigStack, compactButton] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
            NSLayoutConstraint.activate([
                v.centerXAnchor.constraint(equalTo: centerXAnchor),
                v.centerYAnchor.constraint(equalTo: centerYAnchor),
                v.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 14),
                v.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
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
        compactButton.isHidden = !compact
        heightConstraint.constant = compact ? 44 : 140
        compactButton.title = L("Add another app… · %ld of %ld", count, maxPinnedApps)
        toolTip = L("Drop the .app whose volume you want to keep fixed (up to %ld apps)", maxPinnedApps)
        isHidden = count >= maxPinnedApps
    }

    /// Clic en cualquier punto de la tarjeta: la acción es la misma que la del botón.
    override func mouseDown(with event: NSEvent) { onAdd?() }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    @objc private func addTapped() { onAdd?() }

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
    var onRetry: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    private let appName: String
    private let nameLabel = makeLabel("", size: 13, weight: .medium)
    private let dot = NSImageView(image: symbol("circle.fill", size: 7) ?? NSImage())
    private let caption = makeLabel("", size: 11, color: .secondaryLabelColor)
    private let slider = NSSlider(value: 0.5, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let percent = makeLabel("", size: 11, color: .secondaryLabelColor)
    private let detailBox = NSStackView()
    private let detailLabel = makeLabel("", size: 11, color: .secondaryLabelColor)
    private let fixButton = NSButton(title: L("Open System Settings"), target: nil, action: nil)
    private let retryButton = NSButton(title: L("Retry"), target: nil, action: nil)
    private let rowStack = NSStackView()
    private let removeButton = NSButton()
    private var dragging = false

    var focusTarget: NSView { slider }

    init(id: String) {
        let info = appLookup(id)
        appName = info.name
        self.id = id
        super.init(frame: .zero)

        let icon = NSImageView(image: info.icon)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 32).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 32).isActive = true
        icon.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        icon.setAccessibilityElement(false)

        nameLabel.stringValue = appName
        // Si el estado es largo (p. ej. un error), se acorta él y no el nombre de la app; el texto completo va en el tooltip.
        nameLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        nameLabel.setAccessibilityElement(false)
        caption.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        dot.contentTintColor = .tertiaryLabelColor
        dot.setAccessibilityElement(false)
        let top = NSStackView(views: [nameLabel, spacer(), dot, caption])
        top.alignment = .centerY
        top.spacing = 5

        slider.target = self
        slider.action = #selector(sliderMoved)
        slider.isContinuous = true
        slider.controlSize = .small
        slider.setAccessibilityLabel(L("Fixed level for %@", appName))
        slider.setAccessibilityHelp(L("The volume %@ will play at, on the same scale as the system volume", appName))
        slider.toolTip = L("The volume %@ will play at, on the same scale as the system volume", appName)
        percent.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        percent.alignment = .right
        percent.widthAnchor.constraint(equalToConstant: 36).isActive = true
        percent.setContentHuggingPriority(.required, for: .horizontal)
        percent.setAccessibilityElement(false)   // el slider ya anuncia su valor: no duplicarlo
        let bottom = NSStackView(views: [slider, percent])
        bottom.alignment = .centerY
        bottom.spacing = 8

        // Explicación visible y acciones de recuperación (permiso de audio, reintento): nada de tooltips.
        detailLabel.lineBreakMode = .byWordWrapping
        detailLabel.maximumNumberOfLines = 3
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detailLabel.setAccessibilityElement(false)
        for b in [fixButton, retryButton] {
            b.bezelStyle = .rounded
            b.controlSize = .small
        }
        fixButton.target = self
        fixButton.action = #selector(openSettingsTapped)
        fixButton.setAccessibilityLabel(L("Open audio settings for %@", appName))
        retryButton.target = self
        retryButton.action = #selector(retryTapped)
        retryButton.setAccessibilityLabel(L("Retry %@", appName))
        let fixes = NSStackView(views: [fixButton, retryButton, spacer()])
        fixes.orientation = .horizontal
        fixes.alignment = .centerY
        fixes.spacing = 8
        detailBox.orientation = .vertical
        detailBox.alignment = .leading
        detailBox.spacing = 4
        for v in [detailLabel, fixes] { detailBox.addArrangedSubview(v) }
        detailLabel.widthAnchor.constraint(equalTo: detailBox.widthAnchor).isActive = true
        fixes.widthAnchor.constraint(equalTo: detailBox.widthAnchor).isActive = true
        detailBox.isHidden = true

        let mid = NSStackView(views: [top, bottom, detailBox])
        mid.orientation = .vertical
        mid.alignment = .leading
        mid.spacing = 3
        mid.setContentHuggingPriority(.defaultLow, for: .horizontal)
        top.widthAnchor.constraint(equalTo: mid.widthAnchor).isActive = true
        bottom.widthAnchor.constraint(equalTo: mid.widthAnchor).isActive = true
        detailBox.widthAnchor.constraint(equalTo: mid.widthAnchor).isActive = true

        removeButton.image = symbol("xmark.circle.fill", size: 14) ?? NSImage()
        removeButton.isBordered = false
        removeButton.contentTintColor = .tertiaryLabelColor
        removeButton.toolTip = L("Stop controlling %@", appName)
        removeButton.setAccessibilityLabel(L("Remove %@", appName))
        removeButton.target = self
        removeButton.action = #selector(removeTapped)
        removeButton.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        removeButton.widthAnchor.constraint(equalToConstant: 24).isActive = true
        removeButton.heightAnchor.constraint(equalToConstant: 24).isActive = true

        for v in [icon, mid, removeButton] { rowStack.addArrangedSubview(v) }
        rowStack.alignment = .centerY
        rowStack.spacing = 10
        rowStack.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 10)
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowStack)
        NSLayoutConstraint.activate([
            rowStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rowStack.trailingAnchor.constraint(equalTo: trailingAnchor),
            rowStack.topAnchor.constraint(equalTo: topAnchor),
            rowStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        setAccessibilityRole(.group)
        setAccessibilityLabel(appName)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// `updateLevel` es falso en las actualizaciones de estado, para no pisar el slider mientras se arrastra.
    func configure(_ app: PinnedApp, updateLevel: Bool) {
        if updateLevel && !dragging { slider.floatValue = app.level }
        percent.stringValue = percentText(slider.floatValue)
        let s = app.status
        caption.stringValue = Self.caption(for: s)
        dot.isHidden = caption.stringValue.isEmpty
        dot.contentTintColor = statusColor(s.kind)
        caption.toolTip = s.detail ?? s.text

        let recovery = s.recovery
        rowStack.alignment = recovery == .none ? .centerY : .top
        detailBox.isHidden = recovery == .none
        if recovery != .none {
            detailLabel.stringValue = s.detail ?? s.text
            fixButton.isHidden = recovery != .audioPermission
            retryButton.isHidden = false
        }
    }

    /// Texto corto para la fila: «Active · +6.2 dB» pasa a «+6.2 dB»; en reposo no se muestra nada.
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
        percent.stringValue = percentText(slider.floatValue)
        onLevel?(slider.floatValue)
    }

    @objc private func removeTapped() { onRemove?() }
    @objc private func retryTapped() { onRetry?() }
    @objc private func openSettingsTapped() { onOpenSettings?() }

    override func menu(for event: NSEvent) -> NSMenu? {
        let m = NSMenu()
        m.addItem(withTitle: L("Remove app"), action: #selector(removeTapped), keyEquivalent: "").target = self
        return m
    }
}

// MARK: - Panel de apps

/// Lista de apps fijadas (hasta `maxPinnedApps`) más la zona de arrastre. Acepta soltar `.app` sobre todo el panel.
final class AppsPanel: NSView {
    var onDrop: (([URL]) -> Void)?
    var onAdd: (() -> Void)?
    var onRemove: ((String) -> Void)?
    var onRetry: ((String) -> Void)?
    var onOpenSettings: ((String) -> Void)?
    var onLevel: ((String, Float) -> Void)?
    private let drop = DropCard()
    private let list = Card()
    private var rows: [String: AppRow] = [:]
    private var shownIDs: [String] = []

    /// Primer control que recibe el foco al abrir la ventana: el primer slider, o el botón de añadir.
    var firstFocusable: NSView? { shownIDs.first.flatMap { rows[$0]?.focusTarget } ?? drop.focusTarget }

    init() {
        super.init(frame: .zero)
        registerForDraggedTypes([.fileURL])
        drop.onAdd = { [weak self] in self?.onAdd?() }
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
                r.onRetry = { [weak self] in self?.onRetry?(app.id) }
                r.onOpenSettings = { [weak self] in self?.onOpenSettings?(app.id) }
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
