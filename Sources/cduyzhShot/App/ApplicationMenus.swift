import AppKit

/// 让文本框和原生文件面板共享 macOS 标准编辑命令。
enum ApplicationMenus {
    static func addEditMenu(to mainMenu: NSMenu) {
        let menu = NSMenu(title: "编辑")
        let commands: [(String, String, String)] = [
            ("撤销", "undo:", "z"),
            ("重做", "redo:", "Z"),
            ("剪切", "cut:", "x"),
            ("复制", "copy:", "c"),
            ("粘贴", "paste:", "v"),
            ("全选", "selectAll:", "a")
        ]
        for (index, command) in commands.enumerated() {
            if index == 2 { menu.addItem(.separator()) }
            let item = NSMenuItem(title: command.0, action: Selector(command.1), keyEquivalent: command.2)
            item.keyEquivalentModifierMask = index == 1 ? [.command, .shift] : [.command]
            menu.addItem(item)
        }
        let item = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        item.submenu = menu
        mainMenu.addItem(item)
    }
}
