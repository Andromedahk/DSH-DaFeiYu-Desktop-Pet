import Foundation

/// One successful balance read.
struct BalanceReading {
    let normalCny: Double
    let bonusCny: Double
    let spentCny: Double?
    let raw: String

    var totalCny: Double { normalCny + bonusCny }
}

enum FetchError: Error {
    case auth(String)              // 401 / 403 / platform code 40003
    case rateLimited(Double?)      // 429, optional Retry-After seconds
    case http(Int, String)
    case transport(String)
    case parse(String)

    var describe: String {
        switch self {
        case .auth(let s):            return "认证失败（\(s)）——请检查 API Key / 账号是否过期"
        case .rateLimited(let ra):    return "请求过于频繁（429）" + (ra.map { "，\(Int($0))s 后重试" } ?? "")
        case .http(let code, let b):  return "HTTP \(code)\(b.isEmpty ? "" : " · " + b)"
        case .transport(let s):       return "网络错误：\(s)"
        case .parse(let s):           return "响应无法解析：\(s)"
        }
    }

    var retryAfter: Double? {
        if case .rateLimited(let ra) = self { return ra }
        return nil
    }
}

enum BalanceClient {

    /// Ephemeral session: a balance response must never reach a disk cache.
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.urlCache = nil
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.httpCookieStorage = nil
        cfg.httpShouldSetCookies = false
        cfg.timeoutIntervalForRequest = 20
        return URLSession(configuration: cfg)
    }()

    static func fetch(_ cred: Credential, timeout: TimeInterval = 20) throws -> BalanceReading {
        var req = URLRequest(url: cred.endpoint)
        req.httpMethod = "GET"
        req.timeoutInterval = timeout
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("DSHBalancePet/1.0 (macOS)", forHTTPHeaderField: "User-Agent")
        switch cred.mode {
        case .apiKey:  req.setValue("Bearer \(cred.token)", forHTTPHeaderField: "Authorization")
        case .account: req.setValue(cred.token, forHTTPHeaderField: "x-dsh-auth-token")
        }

        let sem = DispatchSemaphore(value: 0)
        var boxed: Result<(Int, Data, [String: String]), Error> = .failure(FetchError.transport("no response"))

        let task = session.dataTask(with: req) { data, response, error in
            defer { sem.signal() }
            if let error = error {
                boxed = .failure(FetchError.transport(error.localizedDescription))
                return
            }
            let http = response as? HTTPURLResponse
            var headers: [String: String] = [:]
            if let h = http {
                for (k, v) in h.allHeaderFields {
                    headers[String(describing: k).lowercased()] = String(describing: v)
                }
            }
            boxed = .success((http?.statusCode ?? 0, data ?? Data(), headers))
        }
        task.resume()
        if sem.wait(timeout: .now() + timeout + 5) == .timedOut {
            task.cancel()
            throw FetchError.transport("超时")
        }

        let (status, data, headers) = try boxed.get()
        let body = String(data: data, encoding: .utf8) ?? ""

        if status == 401 || status == 403 {
            throw FetchError.auth("HTTP \(status)")
        }
        if status == 429 {
            let retry = headers["retry-after"].flatMap { Double($0) }
            throw FetchError.rateLimited(retry)
        }
        guard status == 200 else {
            throw FetchError.http(status, String(body.prefix(160)))
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let root = json else { throw FetchError.parse(String(body.prefix(160))) }

        // Platform deployments answer with an envelope; a rejected grant reports code 40003.
        if let code = intValue(find(root, "code")), code == 40003 {
            throw FetchError.auth("平台返回 code 40003")
        }

        switch cred.mode {
        case .account: return try parseAccount(root, raw: body)
        case .apiKey:  return try parseApiKey(root, raw: body)
        }
    }

    // MARK: - Platform account payload
    // {"code":0,"data":{"biz_code":0,"biz_data":{
    //     "normal_wallets":[{"currency":"CNY","balance":"38.61"}]}}}

    private static func parseAccount(_ root: [String: Any], raw: String) throws -> BalanceReading {
        guard let wallets = find(root, "normal_wallets") as? [[String: Any]] else {
            throw FetchError.parse("找不到 normal_wallets")
        }
        let normal = cnyTotal(wallets)
        let bonus = cnyTotal(find(root, "bonus_wallets") as? [[String: Any]] ?? [])

        var spent: Double?
        if let costs = find(root, "total_costs") as? [[String: Any]] {
            let v = cnyTotal(costs, amountKey: "amount")
            if v > 0 { spent = v }
        }
        return BalanceReading(normalCny: normal, bonusCny: bonus, spentCny: spent, raw: raw)
    }

    // MARK: - api.deepseek.com payload
    // {"is_available":true,"balance_infos":[{"currency":"CNY","total_balance":"38.61",...}]}

    private static func parseApiKey(_ root: [String: Any], raw: String) throws -> BalanceReading {
        guard let infos = root["balance_infos"] as? [[String: Any]] else {
            throw FetchError.parse("找不到 balance_infos")
        }
        var cny: Double?
        var usd: Double?
        for w in infos {
            guard let cur = w["currency"] as? String else { continue }
            let v = doubleValue(w["total_balance"]) ?? 0
            if cur == "CNY" { cny = v }
            if cur == "USD" { usd = v }
        }
        guard let normal = cny ?? usd else { throw FetchError.parse("没有可用的余额字段") }
        return BalanceReading(normalCny: normal, bonusCny: 0, spentCny: nil, raw: raw)
    }

    // MARK: - Helpers

    private static func cnyTotal(_ wallets: [[String: Any]], amountKey: String = "balance") -> Double {
        var total = 0.0
        for w in wallets {
            guard let cur = w["currency"] as? String else { continue }
            if cur == "CNY" { total += doubleValue(w[amountKey]) ?? 0 }
        }
        // If no CNY wallet exists at all, fall back to whatever is there.
        if total == 0, !wallets.contains(where: { ($0["currency"] as? String) == "CNY" }) {
            for w in wallets { total += doubleValue(w[amountKey]) ?? 0 }
        }
        return total
    }

    /// Depth-first search for the first value stored under `key`.
    private static func find(_ object: Any, _ key: String) -> Any? {
        if let dict = object as? [String: Any] {
            if let v = dict[key] { return v }
            for (_, v) in dict {
                if let hit = find(v, key) { return hit }
            }
        }
        if let array = object as? [Any] {
            for v in array {
                if let hit = find(v, key) { return hit }
            }
        }
        return nil
    }

    private static func doubleValue(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return Double(s) }
        return nil
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        if let s = any as? String { return Int(s) }
        return nil
    }
}
