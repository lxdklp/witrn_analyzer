import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var analyzerMenus: AnalyzerMenuController?
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = NSRect(x: self.frame.origin.x, y: self.frame.origin.y, width: 1360, height: 920)
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 400, height: 600)
    self.center()

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
    analyzerMenus = AnalyzerMenuController(messenger: flutterViewController.engine.binaryMessenger)
  }
}

/// Keep AppKit's application, edit and window menus and their responder actions.
private final class AnalyzerMenuController: NSObject, NSMenuItemValidation {
  private let channel: FlutterMethodChannel
  private var items: [String: NSMenuItem] = [:]
  private var state: [String: Bool] = [:]

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "witrn_analyzer/menu", binaryMessenger: messenger)
    super.init()
    installMenus()
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "setState", let state = call.arguments as? [String: Bool] else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.update(state)
      result(nil)
    }
  }

  private func item(_ id: String, _ title: String, key: String = "",
                    modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: #selector(invoke(_:)), keyEquivalent: key)
    item.keyEquivalentModifierMask = modifiers
    item.representedObject = id
    item.target = self
    item.isEnabled = false
    items[id] = item
    return item
  }

  private func installMenus() {
    guard let main = NSApp.mainMenu else { return }
    if let preferences = main.items.first?.submenu?.items.first(where: { $0.keyEquivalent == "," }) {
      preferences.title = "设置…"
      preferences.action = #selector(invoke(_:))
      preferences.target = self
      preferences.representedObject = "settings"
      preferences.isEnabled = false
      items["settings"] = preferences
    }

    let file = NSMenu(title: "文件")
    file.addItem(item("newSession", "新建采集会话…", key: "n"))
    file.addItem(.separator())
    file.addItem(item("importChart", "导入图表…", key: "o"))
    file.addItem(item("exportChart", "导出图表…", key: "s"))
    file.addItem(.separator())
    file.addItem(item("importMessages", "导入 PD 报文…", key: "o", modifiers: [.command, .shift]))
    file.addItem(item("exportMessages", "导出 PD 报文…", key: "s", modifiers: [.command, .shift]))
    file.addItem(.separator())
    file.addItem(NSMenuItem(title: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
    let fileItem = NSMenuItem(title: "文件", action: nil, keyEquivalent: "")
    fileItem.submenu = file
    main.insertItem(fileItem, at: 1)

    let device = NSMenu(title: "设备")
    device.addItem(item("refresh", "刷新设备", key: "r"))
    device.addItem(item("connect", "连接设备", key: "k"))
    let f5 = String(UnicodeScalar(NSF5FunctionKey)!)
    device.addItem(item("connectAndStart", "连接或继续采集", key: f5, modifiers: []))
    device.addItem(item("disconnect", "断开连接", key: f5, modifiers: [.shift]))
    device.addItem(.separator())
    device.addItem(item("record", "继续采集", key: "\r"))
    let deviceItem = NSMenuItem(title: "设备", action: nil, keyEquivalent: "")
    deviceItem.submenu = device
    main.insertItem(deviceItem, at: 3)

    if let view = main.items.first(where: { $0.title == "显示" })?.submenu {
      view.insertItem(item("follow", "跟随最新数据", key: "l"), at: 0)
      view.insertItem(.separator(), at: 1)
    }
    if let help = main.items.first(where: { $0.title == "帮助" })?.submenu {
      help.addItem(item("diagnostics", "采集与导入诊断…"))
    }
  }

  private func update(_ nextState: [String: Bool]) {
    state = nextState
    for (id, item) in items {
      item.isEnabled = state[id] == true
    }
    items["record"]?.title = state["recording"] == true ? "暂停采集" : "继续采集"
    items["disconnect"]?.title = state["connecting"] == true ? "取消连接" : "断开连接"
    items["follow"]?.state = state["following"] == true ? .on : .off
  }

  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    guard let id = menuItem.representedObject as? String else { return false }
    return state[id] == true
  }

  @objc private func invoke(_ sender: NSMenuItem) {
    guard validateMenuItem(sender), let id = sender.representedObject as? String else { return }
    channel.invokeMethod("invoke", arguments: id)
  }
}
