// keepactive — 让 Mac 在无人操作时自动模拟真人活动（小幅移动鼠标 / 在飞书文档里打字后自动删除）。
//
// 用法：
//   keepactive start     在后台启动（自动检测并引导授予「辅助功能」权限）
//   keepactive stop      停止后台运行
//   keepactive status    查看运行状态和最近日志
//   keepactive run       在当前终端前台运行（按 Ctrl+C 停止，方便观察）
//   keepactive selftest  自检（不会模拟任何操作）
//   keepactive config    打印配置文件路径与当前配置
//
// 编译： swiftc -O main.swift -o keepactive && codesign --force --sign - keepactive

import Foundation
import AppKit
import ApplicationServices
import CoreGraphics
import Darwin

// MARK: - 路径

let supportDir: URL = {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return base.appendingPathComponent("KeepActive", isDirectory: true)
}()
let configPath = supportDir.appendingPathComponent("config.json")
let pidPath    = supportDir.appendingPathComponent("keepactive.pid")
let logPath    = supportDir.appendingPathComponent("keepactive.log")

func ensureSupportDir() {
    try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
}

func executablePath() -> String {
    var size: UInt32 = 0
    _NSGetExecutablePath(nil, &size)
    var buf = [CChar](repeating: 0, count: Int(size) + 1)
    _NSGetExecutablePath(&buf, &size)
    let raw = String(cString: buf)
    if let real = realpath(raw, nil) {
        defer { free(real) }
        return String(cString: real)
    }
    return raw
}

// MARK: - 配置

struct Config: Codable {
    // 空闲多久后开始动鼠标（秒，每次在区间内随机）。真人一碰鼠标键盘，计时清零，程序自动让位。
    var jiggleIdleMin: Double = 35
    var jiggleIdleMax: Double = 65
    // 主循环轮询间隔（秒）
    var pollMin: Double = 5
    var pollMax: Double = 11

    // 飞书打字
    var feishuEnabled: Bool = true
    var larkBundleId: String = "com.electron.lark"
    // 可选：打字前先打开这个文档链接（留空则只是把飞书切到前台，输入到当前光标所在位置）
    var feishuDocURL: String = ""
    // 固定输入的那段话（建议纯中文、不含换行、不含括号引号等会被自动配对的符号）
    var feishuText: String = "今天主要跟进了几位客户的沟通情况，梳理了一下后续需要处理的事项，整体进展比较顺利，接下来继续保持节奏推进。"
    // 两次打字之间的间隔（秒，随机）
    var typeIntervalMin: Double = 240
    var typeIntervalMax: Double = 600
    // 打字前先「静默观察」几秒确认真的没人在用
    var awayCheckSeconds: Double = 3
    // 每个字之间的间隔（秒，随机）
    var charDelayMin: Double = 0.06
    var charDelayMax: Double = 0.18
    // 打完之后停顿多久再删除（秒，随机）
    var afterTypePauseMin: Double = 0.8
    var afterTypePauseMax: Double = 2.0
    // 打完后是否自动用退格删掉刚输入的字
    var autoUndo: Bool = true

    init() {}

    // 容错解析：配置文件里缺某个字段时用默认值，避免用户改坏文件后程序起不来
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

    // 保证 min <= max，避免随机区间反了导致崩溃
    func sanitized() -> Config {
        var s = self
        func fix(_ a: inout Double, _ b: inout Double) { if a > b { swap(&a, &b) } }
        fix(&s.jiggleIdleMin, &s.jiggleIdleMax)
        fix(&s.pollMin, &s.pollMax)
        fix(&s.typeIntervalMin, &s.typeIntervalMax)
        fix(&s.charDelayMin, &s.charDelayMax)
        fix(&s.afterTypePauseMin, &s.afterTypePauseMax)
        s.pollMin = max(1, s.pollMin); s.pollMax = max(s.pollMin, s.pollMax)
        s.jiggleIdleMin = max(5, s.jiggleIdleMin); s.jiggleIdleMax = max(s.jiggleIdleMin, s.jiggleIdleMax)
        s.awayCheckSeconds = max(1, s.awayCheckSeconds)
        return s
    }
}

func writeDefaultConfig() {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    if let data = try? enc.encode(Config()) {
        try? data.write(to: configPath)
    }
}

func loadConfig() -> Config {
    ensureSupportDir()
    if !FileManager.default.fileExists(atPath: configPath.path) {
        writeDefaultConfig()
    }
    guard let data = try? Data(contentsOf: configPath) else { return Config() }
    do {
        return try JSONDecoder().decode(Config.self, from: data).sanitized()
    } catch {
        // 配置文件损坏：备份后重建默认配置
        let backup = supportDir.appendingPathComponent("config.broken.\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.moveItem(at: configPath, to: backup)
        writeDefaultConfig()
        return Config()
    }
}

// MARK: - 日志

let logQueue = DispatchQueue(label: "keepactive.log")
let dateFmt: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f
}()

func log(_ msg: String, alsoStdout: Bool = false) {
    let line = "[\(dateFmt.string(from: Date()))] \(msg)\n"
    if alsoStdout { FileHandle.standardOutput.write(line.data(using: .utf8)!) }
    logQueue.sync {
        if let h = FileHandle(forWritingAtPath: logPath.path) {
            h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); h.closeFile()
        } else {
            try? line.write(to: logPath, atomically: true, encoding: .utf8)
        }
    }
}

func trimLogIfLarge() {
    if let attrs = try? FileManager.default.attributesOfItem(atPath: logPath.path),
       let size = attrs[.size] as? Int, size > 2_000_000 {
        try? FileManager.default.removeItem(at: logPath)
    }
}

func tailLog(_ n: Int) -> String {
    guard let s = try? String(contentsOf: logPath, encoding: .utf8) else { return "(暂无日志)" }
    let lines = s.split(separator: "\n", omittingEmptySubsequences: true)
    return lines.suffix(n).joined(separator: "\n")
}

// MARK: - 系统信息

let anyInputEvent = CGEventType(rawValue: ~0)!  // kCGAnyInputEventType

/// 距离上一次鼠标/键盘事件过去了多少秒（包含我们自己模拟的事件）
func idleSeconds() -> Double {
    return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInputEvent)
}

func isAccessibilityTrusted(prompt: Bool) -> Bool {
    if !prompt { return AXIsProcessTrusted() }
    let opts = ["AXTrustedCheckOptionPrompt": kCFBooleanTrue as Any] as CFDictionary
    return AXIsProcessTrustedWithOptions(opts)
}

func frontmostBundleId() -> String? {
    return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
}

func isAppRunning(bundleId: String) -> Bool {
    return !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty
}

@discardableResult
func runProcess(_ path: String, _ args: [String]) -> Int32 {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return -1 }
    p.waitUntilExit()
    return p.terminationStatus
}

// MARK: - 停止信号

var gStop: sig_atomic_t = 0
func handleStopSignal(_ sig: Int32) { gStop = 1 }

func sleepInterruptible(_ seconds: Double) {
    var remaining = seconds
    while remaining > 0 && gStop == 0 {
        let step = min(0.25, remaining)
        usleep(UInt32(step * 1_000_000))
        remaining -= step
    }
}

// MARK: - 模拟输入

let eventSource = CGEventSource(stateID: .hidSystemState)

func currentMouse() -> CGPoint {
    return CGEvent(source: nil)?.location ?? .zero
}

func postMove(to p: CGPoint) {
    if let e = CGEvent(mouseEventSource: eventSource, mouseType: .mouseMoved,
                       mouseCursorPosition: p, mouseButton: .left) {
        e.post(tap: .cghidEventTap)
    }
}

/// 小幅、带随机曲线的鼠标移动，像人手无意识地碰了一下鼠标
func jiggleMouse() {
    let start = currentMouse()
    let angle = Double.random(in: 0..<(2 * Double.pi))
    let dist = Double.random(in: 12...40)
    let target = CGPoint(x: start.x + cos(angle) * dist, y: start.y + sin(angle) * dist)

    func glide(from a: CGPoint, to b: CGPoint, steps: Int) {
        for i in 1...steps {
            if gStop != 0 { return }
            let t = Double(i) / Double(steps)
            // 轻微的 ease-in-out + 小抖动
            let e = t * t * (3 - 2 * t)
            let jitter = CGFloat(Double.random(in: -0.8...0.8))
            let p = CGPoint(x: a.x + (b.x - a.x) * e + jitter, y: a.y + (b.y - a.y) * e + jitter)
            postMove(to: p)
            usleep(UInt32.random(in: 7_000...16_000))
        }
    }

    glide(from: start, to: target, steps: Int.random(in: 6...14))
    // 一半概率再往回挪一点，不至于每次都单向漂移
    if Bool.random() {
        usleep(UInt32.random(in: 80_000...300_000))
        let back = CGPoint(x: start.x + (target.x - start.x) * Double.random(in: 0.0...0.6),
                           y: start.y + (target.y - start.y) * Double.random(in: 0.0...0.6))
        glide(from: target, to: back, steps: Int.random(in: 4...10))
    }
}

/// 逐字输入任意 Unicode 文本（中文无需依赖输入法）。返回实际输入的字数。
func typeText(_ text: String, cfg: Config) -> Int {
    var typed = 0
    for ch in text {
        if gStop != 0 { break }
        let units = Array(String(ch).utf16)
        if let down = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true) {
            down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            down.post(tap: .cghidEventTap)
        }
        usleep(UInt32.random(in: 15_000...45_000))
        if let up = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: false) {
            up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            up.post(tap: .cghidEventTap)
        }
        typed += 1
        usleep(UInt32(Double.random(in: cfg.charDelayMin...cfg.charDelayMax) * 1_000_000))
        // 偶尔停顿一下，像在想下一句
        if Int.random(in: 0..<9) == 0 {
            usleep(UInt32(Double.random(in: 0.3...1.1) * 1_000_000))
        }
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

/// 静默观察几秒：期间我们不发任何事件；如果空闲时间正常累积，说明真的没人在用电脑
func userIsAway(cfg: Config) -> Bool {
    let before = idleSeconds()
    sleepInterruptible(cfg.awayCheckSeconds)
    if gStop != 0 { return false }
    let after = idleSeconds()
    return after >= before + cfg.awayCheckSeconds * 0.8
}

/// 把飞书切到前台并输入固定的一段话，然后（可选）精确删除
func feishuSession(cfg: Config) {
    if !cfg.feishuDocURL.isEmpty {
        runProcess("/usr/bin/open", [cfg.feishuDocURL])
        sleepInterruptible(2.5)
    } else {
        if !isAppRunning(bundleId: cfg.larkBundleId) {
            log("飞书没有在运行，跳过本次打字（不会自动启动飞书）")
            return
        }
        runProcess("/usr/bin/open", ["-b", cfg.larkBundleId])
        sleepInterruptible(1.2)
    }
    if gStop != 0 { return }

    // 安全护栏：确认飞书真的在前台，否则绝不打字，避免把文字打进别的软件
    var front = frontmostBundleId()
    if front != cfg.larkBundleId {
        sleepInterruptible(1.0)
        front = frontmostBundleId()
    }
    guard front == cfg.larkBundleId else {
        log("飞书未能切到前台（当前前台：\(front ?? "未知")），跳过本次打字")
        return
    }

    let typed = typeText(cfg.feishuText, cfg: cfg)
    if cfg.autoUndo {
        usleep(UInt32(Double.random(in: cfg.afterTypePauseMin...cfg.afterTypePauseMax) * 1_000_000))
        pressBackspace(times: typed)
        log("飞书打字 \(typed) 字，已自动删除")
    } else {
        log("飞书打字 \(typed) 字，保留在文档中")
    }
}

// MARK: - 后台工作循环

func workerMain() {
    ensureSupportDir()
    trimLogIfLarge()

    // 脱离终端会话：关掉终端窗口也不会被杀掉
    _ = setsid()
    signal(SIGHUP, SIG_IGN)
    signal(SIGTERM, handleStopSignal)
    signal(SIGINT, handleStopSignal)

    let pid = getpid()
    try? "\(pid)".write(to: pidPath, atomically: true, encoding: .utf8)

    let cfg = loadConfig()
    log("启动 (pid \(pid))。鼠标：空闲 \(Int(cfg.jiggleIdleMin))~\(Int(cfg.jiggleIdleMax)) 秒后微动；飞书打字：\(cfg.feishuEnabled ? "开启，每 \(Int(cfg.typeIntervalMin/60))~\(Int(cfg.typeIntervalMax/60)) 分钟一次，打完\(cfg.autoUndo ? "自动删除" : "保留")" : "关闭")")

    if !isAccessibilityTrusted(prompt: false) {
        log("⚠️ 未获得「辅助功能」权限，模拟操作不会生效。请到 系统设置 → 隐私与安全性 → 辅助功能 打开 keepactive 的开关后重新 start。")
    }

    var nextType = Date().addingTimeInterval(Double.random(in: 60...180))
    var jiggleThreshold = Double.random(in: cfg.jiggleIdleMin...cfg.jiggleIdleMax)
    var jiggleCount = 0

    while gStop == 0 {
        let idle = idleSeconds()

        if idle >= jiggleThreshold {
            jiggleMouse()
            jiggleCount += 1
            if jiggleCount % 10 == 1 {   // 不用每次都记，避免日志刷屏
                log("鼠标微动（此前空闲 \(Int(idle)) 秒，累计 \(jiggleCount) 次）")
            }
            jiggleThreshold = Double.random(in: cfg.jiggleIdleMin...cfg.jiggleIdleMax)
        }

        if cfg.feishuEnabled && Date() >= nextType && gStop == 0 {
            if userIsAway(cfg: cfg) {
                feishuSession(cfg: cfg)
                nextType = Date().addingTimeInterval(Double.random(in: cfg.typeIntervalMin...cfg.typeIntervalMax))
            } else {
                // 有人在用电脑，先不打扰，稍后再看
                nextType = Date().addingTimeInterval(Double.random(in: 45...120))
            }
        }

        sleepInterruptible(Double.random(in: cfg.pollMin...cfg.pollMax))
    }

    try? FileManager.default.removeItem(at: pidPath)
    log("已停止 (pid \(pid))")
}

// MARK: - 命令

func readRunningPid() -> pid_t? {
    guard let s = try? String(contentsOf: pidPath, encoding: .utf8),
          let pid = pid_t(s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
    if kill(pid, 0) == 0 { return pid }
    try? FileManager.default.removeItem(at: pidPath)   // 残留的 pid 文件
    return nil
}

func openAccessibilitySettings() {
    runProcess("/usr/bin/open", ["x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"])
}

func cmdStart() {
    ensureSupportDir()
    _ = loadConfig()

    if let pid = readRunningPid() {
        print("已经在运行了 (pid \(pid))。要停止请执行：keepactive stop")
        return
    }

    if !isAccessibilityTrusted(prompt: true) {
        openAccessibilitySettings()
        print("""
        ⚠️ 还没有「辅助功能」权限，暂时没有启动。

        请在刚打开的「系统设置 → 隐私与安全性 → 辅助功能」里：
          1. 找到 keepactive（如果列表里没有，点左下角「+」，选择这个文件：
             \(executablePath())）
          2. 把它右边的开关打开
          3. 回到终端，重新执行一次 start 命令
        """)
        exit(1)
    }

    let p = Process()
    p.executableURL = URL(fileURLWithPath: executablePath())
    p.arguments = ["_worker"]
    p.standardInput = FileHandle.nullDevice
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do {
        try p.run()
    } catch {
        print("启动失败：\(error)")
        exit(1)
    }
    try? "\(p.processIdentifier)".write(to: pidPath, atomically: true, encoding: .utf8)

    let cfg = loadConfig()
    print("""
    ✅ 已在后台启动 (pid \(p.processIdentifier))。现在可以关掉这个终端窗口了。

      · 空闲 \(Int(cfg.jiggleIdleMin))~\(Int(cfg.jiggleIdleMax)) 秒后开始小幅移动鼠标；真人一碰鼠标键盘就自动让位
      · 飞书打字：\(cfg.feishuEnabled ? "每 \(Int(cfg.typeIntervalMin/60))~\(Int(cfg.typeIntervalMax/60)) 分钟一次，打完\(cfg.autoUndo ? "自动删除" : "保留")" : "已关闭")
      · 日志：\(logPath.path)
      · 配置：\(configPath.path)

    停止：keepactive stop     查看状态：keepactive status
    """)
}

func cmdStop() {
    guard let pid = readRunningPid() else {
        print("当前没有在运行。")
        return
    }
    kill(pid, SIGTERM)
    for _ in 0..<40 {   // 最多等 4 秒
        usleep(100_000)
        if kill(pid, 0) != 0 { break }
    }
    if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
    try? FileManager.default.removeItem(at: pidPath)
    print("🛑 已停止 (pid \(pid))。")
}

func cmdStatus() {
    if let pid = readRunningPid() {
        print("状态：运行中 (pid \(pid))")
    } else {
        print("状态：未运行")
    }
    print("辅助功能权限：\(isAccessibilityTrusted(prompt: false) ? "已授予" : "未授予 ⚠️")")
    print("当前空闲：\(String(format: "%.1f", idleSeconds())) 秒")
    print("日志：\(logPath.path)")
    print("--- 最近日志 ---")
    print(tailLog(12))
}

func cmdSelftest() {
    let cfg = loadConfig()
    print("可执行文件：\(executablePath())")
    print("辅助功能权限：\(isAccessibilityTrusted(prompt: false) ? "已授予 ✅" : "未授予 ⚠️（start 时会引导授权）")")
    print("当前空闲时间：\(String(format: "%.1f", idleSeconds())) 秒")
    print("飞书是否在运行：\(isAppRunning(bundleId: cfg.larkBundleId) ? "是" : "否")")
    print("当前前台应用：\(frontmostBundleId() ?? "未知")")
    print("鼠标位置：\(currentMouse())")
    print("配置文件：\(configPath.path)")
    print("飞书打字：\(cfg.feishuEnabled ? "开启" : "关闭")，文本 \(cfg.feishuText.count) 字，自动删除：\(cfg.autoUndo)")
}

func cmdConfig() {
    _ = loadConfig()
    print("配置文件：\(configPath.path)\n")
    if let s = try? String(contentsOf: configPath, encoding: .utf8) { print(s) }
    print("\n用文本编辑器修改后，执行 keepactive stop 再 keepactive start 生效。")
}

/// 立刻做一次飞书打字（供第一次验证用）：打开文档、光标放好后运行，可亲眼看它打字并自动删除
func cmdTestFeishu() {
    if !isAccessibilityTrusted(prompt: true) {
        openAccessibilitySettings()
        print("⚠️ 还没有辅助功能权限。请先在「系统设置 → 隐私与安全性 → 辅助功能」里打开 keepactive 的开关，再试。")
        exit(1)
    }
    let cfg = loadConfig()
    print("3 秒后开始：会把飞书切到前台，输入 \(cfg.feishuText.count) 个字，然后\(cfg.autoUndo ? "自动删除" : "保留")。")
    print("请确保你要写入的飞书文档是打开的、且光标已经点进正文里。")
    signal(SIGINT, handleStopSignal)
    sleepInterruptible(3)
    if gStop != 0 { return }
    feishuSession(cfg: cfg)
    print("完成。文本内容可在 keepactive config 里修改（feishuText 字段）。")
}

func usage() {
    print("""
    keepactive — 无人操作时自动模拟真人活动

      keepactive start        在后台启动
      keepactive stop         停止
      keepactive status       查看状态和最近日志
      keepactive run          在前台运行（Ctrl+C 停止）
      keepactive test-feishu  立刻试打一次飞书（第一次用来验证）
      keepactive selftest     自检（不会模拟任何操作）
      keepactive config       查看配置文件
    """)
}

// MARK: - 入口

let args = CommandLine.arguments.dropFirst()
switch args.first ?? "" {
case "start":    cmdStart()
case "stop":     cmdStop()
case "status":   cmdStatus()
case "selftest": cmdSelftest()
case "test-feishu": cmdTestFeishu()
case "config":   cmdConfig()
case "_worker":  workerMain()
case "run":
    if let pid = readRunningPid() {
        print("后台已经在运行 (pid \(pid))，请先 keepactive stop。")
        exit(1)
    }
    if !isAccessibilityTrusted(prompt: true) {
        openAccessibilitySettings()
        print("⚠️ 请先在「系统设置 → 隐私与安全性 → 辅助功能」里打开 keepactive 的开关，然后重新运行。")
        exit(1)
    }
    print("前台运行中，按 Ctrl+C 停止。日志同时写入 \(logPath.path)")
    workerMain()
default: usage()
}
