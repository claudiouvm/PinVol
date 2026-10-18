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

/// Los botones con bisel no escalan su fuente: se agranda el tamaño de control cuando el texto crece.
func scaledControlSize(_ size: NSControl.ControlSize) -> NSControl.ControlSize {
    switch textScale {
    case 1.45...: return .large
    case 1.1...: return .regular
    default: return size
    }
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
