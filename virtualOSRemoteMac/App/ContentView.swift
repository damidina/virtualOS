import AppKit
import Combine
import Foundation
import SwiftUI

enum CaptureSource: String, CaseIterable, Identifiable {
    case window
    case screen

    var id: String { rawValue }
}

enum ConnectionMode: String, CaseIterable, Identifiable {
    case auto
    case direct
    case remote

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Auto"
        case .direct: return "Direct"
        case .remote: return "Remote"
        }
    }
}

struct DiscoveredEndpoint: Identifiable, Hashable {
    let id: String
    let name: String
    let host: String
    let port: Int
    let isLocal: Bool

    var label: String {
        "\(name)  \(host):\(port)"
    }
}

struct QuickAction: Identifiable {
    let id: String
    let title: String
    let key: String
    let modifiers: [String]
}

final class BonjourDiscovery: NSObject, ObservableObject, NetServiceBrowserDelegate, NetServiceDelegate {
    @Published private(set) var endpoints: [DiscoveredEndpoint] = []
    @Published private(set) var status: String = "Idle"

    private let browser = NetServiceBrowser()
    private var servicesByName: [String: NetService] = [:]
    private var endpointsByName: [String: DiscoveredEndpoint] = [:]
    private let localIPs: Set<String>

    override init() {
        self.localIPs = BonjourDiscovery.currentLocalIPs()
        super.init()
    }

    func start() {
        stop()
        status = "Searching LAN..."
        browser.delegate = self
        browser.searchForServices(ofType: "_virtualosremote._tcp.", inDomain: "local.")
    }

    func refresh() {
        start()
    }

    func stop() {
        browser.stop()
        for service in servicesByName.values {
            service.stop()
        }
        servicesByName.removeAll()
        endpointsByName.removeAll()
        publish()
    }

    func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
        status = "Searching LAN..."
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        status = "Discovery failed"
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        if endpoints.isEmpty {
            status = "No servers found"
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        servicesByName[service.name] = service
        service.delegate = self
        service.resolve(withTimeout: 3)
        if !moreComing {
            publish()
        }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        servicesByName[service.name] = nil
        endpointsByName[service.name] = nil
        if !moreComing {
            publish()
        }
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        let allHosts = BonjourDiscovery.ipAddresses(from: sender.addresses ?? [])
        guard let preferred = BonjourDiscovery.preferredHost(from: allHosts) else {
            return
        }
        let endpoint = DiscoveredEndpoint(
            id: "\(sender.name)|\(preferred)|\(sender.port)",
            name: sender.name,
            host: preferred,
            port: sender.port,
            isLocal: localIPs.contains(preferred) || preferred == "127.0.0.1" || preferred == "::1"
        )
        endpointsByName[sender.name] = endpoint
        publish()
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        endpointsByName[sender.name] = nil
        publish()
    }

    private func publish() {
        endpoints = endpointsByName.values.sorted {
            if $0.isLocal != $1.isLocal {
                return !$0.isLocal
            }
            if $0.name != $1.name {
                return $0.name < $1.name
            }
            return $0.host < $1.host
        }
        if endpoints.isEmpty {
            status = "No servers found"
        } else {
            status = "Found \(endpoints.count) server\(endpoints.count == 1 ? "" : "s")"
        }
    }

    private static func preferredHost(from hosts: [String]) -> String? {
        if let ipv4 = hosts.first(where: { $0.contains(".") && !$0.hasPrefix("169.254.") }) {
            return ipv4
        }
        if let nonLinkLocalV6 = hosts.first(where: { $0.contains(":") && !$0.lowercased().hasPrefix("fe80:") }) {
            return nonLinkLocalV6
        }
        return hosts.first
    }

    private static func ipAddresses(from addressData: [Data]) -> [String] {
        addressData.compactMap { ipAddress(from: $0) }
    }

    private static func ipAddress(from data: Data) -> String? {
        data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return nil }
            let sockaddrPointer = base.assumingMemoryBound(to: sockaddr.self)
            let family = Int32(sockaddrPointer.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { return nil }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                sockaddrPointer,
                socklen_t(data.count),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { return nil }
            return String(cString: host)
        }
    }

    private static func currentLocalIPs() -> Set<String> {
        var result: Set<String> = ["127.0.0.1", "::1"]
        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPointer) == 0, let firstAddr = ifaddrPointer else {
            return result
        }
        defer { freeifaddrs(ifaddrPointer) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let ifaddr = cursor?.pointee {
            guard let addrPointer = ifaddr.ifa_addr else {
                cursor = ifaddr.ifa_next
                continue
            }
            let family = Int32(addrPointer.pointee.sa_family)
            if family == AF_INET || family == AF_INET6 {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let length = socklen_t(
                    family == AF_INET
                        ? MemoryLayout<sockaddr_in>.size
                        : MemoryLayout<sockaddr_in6>.size
                )
                if getnameinfo(addrPointer, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    result.insert(String(cString: host))
                }
            }
            cursor = ifaddr.ifa_next
        }
        return result
    }
}

@MainActor
final class StreamViewModel: ObservableObject {
    private enum HostRuntimeError: LocalizedError {
        case missingServerScript
        case missingInputController
        case missingPython

        var errorDescription: String? {
            switch self {
            case .missingServerScript:
                return "Bundled host server is missing"
            case .missingInputController:
                return "Bundled input controller is missing"
            case .missingPython:
                return "Python 3 was not found on this Mac"
            }
        }
    }

    @Published var connectionMode: ConnectionMode
    @Published var host: String
    @Published var port: String
    @Published var remoteURL: String
    @Published var authToken: String
    @Published var cfAccessClientID: String
    @Published var cfAccessClientSecret: String
    @Published var targetApp: String
    @Published var captureSource: CaptureSource
    @Published var image: NSImage?
    @Published var status: String = "Idle"
    @Published var detail: String = ""
    @Published var isStreaming = false
    @Published var discoveredEndpoints: [DiscoveredEndpoint] = []
    @Published var discoveryStatus: String = "Idle"
    @Published var lastFrameURL: String = ""
    @Published var lastCaptureMode: String = ""
    @Published var lastHTTPStatus: Int = 0
    @Published var lastLatencyMs: Int = 0
    @Published var recentLogs: [String] = []
    @Published var hostServerStatus: String = "Host idle"
    @Published var hostServerRunning = false

    private let fileManager = FileManager.default
    private let discovery = BonjourDiscovery()
    private var cancellables: Set<AnyCancellable> = []
    private var timerTask: Task<Void, Never>?
    private var hostServerProcess: Process?
    private var hostServerPipe: Pipe?

    init() {
        self.connectionMode = ConnectionMode(rawValue: UserDefaults.standard.string(forKey: "macstream.connectionMode") ?? "auto") ?? .auto
        self.host = UserDefaults.standard.string(forKey: "macstream.host") ?? "127.0.0.1"
        self.port = UserDefaults.standard.string(forKey: "macstream.port") ?? "8899"
        self.remoteURL = UserDefaults.standard.string(forKey: "macstream.remoteURL") ?? ""
        self.authToken = UserDefaults.standard.string(forKey: "macstream.authToken") ?? ""
        self.cfAccessClientID = UserDefaults.standard.string(forKey: "macstream.cfAccessClientID") ?? ""
        self.cfAccessClientSecret = UserDefaults.standard.string(forKey: "macstream.cfAccessClientSecret") ?? ""
        self.targetApp = UserDefaults.standard.string(forKey: "macstream.targetApp") ?? "Codex"
        let savedSource = UserDefaults.standard.string(forKey: "macstream.captureSource") ?? CaptureSource.window.rawValue
        self.captureSource = CaptureSource(rawValue: savedSource) ?? .window

        discovery.$endpoints
            .receive(on: DispatchQueue.main)
            .sink { [weak self] endpoints in
                self?.discoveredEndpoints = endpoints
                self?.autoApplyBestEndpointIfNeeded()
            }
            .store(in: &cancellables)

        discovery.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newStatus in
                self?.discoveryStatus = newStatus
                self?.addLog("discovery status: \(newStatus)")
            }
            .store(in: &cancellables)

        discovery.start()
    }

    deinit {
        discovery.stop()
        hostServerPipe?.fileHandleForReading.readabilityHandler = nil
        hostServerProcess?.terminate()
    }

    func start() {
        guard !isStreaming else { return }
        autoApplyBestEndpointIfNeeded()
        isStreaming = true
        status = "Connecting..."
        detail = ""
        addLog("stream start mode=\(connectionMode.rawValue)")
        persist()

        timerTask = Task { [weak self] in
            guard let self else { return }
            await self.ensureLocalHostReadyIfNeeded()
            while !Task.isCancelled {
                await self.fetchFrame()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stop() {
        isStreaming = false
        timerTask?.cancel()
        timerTask = nil
        status = "Stopped"
        detail = ""
        addLog("stream stopped")
    }

    func refreshDiscovery() {
        discovery.refresh()
        addLog("discovery refresh requested")
    }

    func useEndpoint(_ endpoint: DiscoveredEndpoint) {
        connectionMode = .direct
        host = endpoint.host
        port = String(endpoint.port)
        detail = "Using \(endpoint.label)"
        addLog("selected server \(endpoint.label)")
        persist()
    }

    func testConnection() async {
        guard let url = makeURL(path: "/health") else {
            status = "Bad URL"
            detail = "Invalid connection settings"
            return
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 3
        applyAuthHeaders(to: &request)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                status = "Health failed"
                detail = "No HTTP response"
                addLog("health failed no-http")
                return
            }
            lastHTTPStatus = http.statusCode
            if http.statusCode == 200 {
                status = "Health OK"
                detail = "Server reachable"
                addLog("health ok \(url.absoluteString)")
            } else {
                status = "Health failed"
                detail = "HTTP \(http.statusCode)"
                addLog("health failed status=\(http.statusCode) url=\(url.absoluteString)")
            }
        } catch {
            status = "Health failed"
            detail = error.localizedDescription
            addLog("health error \(error.localizedDescription)")
        }
    }

    func focusTargetApp() async {
        let app = targetApp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !app.isEmpty else {
            detail = "Target app is empty"
            return
        }
        guard let url = makeURL(path: "/control/focus") else { return }

        let payload: [String: Any] = ["app": app]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 3
        applyAuthHeaders(to: &request)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                detail = "Focused \(app)"
                addLog("focus ok app=\(app)")
            } else if let http = response as? HTTPURLResponse {
                addLog("focus failed status=\(http.statusCode) app=\(app)")
            }
        } catch {
            detail = "Focus failed: \(error.localizedDescription)"
            addLog("focus error \(error.localizedDescription)")
        }
    }

    func sendAction(_ action: QuickAction) async {
        await sendShortcut(key: action.key, modifiers: action.modifiers)
    }

    func sendShortcut(key: String, modifiers: [String] = []) async {
        guard let url = makeURL(path: "/control/shortcut") else {
            status = "Bad URL"
            detail = "Invalid connection settings"
            return
        }

        let payload: [String: Any] = [
            "key": key,
            "modifiers": modifiers,
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            status = "Control error"
            detail = "Could not encode shortcut payload"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 3
        applyAuthHeaders(to: &request)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                status = "Control error"
                detail = "No HTTP response"
                addLog("shortcut failed no-http key=\(key)")
                return
            }
            lastHTTPStatus = http.statusCode
            guard (200..<300).contains(http.statusCode) else {
                status = "Shortcut failed"
                detail = "HTTP \(http.statusCode)"
                addLog("shortcut failed status=\(http.statusCode) key=\(key)")
                return
            }
            if
                let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let ok = obj["ok"] as? Bool,
                ok == true
            {
                status = "Live"
                detail = modifiers.isEmpty ? "Shortcut: \(key)" : "Shortcut: \(modifiers.joined(separator: "+"))+\(key)"
                addLog("shortcut ok \(detail)")
            } else {
                status = "Shortcut failed"
                detail = "Bad shortcut response"
                addLog("shortcut bad-response key=\(key)")
            }
        } catch {
            status = "Control error"
            detail = error.localizedDescription
            addLog("shortcut error \(error.localizedDescription)")
        }
    }

    func clickNormalized(nx: CGFloat, ny: CGFloat) async {
        guard let url = makeURL(path: "/control/click") else {
            status = "Bad URL"
            detail = "Invalid connection settings"
            return
        }

        let payload: [String: Any] = [
            "nx": Double(nx),
            "ny": Double(ny),
            "source": captureSource == .screen ? "screen" : "window",
            "app": targetApp,
        ]
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            status = "Control error"
            detail = "Could not encode click payload"
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 3
        applyAuthHeaders(to: &request)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                status = "Control error"
                detail = "No HTTP response"
                addLog("click failed no-http")
                return
            }
            lastHTTPStatus = http.statusCode
            guard (200..<300).contains(http.statusCode) else {
                status = "Control failed"
                detail = "HTTP \(http.statusCode)"
                addLog("click failed status=\(http.statusCode)")
                return
            }
            if
                let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let ok = obj["ok"] as? Bool,
                ok == true
            {
                status = "Live"
                detail = "Clicked (\(Int(nx * 100))%, \(Int(ny * 100))%)"
                addLog("click ok nx=\(String(format: "%.2f", nx)) ny=\(String(format: "%.2f", ny))")
            } else {
                status = "Control failed"
                detail = "Bad control response"
                addLog("click bad-response")
            }
        } catch {
            status = "Control error"
            detail = error.localizedDescription
            addLog("click error \(error.localizedDescription)")
        }
    }

    func quickActions() -> [QuickAction] {
        let app = targetApp.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if app.contains("codex") || app.contains("chatgpt") {
            return [
                QuickAction(id: "enter", title: "Enter", key: "enter", modifiers: []),
                QuickAction(id: "esc", title: "Esc", key: "escape", modifiers: []),
                QuickAction(id: "copy", title: "Cmd+C", key: "c", modifiers: ["command"]),
                QuickAction(id: "paste", title: "Cmd+V", key: "v", modifiers: ["command"]),
                QuickAction(id: "tab", title: "Cmd+Tab", key: "tab", modifiers: ["command"]),
                QuickAction(id: "new", title: "Cmd+N", key: "n", modifiers: ["command"]),
                QuickAction(id: "find", title: "Cmd+F", key: "f", modifiers: ["command"]),
            ]
        }

        if app.contains("finder") {
            return [
                QuickAction(id: "newwin", title: "New Window", key: "n", modifiers: ["command"]),
                QuickAction(id: "newfolder", title: "New Folder", key: "n", modifiers: ["command", "shift"]),
                QuickAction(id: "close", title: "Close", key: "w", modifiers: ["command"]),
                QuickAction(id: "copy", title: "Copy", key: "c", modifiers: ["command"]),
                QuickAction(id: "paste", title: "Paste", key: "v", modifiers: ["command"]),
            ]
        }

        if app.contains("chrome") || app.contains("safari") {
            return [
                QuickAction(id: "newtab", title: "New Tab", key: "t", modifiers: ["command"]),
                QuickAction(id: "close", title: "Close Tab", key: "w", modifiers: ["command"]),
                QuickAction(id: "address", title: "Address Bar", key: "l", modifiers: ["command"]),
                QuickAction(id: "reload", title: "Reload", key: "r", modifiers: ["command"]),
                QuickAction(id: "find", title: "Find", key: "f", modifiers: ["command"]),
            ]
        }

        if app.contains("terminal") {
            return [
                QuickAction(id: "enter", title: "Enter", key: "enter", modifiers: []),
                QuickAction(id: "copy", title: "Cmd+C", key: "c", modifiers: ["command"]),
                QuickAction(id: "paste", title: "Cmd+V", key: "v", modifiers: ["command"]),
                QuickAction(id: "newtab", title: "Cmd+T", key: "t", modifiers: ["command"]),
                QuickAction(id: "clear", title: "Cmd+K", key: "k", modifiers: ["command"]),
            ]
        }

        return [
            QuickAction(id: "enter", title: "Enter", key: "enter", modifiers: []),
            QuickAction(id: "esc", title: "Esc", key: "escape", modifiers: []),
            QuickAction(id: "copy", title: "Cmd+C", key: "c", modifiers: ["command"]),
            QuickAction(id: "paste", title: "Cmd+V", key: "v", modifiers: ["command"]),
            QuickAction(id: "tab", title: "Cmd+Tab", key: "tab", modifiers: ["command"]),
        ]
    }

    func startLocalHostServer() {
        if hostServerRunning {
            hostServerStatus = "Host already running"
            return
        }

        guard let portInt = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)), portInt > 0 else {
            hostServerStatus = "Invalid host port"
            return
        }

        let scriptURL: URL
        do {
            scriptURL = try prepareBundledHostRuntime()
        } catch {
            hostServerStatus = "Host runtime missing"
            addLog("host runtime prepare failed \(error.localizedDescription)")
            detail = error.localizedDescription
            return
        }

        guard let pythonURL = pythonExecutableURL() else {
            hostServerStatus = "Python 3 not found"
            addLog("host python not found")
            detail = HostRuntimeError.missingPython.localizedDescription
            return
        }

        let proc = Process()
        proc.executableURL = pythonURL
        proc.arguments = [scriptURL.path, "--host", "0.0.0.0", "--port", String(portInt)]
        proc.currentDirectoryURL = scriptURL.deletingLastPathComponent()
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        proc.environment = environment

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            guard let chunk = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                self?.ingestHostServerOutput(chunk)
            }
        }

        proc.terminationHandler = { [weak self] process in
            Task { @MainActor [weak self] in
                self?.hostServerRunning = false
                self?.hostServerStatus = "Host stopped (exit \(process.terminationStatus))"
                self?.addLog("host stopped exit=\(process.terminationStatus)")
                self?.hostServerProcess = nil
                self?.hostServerPipe?.fileHandleForReading.readabilityHandler = nil
                self?.hostServerPipe = nil
            }
        }

        do {
            try proc.run()
            hostServerProcess = proc
            hostServerPipe = pipe
            hostServerRunning = true
            hostServerStatus = "Host starting on :\(portInt)"
            addLog("host starting script=\(scriptURL.path)")
            refreshDiscovery()
        } catch {
            hostServerRunning = false
            hostServerStatus = "Host start failed"
            addLog("host start failed \(error.localizedDescription)")
        }
    }

    func stopLocalHostServer() {
        guard let proc = hostServerProcess else {
            hostServerRunning = false
            hostServerStatus = "Host idle"
            return
        }
        proc.terminate()
        hostServerStatus = "Stopping host..."
        addLog("host stopping requested")
    }

    func hostCommandHint() -> String {
        "App-managed host runtime on port \(port)"
    }

    private func ingestHostServerOutput(_ chunk: String) {
        let lines = chunk
            .split(whereSeparator: \.isNewline)
            .map { String($0) }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !lines.isEmpty else { return }
        for line in lines {
            addLog("host> \(line)")
            if line.contains("Serving on http://") {
                hostServerStatus = "Host running"
                hostServerRunning = true
            }
            if line.contains("Address already in use") {
                hostServerStatus = "Host failed: port in use"
                hostServerRunning = false
            }
        }
    }

    private func autoApplyBestEndpointIfNeeded() {
        guard connectionMode == .auto else { return }
        guard let best = discoveredEndpoints.first(where: { !$0.isLocal }) ?? discoveredEndpoints.first else { return }

        let desiredHost = best.host
        let desiredPort = String(best.port)
        if host != desiredHost || port != desiredPort {
            host = desiredHost
            port = desiredPort
            detail = "Auto connected: \(best.label)"
            addLog("auto-selected server \(best.label)")
            persist()
        }
    }

    func pullSingleFrame() async {
        await fetchFrame()
    }

    func saveSettings() {
        persist()
    }

    func copyDiagnosticsToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(diagnosticsReport(), forType: .string)
        addLog("diagnostics copied to clipboard")
    }

    func diagnosticsReport() -> String {
        var lines: [String] = []
        lines.append("mode=\(connectionMode.rawValue)")
        lines.append("targetApp=\(targetApp)")
        lines.append("source=\(captureSource.rawValue)")
        lines.append("resolved=\(resolvedEndpointDescription())")
        lines.append("lastFrameURL=\(lastFrameURL)")
        lines.append("lastHTTPStatus=\(lastHTTPStatus)")
        lines.append("lastCaptureMode=\(lastCaptureMode)")
        lines.append("lastLatencyMs=\(lastLatencyMs)")
        lines.append("discoveryStatus=\(discoveryStatus)")
        lines.append("discovered=\(discoveredEndpoints.map { $0.label }.joined(separator: " | "))")
        lines.append("authTokenConfigured=\(!authToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)")
        lines.append("cfAccessConfigured=\(!cfAccessClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !cfAccessClientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)")
        lines.append("hostServerRunning=\(hostServerRunning)")
        lines.append("hostServerStatus=\(hostServerStatus)")
        lines.append("hostCommand=\(hostCommandHint())")
        lines.append("logs=")
        for line in recentLogs {
            lines.append("  \(line)")
        }
        return lines.joined(separator: "\n")
    }

    private func fetchFrame() async {
        autoApplyBestEndpointIfNeeded()
        let trimmedApp = targetApp.trimmingCharacters(in: .whitespacesAndNewlines)
        var queryItems = [
            URLQueryItem(name: "ts", value: String(Date().timeIntervalSince1970)),
            URLQueryItem(name: "source", value: captureSource.rawValue),
            URLQueryItem(name: "max", value: "1800"),
        ]
        if !trimmedApp.isEmpty {
            queryItems.append(URLQueryItem(name: "app", value: trimmedApp))
        }

        guard let url = makeURL(path: "/frame.jpg", queryItems: queryItems) else {
            status = "Bad URL"
            detail = "Invalid connection settings"
            addLog("frame bad-url")
            return
        }
        lastFrameURL = url.absoluteString

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 3
        applyAuthHeaders(to: &request)

        let started = CFAbsoluteTimeGetCurrent()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            lastLatencyMs = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
            guard let http = response as? HTTPURLResponse else {
                status = "HTTP error"
                detail = "No HTTP response"
                addLog("frame failed no-http url=\(url.absoluteString)")
                return
            }
            lastHTTPStatus = http.statusCode
            lastCaptureMode = http.value(forHTTPHeaderField: "X-Capture-Mode") ?? ""
            guard http.statusCode == 200 else {
                status = "HTTP error"
                detail = "HTTP \(http.statusCode)"
                addLog("frame failed status=\(http.statusCode) url=\(url.absoluteString)")
                return
            }
            guard let img = NSImage(data: data) else {
                status = "Decode failed"
                detail = "Could not decode image"
                addLog("frame decode failed bytes=\(data.count)")
                return
            }
            image = img
            status = "Live"
            detail = ""
            addLog("frame ok status=\(http.statusCode) mode=\(lastCaptureMode) latency=\(lastLatencyMs)ms")
        } catch {
            status = "Network error"
            detail = error.localizedDescription
            lastLatencyMs = Int((CFAbsoluteTimeGetCurrent() - started) * 1000)
            addLog("frame network error \(error.localizedDescription)")
        }
    }

    private func resolvedEndpointDescription() -> String {
        switch connectionMode {
        case .auto, .direct:
            return "\(host):\(port)"
        case .remote:
            return remoteURL
        }
    }

    private func applyAuthHeaders(to request: inout URLRequest) {
        let trimmedToken = authToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedToken.isEmpty {
            request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
        }

        let cfID = cfAccessClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cfSecret = cfAccessClientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cfID.isEmpty && !cfSecret.isEmpty {
            request.setValue(cfID, forHTTPHeaderField: "CF-Access-Client-Id")
            request.setValue(cfSecret, forHTTPHeaderField: "CF-Access-Client-Secret")
        }
    }

    func resolvedEndpointLabel() -> String {
        resolvedEndpointDescription()
    }

    private func addLog(_ text: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let line = "\(formatter.string(from: Date()))  \(text)"
        recentLogs.insert(line, at: 0)
        if recentLogs.count > 80 {
            recentLogs = Array(recentLogs.prefix(80))
        }
    }

    private func ensureLocalHostReadyIfNeeded() async {
        guard shouldAutoStartLocalHost() else { return }

        if await resolvedHealthReachable() {
            if hostServerProcess == nil {
                hostServerStatus = "Host reachable"
            }
            return
        }

        startLocalHostServer()

        for _ in 0..<12 {
            if Task.isCancelled {
                return
            }
            if await resolvedHealthReachable() {
                if hostServerProcess != nil {
                    hostServerStatus = "Host running"
                    hostServerRunning = true
                }
                addLog("host ready after auto-start")
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
        }

        addLog("host did not become reachable after auto-start")
    }

    private func shouldAutoStartLocalHost() -> Bool {
        switch connectionMode {
        case .remote:
            return false
        case .direct:
            return isLoopbackHost(host)
        case .auto:
            return discoveredEndpoints.first(where: { !$0.isLocal }) == nil
        }
    }

    private func isLoopbackHost(_ rawHost: String) -> Bool {
        let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return host.isEmpty || host == "127.0.0.1" || host == "localhost" || host == "::1"
    }

    private func resolvedHealthReachable() async -> Bool {
        guard let url = makeURL(path: "/health") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1
        request.cachePolicy = .reloadIgnoringLocalCacheData
        applyAuthHeaders(to: &request)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return http.statusCode == 200
        } catch {
            return false
        }
    }

    private func pythonExecutableURL() -> URL? {
        let directCandidates = [
            "/usr/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
        ]

        for path in directCandidates where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        for entry in pathEntries {
            let candidate = URL(fileURLWithPath: entry).appendingPathComponent("python3")
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }

    private func hostRuntimeDirectory() throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let runtimeDirectory = appSupport
            .appendingPathComponent("virtualOSRemoteMac", isDirectory: true)
            .appendingPathComponent("HostRuntime", isDirectory: true)
        try fileManager.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true, attributes: nil)
        return runtimeDirectory
    }

    private func bundledHostResourceURL(named fileName: String) -> URL? {
        var urls: [URL] = []
        let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        urls.append(cwd.appendingPathComponent("tools/virtualos_stream_server").appendingPathComponent(fileName))
        urls.append(
            URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Documents/GitHub/virtualOS/tools/virtualos_stream_server")
                .appendingPathComponent(fileName)
        )
        if let bundle = Bundle.main.resourceURL {
            urls.append(bundle.appendingPathComponent(fileName))
            urls.append(bundle.appendingPathComponent("HostRuntime").appendingPathComponent(fileName))
            urls.append(bundle.appendingPathComponent("tools/virtualos_stream_server").appendingPathComponent(fileName))
        }

        var seen: Set<String> = []
        for url in urls {
            guard seen.insert(url.path).inserted else { continue }
            if fileManager.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private func syncHostRuntimeFile(named fileName: String, into runtimeDirectory: URL) throws -> URL {
        guard let sourceURL = bundledHostResourceURL(named: fileName) else {
            if fileName == "server.py" {
                throw HostRuntimeError.missingServerScript
            }
            throw HostRuntimeError.missingInputController
        }

        let destinationURL = runtimeDirectory.appendingPathComponent(fileName)
        let sourceData = try Data(contentsOf: sourceURL)
        let currentData = try? Data(contentsOf: destinationURL)
        if currentData != sourceData {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try sourceData.write(to: destinationURL, options: .atomic)
        }

        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationURL.path)
        return destinationURL
    }

    private func prepareBundledHostRuntime() throws -> URL {
        let runtimeDirectory = try hostRuntimeDirectory()
        let scriptURL = try syncHostRuntimeFile(named: "server.py", into: runtimeDirectory)
        _ = try syncHostRuntimeFile(named: "inputctl", into: runtimeDirectory)
        return scriptURL
    }

    private func makeURL(path: String, queryItems: [URLQueryItem] = []) -> URL? {
        switch connectionMode {
        case .auto, .direct:
            let cleanHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanPort = port.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanHost.isEmpty, let portInt = Int(cleanPort) else {
                return nil
            }
            var components = URLComponents()
            components.scheme = "http"
            components.host = cleanHost
            components.port = portInt
            components.path = path
            components.queryItems = queryItems.isEmpty ? nil : queryItems
            return components.url

        case .remote:
            var raw = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !raw.isEmpty else { return nil }
            if !raw.contains("://") {
                raw = "https://\(raw)"
            }
            guard var components = URLComponents(string: raw) else {
                return nil
            }
            let suffix = path.hasPrefix("/") ? path : "/\(path)"
            if components.path.isEmpty || components.path == "/" {
                components.path = suffix
            } else if components.path.hasSuffix("/") {
                components.path = String(components.path.dropLast()) + suffix
            } else {
                components.path = components.path + suffix
            }
            components.queryItems = queryItems.isEmpty ? nil : queryItems
            return components.url
        }
    }

    private func persist() {
        UserDefaults.standard.set(connectionMode.rawValue, forKey: "macstream.connectionMode")
        UserDefaults.standard.set(host, forKey: "macstream.host")
        UserDefaults.standard.set(port, forKey: "macstream.port")
        UserDefaults.standard.set(remoteURL, forKey: "macstream.remoteURL")
        UserDefaults.standard.set(authToken, forKey: "macstream.authToken")
        UserDefaults.standard.set(cfAccessClientID, forKey: "macstream.cfAccessClientID")
        UserDefaults.standard.set(cfAccessClientSecret, forKey: "macstream.cfAccessClientSecret")
        UserDefaults.standard.set(targetApp, forKey: "macstream.targetApp")
        UserDefaults.standard.set(captureSource.rawValue, forKey: "macstream.captureSource")
    }
}

struct ContentView: View {
    @StateObject private var vm = StreamViewModel()
    @State private var didAutoStart = false
    @State private var showDebug = true

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Picker("Connection", selection: $vm.connectionMode) {
                    ForEach(ConnectionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)

                if vm.connectionMode == .remote {
                    TextField("Remote URL (https://...)", text: $vm.remoteURL)
                        .textFieldStyle(.roundedBorder)
                } else {
                    TextField("Host", text: $vm.host)
                        .textFieldStyle(.roundedBorder)
                    TextField("Port", text: $vm.port)
                        .frame(width: 90)
                        .textFieldStyle(.roundedBorder)
                }

                TextField("Target app", text: $vm.targetApp)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 170)

                Button("Focus") {
                    Task { await vm.focusTargetApp() }
                }
            }

            HStack(spacing: 10) {
                SecureField("Auth token (Bearer)", text: $vm.authToken)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 220)
                TextField("CF Access Client ID", text: $vm.cfAccessClientID)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 220)
                SecureField("CF Access Client Secret", text: $vm.cfAccessClientSecret)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 220)
                Spacer()
            }

            HStack(spacing: 10) {
                Menu("Servers") {
                    if vm.discoveredEndpoints.isEmpty {
                        Text("No discovered servers")
                    } else {
                        ForEach(vm.discoveredEndpoints) { endpoint in
                            Button(endpoint.label) {
                                vm.useEndpoint(endpoint)
                            }
                        }
                    }
                }
                .menuStyle(.borderlessButton)

                Button("Refresh Servers") {
                    vm.refreshDiscovery()
                }
                .buttonStyle(.bordered)

                Button("Start Host") {
                    vm.startLocalHostServer()
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(vm.hostServerRunning)

                Button("Stop Host") {
                    vm.stopLocalHostServer()
                }
                .buttonStyle(.bordered)
                .disabled(!vm.hostServerRunning)

                Text(vm.discoveryStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(vm.hostServerStatus)
                    .font(.caption)
                    .foregroundStyle(vm.hostServerRunning ? .green : .secondary)

                Spacer()

                Picker("Source", selection: $vm.captureSource) {
                    Text("Window").tag(CaptureSource.window)
                    Text("Screen").tag(CaptureSource.screen)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)

                Button(vm.isStreaming ? "Stop" : "Start") {
                    if vm.isStreaming {
                        vm.stop()
                    } else {
                        vm.start()
                    }
                }
                .buttonStyle(.borderedProminent)

                Button("Test") {
                    Task { await vm.testConnection() }
                }
                .buttonStyle(.bordered)

                Button("Single") {
                    Task { await vm.pullSingleFrame() }
                }
                .buttonStyle(.bordered)

                Button("Copy Debug") {
                    vm.copyDiagnosticsToClipboard()
                }
                .buttonStyle(.bordered)

                Text(vm.status)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.quickActions()) { action in
                        Button(action.title) {
                            Task { await vm.sendAction(action) }
                        }
                    }
                }
                .buttonStyle(.bordered)
            }

            if !vm.detail.isEmpty {
                Text(vm.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            DisclosureGroup("Debug", isExpanded: $showDebug) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Resolved: \(vm.resolvedEndpointLabel())")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Host Command: \(vm.hostCommandHint())")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("Frame URL: \(vm.lastFrameURL)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    let captureLabel = vm.lastCaptureMode.isEmpty ? "-" : vm.lastCaptureMode
                    HStack(spacing: 14) {
                        Text("HTTP: \(vm.lastHTTPStatus)")
                        Text("Capture: \(captureLabel)")
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text("Latency: \(vm.lastLatencyMs)ms")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(vm.recentLogs.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.caption2.monospaced())
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                }
                .padding(8)
                .background(Color.black.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .font(.caption)

            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.9))

                if let image = vm.image {
                    GeometryReader { proxy in
                        let container = proxy.size
                        let imageSize = image.size
                        let scale = min(
                            container.width / max(imageSize.width, 1),
                            container.height / max(imageSize.height, 1)
                        )
                        let drawnWidth = imageSize.width * scale
                        let drawnHeight = imageSize.height * scale
                        let drawnMinX = (container.width - drawnWidth) / 2
                        let drawnMinY = (container.height - drawnHeight) / 2

                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .frame(width: container.width, height: container.height)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onEnded { gesture in
                                        guard vm.isStreaming else { return }
                                        let p = gesture.location
                                        guard p.x >= drawnMinX, p.x <= drawnMinX + drawnWidth else { return }
                                        guard p.y >= drawnMinY, p.y <= drawnMinY + drawnHeight else { return }
                                        let nx = (p.x - drawnMinX) / max(drawnWidth, 1)
                                        let ny = (p.y - drawnMinY) / max(drawnHeight, 1)
                                        Task { await vm.clickNormalized(nx: nx, ny: ny) }
                                    }
                            )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Text("No frame yet")
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .padding(12)
        .frame(minWidth: 980, minHeight: 660)
        .task {
            guard !didAutoStart else { return }
            didAutoStart = true
            vm.start()
        }
        .onChange(of: vm.connectionMode) { _, _ in
            vm.refreshDiscovery()
            vm.saveSettings()
        }
        .onChange(of: vm.host) { _, _ in
            vm.saveSettings()
        }
        .onChange(of: vm.port) { _, _ in
            vm.saveSettings()
        }
        .onChange(of: vm.remoteURL) { _, _ in
            vm.saveSettings()
        }
        .onChange(of: vm.authToken) { _, _ in
            vm.saveSettings()
        }
        .onChange(of: vm.cfAccessClientID) { _, _ in
            vm.saveSettings()
        }
        .onChange(of: vm.cfAccessClientSecret) { _, _ in
            vm.saveSettings()
        }
        .onChange(of: vm.captureSource) { _, _ in
            vm.saveSettings()
        }
        .onChange(of: vm.targetApp) { _, _ in
            vm.saveSettings()
        }
    }
}
