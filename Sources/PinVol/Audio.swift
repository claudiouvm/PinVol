import CoreAudio
import Foundation

// MARK: - Core Audio helpers

private let system = AudioObjectID(kAudioObjectSystemObject)

func caAddr(_ sel: AudioObjectPropertySelector,
            _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
            _ element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: element)
}

func caGet<T>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector,
              scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
              element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain,
              as: T.Type = T.self) -> T? {
    var a = caAddr(sel, scope, element)
    var size = UInt32(MemoryLayout<T>.size)
    let p = UnsafeMutablePointer<T>.allocate(capacity: 1)
    defer { p.deallocate() }
    guard AudioObjectGetPropertyData(obj, &a, 0, nil, &size, p) == noErr else { return nil }
    return p.pointee
}

func caString(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String? {
    caGet(obj, sel, as: Unmanaged<CFString>.self)?.takeRetainedValue() as String?
}

func caArray<T>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, as: T.Type) -> [T] {
    var a = caAddr(sel)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(obj, &a, 0, nil, &size) == noErr, size > 0 else { return [] }
    return [T](unsafeUninitializedCapacity: Int(size) / MemoryLayout<T>.stride) { buf, n in
        var s = size
        n = AudioObjectGetPropertyData(obj, &a, 0, nil, &s, buf.baseAddress!) == noErr
            ? Int(s) / MemoryLayout<T>.stride : 0
    }
}

func defaultOutputDevice() -> AudioObjectID? {
    guard let d = caGet(system, kAudioHardwarePropertyDefaultOutputDevice, as: AudioObjectID.self),
          d != kAudioObjectUnknown else { return nil }
    return d
}

/// Observa una propiedad y ejecuta `fire` en el hilo principal.
final class Listener {
    private let obj: AudioObjectID
    private var addr: AudioObjectPropertyAddress
    private let block: AudioObjectPropertyListenerBlock

    init(_ obj: AudioObjectID, _ addr: AudioObjectPropertyAddress, fire: @escaping () -> Void) {
        self.obj = obj
        self.addr = addr
        self.block = { _, _ in fire() }
        AudioObjectAddPropertyListenerBlock(obj, &self.addr, .main, block)
    }

    deinit { AudioObjectRemovePropertyListenerBlock(obj, &addr, .main, block) }
}

// MARK: - Volumen master del dispositivo de salida

struct MasterVolume {
    let device: AudioObjectID
    let elements: [UInt32]   // [0] (principal) o [1, 2] (canales)

    init?(device: AudioObjectID) {
        let out = kAudioObjectPropertyScopeOutput
        if caGet(device, kAudioDevicePropertyVolumeScalar, scope: out, element: 0, as: Float32.self) != nil {
            elements = [0]
        } else if caGet(device, kAudioDevicePropertyVolumeScalar, scope: out, element: 1, as: Float32.self) != nil {
            elements = [1, 2]
        } else {
            return nil
        }
        self.device = device
    }

    var scalar: Float {
        let vs = elements.compactMap {
            caGet(device, kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput, element: $0, as: Float32.self)
        }
        return vs.isEmpty ? 1 : vs.reduce(0, +) / Float(vs.count)
    }

    var isMuted: Bool {
        elements.contains {
            (caGet(device, kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput, element: $0, as: UInt32.self) ?? 0) != 0
        }
    }

    /// Atenuación real (dB) que el dispositivo aplica ahora mismo.
    var decibels: Float {
        let ds = elements.compactMap {
            caGet(device, kAudioDevicePropertyVolumeDecibels, scope: kAudioObjectPropertyScopeOutput, element: $0, as: Float32.self)
        }
        return ds.isEmpty ? decibels(forScalar: scalar) : ds.reduce(0, +) / Float(ds.count)
    }

    /// dB reales para un valor del slider del sistema (0...1).
    /// La conversión estándar escalar→dB no coincide con la curva real del sistema (en los Mac es cuadrática),
    /// así que se invierte la conversión dB→escalar del propio dispositivo, que sí la sigue.
    func decibels(forScalar s: Float) -> Float {
        let out = kAudioObjectPropertyScopeOutput
        let el = elements[0]
        func convert(_ sel: AudioObjectPropertySelector, _ x: Float) -> Float? {
            var a = caAddr(sel, out, el)
            var v = x
            var size = UInt32(MemoryLayout<Float32>.size)
            return AudioObjectGetPropertyData(device, &a, 0, nil, &size, &v) == noErr ? v : nil
        }
        var lo: Float = -96, hi: Float = 0
        if let r = caGet(device, kAudioDevicePropertyVolumeRangeDecibels, scope: out, element: el, as: AudioValueRange.self) {
            lo = Float(r.mMinimum); hi = Float(r.mMaximum)
        }
        let target = min(max(s, 0), 1)
        guard convert(kAudioDevicePropertyVolumeDecibelsToScalar, lo) != nil else {
            return convert(kAudioDevicePropertyVolumeScalarToDecibels, target) ?? 40 * log10f(max(target, 1e-4))
        }
        for _ in 0..<24 {
            let mid = (lo + hi) / 2
            if let v = convert(kAudioDevicePropertyVolumeDecibelsToScalar, mid), v < target { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    /// Listeners para cambios de volumen y mute.
    func listeners(_ fire: @escaping () -> Void) -> [Listener] {
        let out = kAudioObjectPropertyScopeOutput
        return elements.flatMap { el in
            [Listener(device, caAddr(kAudioDevicePropertyVolumeScalar, out, el), fire: fire),
             Listener(device, caAddr(kAudioDevicePropertyVolumeDecibels, out, el), fire: fire),
             Listener(device, caAddr(kAudioDevicePropertyMute, out, el), fire: fire)]
        }
    }
}

// MARK: - Motor: tap + dispositivo agregado + ganancia

struct EngineStatus {
    enum Kind: String { case idle, waiting, active, warning, error }
    let kind: Kind
    let text: String
    var detail: String? = nil   // texto largo para el tooltip
}

/// Controla una app: un tap sobre sus procesos, un dispositivo agregado privado y la ganancia que compensa el volumen del sistema.
/// PinVol crea un `Engine` por cada app fijada.
final class Engine {
    static let maxGain: Float = 16   // +24 dB

    var bundleID: String? { didSet { reconcile() } }
    var enabled = false { didSet { reconcile() } }
    var level: Float = 0.5 { didSet { updateGain() } }
    /// Identificadores de las otras apps fijadas: sus procesos no se capturan aquí (ver `matchingProcesses`).
    var otherBundleIDs: [String] = [] { didSet { if oldValue != otherBundleIDs { reconcile() } } }
    var onStatus: ((EngineStatus) -> Void)?

    private let gain = UnsafeMutablePointer<Float>.allocate(capacity: 1)
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var activeObjects: [AudioObjectID] = []
    private var activeDevice: AudioObjectID?
    private var master: MasterVolume?
    private var levelDB: (level: Float, db: Float)?
    private var volumeListeners: [Listener] = []
    private var systemListeners: [Listener] = []

    init(bundleID: String? = nil, level: Float = 0.5) {
        self.bundleID = bundleID
        self.level = level
        gain.pointee = 1
        systemListeners = [
            Listener(system, caAddr(kAudioHardwarePropertyProcessObjectList)) { [weak self] in self?.reconcile() },
            Listener(system, caAddr(kAudioHardwarePropertyDefaultOutputDevice)) { [weak self] in self?.reconcile() },
        ]
    }

    /// ¿Pertenece el proceso `id` a la app `owner`? Coincide por prefijo: así entran los procesos auxiliares
    /// de navegadores y apps Electron (com.app.helper).
    private func claims(_ id: String, _ owner: String) -> Bool { id == owner || id.hasPrefix(owner + ".") }

    private func matchingProcesses() -> [AudioObjectID] {
        guard let b = bundleID else { return [] }
        return caArray(system, kAudioHardwarePropertyProcessObjectList, as: AudioObjectID.self).filter { proc in
            guard let id = caString(proc, kAudioProcessPropertyBundleID), claims(id, b) else { return false }
            // Si otra app fijada es más específica (com.google.Chrome.canary frente a com.google.Chrome), se queda con el proceso.
            return !otherBundleIDs.contains { $0.count > b.count && claims(id, $0) }
        }
    }

    func reconcile() {
        let device = defaultOutputDevice()
        let objects = (enabled && device != nil) ? matchingProcesses() : []

        if objects == activeObjects, device == activeDevice, (objects.isEmpty || tapID != kAudioObjectUnknown) {
            if tapID == kAudioObjectUnknown { report(idleStatus(device: device)) }
            updateGain()
            return
        }
        teardown()
        activeObjects = objects
        activeDevice = device

        guard enabled, bundleID != nil, let device, !objects.isEmpty else { return report(idleStatus(device: device)) }

        master = MasterVolume(device: device)
        if let m = master {
            volumeListeners = m.listeners { [weak self] in self?.updateGain() }
        }
        if let err = setup(objects: objects, device: device) {
            teardown()
            activeObjects = []   // reintenta en el próximo evento
            report(.error, "No se pudo capturar el audio (\(err))",
                   detail: "Revisa que PinVol tenga permiso en Ajustes del Sistema → Privacidad y seguridad → Grabación de audio del sistema.")
        } else {
            updateGain()
        }
    }

    private func idleStatus(device: AudioObjectID?) -> EngineStatus {
        if bundleID == nil { return EngineStatus(kind: .idle, text: "Arrastra una app para empezar") }
        if !enabled { return EngineStatus(kind: .idle, text: "Nivel fijo desactivado") }
        if device == nil { return EngineStatus(kind: .error, text: "Sin dispositivo de salida") }
        return EngineStatus(kind: .waiting, text: "Esperando audio de la app…")
    }

    func updateGain() {
        guard tapID != kAudioObjectUnknown else { return }
        guard let m = master else {
            gain.pointee = 1
            return report(.warning, "Salida sin control de volumen")
        }
        if m.isMuted { gain.pointee = 1; return report(.active, "Activo · sistema en silencio") }
        if levelDB?.level != level { levelDB = (level, m.decibels(forScalar: level)) }
        let g = powf(10, (levelDB!.db - m.decibels) / 20)
        gain.pointee = min(g, Engine.maxGain)
        let db = String(format: "%+.1f dB", 20 * log10f(max(gain.pointee, 1e-6)))
        report(g > Engine.maxGain ? .warning : .active, g > Engine.maxGain ? "Al límite de ganancia · \(db)" : "Activo · \(db)")
    }

    private func report(_ s: EngineStatus) { onStatus?(s) }
    private func report(_ kind: EngineStatus.Kind, _ text: String, detail: String? = nil) {
        onStatus?(EngineStatus(kind: kind, text: text, detail: detail))
    }

    private func setup(objects: [AudioObjectID], device: AudioObjectID) -> OSStatus? {
        guard let outUID = caString(device, kAudioDevicePropertyDeviceUID) else { return -1 }

        let desc = CATapDescription(stereoMixdownOfProcesses: objects)
        desc.uuid = UUID()
        desc.muteBehavior = .muted
        desc.isPrivate = true
        var st = AudioHardwareCreateProcessTap(desc, &tapID)
        guard st == noErr else { tapID = AudioObjectID(kAudioObjectUnknown); return st }

        let dict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "PinVol",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: desc.uuid.uuidString,
            ]],
        ]
        st = AudioHardwareCreateAggregateDevice(dict as CFDictionary, &aggID)
        guard st == noErr else { aggID = AudioObjectID(kAudioObjectUnknown); return st }

        let asbd = caGet(tapID, kAudioTapPropertyFormat, as: AudioStreamBasicDescription.self)
        let tapInterleaved = asbd.map { $0.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0 } ?? true
        let tapChannels = Int(asbd?.mChannelsPerFrame ?? 2)
        let tapBuffers = tapInterleaved ? 1 : tapChannels

        let g = gain
        var current: Float = g.pointee
        st = AudioDeviceCreateIOProcIDWithBlock(&procID, aggID, nil) { _, inData, _, outData, _ in
            let ins = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inData))
            let outs = UnsafeMutableAudioBufferListPointer(outData)
            guard ins.count >= tapBuffers else {
                for b in outs { if let p = b.mData { memset(p, 0, Int(b.mDataByteSize)) } }
                return
            }
            let first = ins.count - tapBuffers   // el tap va al final de los inputs
            let target = g.pointee
            let start = current
            var outChannel = 0

            for ob in outs {
                guard let odata = ob.mData?.assumingMemoryBound(to: Float.self) else { continue }
                let oc = Int(ob.mNumberChannels)
                let frames = Int(ob.mDataByteSize) / (MemoryLayout<Float>.size * max(oc, 1))
                for k in 0..<oc {
                    // buffer/canal de origen para este canal de salida
                    let ch = min(outChannel + k, tapChannels - 1)
                    let src = ins[first + (tapInterleaved ? 0 : ch)]
                    guard let idata = src.mData?.assumingMemoryBound(to: Float.self) else { continue }
                    let ic = tapInterleaved ? Int(src.mNumberChannels) : 1
                    let ich = tapInterleaved ? ch : 0
                    let inFrames = Int(src.mDataByteSize) / (MemoryLayout<Float>.size * max(ic, 1))
                    let n = min(frames, inFrames)
                    for f in 0..<frames {
                        var y: Float = 0
                        if f < n {
                            let gg = start + (target - start) * Float(f) / Float(max(n, 1))
                            y = idata[f * ic + ich] * gg
                            let a = abs(y)
                            if a > 0.9 { y = (y < 0 ? -1 : 1) * (0.9 + 0.1 * tanhf((a - 0.9) / 0.1)) }
                        }
                        odata[f * oc + k] = y
                    }
                }
                outChannel += oc
            }
            current = target
        }
        guard st == noErr else { return st }
        st = AudioDeviceStart(aggID, procID)
        return st == noErr ? nil : st
    }

    private func teardown() {
        volumeListeners = []
        master = nil
        levelDB = nil
        if aggID != kAudioObjectUnknown {
            if let p = procID {
                AudioDeviceStop(aggID, p)
                AudioDeviceDestroyIOProcID(aggID, p)
            }
            AudioHardwareDestroyAggregateDevice(aggID)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        aggID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    deinit {
        teardown()
        gain.deallocate()
    }
}
