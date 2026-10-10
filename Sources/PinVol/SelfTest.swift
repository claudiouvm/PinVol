import Foundation

#if SNAPSHOT
// MARK: - Solo desarrollo y CI: prueba de la instalación de actualizaciones
//
// `PinVol --selftest-install <dmg> <app instalada> <bundle id> <versión del dmg> <versión instalada>`
// Prueba en un macOS de verdad (lo ejecuta tools/test-install.sh en el CI) el análisis de la release, la descarga con huella y
// la instalación, incluidos los casos que deben fallar. Instala sobre la app que se le da: hay que pasarle una copia.
// Sale con 0 si todo pasa, con 1 si algo falla y con 2 si los argumentos no son los esperados.

func runInstallSelfTest(_ args: [String]) -> Never {
    guard args.count == 5 else {
        print("uso: PinVol --selftest-install <dmg> <app instalada> <bundle id> <versión del dmg> <versión instalada>")
        exit(2)
    }
    let dmg = URL(fileURLWithPath: args[0])
    let target = URL(fileURLWithPath: args[1])
    let bundleID = args[2], version = args[3], current = args[4]
    let fm = FileManager.default
    var failures = 0

    func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print("\(ok ? "ok   " : "FALLA") \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        if !ok { failures += 1 }
    }
    // Se lee el Info.plist del disco: `Bundle` guarda en memoria el de la primera lectura y no vería el cambio.
    func installedVersion() -> String? {
        guard let data = try? Data(contentsOf: target.appendingPathComponent("Contents/Info.plist")),
              let info = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else { return nil }
        return info["CFBundleShortVersionString"] as? String
    }
    func wait(_ done: () -> Bool) {
        let limit = Date(timeIntervalSinceNow: 60)
        while !done() && Date() < limit { RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05)) }
    }

    // Instalar borra el .dmg que recibe: cada prueba usa su copia.
    let work = fm.temporaryDirectory.appendingPathComponent("pinvol-selftest-\(UUID().uuidString)")
    try? fm.createDirectory(at: work, withIntermediateDirectories: true)
    func copyOfDMG(_ name: String) -> URL {
        let copy = work.appendingPathComponent(name)
        try? fm.copyItem(at: dmg, to: copy)
        return copy
    }

    // 1. Lo que dice la API de GitHub
    let sample: [String: Any] = [
        "tag_name": "v9.9.9",
        "html_url": "https://github.com/claudiouvm/PinVol/releases/tag/v9.9.9",
        "assets": [
            ["name": "Otro.zip", "browser_download_url": "https://example.com/Otro.zip"],
            ["name": "PinVol.dmg", "browser_download_url": "https://example.com/PinVol.dmg", "digest": "sha256:ABCDEF0123"],
        ],
    ]
    let release = UpdateChecker.parseRelease(sample)
    check("release: versión sin la v", release?.version == "9.9.9")
    check("release: dirección del .dmg", release?.assetURL?.absoluteString == "https://example.com/PinVol.dmg")
    check("release: huella en minúsculas", release?.sha256 == "abcdef0123")
    check("release sin adjuntos", UpdateChecker.parseRelease(["tag_name": "v1.0"])?.assetURL == nil)
    check("respuesta sin tag", UpdateChecker.parseRelease([:]) == nil)

    // 2. Descarga (de un archivo local) con la huella buena y con una mala
    let sha = try? UpdateInstaller.sha256(of: dmg)
    check("huella SHA-256 de 64 cifras", sha?.count == 64)
    var outcome: Result<URL, InstallError>?
    UpdateInstaller.download(dmg, to: work.appendingPathComponent("bajado.dmg"), sha256: sha, progress: { _ in }) { outcome = $0 }
    wait { outcome != nil }
    if case .success(let file)? = outcome {
        check("descarga con la huella buena", fm.fileExists(atPath: file.path))
    } else {
        check("descarga con la huella buena", false, String(describing: outcome))
    }
    outcome = nil
    UpdateInstaller.download(dmg, to: work.appendingPathComponent("malo.dmg"), sha256: String(repeating: "0", count: 64),
                             progress: { _ in }) { outcome = $0 }
    wait { outcome != nil }
    if case .failure(.checksum)? = outcome {
        check("descarga con la huella mala se rechaza", !fm.fileExists(atPath: work.appendingPathComponent("malo.dmg").path))
    } else {
        check("descarga con la huella mala se rechaza", false, String(describing: outcome))
    }

    // 3. Instalaciones que deben fallar sin tocar la app instalada
    func mustFail(_ name: String, into: URL, id: String, version v: String, current c: String, _ expected: (InstallError) -> Bool) {
        do {
            try UpdateInstaller.install(dmg: copyOfDMG("\(name).dmg"), into: into, bundleID: id, version: v, currentVersion: c)
            check(name, false, "no falló")
        } catch let e as InstallError {
            check(name, expected(e) && installedVersion() == current, "\(e)")
        } catch {
            check(name, false, "\(error)")
        }
    }
    func isInvalid(_ e: InstallError) -> Bool { if case .invalid = e { return true } else { return false } }
    func isNotWritable(_ e: InstallError) -> Bool { if case .notWritable = e { return true } else { return false } }
    mustFail("otro identificador de bundle", into: target, id: "com.example.otra", version: version, current: current, isInvalid)
    mustFail("otra versión que la esperada", into: target, id: bundleID, version: "0.0.9", current: current, isInvalid)
    mustFail("versión que no es más nueva", into: target, id: bundleID, version: version, current: version, isInvalid)
    mustFail("carpeta sin permiso de escritura", into: URL(fileURLWithPath: "/System/Applications/PinVol.app"), id: bundleID,
             version: version, current: current, isNotWritable)

    // 4. La instalación buena
    let good = copyOfDMG("bueno.dmg")
    do {
        try UpdateInstaller.install(dmg: good, into: target, bundleID: bundleID, version: version, currentVersion: current)
        check("instalación: la app instalada es la nueva", installedVersion() == version, installedVersion() ?? "sin versión")
    } catch {
        check("instalación", false, "\(error)")
    }
    check("instalación: se borra el .dmg", !fm.fileExists(atPath: good.path))
    let leftovers = (try? fm.contentsOfDirectory(atPath: target.deletingLastPathComponent().path))?.filter { $0.hasPrefix(".PinVol-update-") } ?? []
    check("instalación: sin restos junto a la app", leftovers.isEmpty, leftovers.joined(separator: ", "))

    try? fm.removeItem(at: work)
    print(failures == 0 ? "OK: todo pasó" : "\(failures) prueba(s) fallaron")
    exit(failures == 0 ? 0 : 1)
}
#endif
