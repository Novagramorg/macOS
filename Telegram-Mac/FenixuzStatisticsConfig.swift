import Foundation

// Fenixuz Analytics — Novagram Statistics API (REST) configuration.
//
// Port of submodules/Fenixuz/Analytics/Sources/FenixuzAnalyticsConfig.swift (iOS).
// Backend: https://statistics.novagram.org (FastAPI). Dedup happens SERVER-SIDE by
// `device_id`, so the client just fires simple idempotent calls and never owns a counter.
// Foundation-only on purpose (no Telegram / SwiftSignalKit deps).
enum FenixuzAnalyticsConfig {
    // Base URL, NO trailing slash.
    static let baseURL: String = "https://statistics.novagram.org"

    // x-api-key header value. The server enforces this on /install, /account/* and /stats —
    // a request without it gets HTTP 401. Not a high-value secret (at most it lets someone
    // inflate public counters), so it lives here the same way the demo-login endpoint does.
    static let apiKey: String = "fbebe2c70b4ac933afce001192f3cdf6f88624d65317ddc3c63bf067577e8c3a"

    // Endpoint paths (relative to baseURL).
    static let installPath: String = "/v1/install"               // downloads +1 (per device)
    static let accountCreatePath: String = "/v1/account/create"  // active +1
    static let accountDeletePath: String = "/v1/account/delete"  // active -1
    static let statsPath: String = "/v1/stats"                   // { downloads, active }

    static var isConfigured: Bool {
        return !baseURL.isEmpty && !apiKey.isEmpty
    }
}
