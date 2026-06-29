import Foundation

// Minimal REST client for the Novagram Statistics API. Pure Foundation (URLSession) — no
// Telegram / SwiftSignalKit dependencies. Direct port of the iOS client.
//
// The server dedups by `device_id`, so install / accountCreate / accountDelete are all
// idempotent: calling one twice with the same id won't double-count. The response's
// `*_changed` flags say whether the call actually moved a counter.
final class FenixuzStatisticsClient {
    static let shared = FenixuzStatisticsClient()

    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15.0
        configuration.allowsCellularAccess = true
        self.session = URLSession(configuration: configuration)
    }

    // Response of the three mutation endpoints (/install, /account/create, /account/delete).
    struct MutationResponse: Decodable {
        let downloads: Int
        let active: Int
        let downloadsChanged: Bool
        let activeChanged: Bool

        enum CodingKeys: String, CodingKey {
            case downloads
            case active
            case downloadsChanged = "downloads_changed"
            case activeChanged = "active_changed"
        }
    }

    // Response of GET /v1/stats.
    private struct StatisticsResponse: Decodable {
        let downloads: Int
        let active: Int
    }

    private func authorizedRequest(path: String, method: String) -> URLRequest? {
        guard FenixuzAnalyticsConfig.isConfigured, let url = URL(string: FenixuzAnalyticsConfig.baseURL + path) else {
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(FenixuzAnalyticsConfig.apiKey, forHTTPHeaderField: "x-api-key")
        return request
    }

    private static func decoded<T: Decodable>(_ type: T.Type, data: Data?, response: URLResponse?, error: Error?) -> T? {
        guard error == nil,
              let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode),
              let data = data,
              let value = try? JSONDecoder().decode(T.self, from: data) else {
            return nil
        }
        return value
    }

    // POST { "device_id": ... } to a mutation endpoint. completion gets the parsed response,
    // or nil on any network / decoding / non-2xx failure.
    private func postDevice(path: String, deviceId: String, completion: @escaping (MutationResponse?) -> Void) {
        guard var request = self.authorizedRequest(path: path, method: "POST") else {
            completion(nil)
            return
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let body = try? JSONSerialization.data(withJSONObject: ["device_id": deviceId], options: []) else {
            completion(nil)
            return
        }
        request.httpBody = body
        let task = self.session.dataTask(with: request) { data, response, error in
            completion(FenixuzStatisticsClient.decoded(MutationResponse.self, data: data, response: response, error: error))
        }
        task.resume()
    }

    func registerInstall(deviceId: String, completion: @escaping (MutationResponse?) -> Void) {
        self.postDevice(path: FenixuzAnalyticsConfig.installPath, deviceId: deviceId, completion: completion)
    }

    func registerAccountCreate(deviceId: String, completion: @escaping (MutationResponse?) -> Void) {
        self.postDevice(path: FenixuzAnalyticsConfig.accountCreatePath, deviceId: deviceId, completion: completion)
    }

    func registerAccountDelete(deviceId: String, completion: @escaping (MutationResponse?) -> Void) {
        self.postDevice(path: FenixuzAnalyticsConfig.accountDeletePath, deviceId: deviceId, completion: completion)
    }

    // GET /v1/stats. completion gets (downloads, active), or nil on failure.
    func fetchStats(completion: @escaping ((downloads: Int, active: Int)?) -> Void) {
        guard let request = self.authorizedRequest(path: FenixuzAnalyticsConfig.statsPath, method: "GET") else {
            completion(nil)
            return
        }
        let task = self.session.dataTask(with: request) { data, response, error in
            if let value = FenixuzStatisticsClient.decoded(StatisticsResponse.self, data: data, response: response, error: error) {
                completion((value.downloads, value.active))
            } else {
                completion(nil)
            }
        }
        task.resume()
    }
}
