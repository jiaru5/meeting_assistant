#!/usr/bin/env swift
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

enum AXSmokeError: Error, CustomStringConvertible {
    case usage
    case invalidPID(String)
    case noWindows(pid_t)
    case noVisibleWindow(pid_t)
    case missingIdentifier(String)
    case actionFailed(String, AXError)

    var description: String {
        switch self {
        case .usage:
            return "usage: local-app-ax.swift snapshot <timeout-seconds> <pid> | press <timeout-seconds> <pid> <AXIdentifier> | confirm <timeout-seconds> <pid> <AXIdentifier> | set-value <timeout-seconds> <pid> <AXIdentifier> <value> | window <timeout-seconds> <pid>"
        case .invalidPID(let raw):
            return "invalid pid: \(raw)"
        case .noWindows(let pid):
            return "MeetingAssistantNative window was not visible for pid \(pid)"
        case .noVisibleWindow(let pid):
            return "MeetingAssistantNative CoreGraphics window was not visible for pid \(pid)"
        case .missingIdentifier(let identifier):
            return "Missing AXIdentifier \(identifier)"
        case .actionFailed(let identifier, let error):
            return "AX action failed for \(identifier): \(error.rawValue)"
        }
    }
}

func pid(from raw: String) throws -> pid_t {
    guard let value = Int32(raw) else {
        throw AXSmokeError.invalidPID(raw)
    }
    return value
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, name as CFString, &value)
    guard error == .success else {
        return nil
    }
    return value
}

func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
    guard let value = attribute(element, name) else {
        return nil
    }
    if let bool = value as? Bool {
        return bool ? "true" : "false"
    }
    return String(describing: value)
        .replacingOccurrences(of: "\n", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func children(of element: AXUIElement) -> [AXUIElement] {
    guard let values = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else {
        return []
    }
    return values
}

func activateApp(pid: pid_t) {
    NSRunningApplication(processIdentifier: pid)?.activate(
        options: [.activateAllWindows]
    )
}

func isWindowElement(_ element: AXUIElement) -> Bool {
    stringAttribute(element, kAXRoleAttribute) == "AXWindow"
        || stringAttribute(element, kAXRoleAttribute) == "AXSheet"
}

func focusedOrMainWindows(for app: AXUIElement) -> [AXUIElement] {
    [kAXFocusedWindowAttribute, kAXMainWindowAttribute]
        .compactMap { name -> AXUIElement? in
            guard let value = attribute(app, name) else {
                return nil
            }
            return (value as! AXUIElement)
        }
        .filter(isWindowElement)
}

func raiseWindows(_ windows: [AXUIElement]) {
    for window in windows {
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }
}

func focus(_ element: AXUIElement) {
    _ = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
}

func setStringValue(_ value: String, on element: AXUIElement) -> AXError {
    focus(element)
    return AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as NSString)
}

func windows(for app: AXUIElement, pid: pid_t, timeout: TimeInterval) throws -> [AXUIElement] {
    activateApp(pid: pid)
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if let values = attribute(app, kAXWindowsAttribute) as? [AXUIElement],
           !values.isEmpty {
            let concreteWindows = values.filter { !CFEqual($0, app) }
            let rawCandidates = concreteWindows.isEmpty ? values : concreteWindows
            let windowCandidates = rawCandidates.filter(isWindowElement)
            if !windowCandidates.isEmpty {
                raiseWindows(windowCandidates)
                return windowCandidates
            }
        }
        let fallbackWindows = focusedOrMainWindows(for: app)
        if !fallbackWindows.isEmpty {
            raiseWindows(fallbackWindows)
            return fallbackWindows
        }
        _ = try? visibleWindow(for: pid, timeout: 0.25)
        Thread.sleep(forTimeInterval: 0.25)
    } while Date() < deadline
    throw AXSmokeError.noWindows(pid)
}

func visibleWindow(for pid: pid_t, timeout: TimeInterval) throws -> [String: Any] {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        let rawWindows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []
        if let window = rawWindows.first(where: { window in
            let ownerPID = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
                ?? Int32(window[kCGWindowOwnerPID as String] as? Int ?? -1)
            let layer = (window[kCGWindowLayer as String] as? NSNumber)?.intValue
                ?? window[kCGWindowLayer as String] as? Int
                ?? -1
            let isOnscreen = (window[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue
                ?? window[kCGWindowIsOnscreen as String] as? Bool
                ?? false
            return ownerPID == pid && layer == 0 && isOnscreen
        }) {
            return visibleWindowPayload(window, pid: pid)
        }
        Thread.sleep(forTimeInterval: 0.25)
    } while Date() < deadline
    throw AXSmokeError.noVisibleWindow(pid)
}

func visibleWindowPayload(_ window: [String: Any], pid: pid_t) -> [String: Any] {
    let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
    return [
        "pid": Int(pid),
        "window_number": numberValue(window[kCGWindowNumber as String]).map(Int.init) ?? 0,
        "owner_name": stringValue(window[kCGWindowOwnerName as String]),
        "window_name": stringValue(window[kCGWindowName as String]),
        "is_onscreen": boolValue(window[kCGWindowIsOnscreen as String]),
        "layer": numberValue(window[kCGWindowLayer as String]).map(Int.init) ?? -1,
        "bounds": [
            "x": numberValue(bounds["X"]) ?? 0,
            "y": numberValue(bounds["Y"]) ?? 0,
            "width": numberValue(bounds["Width"]) ?? 0,
            "height": numberValue(bounds["Height"]) ?? 0,
        ],
    ]
}

func stringValue(_ value: Any?) -> String {
    guard let value else {
        return ""
    }
    return String(describing: value)
}

func boolValue(_ value: Any?) -> Bool {
    if let bool = value as? Bool {
        return bool
    }
    if let number = value as? NSNumber {
        return number.boolValue
    }
    return false
}

func numberValue(_ value: Any?) -> Double? {
    if let number = value as? NSNumber {
        return number.doubleValue
    }
    if let double = value as? Double {
        return double
    }
    if let int = value as? Int {
        return Double(int)
    }
    return nil
}

func line(for element: AXUIElement) -> String {
    var parts: [String] = []
    if let role = stringAttribute(element, kAXRoleAttribute) {
        parts.append("role=\(role)")
    }
    if let identifier = stringAttribute(element, "AXIdentifier") {
        parts.append("identifier=\(identifier)")
    }
    if let enabled = stringAttribute(element, kAXEnabledAttribute) {
        parts.append("enabled=\(enabled)")
    }
    if let subrole = stringAttribute(element, kAXSubroleAttribute) {
        parts.append("subrole=\(subrole)")
    }
    if let title = stringAttribute(element, kAXTitleAttribute) {
        parts.append("name=\(title)")
    }
    if let description = stringAttribute(element, kAXDescriptionAttribute) {
        parts.append("description=\(description)")
    }
    if let value = stringAttribute(element, kAXValueAttribute) {
        parts.append("value=\(value)")
    }
    return parts.joined(separator: " ")
}

func dump(_ element: AXUIElement, depth: Int, visited: inout Set<CFHashCode>, output: inout [String]) {
    guard depth <= 30 else {
        return
    }
    let elementID = CFHash(element)
    guard !visited.contains(elementID) else {
        return
    }
    visited.insert(elementID)
    let elementLine = line(for: element)
    if !elementLine.isEmpty {
        output.append(elementLine)
    }
    for child in children(of: element) {
        dump(child, depth: depth + 1, visited: &visited, output: &output)
    }
}

func find(identifier: String, in element: AXUIElement, depth: Int = 0, visited: inout Set<CFHashCode>) -> AXUIElement? {
    guard depth <= 30 else {
        return nil
    }
    let elementID = CFHash(element)
    guard !visited.contains(elementID) else {
        return nil
    }
    visited.insert(elementID)
    if stringAttribute(element, "AXIdentifier") == identifier {
        return element
    }
    for child in children(of: element) {
        if let found = find(identifier: identifier, in: child, depth: depth + 1, visited: &visited) {
            return found
        }
    }
    return nil
}

func main() throws {
    let arguments = CommandLine.arguments
    guard arguments.count == 4 || arguments.count == 5 || arguments.count == 6 else {
        throw AXSmokeError.usage
    }
    let command = arguments[1]
    let timeout = TimeInterval(arguments[2]) ?? 20
    let targetPID = try pid(from: arguments[3])
    let app = AXUIElementCreateApplication(targetPID)

    switch command {
    case "window":
        let window = try visibleWindow(for: targetPID, timeout: timeout)
        let data = try JSONSerialization.data(withJSONObject: window, options: [.prettyPrinted, .sortedKeys])
        print(String(data: data, encoding: .utf8) ?? "{}")
    case "snapshot":
        let appWindows = try windows(for: app, pid: targetPID, timeout: timeout)
        var output: [String] = []
        var visited: Set<CFHashCode> = []
        for window in appWindows {
            dump(window, depth: 0, visited: &visited, output: &output)
        }
        print(output.joined(separator: "\n"))
    case "press":
        guard arguments.count == 5 else {
            throw AXSmokeError.usage
        }
        let appWindows = try windows(for: app, pid: targetPID, timeout: timeout)
        let identifier = arguments[4]
        var visited: Set<CFHashCode> = []
        for window in appWindows {
            if let element = find(identifier: identifier, in: window, visited: &visited) {
                let error = AXUIElementPerformAction(element, kAXPressAction as CFString)
                guard error == .success else {
                    throw AXSmokeError.actionFailed(identifier, error)
                }
                print("pressed \(identifier)")
                return
            }
        }
        throw AXSmokeError.missingIdentifier(identifier)
    case "confirm":
        guard arguments.count == 5 else {
            throw AXSmokeError.usage
        }
        let appWindows = try windows(for: app, pid: targetPID, timeout: timeout)
        let identifier = arguments[4]
        var visited: Set<CFHashCode> = []
        for window in appWindows {
            if let element = find(identifier: identifier, in: window, visited: &visited) {
                focus(element)
                let error = AXUIElementPerformAction(element, kAXConfirmAction as CFString)
                guard error == .success else {
                    throw AXSmokeError.actionFailed(identifier, error)
                }
                print("confirmed \(identifier)")
                return
            }
        }
        throw AXSmokeError.missingIdentifier(identifier)
    case "set-value":
        guard arguments.count == 6 else {
            throw AXSmokeError.usage
        }
        let appWindows = try windows(for: app, pid: targetPID, timeout: timeout)
        let identifier = arguments[4]
        let value = arguments[5]
        var visited: Set<CFHashCode> = []
        for window in appWindows {
            if let element = find(identifier: identifier, in: window, visited: &visited) {
                let error = setStringValue(value, on: element)
                guard error == .success else {
                    throw AXSmokeError.actionFailed(identifier, error)
                }
                print("set \(identifier)")
                return
            }
        }
        throw AXSmokeError.missingIdentifier(identifier)
    default:
        throw AXSmokeError.usage
    }
}

do {
    try main()
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
