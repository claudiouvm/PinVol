import AppKit

// MARK: - Estilo

/// Relleno de las tarjetas: blanco en claro, velo translúcido en oscuro (como Ajustes del Sistema).
let cardFill = NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.07) : .white
}

func makeLabel(_ text: String = "", size: CGFloat = 13, weight: NSFont.Weight = .regular,
               color: NSColor = .labelColor) -> NSTextField {
    let l = NSTextField(labelWithString: text)
    l.font = .systemFont(ofSize: size, weight: weight)
    l.textColor = color
    l.lineBreakMode = .byTruncatingTail
    return l
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
func statusColor(_ kind: EngineStatus.Kind) -> NSColor {
    switch kind {
    case .idle: return .tertiaryLabelColor
    case .waiting, .warning: return .systemOrange
    case .active: return .systemGreen
    case .error: return .systemRed
    }
}

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
        NSRect(x: 14, y: 0, width: max(bounds.width - 14, 0), height: 0.5).fill()
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
        NSColor.separatorColor.setStroke()
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
        row.heightAnchor.constraint(equalToConstant: detailLabel == nil ? 44 : 54),
    ])
    return row
}
