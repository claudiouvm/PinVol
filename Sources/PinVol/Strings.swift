import Foundation

// MARK: - Idioma de la interfaz
//
// El inglés es el idioma base y el de reserva: la clave de cada texto es el propio texto en inglés, y
// `Resources/es.lproj/Localizable.strings` lo traduce al español. Si el idioma preferido del Mac es el español, la app
// sale en español; con cualquier otro idioma sale en inglés. `tools/check-strings.py` comprueba que cada texto tenga
// su traducción (lo ejecuta el CI).

/// Locale del idioma de la interfaz con la región del Mac: el texto va en el idioma preferido y los números
/// siguen la región, como hace macOS (es-CL: «45%» y «11,9 dB»; es-ES: «45 %»).
let uiLocale: Locale = {
    let language = Bundle.main.preferredLocalizations.first ?? "en"
    if let region = Locale.current.region?.identifier, !region.isEmpty {
        return Locale(identifier: "\(language)_\(region)")
    }
    return Locale(identifier: language)
}()

/// Texto de la interfaz en el idioma del Mac. `args` rellena los especificadores de formato del texto (%@, %ld, %d…).
func L(_ key: String, _ args: CVarArg...) -> String {
    let text = NSLocalizedString(key, comment: "")
    return args.isEmpty ? text : String(format: text, locale: uiLocale, arguments: args)
}

private let percentFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .percent
    f.maximumFractionDigits = 0
    f.roundingMode = .halfUp
    f.locale = uiLocale
    return f
}()

/// Una fracción como porcentaje, a la manera del idioma: «45%» en inglés y «45 %» en español.
func percentText(_ fraction: Float) -> String {
    percentFormatter.string(from: NSNumber(value: Double(fraction))) ?? "\(Int((fraction * 100).rounded()))%"
}

/// Ganancia en dB con el separador decimal del idioma: «+11.9 dB» en inglés y «+11,9 dB» en español.
func gainText(_ db: Float) -> String { String(format: "%+.1f dB", locale: uiLocale, db) }
