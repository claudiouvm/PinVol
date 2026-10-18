import AppKit

// MARK: - Escala de texto
//
// macOS no agranda por su cuenta el texto de una app que usa tamaños fijos. Este factor sigue el tamaño
// de cuerpo preferido por el sistema y se puede forzar en las capturas y en las pruebas (PV_TEXT_SCALE).

private let systemTextScale: CGFloat = {
    let body = NSFont.preferredFont(forTextStyle: .body).pointSize
    return max(1, body / 13)
}()

let textScale: CGFloat = {
    let env = ProcessInfo.processInfo.environment["PV_TEXT_SCALE"].flatMap(Double.init).map { CGFloat($0) } ?? 1
    return max(0.8, min(env, 3)) * systemTextScale
}()

func scaled(_ value: CGFloat) -> CGFloat { (value * textScale).rounded() }

func scaledFont(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
    .systemFont(ofSize: scaled(size), weight: weight)
}

func scaledMonospacedDigitFont(_ size: CGFloat) -> NSFont {
    .monospacedDigitSystemFont(ofSize: scaled(size), weight: .regular)
}

// MARK: - Paleta

/// Colores propios con contraste comprobado. Los del sistema (texto, separadores) se adaptan solos;
/// los que dibuja la app se resuelven aquí para poder medirlos en las pruebas de accesibilidad.
enum PinVolPalette {
    /// Verde, naranja y rojo con al menos 3:1 sobre la tarjeta blanca (WCAG 1.4.11), y sus versiones en modo oscuro.
    static let activeLight = NSColor(srgbRed: 0.09, green: 0.47, blue: 0.22, alpha: 1)
    static let waitingLight = NSColor(srgbRed: 0.64, green: 0.35, blue: 0.00, alpha: 1)
    static let errorLight = NSColor(srgbRed: 0.76, green: 0.18, blue: 0.16, alpha: 1)
    static let activeDark = NSColor(calibratedRed: 0.19, green: 0.82, blue: 0.35, alpha: 1)
    static let waitingDark = NSColor(calibratedRed: 1.00, green: 0.62, blue: 0.04, alpha: 1)
    static let errorDark = NSColor(calibratedRed: 1.00, green: 0.27, blue: 0.23, alpha: 1)

    static func status(_ kind: EngineStatus.Kind, dark: Bool) -> NSColor {
        switch kind {
        case .idle: return dark ? NSColor(white: 0.62, alpha: 1) : NSColor(white: 0.42, alpha: 1)
        case .waiting, .warning: return dark ? waitingDark : waitingLight
        case .active: return dark ? activeDark : activeLight
        case .error: return dark ? errorDark : errorLight
        }
    }

    static func status(_ kind: EngineStatus.Kind) -> NSColor {
        NSColor(name: nil) { appearance in
            status(kind, dark: appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        }
    }

    /// El `×` y el borde de la zona de arrastre no son decorativos: usan el color de etiqueta secundaria,
    /// que ronda 10:1 en ambos modos y se refuerza con «Aumentar contraste».
    static var controlOutline: NSColor { .secondaryLabelColor }

    /// Track del slider: ≥3:1 sobre la tarjeta en claro y oscuro.
    static let sliderTrack = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.62, alpha: 1)
                                                                   : NSColor(white: 0.48, alpha: 1)
    }

    /// Knob del slider y su borde.
    static let knobFill = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.12, alpha: 1) : .white
    }
    static var knobBorder: NSColor { .secondaryLabelColor }

    /// Fondo y borde de los botones propios (PillButton).
    static let buttonFill = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.22, alpha: 1)
                                                                   : NSColor(white: 0.95, alpha: 1)
    }
    static let buttonFillPressed = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.28, alpha: 1)
                                                                   : NSColor(white: 0.90, alpha: 1)
    }
    static let buttonBorder = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 0.58, alpha: 1)
                                                                   : NSColor(white: 0.45, alpha: 1)
    }

    /// Acento del sistema oscurecido lo justo para que el texto blanco del segmento seleccionado llegue a 4,5:1.
    /// Conserva el tono que eligió el usuario; solo baja el brillo.
    static func accessibleAccent(for appearance: NSAppearance) -> NSColor {
        var base = NSColor.controlAccentColor
        appearance.performAsCurrentDrawingAppearance {
            base = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .controlAccentColor
        }
        let white = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        var fraction: CGFloat = 0
        var candidate = base
        while contrastRatio(white, candidate) < 4.5, fraction < 0.6 {
            fraction += 0.05
            candidate = base.blended(withFraction: fraction, of: .black)?.usingColorSpace(.sRGB) ?? base
        }
        return candidate
    }
}

/// Contraste WCAG entre dos colores ya resueltos (sin transparencia).
func contrastRatio(_ a: NSColor, _ b: NSColor) -> CGFloat {
    func linear(_ v: CGFloat) -> CGFloat { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    func luminance(_ color: NSColor) -> CGFloat {
        let c = color.usingColorSpace(.sRGB) ?? color
        return 0.2126 * linear(c.redComponent) + 0.7152 * linear(c.greenComponent) + 0.0722 * linear(c.blueComponent)
    }
    let la = luminance(a), lb = luminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
}

/// Relleno de las tarjetas: blanco en claro, velo translúcido en oscuro (como Ajustes del Sistema).
/// Con «Aumentar contraste» el velo es más opaco.
let cardFill = NSColor(name: nil) { appearance in
    let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    let high = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
    return dark ? NSColor(white: 1, alpha: high ? 0.16 : 0.07) : .white
}

/// Borde de las tarjetas; más marcado si el usuario pidió aumentar el contraste.
func cardStrokeColor() -> NSColor {
    NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? .tertiaryLabelColor : .separatorColor
}

func makeLabel(_ text: String = "", size: CGFloat = 13, weight: NSFont.Weight = .regular,
               color: NSColor = .labelColor) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = scaledFont(size, weight: weight)
    l.textColor = color
    l.lineBreakMode = .byTruncatingTail
    return l
}

/// Anuncia un mensaje a las tecnologías de asistencia (VoiceOver) sin mover el foco.
/// Los mensajes del pie y de la barra de menús duran pocos segundos: sin esto, quien no ve la pantalla
/// no se entera de que una app se añadió o de que algo falló.
func announce(_ text: String, priority: NSAccessibilityPriorityLevel = .medium) {
    guard !text.isEmpty else { return }
    let element: Any = NSApp.mainWindow ?? NSApplication.shared
    NSAccessibility.post(element: element, notification: .announcementRequested,
                         userInfo: [.announcement: text, .priority: priority.rawValue])
}

func symbol(_ name: String, size: CGFloat, weight: NSFont.Weight = .regular) -> NSImage? {
    NSImage(systemSymbolName: name, accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: size, weight: weight))
}

func symbolView(_ name: String, size: CGFloat, color: NSColor) -> NSImageView {
    let v = NSImageView(image: symbol(name, size: size) ?? NSImage())
    v.contentTintColor = color
    return v
}

func spacer() -> NSView {
    let v = NSView()
    v.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
    return v
}

/// Color del punto de estado según el tipo de estado del motor.
func statusColor(_ kind: EngineStatus.Kind) -> NSColor { PinVolPalette.status(kind) }

/// Nombre e ícono de una app a partir de su identificador de bundle.
func appLookup(_ id: String) -> (name: String, icon: NSImage) {
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
        return (id, symbol("app.dashed", size: 28, weight: .light) ?? NSImage())
    }
    let info = Bundle(url: url)
    let name = info?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? info?.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? url.deletingPathExtension().lastPathComponent
    return (name, NSWorkspace.shared.icon(forFile: url.path))
}

// MARK: - Tarjeta agrupada

final class Separator: NSView {
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 1) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        let x = 14 * textScale
        NSRect(x: x, y: 0, width: max(bounds.width - x, 0), height: 0.5).fill()
    }
}

/// Filas separadas por líneas finas dentro de un rectángulo redondeado. Las filas se pueden reemplazar.
final class Card: NSView {
    private let stack = NSStackView()

    init(rows: [NSView] = []) {
        super.init(frame: .zero)
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
        setRows(rows)
    }
    required init?(coder: NSCoder) { fatalError() }

    func setRows(_ rows: [NSView]) {
        for v in stack.arrangedSubviews {
            stack.removeArrangedSubview(v)
            v.removeFromSuperview()
        }
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

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 12, yRadius: 12)
        cardFill.setFill()
        path.fill()
        cardStrokeColor().setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

/// Fila de ajustes: título (y detalle opcional) a la izquierda, control a la derecha.
func formRow(_ title: String, detail: String? = nil, control: NSView) -> NSView {
    let detailLabel = detail.map { makeLabel($0, size: 11, color: .secondaryLabelColor) }
    return formRow(title, detailLabel: detailLabel, control: control)
}

/// Igual que la anterior, pero con una etiqueta de detalle que el llamador puede actualizar.
func formRow(_ title: String, detailLabel: NSTextField?, control: NSView) -> NSView {
    let titleLabel = makeLabel(title)
    let left: NSView
    if let detailLabel {
        let v = NSStackView(views: [titleLabel, detailLabel])
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
        row.heightAnchor.constraint(equalToConstant: scaled(detailLabel == nil ? 44 : 54)),
    ])
    return row
}

// MARK: - Barra de pestañas

/// Barra propia en lugar de `NSSegmentedControl`: el control del sistema dibuja el texto del segmento
/// seleccionado en blanco sobre el acento y no permite cambiar ese color. Aquí el fondo del segmento se
/// oscurece lo justo para que el texto blanco llegue a 4,5:1, conservando el tono del acento del usuario.
final class TabBar: NSView {
    var onSelect: ((Int) -> Void)?
    private var buttons: [NSButton] = []
    private let titles: [String]
    private var selectedIndex = 0

    init(titles: [String]) {
        self.titles = titles
        super.init(frame: .zero)
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .centerY
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        for (i, title) in titles.enumerated() {
            let b = NSButton(title: title, target: self, action: #selector(tapped(_:)))
            b.tag = i
            b.isBordered = false
            b.setAccessibilityRole(.radioButton)
            b.setContentHuggingPriority(.defaultLow, for: .horizontal)
            stack.addArrangedSubview(b)
            buttons.append(b)
        }
        updateTitles()
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: scaled(28)) }

    func select(_ index: Int) {
        selectedIndex = max(0, min(index, buttons.count - 1))
        updateTitles()
        needsDisplay = true
    }

    @objc private func tapped(_ sender: NSButton) { onSelect?(sender.tag) }

    private func updateTitles() {
        for (i, b) in buttons.enumerated() {
            let isSelected = i == selectedIndex
            b.attributedTitle = NSAttributedString(string: titles[i], attributes: [
                .font: scaledFont(13, weight: isSelected ? .semibold : .regular),
                .foregroundColor: isSelected ? NSColor.white : NSColor.labelColor,
            ])
            b.setAccessibilityLabel(titles[i])
            b.setAccessibilityValue(NSNumber(value: isSelected ? 1 : 0))
        }
    }

    override func layout() {
        super.layout()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        NSColor.quaternaryLabelColor.setFill()
        path.fill()
        guard selectedIndex < buttons.count else { return }
        let frame = buttons[selectedIndex].frame.insetBy(dx: 1, dy: 1)
        guard frame.width > 0, frame.height > 0 else { return }
        let selected = NSBezierPath(roundedRect: frame, xRadius: 6, yRadius: 6)
        PinVolPalette.accessibleAccent(for: effectiveAppearance).setFill()
        selected.fill()
    }
}

// MARK: - Botón propio

/// Botón con bisel dibujado por la app: crece con el texto (el bisel del sistema no) y mantiene el
/// borde por encima de 3:1. Sigue siendo un NSButton, así que conserva clic, teclado y accesibilidad.
final class PillButton: NSButton {
    convenience init(title: String) {
        self.init(frame: .zero)
        self.title = title
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        font = scaledFont(13)
        focusRingType = .none
        contentTintColor = .labelColor
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        let titleSize = title.size(withAttributes: [.font: font ?? scaledFont(13)])
        let imageWidth = image == nil ? 0 : scaled(6) + (image?.size.width ?? 0)
        return NSSize(width: max(scaled(40), titleSize.width + imageWidth + scaled(16)),
                      height: max(scaled(24), titleSize.height + scaled(10)))
    }

    override func draw(_ dirtyRect: NSRect) {
        let pressed = (cell as? NSButtonCell)?.isHighlighted ?? false
        let rect = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        (pressed ? PinVolPalette.buttonFillPressed : PinVolPalette.buttonFill).setFill()
        path.fill()
        PinVolPalette.buttonBorder.setStroke()
        path.lineWidth = 1
        path.stroke()
        super.draw(dirtyRect)
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5),
                                    xRadius: (bounds.height - 3) / 2, yRadius: (bounds.height - 3) / 2)
            ring.lineWidth = 2
            ring.stroke()
        }
    }
}

// MARK: - Slider con track propio

/// Célula del slider con un track de 3:1 en lugar del gris claro del sistema. El resto (arrastre,
/// teclado, VoiceOver, foco) lo sigue poniendo NSSlider.
final class ContrastSliderCell: NSSliderCell {
    override func drawBar(inside rect: NSRect, flipped: Bool) {
        let height = max(scaled(4), 3)
        let bar = NSRect(x: rect.minX, y: rect.midY - height / 2, width: rect.width, height: height)
        let track = NSBezierPath(roundedRect: bar, xRadius: height / 2, yRadius: height / 2)
        PinVolPalette.sliderTrack.setFill()
        track.fill()

        let knob = knobRect(flipped: flipped)
        let filledWidth = max(0, min(knob.midX - bar.minX, bar.width))
        guard filledWidth > 0 else { return }
        let filled = NSRect(x: bar.minX, y: bar.minY, width: filledWidth, height: bar.height)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: filled, xRadius: height / 2, yRadius: height / 2).fill()
    }

    override func drawKnob(_ knobRect: NSRect) {
        let inset = max(1, scaled(1))
        let path = NSBezierPath(ovalIn: knobRect.insetBy(dx: inset, dy: inset))
        PinVolPalette.knobFill.setFill()
        path.fill()
        PinVolPalette.knobBorder.setStroke()
        path.lineWidth = max(1, scaled(1.5))
        path.stroke()
    }
}
