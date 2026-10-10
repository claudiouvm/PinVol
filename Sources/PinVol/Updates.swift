import Foundation

// MARK: - Comprobación de versión
//
// Consulta la última release publicada en GitHub (`releases/latest`) y la compara con la versión instalada.
// Aquí solo se averigua qué hay y dónde está el .dmg; descargarlo e instalarlo, cuando el usuario lo pide, es de Installer.swift.
// Nota: la API pública de GitHub solo responde si el repositorio es público.

struct ReleaseInfo {
    let version: String    // sin la «v» inicial
    let pageURL: String
    let assetURL: URL?     // el PinVol.dmg adjunto a la release
    let sha256: String?    // su huella SHA-256 en minúsculas, si la API de GitHub la da
}

enum UpdateError: Error {
    case notFound
    case rateLimited
    case network(String)
    case badResponse

    var message: String {
        switch self {
        case .notFound: return L("No releases published (or the repository is private)")
        case .rateLimited: return L("GitHub rate-limited the requests; try again later")
        case .network(let m): return L("No connection: %@", m)
        case .badResponse: return L("Unexpected response from GitHub")
        }
    }
}

enum UpdateChecker {
    static let repo = "claudiouvm/PinVol"
    static let repoURL = URL(string: "https://github.com/\(repo)")!

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Compara versiones numéricas separadas por puntos (1.10 > 1.9). Ignora una «v» inicial y sufijos como «-beta».
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            var t = s.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("v") || t.hasPrefix("V") { t.removeFirst() }
            let core = t.split(separator: "-", maxSplits: 1).first.map { String($0) } ?? t
            return core.split(separator: ".").map { part in Int(part.prefix(while: { $0.isNumber })) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Pide la última release. `completion` se llama en un hilo secundario.
    static func fetchLatest(completion: @escaping (Result<ReleaseInfo, UpdateError>) -> Void) {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        req.timeoutInterval = 15
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("PinVol/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, response, error in
            if let error { return completion(.failure(.network(error.localizedDescription))) }
            guard let http = response as? HTTPURLResponse else { return completion(.failure(.badResponse)) }
            switch http.statusCode {
            case 200: break
            case 404: return completion(.failure(.notFound))
            case 403, 429: return completion(.failure(.rateLimited))
            default: return completion(.failure(.badResponse))
            }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let release = parseRelease(json) else { return completion(.failure(.badResponse)) }
            completion(.success(release))
        }.resume()
    }

    /// Lee la respuesta de `releases/latest`: versión, página y el PinVol.dmg adjunto con su huella.
    static func parseRelease(_ json: [String: Any]) -> ReleaseInfo? {
        guard let tag = json["tag_name"] as? String else { return nil }
        let version = tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
        let page = json["html_url"] as? String ?? repoURL.appendingPathComponent("releases").absoluteString
        let dmg = (json["assets"] as? [[String: Any]])?.first { $0["name"] as? String == "PinVol.dmg" }
        let asset = (dmg?["browser_download_url"] as? String).flatMap { URL(string: $0) }
        var sha: String?
        if let digest = dmg?["digest"] as? String, digest.hasPrefix("sha256:") { sha = String(digest.dropFirst(7)).lowercased() }
        return ReleaseInfo(version: version, pageURL: page, assetURL: asset, sha256: sha)
    }
}
