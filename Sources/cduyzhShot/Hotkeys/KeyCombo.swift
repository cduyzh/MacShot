import AppKit
import Carbon

public struct KeyCombo: Codable, Equatable, Hashable {
    public var keyCode: UInt16
    public var modifiers: UInt32 // Carbon modifier flags or NSEvent.ModifierFlags rawValue
    public var characters: String

    public init(keyCode: UInt16, modifiers: UInt32, characters: String = "") {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.characters = characters.isEmpty ? KeyCombo.stringForKeyCode(keyCode) : characters
    }

    // Convert NSEvent modifier flags to Carbon modifiers
    public var carbonModifiers: UInt32 {
        var carbonFlags: UInt32 = 0
        let nsFlags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        if nsFlags.contains(.control) { carbonFlags |= UInt32(controlKey) }
        if nsFlags.contains(.option) { carbonFlags |= UInt32(optionKey) }
        if nsFlags.contains(.command) { carbonFlags |= UInt32(cmdKey) }
        if nsFlags.contains(.shift) { carbonFlags |= UInt32(shiftKey) }
        return carbonFlags
    }

    public var displayString: String {
        var s = ""
        let nsFlags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        if nsFlags.contains(.control) { s += "⌃" }
        if nsFlags.contains(.option) { s += "⌥" }
        if nsFlags.contains(.shift) { s += "⇧" }
        if nsFlags.contains(.command) { s += "⌘" }
        s += KeyCombo.stringForKeyCode(keyCode)
        return s
    }

    public static func stringForKeyCode(_ code: UInt16) -> String {
        switch Int(code) {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_Minus: return "-"
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Escape: return "⎋"
        default: return "Key(\(code))"
        }
    }
}
