// MeetingNotes.app — 菜单栏版（无需终端）
// 双击打开后常驻菜单栏，点图标即可开始/停止。核心逻辑与命令行版一致。
//
// 编译见 build-app.sh

import Foundation
import AppKit
import ApplicationServices
import CoreGraphics
import ServiceManagement

typealias StopCheck = () -> Bool

// MARK: - 路径

let supportDir: URL = {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return base.appendingPathComponent("MeetingNotes", isDirectory: true)
}()
let configPath = supportDir.appendingPathComponent("config.json")
let logPath    = supportDir.appendingPathComponent("meetingnotes.log")

func ensureSupportDir() {
    try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
}

// MARK: - 配置

struct Config: Codable {
    var jiggleIdleMin: Double = 35
    var jiggleIdleMax: Double = 65
    var pollMin: Double = 5
    var pollMax: Double = 11
    var feishuEnabled: Bool = true
    var larkBundleId: String = "com.electron.lark"
    var feishuDocURL: String = ""
    var feishuText: String = "今天主要跟进了几位客户的沟通情况，梳理了一下后续需要处理的事项，整体进展比较顺利，接下来继续保持节奏推进。"
    var typeIntervalMin: Double = 240
    var typeIntervalMax: Double = 600
    var awayCheckSeconds: Double = 3
    var charDelayMin: Double = 0.06
    var charDelayMax: Double = 0.18
    var afterTypePauseMin: Double = 0.8
    var afterTypePauseMax: Double = 2.0
    var autoUndo: Bool = true

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        jiggleIdleMin     = try c.decodeIfPresent(Double.self, forKey: .jiggleIdleMin) ?? d.jiggleIdleMin
        jiggleIdleMax     = try c.decodeIfPresent(Double.self, forKey: .jiggleIdleMax) ?? d.jiggleIdleMax
        pollMin           = try c.decodeIfPresent(Double.self, forKey: .pollMin) ?? d.pollMin
        pollMax           = try c.decodeIfPresent(Double.self, forKey: .pollMax) ?? d.pollMax
        feishuEnabled     = try c.decodeIfPresent(Bool.self,   forKey: .feishuEnabled) ?? d.feishuEnabled
        larkBundleId      = try c.decodeIfPresent(String.self, forKey: .larkBundleId) ?? d.larkBundleId
        feishuDocURL      = try c.decodeIfPresent(String.self, forKey: .feishuDocURL) ?? d.feishuDocURL
        feishuText        = try c.decodeIfPresent(String.self, forKey: .feishuText) ?? d.feishuText
        typeIntervalMin   = try c.decodeIfPresent(Double.self, forKey: .typeIntervalMin) ?? d.typeIntervalMin
        typeIntervalMax   = try c.decodeIfPresent(Double.self, forKey: .typeIntervalMax) ?? d.typeIntervalMax
        awayCheckSeconds  = try c.decodeIfPresent(Double.self, forKey: .awayCheckSeconds) ?? d.awayCheckSeconds
        charDelayMin      = try c.decodeIfPresent(Double.self, forKey: .charDelayMin) ?? d.charDelayMin
        charDelayMax      = try c.decodeIfPresent(Double.self, forKey: .charDelayMax) ?? d.charDelayMax
        afterTypePauseMin = try c.decodeIfPresent(Double.self, forKey: .afterTypePauseMin) ?? d.afterTypePauseMin
        afterTypePauseMax = try c.decodeIfPresent(Double.self, forKey: .afterTypePauseMax) ?? d.afterTypePauseMax
        autoUndo          = try c.decodeIfPresent(Bool.self,   forKey: .autoUndo) ?? d.autoUndo
    }
    func sanitized() -> Config {
        var s = self
        func fix(_ a: inout Double, _ b: inout Double) { if a > b { swap(&a, &b) } }
        fix(&s.jiggleIdleMin, &s.jiggleIdleMax); fix(&s.pollMin, &s.pollMax)
        fix(&s.typeIntervalMin, &s.typeIntervalMax); fix(&s.charDelayMin, &s.charDelayMax)
        fix(&s.afterTypePauseMin, &s.afterTypePauseMax)
        s.pollMin = max(1, s.pollMin); s.pollMax = max(s.pollMin, s.pollMax)
        s.jiggleIdleMin = max(5, s.jiggleIdleMin); s.jiggleIdleMax = max(s.jiggleIdleMin, s.jiggleIdleMax)
        s.awayCheckSeconds = max(1, s.awayCheckSeconds)
        return s
    }
}

func writeDefaultConfig() {
    let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    if let data = try? enc.encode(Config()) { try? data.write(to: configPath) }
}
func loadConfig() -> Config {
    ensureSupportDir()
    if !FileManager.default.fileExists(atPath: configPath.path) { writeDefaultConfig() }
    guard let data = try? Data(contentsOf: configPath) else { return Config() }
    return (try? JSONDecoder().decode(Config.self, from: data).sanitized()) ?? Config()
}

// MARK: - 日志

let logQueue = DispatchQueue(label: "meetingnotes.log")
let dateFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"; return f }()
func log(_ msg: String) {
    let line = "[\(dateFmt.string(from: Date()))] \(msg)\n"
    logQueue.sync {
        if let h = FileHandle(forWritingAtPath: logPath.path) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile()
        } else { try? line.write(to: logPath, atomically: true, encoding: .utf8) }
    }
}

// MARK: - 系统信息 / 模拟输入

let anyInputEvent = CGEventType(rawValue: ~0)!
func idleSeconds() -> Double { CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInputEvent) }
func isAccessibilityTrusted(prompt: Bool) -> Bool {
    if !prompt { return AXIsProcessTrusted() }
    return AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": kCFBooleanTrue as Any] as CFDictionary)
}
func frontmostBundleId() -> String? { NSWorkspace.shared.frontmostApplication?.bundleIdentifier }
func isAppRunning(bundleId: String) -> Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty }
@discardableResult
func runProcess(_ path: String, _ args: [String]) -> Int32 {
    let p = Process(); p.executableURL = URL(fileURLWithPath: path); p.arguments = args
    p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return -1 }; p.waitUntilExit(); return p.terminationStatus
}
func openAccessibilitySettings() {
    runProcess("/usr/bin/open", ["x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"])
}

let eventSource = CGEventSource(stateID: .hidSystemState)
func currentMouse() -> CGPoint { CGEvent(source: nil)?.location ?? .zero }
func postMove(to p: CGPoint) {
    CGEvent(mouseEventSource: eventSource, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}

func sleepInterruptible(_ seconds: Double, stop: StopCheck) {
    var r = seconds
    while r > 0 && !stop() { let step = min(0.2, r); usleep(UInt32(step * 1_000_000)); r -= step }
}

func jiggleMouse(stop: StopCheck) {
    let start = currentMouse()
    let angle = Double.random(in: 0..<(2 * Double.pi))
    let dist = Double.random(in: 12...40)
    let target = CGPoint(x: start.x + cos(angle) * dist, y: start.y + sin(angle) * dist)
    func glide(_ a: CGPoint, _ b: CGPoint, _ steps: Int) {
        for i in 1...steps {
            if stop() { return }
            let t = Double(i) / Double(steps); let e = t * t * (3 - 2 * t)
            let j = CGFloat(Double.random(in: -0.8...0.8))
            postMove(to: CGPoint(x: a.x + (b.x - a.x) * e + j, y: a.y + (b.y - a.y) * e + j))
            usleep(UInt32.random(in: 7_000...16_000))
        }
    }
    glide(start, target, Int.random(in: 6...14))
    if Bool.random() {
        usleep(UInt32.random(in: 80_000...300_000))
        let back = CGPoint(x: start.x + (target.x - start.x) * Double.random(in: 0.0...0.6),
                           y: start.y + (target.y - start.y) * Double.random(in: 0.0...0.6))
        glide(target, back, Int.random(in: 4...10))
    }
}

func typeText(_ text: String, cfg: Config, stop: StopCheck) -> Int {
    var typed = 0
    for ch in text {
        if stop() { break }
        let u = Array(String(ch).utf16)
        if let d = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true) {
            d.keyboardSetUnicodeString(stringLength: u.count, unicodeString: u); d.post(tap: .cghidEventTap)
        }
        usleep(UInt32.random(in: 15_000...45_000))
        if let up = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: false) {
            up.keyboardSetUnicodeString(stringLength: u.count, unicodeString: u); up.post(tap: .cghidEventTap)
        }
        typed += 1
        usleep(UInt32(Double.random(in: cfg.charDelayMin...cfg.charDelayMax) * 1_000_000))
        if Int.random(in: 0..<9) == 0 { usleep(UInt32(Double.random(in: 0.3...1.1) * 1_000_000)) }
    }
    return typed
}

func pressBackspace(times: Int) {
    guard times > 0 else { return }
    for _ in 0..<times {
        if let d = CGEvent(keyboardEventSource: eventSource, virtualKey: 51, keyDown: true) { d.post(tap: .cghidEventTap) }
        usleep(UInt32.random(in: 18_000...45_000))
        if let u = CGEvent(keyboardEventSource: eventSource, virtualKey: 51, keyDown: false) { u.post(tap: .cghidEventTap) }
        usleep(UInt32.random(in: 12_000...40_000))
    }
}

func userIsAway(cfg: Config, stop: StopCheck) -> Bool {
    let before = idleSeconds()
    sleepInterruptible(cfg.awayCheckSeconds, stop: stop)
    if stop() { return false }
    return idleSeconds() >= before + cfg.awayCheckSeconds * 0.8
}

func feishuSession(cfg: Config, stop: StopCheck) {
    if !cfg.feishuDocURL.isEmpty {
        runProcess("/usr/bin/open", [cfg.feishuDocURL]); sleepInterruptible(2.5, stop: stop)
    } else {
        if !isAppRunning(bundleId: cfg.larkBundleId) { log("飞书没有在运行，跳过本次打字"); return }
        runProcess("/usr/bin/open", ["-b", cfg.larkBundleId]); sleepInterruptible(1.2, stop: stop)
    }
    if stop() { return }
    var front = frontmostBundleId()
    if front != cfg.larkBundleId { sleepInterruptible(1.0, stop: stop); front = frontmostBundleId() }
    guard front == cfg.larkBundleId else { log("飞书未能切到前台（当前：\(front ?? "未知")），跳过打字"); return }
    let typed = typeText(cfg.feishuText, cfg: cfg, stop: stop)
    if cfg.autoUndo {
        usleep(UInt32(Double.random(in: cfg.afterTypePauseMin...cfg.afterTypePauseMax) * 1_000_000))
        pressBackspace(times: typed); log("飞书打字 \(typed) 字，已自动删除")
    } else { log("飞书打字 \(typed) 字，保留") }
}

// MARK: - 后台工作线程

final class Worker {
    private(set) var running = false
    private var stopFlag = true
    var onState: (() -> Void)?

    func start() {
        guard !running else { return }
        stopFlag = false; running = true
        onState?()
        let t = Thread { [weak self] in self?.loop() }
        t.stackSize = 1 << 20
        t.start()
    }
    func stop() {
        guard running else { return }
        stopFlag = true; running = false; onState?()
        log("已停止")
    }
    private func loop() {
        let cfg = loadConfig()
        log("启动（菜单栏版）。空闲 \(Int(cfg.jiggleIdleMin))~\(Int(cfg.jiggleIdleMax)) 秒后微动鼠标；飞书打字：\(cfg.feishuEnabled ? "开启" : "关闭")")
        let stop: StopCheck = { [weak self] in self?.stopFlag ?? true }
        var nextType = Date().addingTimeInterval(Double.random(in: 60...180))
        var threshold = Double.random(in: cfg.jiggleIdleMin...cfg.jiggleIdleMax)
        while !stopFlag {
            if idleSeconds() >= threshold {
                jiggleMouse(stop: stop)
                threshold = Double.random(in: cfg.jiggleIdleMin...cfg.jiggleIdleMax)
            }
            if cfg.feishuEnabled && Date() >= nextType && !stopFlag {
                if userIsAway(cfg: cfg, stop: stop) {
                    feishuSession(cfg: cfg, stop: stop)
                    nextType = Date().addingTimeInterval(Double.random(in: cfg.typeIntervalMin...cfg.typeIntervalMax))
                } else {
                    nextType = Date().addingTimeInterval(Double.random(in: 45...120))
                }
            }
            sleepInterruptible(Double.random(in: cfg.pollMin...cfg.pollMax), stop: stop)
        }
    }
}

// MARK: - 菜单栏 UI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    let worker = Worker()
    var permTimer: Timer?
    var uiTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // 只在菜单栏，不出现在程序坞
        ensureSupportDir(); _ = loadConfig()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        worker.onState = { [weak self] in DispatchQueue.main.async { self?.updateUI() } }

        // 命令行传 --nostart 时不自动启动（仅供测试）
        let noStart = CommandLine.arguments.contains("--nostart")

        if isAccessibilityTrusted(prompt: false) {
            if !noStart { worker.start() }
        } else {
            _ = isAccessibilityTrusted(prompt: true)   // 弹出系统授权提示
            openAccessibilitySettings()
            showPermissionAlert()
            // 轮询：一旦授权成功就自动开始
            permTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                if isAccessibilityTrusted(prompt: false) {
                    self.permTimer?.invalidate(); self.permTimer = nil
                    if !noStart { self.worker.start() }
                    self.updateUI()
                }
            }
        }
        buildMenu()
        updateUI()
        uiTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in self?.updateUI() }
    }

    func buildMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "meetingnotes", action: nil, keyEquivalent: ""))
        menu.items.first?.isEnabled = false
        statusItem.menu = menu
        updateUI()
    }

    @objc func toggleRun() { worker.running ? worker.stop() : startWithPermCheck() }

    func startWithPermCheck() {
        if isAccessibilityTrusted(prompt: false) { worker.start() }
        else { _ = isAccessibilityTrusted(prompt: true); openAccessibilitySettings(); showPermissionAlert() }
    }

    @objc func testFeishu() {
        guard isAccessibilityTrusted(prompt: false) else { startWithPermCheck(); return }
        let cfg = loadConfig()
        DispatchQueue.global().async {
            let never: StopCheck = { false }
            usleep(300_000)
            feishuSession(cfg: cfg, stop: never)
        }
    }

    @objc func openConfig() {
        _ = loadConfig()
        runProcess("/usr/bin/open", ["-e", configPath.path])   // 用「文本编辑」打开
    }

    @objc func toggleLoginItem() {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
                else { try SMAppService.mainApp.register() }
            } catch { NSLog("login item error: \(error)") }
            updateUI()
        }
    }

    @objc func quit() { worker.stop(); NSApp.terminate(nil) }

    func updateUI() {
        let trusted = isAccessibilityTrusted(prompt: false)
        let running = worker.running

        if let btn = statusItem.button {
            let symbol = running ? "doc.text.fill" : "doc.text"
            btn.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "MeetingNotes")
            btn.image?.isTemplate = true
        }

        let menu = NSMenu()
        let statusText: String
        if !trusted { statusText = "⚠️ 未授权（点下方去授权）" }
        else if running { statusText = "● 运行中（无人操作时自动模拟）" }
        else { statusText = "○ 已暂停" }
        let head = NSMenuItem(title: statusText, action: nil, keyEquivalent: ""); head.isEnabled = false
        menu.addItem(head)
        menu.addItem(NSMenuItem.separator())

        if !trusted {
            menu.addItem(withTitle: "去「辅助功能」里授权…", action: #selector(goAuthorize), keyEquivalent: "")
        } else {
            let toggle = NSMenuItem(title: running ? "暂停" : "开始", action: #selector(toggleRun), keyEquivalent: "")
            menu.addItem(toggle)
        }
        menu.addItem(NSMenuItem(title: "试打飞书一次", action: #selector(testFeishu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "打开配置文件…", action: #selector(openConfig), keyEquivalent: ""))

        if #available(macOS 13.0, *) {
            let on = SMAppService.mainApp.status == .enabled
            let li = NSMenuItem(title: "开机时自动运行", action: #selector(toggleLoginItem), keyEquivalent: "")
            li.state = on ? .on : .off
            menu.addItem(li)
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items where item.action != nil { item.target = self }
        statusItem.menu = menu
    }

    @objc func goAuthorize() {
        _ = isAccessibilityTrusted(prompt: true)
        openAccessibilitySettings()
        showPermissionAlert()
    }

    func showPermissionAlert() {
        let a = NSAlert()
        a.messageText = "需要开启「辅助功能」权限"
        a.informativeText = """
        macOS 规定：模拟鼠标键盘必须先授权。

        已为你打开「系统设置 → 隐私与安全性 → 辅助功能」。请：
        1. 在列表里找到 MeetingNotes，把右边的开关打开
           （若没有，点列表下方的「＋」，添加「应用程序」里的 MeetingNotes）
        2. 打开开关后，本程序会自动开始工作（无需重启）

        若始终不生效，请退出本程序再重新打开一次。
        """
        a.addButton(withTitle: "我知道了")
        a.alertStyle = .informational
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
