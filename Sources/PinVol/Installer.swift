import CryptoKit
import Foundation
import os

// MARK: - Descargar e instalar una versión nueva
//
// Solo lo usa la instancia residente, y solo cuando el usuario pulsa «Descargar» y después «Instalar»: nunca por su cuenta.
//  1. Descarga el PinVol.dmg de la release a la carpeta de cachés y comprueba su huella SHA-256 con la que publica la API de
//     GitHub (ver `UpdateChecker.parseRelease`).
//  2. Al instalar: monta la imagen (solo lectura, fuera del Finder), comprueba que la app de dentro tiene el mismo
//     identificador de bundle y la versión esperada (más nueva que la instalada) y que su firma está íntegra, la copia junto
//     a la instalada y las intercambia de una vez. Quitar la cuarentena es lo mismo que el `xattr` del README.
//  3. La instancia residente abre entonces la app nueva y termina (ver `ResidentDelegate.relaunch`).
// La confianza es la de bajar el .dmg a mano de GitHub: la app va firmada ad-hoc, sin identidad que verificar, así que la huella
// solo protege de descargas dañadas. Si macOS no deja reemplazar la app (carpeta sin permiso de escritura, o «Gestión de apps»
// de Privacidad y seguridad), se abre la imagen para instalar arrastrando, como siempre.

enum InstallError: Error {
    case noAsset
    case download(String)
    case checksum
    case notWritable
    case permission
    case invalid(String)
    case failed(String)

    var message: String {
        switch self {
        case .noAsset: return L("The release has no PinVol.dmg")
        case .download(let m): return L("Couldn't download the update: %@", m)
        case .checksum: return L("The download is damaged; try again")
        case .notWritable: return L("PinVol can't replace itself here: drag the app from the disk image to Applications")
        case .permission:
            return L("macOS blocked the update: allow PinVol in Privacy & Security → App Management, or drag it to Applications")
        case .invalid(let m): return L("The downloaded update is not valid: %@", m)
        case .failed(let m): return L("Couldn't install the update: %@", m)
        }
    }

    /// ¿Falló por la ubicación o los permisos? Entonces se abre la imagen para instalar a mano.
    var opensDiskImage: Bool {
        switch self {
        case .notWritable, .permission: return true
        default: return false
        }
    }
}

enum UpdateInstaller {
    private static let log = Logger(subsystem: "com.claudiouvm.pinvol", category: "update")
    private static var active: Downloader?

    /// ~/Library/Caches/<bundle id>/Updates
    static var cacheDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return caches.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.claudiouvm.pinvol").appendingPathComponent("Updates")
    }

    // MARK: Descarga

    /// Baja `url` a `destination` y comprueba su huella si se conoce. `progress` y `completion` se llaman en el hilo principal.
    static func download(_ url: URL, to destination: URL, sha256: String?, progress: @escaping (Double) -> Void,
                         completion: @escaping (Result<URL, InstallError>) -> Void) {
        let downloader = Downloader(destination: destination, sha256: sha256, progress: progress) { result in
            active = nil
            if case .failure(let e) = result { log.notice("descarga fallida: \(e.message, privacy: .public)") }
            completion(result)
        }
        active = downloader
        log.notice("descargando \(url.absoluteString, privacy: .public)")
        downloader.start(url)
    }

    /// Huella SHA-256 de un archivo, en minúsculas.
    static func sha256(of file: URL) throws -> String {
        var hasher = SHA256()
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Instalación

    /// Instala la versión que trae `dmg` en lugar de la app en `target`. Bloquea (monta y copia): llamar fuera del hilo principal.
    /// No abre la app nueva ni borra la vieja si algo falla. Si sale bien, también borra el .dmg.
    static func install(dmg: URL, into target: URL, bundleID: String, version: String, currentVersion: String) throws {
        let fm = FileManager.default
        let parent = target.deletingLastPathComponent()
        guard target.pathExtension == "app", fm.isWritableFile(atPath: parent.path) else { throw InstallError.notWritable }
        guard UpdateChecker.isNewer(version, than: currentVersion) else {
            throw InstallError.invalid("\(version) is not newer than \(currentVersion)")
        }

        let mount = cacheDirectory.appendingPathComponent("mount-\(UUID().uuidString)")
        try fm.createDirectory(at: mount, withIntermediateDirectories: true)
        do {
            try run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noverify", "-noautoopen", "-mountpoint", mount.path])
        } catch {
            try? fm.removeItem(at: mount)
            throw error
        }
        defer {
            _ = try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
            try? fm.removeItem(at: mount)
        }

        let source = mount.appendingPathComponent("PinVol.app")
        guard let info = Bundle(url: source)?.infoDictionary else { throw InstallError.invalid("PinVol.app is not in the disk image") }
        guard info["CFBundleIdentifier"] as? String == bundleID else { throw InstallError.invalid("another bundle identifier") }
        guard info["CFBundleShortVersionString"] as? String == version else { throw InstallError.invalid("another version") }
        do {
            try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", source.path])
        } catch {
            throw InstallError.invalid("its signature does not verify")
        }

        // Se copia junto a la instalada (mismo volumen) y se intercambian de una vez: nunca queda a medias.
        let staging = parent.appendingPathComponent(".PinVol-update-\(UUID().uuidString).app")
        do {
            try run("/usr/bin/ditto", [source.path, staging.path])
            _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staging.path])
            _ = try fm.replaceItemAt(target, withItemAt: staging, backupItemName: nil, options: [])
            // `replaceItemAt` puede dejar en la app nueva los atributos de la vieja: sin la marca de cuarentena (si la vieja la
            // tenía) macOS no vuelve a revisarla al abrirla, ni bloquea la reapertura.
            _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", target.path])
        } catch {
            try? fm.removeItem(at: staging)
            log.notice("instalación fallida: \(error.localizedDescription, privacy: .public)")
            throw isPermissionError(error) ? InstallError.permission : InstallError.failed(error.localizedDescription)
        }
        try? fm.removeItem(at: dmg)
        log.notice("instalada la versión \(version, privacy: .public) en \(target.path, privacy: .public)")
    }

    private static func isPermissionError(_ error: Error) -> Bool {
        let e = error as NSError
        if e.domain == NSCocoaErrorDomain, e.code == NSFileWriteNoPermissionError || e.code == NSFileReadNoPermissionError { return true }
        if e.domain == NSPOSIXErrorDomain, e.code == Int(EPERM) || e.code == Int(EACCES) { return true }
        if let underlying = e.userInfo[NSUnderlyingErrorKey] as? NSError { return isPermissionError(underlying) }
        return false
    }

    /// Ejecuta una herramienta del sistema y devuelve lo que escribió; lanza si termina con error.
    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let name = URL(fileURLWithPath: tool).lastPathComponent
            throw InstallError.failed("\(name): \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return output
    }
}

/// Descarga un archivo con progreso. Las llamadas de vuelta van al hilo principal.
private final class Downloader: NSObject, URLSessionDownloadDelegate {
    private let destination: URL
    private let sha256: String?
    private let onProgress: (Double) -> Void
    private let onFinish: (Result<URL, InstallError>) -> Void
    private var session: URLSession?
    private var finished = false

    init(destination: URL, sha256: String?, progress: @escaping (Double) -> Void,
         finish: @escaping (Result<URL, InstallError>) -> Void) {
        self.destination = destination
        self.sha256 = sha256
        self.onProgress = progress
        self.onFinish = finish
    }

    func start(_ url: URL) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("PinVol/\(UpdateChecker.currentVersion)", forHTTPHeaderField: "User-Agent")
        let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: .main)
        self.session = session
        session.downloadTask(with: request).resume()
    }

    private func end(_ result: Result<URL, InstallError>) {
        guard !finished else { return }
        finished = true
        session?.finishTasksAndInvalidate()   // la sesión retiene a su delegado hasta que se invalida
        session = nil
        onFinish(result)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(min(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 1))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
            return end(.failure(.download("HTTP \(http.statusCode)")))
        }
        do {
            let fm = FileManager.default
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: destination)
            try fm.moveItem(at: location, to: destination)   // el sistema borra el temporal al volver de esta función
            if let expected = sha256, try UpdateInstaller.sha256(of: destination) != expected {
                try? fm.removeItem(at: destination)
                return end(.failure(.checksum))
            }
            end(.success(destination))
        } catch {
            end(.failure(.download(error.localizedDescription)))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { end(.failure(.download(error.localizedDescription))) }
    }
}
