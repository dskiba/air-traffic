import Carbon.HIToolbox

/// One global shortcut via Carbon's RegisterEventHotKey: no Accessibility permission needed.
final class HotKey {
    private static var action: (() -> Void)?
    private static var handler: EventHandlerRef?
    private var ref: EventHotKeyRef?

    /// `spec` like "ctrl+opt+space" or "cmd+shift+l".
    init?(_ spec: String, action: @escaping () -> Void) {
        guard let (code, mods) = Self.parse(spec) else { return nil }
        Self.action = action
        if Self.handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                MainActor.assumeIsolated { HotKey.action?() }
                return noErr
            }, 1, &type, nil, &Self.handler)
        }
        let id = EventHotKeyID(signature: OSType(0x4149_5254), id: 1) // 'AIRT'
        guard RegisterEventHotKey(code, mods, id, GetApplicationEventTarget(), 0, &ref) == noErr else { return nil }
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }

    /// ANSI key codes 0…47 in order; the index is the virtual key code.
    private static let keys = Array("asdfhgzxcv§bqweryt123465=97-80]ou[ip\rlj'k;\\,/nm.")

    static func parse(_ spec: String) -> (UInt32, UInt32)? {
        var mods: UInt32 = 0
        var code: UInt32?
        for part in spec.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            switch part {
            case "cmd", "command": mods |= UInt32(cmdKey)
            case "opt", "option", "alt": mods |= UInt32(optionKey)
            case "ctrl", "control": mods |= UInt32(controlKey)
            case "shift": mods |= UInt32(shiftKey)
            case "space": code = UInt32(kVK_Space)
            default:
                guard part.count == 1, let i = keys.firstIndex(of: Character(part)) else { return nil }
                code = UInt32(i)
            }
        }
        guard let code, mods != 0 else { return nil }
        return (code, mods)
    }
}
