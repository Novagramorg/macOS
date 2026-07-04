//
//  FenixuzAutoProxy.swift
//  Telegram-Mac
//
//  macOS port of the iOS AutoProxy feature (NovagramProxy).
//  iOS source: submodules/Fenixuz/AutoProxy/Sources/{FenixuzAutoProxyManager,
//  FenixuzProxyProbeSession, FenixuzSocks5Probe, FenixuzProxyPool}.swift
//
//  Opt-in "Enable NovagramProxy" toggle (default OFF). When ON, the app auto-finds a working
//  SOCKS5 proxy from the bundled pool and routes THIS user's Telegram connection through it — so a
//  user in any blocked country can reach Telegram without configuring a proxy by hand. The proxy
//  details are never surfaced by the toggle.
//
//  Everything is kept in this one file (four types + strings) to minimise pbxproj surgery — only
//  this file and the bundled russia_proxies.txt need project entries.
//
//  The whole logic writes only the shared proxy settings via the public
//  `updateProxySettingsInteractively` API; the running account observes that change and applies the
//  proxy automatically. No dependency on a live account/network, so it works before login too (the
//  login server itself may be blocked), and stays merge-stable.
//
//  Safety:
//    • A proxy the user configured themselves is never overridden or removed.
//    • A proxy we set earlier that has since died is re-checked and rotated to a live one.
//    • Turning the toggle OFF removes only our proxy, never the user's own.
//

import Foundation
import Network
import SwiftSignalKit
import Postbox
import TelegramCore

// MARK: - Manager

final class FenixuzAutoProxyManager {
    static let shared = FenixuzAutoProxyManager()

    // Drives the Settings list rebuild (combined into AccountViewController's signal), same idiom as
    // FenixuzAdsGate.uiState. Seeded from the persisted toggle so the switch renders the right state.
    let uiState: ValuePromise<Bool>

    private let coordinationQueue = DispatchQueue(label: "uz.fenixuz.app.AutoProxy.coordination")
    private let readDisposable = MetaDisposable()

    // Persisted opt-in toggle, default OFF. Kept in the shared "pro_messager" defaults suite so it
    // lives alongside the other NovagramPro settings (identical key to the iOS build).
    private let defaults = UserDefaults(suiteName: "pro_messager")
    private let enabledKey = "novagram_proxy_enabled"

    // In-memory source of truth, seeded once from the persisted default. Reads never hit a possibly
    // stale sandboxed cfprefsd (same reasoning as FenixuzAdsGate.memoShowAds).
    private var memoEnabled: Bool

    // Health-probe tuning. ~90% of the pool is alive at any moment, so one batch almost always
    // yields a live proxy; the extra batches are a safety margin.
    private let probeTimeout: TimeInterval = 6.0
    private let batchSize = 6
    private let maxCandidates = 18

    private init() {
        let initial = self.defaults?.object(forKey: self.enabledKey) as? Bool ?? false
        self.memoEnabled = initial
        self.uiState = ValuePromise(initial, ignoreRepeated: true)
    }

    deinit {
        self.readDisposable.dispose()
    }

    // MARK: - Public toggle state

    var isEnabled: Bool {
        return self.memoEnabled
    }

    private func persist(_ enabled: Bool) {
        self.memoEnabled = enabled
        self.defaults?.set(enabled, forKey: self.enabledKey)
        self.uiState.set(enabled)
    }

    // MARK: - Entry points

    // Called once from AppDelegate at launch. If the toggle is ON, make sure a healthy proxy is
    // active (rotating to a fresh one if the previously-chosen proxy has died).
    func start(accountManager: AccountManager<TelegramAccountManagerTypes>) {
        self.coordinationQueue.async { [weak self] in
            guard let self = self, self.isEnabled else {
                return
            }
            self.ensureActiveProxy(accountManager: accountManager)
        }
    }

    // Called from the NovagramPro settings toggle and the login-screen entry. Persists the choice
    // (updating the UI immediately) and applies it in the background.
    func setEnabled(_ enabled: Bool, accountManager: AccountManager<TelegramAccountManagerTypes>) {
        self.persist(enabled)
        self.coordinationQueue.async { [weak self] in
            guard let self = self else {
                return
            }
            if enabled {
                self.ensureActiveProxy(accountManager: accountManager)
            } else {
                self.disableOurProxy(accountManager: accountManager)
            }
        }
    }

    // MARK: - Enable path

    // Runs on coordinationQueue.
    private func ensureActiveProxy(accountManager: AccountManager<TelegramAccountManagerTypes>) {
        self.readDisposable.set((accountManager.sharedData(keys: [SharedDataKeys.proxySettings])
        |> take(1)).start(next: { [weak self] sharedData in
            let settings = sharedData.entries[SharedDataKeys.proxySettings]?.get(ProxySettings.self) ?? ProxySettings.defaultSettings
            self?.coordinationQueue.async {
                self?.handleForEnable(currentSettings: settings, accountManager: accountManager)
            }
        }))
    }

    // Runs on coordinationQueue.
    private func handleForEnable(currentSettings: ProxySettings, accountManager: AccountManager<TelegramAccountManagerTypes>) {
        let pool = FenixuzProxyPool.loadShuffled()
        if pool.isEmpty {
            return
        }
        let poolHosts = Set(pool.map { $0.host })

        if let active = currentSettings.effectiveActiveServer {
            guard case .socks5 = active.connection, poolHosts.contains(active.host) else {
                // The user has their own proxy active — respect it, do nothing.
                return
            }
            // One of ours: keep it if it still works, otherwise rotate to a fresh live one.
            let checkSession = FenixuzProxyProbeSession(candidates: [active], batchSize: 1, probeTimeout: self.probeTimeout, queue: self.coordinationQueue)
            checkSession.start { [weak self] aliveServer in
                guard let self = self, aliveServer == nil else {
                    return
                }
                self.selectAndEnable(pool: pool, excludingHost: active.host, accountManager: accountManager)
            }
        } else {
            self.selectAndEnable(pool: pool, excludingHost: nil, accountManager: accountManager)
        }
    }

    // Runs on coordinationQueue.
    private func selectAndEnable(pool: [ProxyServerSettings], excludingHost: String?, accountManager: AccountManager<TelegramAccountManagerTypes>) {
        var candidates = pool
        if let excludingHost = excludingHost {
            candidates = candidates.filter { $0.host != excludingHost }
        }
        candidates = Array(candidates.prefix(self.maxCandidates))
        if candidates.isEmpty {
            return
        }
        let session = FenixuzProxyProbeSession(candidates: candidates, batchSize: self.batchSize, probeTimeout: self.probeTimeout, queue: self.coordinationQueue)
        session.start { [weak self] server in
            guard let self = self, let server = server else {
                return
            }
            self.enable(server: server, accountManager: accountManager)
        }
    }

    // Runs on coordinationQueue. Writes the chosen proxy to shared data and enables it. Re-checks
    // the toggle in case the user turned it OFF while probing was still in flight.
    private func enable(server: ProxyServerSettings, accountManager: AccountManager<TelegramAccountManagerTypes>) {
        guard self.isEnabled else {
            return
        }
        _ = updateProxySettingsInteractively(accountManager: accountManager, { settings in
            var settings = settings
            if let index = settings.servers.firstIndex(of: server) {
                settings.servers[index] = server
            } else {
                settings.servers.insert(server, at: 0)
            }
            settings.activeServer = server
            settings.enabled = true
            return settings
        }).start()
    }

    // MARK: - Disable path

    // Runs on coordinationQueue. Turns the proxy off and clears our servers ONLY when the active
    // proxy is one of ours; never touches a proxy the user configured themselves.
    private func disableOurProxy(accountManager: AccountManager<TelegramAccountManagerTypes>) {
        self.readDisposable.set((accountManager.sharedData(keys: [SharedDataKeys.proxySettings])
        |> take(1)).start(next: { [weak self] sharedData in
            let settings = sharedData.entries[SharedDataKeys.proxySettings]?.get(ProxySettings.self) ?? ProxySettings.defaultSettings
            self?.coordinationQueue.async {
                let poolHosts = Set(FenixuzProxyPool.loadShuffled().map { $0.host })
                guard let active = settings.effectiveActiveServer, poolHosts.contains(active.host) else {
                    // No active proxy, or it is the user's own — leave everything alone.
                    return
                }
                _ = updateProxySettingsInteractively(accountManager: accountManager, { settings in
                    var settings = settings
                    settings.servers.removeAll(where: { poolHosts.contains($0.host) })
                    if let activeHost = settings.activeServer?.host, poolHosts.contains(activeHost) {
                        settings.activeServer = nil
                    }
                    settings.enabled = false
                    return settings
                }).start()
            }
        }))
    }
}

// MARK: - Probe session

// Probes a candidate list of SOCKS5 proxies in concurrent batches and calls `onResult` with the
// FIRST one that passes an end-to-end health check (FenixuzSocks5Probe), or nil when the whole
// list is exhausted. The first healthy proxy wins immediately — the rest of its batch is
// cancelled. The session retains itself until it completes, so callers don't have to hold it.
private final class FenixuzProxyProbeSession {
    private let candidates: [ProxyServerSettings]
    private let batchSize: Int
    private let probeTimeout: TimeInterval
    private let queue: DispatchQueue

    private var index = 0
    private var pending = 0
    private var finished = false
    private var activeProbes: [FenixuzSocks5Probe] = []
    private var onResult: ((ProxyServerSettings?) -> Void)?
    private var selfRef: FenixuzProxyProbeSession?

    init(candidates: [ProxyServerSettings], batchSize: Int, probeTimeout: TimeInterval, queue: DispatchQueue) {
        self.candidates = candidates
        self.batchSize = max(1, batchSize)
        self.probeTimeout = probeTimeout
        self.queue = queue
    }

    // `onResult` is delivered on `queue`.
    func start(onResult: @escaping (ProxyServerSettings?) -> Void) {
        self.queue.async { [weak self] in
            guard let self = self else {
                return
            }
            self.onResult = onResult
            self.selfRef = self
            self.runBatch()
        }
    }

    // Runs on queue.
    private func runBatch() {
        if self.finished {
            return
        }
        if self.index >= self.candidates.count {
            self.complete(nil)
            return
        }
        let end = min(self.index + self.batchSize, self.candidates.count)
        let batch = Array(self.candidates[self.index ..< end])
        self.index = end

        var startedProbes: [FenixuzSocks5Probe] = []
        for server in batch {
            if let probe = FenixuzSocks5Probe(server: server, timeout: self.probeTimeout) {
                startedProbes.append(probe)
            }
        }
        self.activeProbes = startedProbes
        self.pending = startedProbes.count

        if self.pending == 0 {
            // Nothing probeable in this batch (all malformed) — move to the next.
            self.runBatch()
            return
        }

        for probe in startedProbes {
            let server = probe.server
            probe.start { [weak self] success in
                self?.queue.async {
                    self?.handleProbeResult(server: server, success: success)
                }
            }
        }
    }

    // Runs on queue.
    private func handleProbeResult(server: ProxyServerSettings, success: Bool) {
        if self.finished {
            return
        }
        if success {
            self.complete(server)
            return
        }
        self.pending -= 1
        if self.pending <= 0 {
            self.runBatch()
        }
    }

    // Runs on queue.
    private func complete(_ result: ProxyServerSettings?) {
        if self.finished {
            return
        }
        self.finished = true
        // Dropping the probes cancels any still-running connections via their deinit.
        self.activeProbes.removeAll()
        let onResult = self.onResult
        self.onResult = nil
        onResult?(result)
        self.selfRef = nil
    }
}

// MARK: - SOCKS5 probe

// One end-to-end SOCKS5 health probe, built on Network.framework so it works pre-authorization
// without Telegram's own network stack. Success = TCP connect to the proxy + username/password
// SOCKS5 auth + CONNECT to a Telegram data-center, all within `timeout`. That predicts a working
// MTProto-over-SOCKS5 connection, because MTProto dials the very same DC host:port.
private final class FenixuzSocks5Probe {
    // Telegram DC2 (the default DC). If the proxy can open a tunnel here, it can carry Telegram
    // traffic.
    private static let telegramProbeHost: [UInt8] = [149, 154, 167, 51]
    private static let telegramProbePort: UInt16 = 443

    let server: ProxyServerSettings
    private let username: String
    private let password: String
    private let timeout: TimeInterval
    private let connection: NWConnection
    private let queue: DispatchQueue

    private var finished = false
    private var completion: ((Bool) -> Void)?

    init?(server: ProxyServerSettings, timeout: TimeInterval) {
        guard case let .socks5(username, password) = server.connection else {
            return nil
        }
        guard server.port > 0, server.port <= 65535, let port = NWEndpoint.Port(rawValue: UInt16(server.port)) else {
            return nil
        }
        self.server = server
        self.username = username ?? ""
        self.password = password ?? ""
        self.timeout = timeout
        self.connection = NWConnection(host: NWEndpoint.Host(server.host), port: port, using: .tcp)
        self.queue = DispatchQueue(label: "uz.fenixuz.app.AutoProxy.probe")
    }

    deinit {
        self.connection.cancel()
    }

    // `completion` is delivered on this probe's private serial queue.
    func start(completion: @escaping (Bool) -> Void) {
        self.completion = completion
        self.queue.asyncAfter(deadline: .now() + self.timeout) { [weak self] in
            self?.finish(false)
        }
        self.connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else {
                return
            }
            switch state {
            case .ready:
                self.sendGreeting()
            case .failed, .cancelled:
                self.finish(false)
            default:
                break
            }
        }
        self.connection.start(queue: self.queue)
    }

    // MARK: SOCKS5 handshake

    private func sendGreeting() {
        // VER = 5, NMETHODS = 1, METHOD = 0x02 (username/password).
        self.send([0x05, 0x01, 0x02]) { [weak self] ok in
            guard let self = self else {
                return
            }
            guard ok else {
                self.finish(false)
                return
            }
            self.receive(count: 2) { [weak self] data in
                guard let self = self else {
                    return
                }
                guard let data = data, data.count == 2, data[0] == 0x05, data[1] == 0x02 else {
                    self.finish(false)
                    return
                }
                self.sendAuth()
            }
        }
    }

    private func sendAuth() {
        let user = Array(self.username.utf8)
        let pass = Array(self.password.utf8)
        guard user.count <= 255, pass.count <= 255 else {
            self.finish(false)
            return
        }
        // VER = 1, ULEN, UNAME, PLEN, PASSWD.
        var payload: [UInt8] = [0x01, UInt8(user.count)]
        payload.append(contentsOf: user)
        payload.append(UInt8(pass.count))
        payload.append(contentsOf: pass)
        self.send(payload) { [weak self] ok in
            guard let self = self else {
                return
            }
            guard ok else {
                self.finish(false)
                return
            }
            self.receive(count: 2) { [weak self] data in
                guard let self = self else {
                    return
                }
                guard let data = data, data.count == 2, data[0] == 0x01, data[1] == 0x00 else {
                    self.finish(false)
                    return
                }
                self.sendConnect()
            }
        }
    }

    private func sendConnect() {
        // VER = 5, CMD = CONNECT (1), RSV = 0, ATYP = IPv4 (1), ADDR (4), PORT (2).
        var payload: [UInt8] = [0x05, 0x01, 0x00, 0x01]
        payload.append(contentsOf: FenixuzSocks5Probe.telegramProbeHost)
        payload.append(UInt8(FenixuzSocks5Probe.telegramProbePort >> 8))
        payload.append(UInt8(FenixuzSocks5Probe.telegramProbePort & 0xff))
        self.send(payload) { [weak self] ok in
            guard let self = self else {
                return
            }
            guard ok else {
                self.finish(false)
                return
            }
            // Reply: VER, REP, ... — REP == 0x00 means the tunnel to Telegram is open.
            self.receive(count: 2) { [weak self] data in
                guard let self = self else {
                    return
                }
                guard let data = data, data.count == 2, data[0] == 0x05, data[1] == 0x00 else {
                    self.finish(false)
                    return
                }
                self.finish(true)
            }
        }
    }

    // MARK: Low-level IO (all on self.queue)

    private func send(_ bytes: [UInt8], completion: @escaping (Bool) -> Void) {
        self.connection.send(content: Data(bytes), completion: .contentProcessed { error in
            completion(error == nil)
        })
    }

    private func receive(count: Int, completion: @escaping (Data?) -> Void) {
        self.connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
            if error != nil {
                completion(nil)
            } else if let data = data, data.count == count {
                completion(data)
            } else {
                completion(nil)
            }
        }
    }

    private func finish(_ success: Bool) {
        if self.finished {
            return
        }
        self.finished = true
        self.connection.cancel()
        let completion = self.completion
        self.completion = nil
        completion?(success)
    }
}

// MARK: - Proxy pool

// Loads the bundled Webshare proxy list (one `host:port:username:password` per line) and returns
// it as SOCKS5 proxy servers in randomized order, so each launch spreads load across the pool and
// starts from a different candidate. On macOS the list is a flat resource in the app bundle
// (Bundle.main), unlike the iOS build which nests it in a module resource bundle.
private enum FenixuzProxyPool {
    static func loadShuffled() -> [ProxyServerSettings] {
        guard let text = self.loadBundledText() else {
            return []
        }
        var servers: [ProxyServerSettings] = []
        for rawLine in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                continue
            }
            let components = line.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
            if components.count != 4 {
                continue
            }
            let host = components[0]
            guard !host.isEmpty, let port = Int32(components[1]), port > 0, port <= 65535 else {
                continue
            }
            let username = components[2]
            let password = components[3]
            servers.append(ProxyServerSettings(host: host, port: port, connection: .socks5(username: username, password: password)))
        }
        return servers.shuffled()
    }

    private static func loadBundledText() -> String? {
        guard let url = Bundle.main.url(forResource: "russia_proxies", withExtension: "txt"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Strings (en / uz / ru, kept local to the feature)

enum FenixuzAutoProxyStrings {
    static func toggleTitle(langCode: String) -> String {
        switch langCode {
        case "uz": return "NovagramProxy'ni yoqish"
        case "ru": return "Включить NovagramProxy"
        default:   return "Enable NovagramProxy"
        }
    }

    static func toggleTip(langCode: String) -> String {
        switch langCode {
        case "uz": return "Yoqilsa — Telegram bloklangan hududlarda ham avtomat tanlangan proxy orqali ulanadi"
        case "ru": return "Вкл — Telegram подключается через автоматически подобранный прокси даже там, где он заблокирован"
        default:   return "On — connects Telegram through an auto-selected proxy so it works even where blocked"
        }
    }

    static func loginButtonTitle(langCode: String) -> String {
        return "NovagramProxy"
    }

    static func enabledAlert(langCode: String) -> String {
        switch langCode {
        case "uz": return "NovagramProxy yoqildi. Endi Telegram bloklangan hududda ham avtomat proxy orqali ulanadi."
        case "ru": return "NovagramProxy включён. Теперь Telegram подключается через автоподобранный прокси даже там, где он заблокирован."
        default:   return "NovagramProxy enabled. Telegram now connects through an auto-selected proxy even where it's blocked."
        }
    }

    static func disabledAlert(langCode: String) -> String {
        switch langCode {
        case "uz": return "NovagramProxy o'chirildi."
        case "ru": return "NovagramProxy выключен."
        default:   return "NovagramProxy disabled."
        }
    }
}
