import Foundation
import PuppyBarCore

/// Anything PuppyBar can poll.
protocol UsageProvider {
    var name: String { get }
    func fetch(completion: @escaping (ProviderState) -> Void)
}

// MARK: - Claude

/// Reads Claude's 5-hour and 7-day windows off the rate-limit headers of a
/// 1-token ping to /v1/messages. Approach borrowed from rjwalters/claude-monitor (MIT).
///
/// Why a ping and not a usage endpoint: /api/oauth/usage rate-limits so hard it
/// can't be polled (anthropics/claude-code#31637). The headers come back on every
/// response — including 429s — which makes them the reliable source.
final class AnthropicProvider: UsageProvider {
    let name = "Claude"
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func fetch(completion: @escaping (ProviderState) -> Void) {
        guard let token = Keychain.read(account: Keychain.anthropicAccount) else {
            completion(.notConnected("Not connected. Run `claude setup-token`, then use “Connect Claude…”."))
            return
        }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.1.126", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Cheapest legal request that still gets the headers: one Haiku token.
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "x"]],
        ])

        session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failed(Self.friendlyNetworkMessage(error)))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failed("No response from api.anthropic.com."))
                return
            }

            var headers: [String: String] = [:]
            for (k, v) in http.allHeaderFields {
                if let key = k as? String, let value = v as? String { headers[key] = value }
            }
            let windows = Parsing.anthropicWindows(headers: headers)

            // A 429 still carries usage headers — that's data, not an error.
            let rateLimited = http.statusCode == 429
            if !windows.isEmpty {
                completion(.ok(planLabel: nil, windows: windows, rateLimited: rateLimited))
                return
            }

            // No usable headers: say exactly why rather than showing a blank menu. (DEBUG-01)
            switch http.statusCode {
            case 401, 403:
                completion(.notConnected("Token rejected (HTTP \(http.statusCode)). Re-run `claude setup-token` and reconnect."))
            case 429:
                completion(.failed("Rate limited, and no usage headers came back. Try again shortly."))
            default:
                let body = data.flatMap { String(data: $0.prefix(200), encoding: .utf8) } ?? ""
                let detail = body.isEmpty ? "" : " — \(body)"
                completion(.failed("HTTP \(http.statusCode) from api.anthropic.com\(detail)"))
            }
        }.resume()
    }

    static func friendlyNetworkMessage(_ error: Error) -> String {
        let ns = error as NSError
        switch ns.code {
        case NSURLErrorNotConnectedToInternet: return "You're offline."
        case NSURLErrorTimedOut: return "Request timed out."
        default: return ns.localizedDescription
        }
    }
}

// MARK: - OpenAI / ChatGPT

/// Reads the ChatGPT weekly window from chatgpt.com/backend-api/wham/usage using the
/// credentials the ChatGPT / Codex app already keeps at ~/.codex/auth.json.
///
/// The file is re-read on every poll on purpose: the ChatGPT app refreshes that access
/// token in the background, and re-reading is how we pick the new one up without a restart.
final class OpenAIProvider: UsageProvider {
    let name = "ChatGPT"
    private let session: URLSession
    private let authPath: URL

    init(session: URLSession = .shared, authPath: URL? = nil) {
        self.session = session
        if let authPath {
            self.authPath = authPath
        } else {
            let home = ProcessInfo.processInfo.environment["CODEX_HOME"]
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
            self.authPath = URL(fileURLWithPath: home).appendingPathComponent("auth.json")
        }
    }

    func fetch(completion: @escaping (ProviderState) -> Void) {
        guard let data = try? Data(contentsOf: authPath),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = root["tokens"] as? [String: Any],
              let accessToken = tokens["access_token"] as? String, !accessToken.isEmpty else {
            completion(.notConnected("No ChatGPT credentials at \(authPath.path). Sign in to the ChatGPT or Codex app."))
            return
        }
        let accountID = tokens["account_id"] as? String

        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.timeoutInterval = 20
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("PuppyBar/1.0", forHTTPHeaderField: "User-Agent")
        if let accountID { request.setValue(accountID, forHTTPHeaderField: "chatgpt-account-id") }

        session.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failed(AnthropicProvider.friendlyNetworkMessage(error)))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failed("No response from chatgpt.com."))
                return
            }
            guard http.statusCode == 200, let data else {
                if http.statusCode == 401 || http.statusCode == 403 {
                    completion(.notConnected("ChatGPT session expired. Open the ChatGPT or Codex app to refresh it."))
                } else {
                    completion(.failed("HTTP \(http.statusCode) from chatgpt.com."))
                }
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data),
                  let usage = Parsing.openAIUsage(json: json) else {
                completion(.failed("ChatGPT returned a shape PuppyBar didn't recognise."))
                return
            }
            completion(.ok(planLabel: usage.planLabel, windows: usage.windows, rateLimited: usage.rateLimited))
        }.resume()
    }
}
