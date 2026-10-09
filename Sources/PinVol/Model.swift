import AppKit

// MARK: - Estado compartido entre la instancia residente y la de interfaz
//
// PinVol corre como dos instancias de la misma app:
//  · la residente (Dock/barra de menú + motor de audio), siempre viva y pequeña;
//  · la de interfaz (`--ui`), que muestra la ventana y termina al cerrarla.
// Así la memoria que AppKit reserva para dibujar la ventana se devuelve al sistema al cerrarla.

/// Máximo de apps que se pueden controlar a la vez. Cada una tiene su propio tap de audio.
let maxPinnedApps = 5

struct PinnedApp {
    var id: String
    var level: Float
    var status = EngineStatus(kind: .idle, text: "")

    init(id: String, level: Float) {
        self.id = id
        self.level = level
    }

    init?(_ d: [String: Any]) {
        guard let id = d["id"] as? String else { return nil }
        self.id = id
        level = Float(d["level"] as? Double ?? 0.5)
        status = EngineStatus(kind: EngineStatus.Kind(rawValue: d["kind"] as? String ?? "") ?? .idle,
                              text: d["text"] as? String ?? "", detail: d["detail"] as? String)
    }

    var dictionary: [String: Any] {
        var d: [String: Any] = ["id": id, "level": Double(level), "kind": status.kind.rawValue, "text": status.text]
        if let detail = status.detail { d["detail"] = detail }
        return d
    }
}

struct UpdateState {
    enum Kind: String { case idle, checking, upToDate, available, failed }
    var kind: Kind = .idle
    var latest: String?
    var url: String?
    var message: String?

    init(kind: Kind = .idle, latest: String? = nil, url: String? = nil, message: String? = nil) {
        self.kind = kind
        self.latest = latest
        self.url = url
        self.message = message
    }

    init(_ d: [String: Any]) {
        kind = Kind(rawValue: d["kind"] as? String ?? "") ?? .idle
        latest = d["latest"] as? String
        url = d["url"] as? String
        message = d["message"] as? String
    }

    var dictionary: [String: Any] {
        var d: [String: Any] = ["kind": kind.rawValue]
        if let latest { d["latest"] = latest }
        if let url { d["url"] = url }
        if let message { d["message"] = message }
        return d
    }
}

struct AppState {
    var apps: [PinnedApp] = []
    var enabled = false
    var showDock = true
    var showMenuBar = true
    var checkUpdates = true
    var update = UpdateState()

    init() {}

    init(_ d: [AnyHashable: Any]) {
        apps = (d["apps"] as? [[String: Any]] ?? []).compactMap { PinnedApp($0) }
        enabled = d["enabled"] as? Bool ?? false
        showDock = d["showDock"] as? Bool ?? true
        showMenuBar = d["showMenuBar"] as? Bool ?? true
        checkUpdates = d["checkUpdates"] as? Bool ?? true
        update = UpdateState(d["update"] as? [String: Any] ?? [:])
    }

    func dictionary(full: Bool) -> [String: Any] {
        ["apps": apps.map { $0.dictionary }, "enabled": enabled, "showDock": showDock, "showMenuBar": showMenuBar,
         "checkUpdates": checkUpdates, "update": update.dictionary, "full": full]
    }

    /// Estado general para el pie de la ventana y el menú: el de la app si hay una; un resumen si hay varias.
    var summary: EngineStatus {
        guard !apps.isEmpty else { return .dragToStart }
        if apps.count == 1 { return apps[0].status }
        let all = apps.map { $0.status }
        if let e = all.first(where: { $0.kind == .error }) { return e }
        let warning = all.filter { $0.kind == .warning }.count
        let engaged = all.filter { $0.kind == .active }.count + warning
        guard engaged > 0 else { return all[0] }
        return EngineStatus(kind: warning > 0 ? .warning : .active,
                            text: warning > 0 ? L("Active · %ld of %ld apps · at the limit", engaged, apps.count)
                                              : L("Active · %ld of %ld apps", engaged, apps.count))
    }
}

// MARK: - Mensajería entre procesos

enum IPC {
    // Los nombres derivan del identificador del bundle: dos variantes de la app (p. ej. una de desarrollo) no se mezclan.
    private static let prefix = Bundle.main.bundleIdentifier ?? "com.claudiouvm.pinvol"
    static let toResident = Notification.Name(prefix + ".toResident")
    static let toUI = Notification.Name(prefix + ".toUI")

    static func post(_ name: Notification.Name, _ info: [String: Any]) {
        DistributedNotificationCenter.default().postNotificationName(name, object: nil, userInfo: info, deliverImmediately: true)
    }
}

/// Escucha un tipo de mensaje del otro proceso. Se entrega siempre, aunque la app esté en segundo plano.
final class IPCObserver: NSObject {
    private let handler: ([AnyHashable: Any]) -> Void

    init(_ name: Notification.Name, handler: @escaping ([AnyHashable: Any]) -> Void) {
        self.handler = handler
        super.init()
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(received(_:)), name: name, object: nil,
                                                            suspensionBehavior: .deliverImmediately)
    }

    deinit { DistributedNotificationCenter.default().removeObserver(self) }

    @objc private func received(_ n: Notification) { handler(n.userInfo ?? [:]) }
}

/// Lo que la ventana necesita del resto de la app (en producción, hablar con la instancia residente).
protocol Backend: AnyObject {
    var state: AppState { get }
    var onState: ((AppState, Bool) -> Void)? { get set }   // (estado, ¿completo?)
    func assign(_ id: String)
    func remove(_ id: String)
    func setLevel(_ id: String, _ v: Float)
    func setEnabled(_ on: Bool)
    func setShowDock(_ on: Bool)
    func setShowMenuBar(_ on: Bool)
    func setCheckUpdates(_ on: Bool)
    func checkForUpdates()
    func quit()
}

/// Backend de la instancia de interfaz: habla con la residente.
final class RemoteBackend: Backend {
    private(set) var state = AppState()
    var onState: ((AppState, Bool) -> Void)?
    var onShow: (() -> Void)?
    private var observer: IPCObserver?

    init() {
        observer = IPCObserver(IPC.toUI) { [weak self] d in
            guard let self else { return }
            if d["bye"] != nil { return NSApp.terminate(nil) }
            if d["show"] != nil { self.onShow?(); return }
            let incoming = AppState(d)
            let full = d["full"] as? Bool ?? true
            #if SNAPSHOT
            devLog("interfaz recibió estado full=\(full) resumen=\(incoming.summary.text)")
            #endif
            if full {
                self.state = incoming
            } else {   // solo estados: no pisar el slider mientras se arrastra
                for (i, app) in self.state.apps.enumerated() {
                    if let s = incoming.apps.first(where: { $0.id == app.id }) { self.state.apps[i].status = s.status }
                }
            }
            self.onState?(self.state, full)
        }
    }

    func connect() { IPC.post(IPC.toResident, ["op": "hello"]) }
    func disconnect() { IPC.post(IPC.toResident, ["op": "bye"]) }
    func assign(_ id: String) { IPC.post(IPC.toResident, ["op": "assign", "id": id]) }
    func remove(_ id: String) {
        state.apps.removeAll { $0.id == id }
        IPC.post(IPC.toResident, ["op": "remove", "id": id])
    }
    func setLevel(_ id: String, _ v: Float) {
        if let i = state.apps.firstIndex(where: { $0.id == id }) { state.apps[i].level = v }
        IPC.post(IPC.toResident, ["op": "level", "id": id, "value": Double(v)])
    }
    func setEnabled(_ on: Bool) { state.enabled = on; IPC.post(IPC.toResident, ["op": "enabled", "value": on]) }
    func setShowDock(_ on: Bool) { IPC.post(IPC.toResident, ["op": "dock", "value": on]) }
    func setShowMenuBar(_ on: Bool) { IPC.post(IPC.toResident, ["op": "menubar", "value": on]) }
    func setCheckUpdates(_ on: Bool) { state.checkUpdates = on; IPC.post(IPC.toResident, ["op": "updates", "value": on]) }
    func checkForUpdates() {
        state.update = UpdateState(kind: .checking)
        IPC.post(IPC.toResident, ["op": "checkUpdates"])
    }
    func quit() { IPC.post(IPC.toResident, ["op": "quit"]) }
}
