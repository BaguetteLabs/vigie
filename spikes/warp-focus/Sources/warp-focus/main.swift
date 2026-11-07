// Story 1.5 spike: can Vigie bring one specific Warp tab to the front?
//
//   warp-focus env                      print the Warp/terminal env vars this process sees
//   warp-focus trust [--prompt]         report AXIsProcessTrusted (optionally prompt once)
//   warp-focus dump                     print Warp's AX tree (windows, tab bars, tabs)
//   warp-focus focus --title <substr>   AX: press the tab whose title contains <substr>, raise its window, activate Warp
//   warp-focus focus --session <uuid>   URL: open warp://session/<uuid> (Warp's own WARP_FOCUS_URL)
//   warp-focus open-tab --path <dir>    URL: open warp://action/new_tab?path=<dir>
import AppKit
import ApplicationServices
import Foundation

let warpBundleIDs = ["dev.warp.Warp-Stable", "dev.warp.Warp-Preview", "dev.warp.Warp"]

func out(_ s: String) { FileHandle.standardOutput.write(Data((s + "\n").utf8)) }
func fail(_ s: String) -> Never {
    FileHandle.standardError.write(Data(("error: " + s + "\n").utf8))
    exit(1)
}

// MARK: env

func cmdEnv() {
    let env = ProcessInfo.processInfo.environment
    let keys = env.keys.filter {
        $0.hasPrefix("WARP_") || $0.hasPrefix("TERM") || $0 == "COLORTERM" || $0 == "__CFBundleIdentifier"
    }.sorted()
    for k in keys { out("\(k)=\(env[k] ?? "")") }
    out("tty=\(String(cString: ttyname(STDIN_FILENO) ?? ttyname(STDOUT_FILENO) ?? strdup("none")))")
    out("pid=\(getpid()) ppid=\(getppid())")
}

// MARK: AX helpers

func trusted(prompt: Bool) -> Bool {
    // String literal of kAXTrustedCheckOptionPrompt avoids touching the non-Sendable global in Swift 6.
    let opts = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
    return AXIsProcessTrustedWithOptions(opts)
}

func attr(_ el: AXUIElement, _ name: String) -> AnyObject? {
    var v: CFTypeRef?
    return AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success ? v : nil
}
func str(_ el: AXUIElement, _ name: String) -> String? { attr(el, name) as? String }
func children(_ el: AXUIElement) -> [AXUIElement] { (attr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
func actions(_ el: AXUIElement) -> [String] {
    var names: CFArray?
    return AXUIElementCopyActionNames(el, &names) == .success ? (names as? [String]) ?? [] : []
}

func warpApp() -> NSRunningApplication? {
    for id in warpBundleIDs {
        if let a = NSRunningApplication.runningApplications(withBundleIdentifier: id).first { return a }
    }
    return nil
}

func describe(_ el: AXUIElement) -> String {
    let role = str(el, kAXRoleAttribute) ?? "?"
    var parts = [role]
    if let s = str(el, kAXSubroleAttribute) { parts.append("sub=\(s)") }
    if let t = str(el, kAXTitleAttribute), !t.isEmpty { parts.append("title=\"\(t)\"") }
    if let d = str(el, kAXDescriptionAttribute), !d.isEmpty { parts.append("desc=\"\(d)\"") }
    if let i = str(el, "AXIdentifier"), !i.isEmpty { parts.append("id=\(i)") }
    if let v = attr(el, kAXValueAttribute) { parts.append("value=\(String(describing: v).prefix(60))") }
    if let sel = attr(el, kAXSelectedAttribute) as? Bool { parts.append("selected=\(sel)") }
    let a = actions(el)
    if !a.isEmpty { parts.append("actions=\(a.joined(separator: ","))") }
    return parts.joined(separator: " ")
}

func walk(_ el: AXUIElement, depth: Int, maxDepth: Int, visit: (AXUIElement, Int) -> Void) {
    visit(el, depth)
    guard depth < maxDepth else { return }
    for c in children(el) { walk(c, depth: depth + 1, maxDepth: maxDepth, visit: visit) }
}

func requireTrustedWarp() -> (NSRunningApplication, AXUIElement) {
    let t = trusted(prompt: false)
    out("AXIsProcessTrusted=\(t)")
    guard let app = warpApp() else { fail("Warp is not running") }
    out("warp pid=\(app.processIdentifier) bundle=\(app.bundleIdentifier ?? "?")")
    if !t {
        fail(
            "not trusted for Accessibility; grant it to the responsible process (the app that launched this binary), then re-run"
        )
    }
    return (app, AXUIElementCreateApplication(app.processIdentifier))
}

// MARK: commands

func cmdTrust(prompt: Bool) {
    out("AXIsProcessTrusted=\(trusted(prompt: false))")
    if prompt { out("AXIsProcessTrustedWithOptions(prompt: true)=\(trusted(prompt: true))") }
    out("executable=\(CommandLine.arguments[0]) pid=\(getpid()) ppid=\(getppid())")
    out(
        "env __CFBundleIdentifier=\(ProcessInfo.processInfo.environment["__CFBundleIdentifier"] ?? "-") (the TCC responsible process is normally this app)"
    )
}

func cmdDump(maxDepth: Int) {
    let (_, axApp) = requireTrustedWarp()
    let windows = (attr(axApp, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    out("windows=\(windows.count)")
    for (i, w) in windows.enumerated() {
        out("== window[\(i)] \(describe(w))")
        walk(w, depth: 1, maxDepth: maxDepth) { el, d in out(String(repeating: "  ", count: d) + describe(el)) }
    }
}

/// Candidate tabs: AXRadioButton/AXButton/AXTab-like elements (AXTabGroup children, or any element with AXPress whose title matches).
func findTab(title needle: String, in axApp: AXUIElement) -> (window: AXUIElement, tab: AXUIElement)? {
    let windows = (attr(axApp, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    for w in windows {
        var hit: AXUIElement?
        walk(w, depth: 0, maxDepth: 12) { el, _ in
            guard hit == nil else { return }
            let label = [
                str(el, kAXTitleAttribute), str(el, kAXDescriptionAttribute), attr(el, kAXValueAttribute) as? String,
            ]
            .compactMap { $0 }.joined(separator: " ")
            let role = str(el, kAXRoleAttribute) ?? ""
            let tabby =
                role == "AXRadioButton" || role == "AXTab" || str(el, kAXSubroleAttribute) == "AXTabButton"
                || actions(el).contains(kAXPressAction)
            if tabby, label.localizedCaseInsensitiveContains(needle) { hit = el }
        }
        if let hit { return (w, hit) }
    }
    return nil
}

func cmdFocusTitle(_ needle: String) {
    let (app, axApp) = requireTrustedWarp()
    let start = Date()
    guard let (win, tab) = findTab(title: needle, in: axApp) else {
        fail("no tab whose title contains \"\(needle)\" (run `dump` to see what Warp exposes)")
    }
    out("found \(describe(tab))")
    let press = AXUIElementPerformAction(tab, kAXPressAction as CFString)
    let raise = AXUIElementPerformAction(win, kAXRaiseAction as CFString)
    AXUIElementSetAttributeValue(win, kAXMainAttribute as CFString, kCFBooleanTrue)
    let activated = app.activate()
    out(
        "press=\(press.rawValue) raise=\(raise.rawValue) activate=\(activated) elapsed=\(String(format: "%.0f", Date().timeIntervalSince(start) * 1000))ms"
    )
}

func openURL(_ s: String) {
    guard let url = URL(string: s) else { fail("bad url \(s)") }
    let start = Date()
    let ok = NSWorkspace.shared.open(url)
    out("open \(s) -> \(ok) in \(String(format: "%.0f", Date().timeIntervalSince(start) * 1000))ms")
}

func cmdFocusSession(_ uuid: String) {
    let hex = uuid.lowercased().filter { $0.isHexDigit }
    guard hex.count == 32 else { fail("session uuid must be 32 hex chars (WARP_TERMINAL_SESSION_UUID)") }
    openURL("warp://session/\(hex)")
}

func cmdOpenTab(path: String) {
    var c = URLComponents()
    c.scheme = "warp"
    c.host = "action"
    c.path = "/new_tab"
    c.queryItems = [URLQueryItem(name: "path", value: path)]
    openURL(c.string!)
}

// MARK: main

let args = Array(CommandLine.arguments.dropFirst())
func value(_ flag: String) -> String? {
    args.firstIndex(of: flag).flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
}

switch args.first {
case "env": cmdEnv()
case "trust": cmdTrust(prompt: args.contains("--prompt"))
case "dump": cmdDump(maxDepth: Int(value("--depth") ?? "") ?? 10)
case "focus":
    if let t = value("--title") {
        cmdFocusTitle(t)
    } else if let s = value("--session") {
        cmdFocusSession(s)
    } else {
        fail("focus needs --title <substring> or --session <uuid>")
    }
case "open-tab": cmdOpenTab(path: value("--path") ?? FileManager.default.currentDirectoryPath)
default:
    out(
        "usage: warp-focus env | trust [--prompt] | dump [--depth N] | focus --title <s> | focus --session <uuid> | open-tab --path <dir>"
    )
    exit(2)
}
