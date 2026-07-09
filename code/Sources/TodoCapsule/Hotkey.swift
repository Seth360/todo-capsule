import AppKit
import Carbon.HIToolbox

/// 多全局热键。仍用 Carbon RegisterEventHotKey，无需辅助功能权限；按 id 分发到不同动作。
final class GlobalHotkey {
    static let shared = GlobalHotkey()

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private var installed = false

    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        installHandlerIfNeeded()
        if let existing = refs[id] {
            UnregisterEventHotKey(existing)
            refs[id] = nil
        }
        handlers[id] = handler
        var ref: EventHotKeyRef?
        let hotID = EventHotKeyID(signature: OSType(0x54434150), id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotID, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            refs[id] = ref
        } else {
            NSLog("todo-capsule: 全局热键注册失败(id=\(id), status=\(status))，该组合可能被系统/输入法占用")
        }
    }

    private func installHandlerIfNeeded() {
        guard !installed else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                var hotID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotID
                )
                guard status == noErr else { return status }
                DispatchQueue.main.async {
                    GlobalHotkey.shared.handlers[hotID.id]?()
                }
                return noErr
            },
            1, &spec, nil, nil
        )
        installed = true
    }
}
