import AppKit

// MARK: - Instancia residente: ajustes guardados + motores

/// Dueño del estado. Mantiene un `Engine` (tap + dispositivo agregado) por cada app fijada y habla con la interfaz.
final class Controller {
    let defaults: UserDefaults
    private var engines: [String: Engine] = [:]
    private(set) var apps: [PinnedApp] = []
    private(set) var enabled: Bool
    private(set) var showDock: Bool
    private(set) var showMenuBar: Bool
    private(set) var checkUpdates: Bool
    private(set) var update = UpdateState()
    private var uiActive = false
    private var observer: IPCObserver?
    private var updateTimer: Timer?
    private var broadcastPending = false
    private var broadcastFull = false
    var onStatus: (() -> Void)?
    var onPresence: (() -> Void)?
    var onShow: (() -> Void)?

    var state: AppState {
        var s = AppState()
        s.apps = apps
        s.enabled = enabled
        s.showDock = showDock
        s.showMenuBar = showMenuBar
        s.checkUpdates = checkUpdates
        s.update = update
        return s
    }

    var summary: EngineStatus { state.summary }
    var anyActive: Bool { apps.contains { $0.status.kind == .active } }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        apps = Controller.loadApps(defaults)
        enabled = defaults.bool(forKey: "enabled")
        showDock = defaults.object(forKey: "showDock") as? Bool ?? true
        showMenuBar = defaults.object(forKey: "showMenuBar") as? Bool ?? true
        checkUpdates = defaults.object(forKey: "checkUpdates") as? Bool ?? true
        observer = IPCObserver(IPC.toResident) { [weak self] in self?.handle($0) }
    }

    /// Lee las apps guardadas. Si solo existe el formato de la versión 1.0 (una app), lo migra.
    private static func loadApps(_ d: UserDefaults) -> [PinnedApp] {
        var result: [PinnedApp] = []
        if let list = d.array(forKey: "apps") as? [[String: Any]] {
            result = list.compactMap { item in
                guard let id = item["id"] as? String else { return nil }
                return PinnedApp(id: id, level: Float(item["level"] as? Double ?? 0.5))
            }
        } else if let id = d.string(forKey: "bundleID") {
            result = [PinnedApp(id: id, level: d.object(forKey: "level") as? Float ?? 0.5)]
        }
        var seen = Set<String>()
        return Array(result.filter { seen.insert($0.id).inserted }.prefix(maxPinnedApps))
    }

    private func save() {
        defaults.set(apps.map { ["id": $0.id, "level": Double($0.level)] as [String: Any] }, forKey: "apps")
        defaults.removeObject(forKey: "bundleID")   // claves de la versión 1.0
        defaults.removeObject(forKey: "level")
    }

    /// Arranca los motores con lo guardado.
    func start() {
        for app in apps { makeEngine(for: app) }
        save()
        startUpdateChecks()
    }

    // MARK: Motores

    private func makeEngine(for app: PinnedApp) {
        let e = Engine(bundleID: app.id, level: app.level)
        e.otherBundleIDs = apps.map { $0.id }.filter { $0 != app.id }
        e.onStatus = { [weak self] s in self?.engineStatus(app.id, s) }
        engines[app.id] = e
        e.enabled = enabled   // arranca el motor
    }

    /// Una app no debe quedarse con los procesos de otra más específica (p. ej. com.google.Chrome y com.google.Chrome.canary).
    private func refreshExclusions() {
        for (id, e) in engines { e.otherBundleIDs = apps.map { $0.id }.filter { $0 != id } }
    }

    private func engineStatus(_ id: String, _ s: EngineStatus) {
        guard let i = apps.firstIndex(where: { $0.id == id }) else { return }
        apps[i].status = s
        onStatus?()
        broadcast(full: false)
    }

    // MARK: Mensajes de la interfaz

    private func handle(_ m: [AnyHashable: Any]) {
        #if SNAPSHOT
        devLog("residente recibió op=\(String(describing: m["op"]))")
        #endif
        switch m["op"] as? String {
        case "hello": uiActive = true; broadcast(full: true)
        case "bye": uiActive = false
        case "assign": if let id = m["id"] as? String { assign(id) }
        case "remove": if let id = m["id"] as? String { remove(id) }
        case "level": if let id = m["id"] as? String, let v = m["value"] as? Double { setLevel(id, Float(v)) }
        case "enabled": if let v = m["value"] as? Bool { setEnabled(v) }
        case "dock": if let v = m["value"] as? Bool { setShowDock(v) }
        case "menubar": if let v = m["value"] as? Bool { setShowMenuBar(v) }
        case "updates": if let v = m["value"] as? Bool { setCheckUpdates(v) }
        case "checkUpdates": checkForUpdates(manual: true)
        case "show": onShow?()
        case "quit": NSApp.terminate(nil)
        default: break
        }
    }

    /// Agrupa los envíos: un cambio de volumen del sistema puede disparar varios avisos seguidos.
    private func broadcast(full: Bool) {
        guard uiActive else { return }
        broadcastFull = broadcastFull || full
        guard !broadcastPending else { return }
        broadcastPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self else { return }
            self.broadcastPending = false
            let f = self.broadcastFull
            self.broadcastFull = false
            if self.uiActive { IPC.post(IPC.toUI, self.state.dictionary(full: f)) }
        }
    }

    // MARK: Acciones

    /// Añade una app. Su nivel inicial es el volumen actual del sistema.
    private func assign(_ id: String) {
        guard apps.count < maxPinnedApps, !apps.contains(where: { $0.id == id }) else { return broadcast(full: true) }
        var level: Float = 0.5
        if let dev = defaultOutputDevice(), let m = MasterVolume(device: dev) { level = m.scalar }
        let app = PinnedApp(id: id, level: level)
        apps.append(app)
        makeEngine(for: app)
        refreshExclusions()
        save()
        setEnabled(true)
    }

    /// Deja de controlar la app: se destruye su tap y su audio vuelve a sonar normal.
    private func remove(_ id: String) {
        engines[id] = nil
        apps.removeAll { $0.id == id }
        refreshExclusions()
        save()
        onStatus?()
        broadcast(full: true)
    }

    private func setLevel(_ id: String, _ v: Float) {
        guard let i = apps.firstIndex(where: { $0.id == id }) else { return }
        apps[i].level = v
        engines[id]?.level = v
        save()
    }

    func setEnabled(_ on: Bool) {
        enabled = on
        defaults.set(on, forKey: "enabled")
        for e in engines.values { e.enabled = on }
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

    // MARK: Actualizaciones

    private func startUpdateChecks() {
        // Una versión nueva detectada antes sigue avisando hasta que se instale.
        if let v = defaults.string(forKey: "latestVersion"), UpdateChecker.isNewer(v, than: UpdateChecker.currentVersion) {
            update = UpdateState(kind: .available, latest: v, url: defaults.string(forKey: "latestURL"))
        }
        guard checkUpdates, updateTimer == nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.checkIfDue() }
        let t = Timer(timeInterval: 6 * 3600, repeats: true) { [weak self] _ in self?.checkIfDue() }
        t.tolerance = 600
        RunLoop.main.add(t, forMode: .common)
        updateTimer = t
    }

    /// Como mucho una consulta al día.
    private func checkIfDue() {
        guard checkUpdates else { return }
        let last = defaults.double(forKey: "lastUpdateCheck")
        if Date().timeIntervalSince1970 - last > 24 * 3600 { checkForUpdates(manual: false) }
    }

    private func setCheckUpdates(_ on: Bool) {
        checkUpdates = on
        defaults.set(on, forKey: "checkUpdates")
        if on {
            startUpdateChecks()
            checkIfDue()
        } else {
            updateTimer?.invalidate()
            updateTimer = nil
        }
        broadcast(full: true)
    }

    /// `manual`: la pidió el usuario, así que los fallos se muestran; las automáticas fallan en silencio.
    func checkForUpdates(manual: Bool) {
        guard update.kind != .checking else { return }
        let previous = update
        update = UpdateState(kind: .checking)
        broadcast(full: true)
        UpdateChecker.fetchLatest { [weak self] result in
            DispatchQueue.main.async { self?.finishCheck(result, manual: manual, previous: previous) }
        }
    }

    private func finishCheck(_ result: Result<ReleaseInfo, UpdateError>, manual: Bool, previous: UpdateState) {
        switch result {
        case .success(let r):
            defaults.set(Date().timeIntervalSince1970, forKey: "lastUpdateCheck")
            defaults.set(r.version, forKey: "latestVersion")
            defaults.set(r.pageURL, forKey: "latestURL")
            if UpdateChecker.isNewer(r.version, than: UpdateChecker.currentVersion) {
                update = UpdateState(kind: .available, latest: r.version, url: r.pageURL)
            } else {
                update = UpdateState(kind: .upToDate, latest: r.version)
            }
        case .failure(let e):
            update = manual ? UpdateState(kind: .failed, message: e.message) : previous
        }
        broadcast(full: true)
    }
}
