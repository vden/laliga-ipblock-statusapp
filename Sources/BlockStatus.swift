import Foundation

/// What hayahora.futbol's headline says, rebuilt from its per-ISP lists.
///
/// The page itself downloads `estado/data.json` (5.6 MB of history) and derives
/// the headline from the latest state of every IP. The plain-text lists under
/// `estado/` carry the same "blocked right now" set in a few kilobytes, and the
/// site asks for reasonable use, so we poll those instead. Replaying two months
/// of history at 10-minute steps, both methods agreed on all 8,640 samples.
struct BlockStatus: Sendable {
    struct ISPCount: Sendable {
        let name: String
        let count: Int
    }

    let blocked: Bool
    /// IPs blocked by at least one ISP: the page's "IPs bloqueadas ahora".
    let blockedIPs: Int
    let perISP: [ISPCount]
    let checkedAt: Date
}

enum StatusError: LocalizedError {
    case http(String, Int)
    case unexpectedFormat(String)

    var errorDescription: String? {
        switch self {
        case let .http(list, code): "\(list) returned HTTP \(code)"
        case let .unexpectedFormat(list): "\(list) is not an IP list any more"
        }
    }
}

enum StatusChecker {
    static let site = URL(string: "https://hayahora.futbol")!

    static let isps: [(name: String, slug: String)] = [
        ("Movistar", "movistar"),
        ("DIGI", "digi"),
        ("Vodafone", "vodafone"),
        ("Orange", "orange"),
        ("MásMóvil", "masmovil"),
    ]

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    static func check() async throws -> BlockStatus {
        let lists = try await withThrowingTaskGroup(of: (Int, Set<String>).self) { group in
            for (index, isp) in isps.enumerated() {
                group.addTask { (index, try await fetchList(isp.slug)) }
            }
            var lists = [Set<String>](repeating: [], count: isps.count)
            for try await (index, list) in group {
                lists[index] = list
            }
            return lists
        }
        return BlockStatus(
            blocked: verdict(lists),
            blockedIPs: lists.reduce(into: Set<String>()) { $0.formUnion($1) }.count,
            perISP: zip(isps, lists).map { .init(name: $0.name, count: $1.count) },
            checkedAt: Date()
        )
    }

    private static func fetchList(_ slug: String) async throws -> Set<String> {
        let name = "blocked-\(slug).txt"
        let url = site.appending(path: "estado/\(name)")
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw StatusError.http(name, http.statusCode)
        }
        return try parseList(String(decoding: data, as: UTF8.self), name: name)
    }

    static func parseList(_ body: String, name: String) throws -> Set<String> {
        let lines = body
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let ips = Set(lines.filter { IPAddress($0) != nil })
        // An empty list is the normal state between matches. A non-empty one with
        // no addresses in it means the format changed, and reading that as "not
        // blocked" would be wrong in the most annoying way.
        if !lines.isEmpty && ips.isEmpty {
            throw StatusError.unexpectedFormat(name)
        }
        return ips
    }

    /// The page's rule, from its JS bundle: blocked when more than 10 Cloudflare
    /// IPs are blocked on more than 2 ISPs, or when the pair it singles out,
    /// 188.114.96.5 and 188.114.97.5, are both blocked on any ISP.
    static func verdict(_ lists: [Set<String>]) -> Bool {
        var ispsBlocking: [String: Int] = [:]
        for list in lists {
            for ip in list where Cloudflare.owns(ip) {
                ispsBlocking[ip, default: 0] += 1
            }
        }
        let widelyBlocked = ispsBlocking.values.filter { $0 > 2 }.count
        let canariesBlocked = ["188.114.96.5", "188.114.97.5"].allSatisfy { ip in
            lists.contains { $0.contains(ip) }
        }
        return widelyBlocked > 10 || canariesBlocked
    }
}

/// The page counts IPs its own data labels "Cloudflare"; the lists carry no
/// labels, so we go by Cloudflare's published ranges (cloudflare.com/ips).
/// Hardcoded rather than fetched: cloudflare.com sits on those very addresses,
/// so it tends to be unreachable at exactly the moment we would need it.
enum Cloudflare {
    static let ranges: [Network] = [
        "173.245.48.0/20", "103.21.244.0/22", "103.22.200.0/22", "103.31.4.0/22",
        "141.101.64.0/18", "108.162.192.0/18", "190.93.240.0/20", "188.114.96.0/20",
        "197.234.240.0/22", "198.41.128.0/17", "162.158.0.0/15", "104.16.0.0/13",
        "104.24.0.0/14", "172.64.0.0/13", "131.0.72.0/22",
        "2400:cb00::/32", "2606:4700::/32", "2803:f800::/32", "2405:b500::/32",
        "2405:8100::/32", "2a06:98c0::/29", "2c0f:f248::/32",
    ].map { Network($0)! }

    static func owns(_ ip: String) -> Bool {
        guard let address = IPAddress(ip) else { return false }
        return ranges.contains { $0.contains(address) }
    }
}

struct IPAddress {
    let bytes: [UInt8]

    init?(_ string: String) {
        var v4 = in_addr()
        var v6 = in6_addr()
        if inet_pton(AF_INET, string, &v4) == 1 {
            bytes = withUnsafeBytes(of: v4) { Array($0) }
        } else if inet_pton(AF_INET6, string, &v6) == 1 {
            bytes = withUnsafeBytes(of: v6) { Array($0) }
        } else {
            return nil
        }
    }
}

struct Network {
    let base: IPAddress
    let prefix: Int

    init?(_ cidr: String) {
        let parts = cidr.split(separator: "/")
        guard parts.count == 2, let base = IPAddress(String(parts[0])),
              let prefix = Int(parts[1]), (0...base.bytes.count * 8).contains(prefix)
        else { return nil }
        self.base = base
        self.prefix = prefix
    }

    func contains(_ address: IPAddress) -> Bool {
        guard address.bytes.count == base.bytes.count else { return false }
        let whole = prefix / 8
        let rest = prefix % 8
        if address.bytes[..<whole] != base.bytes[..<whole] { return false }
        if rest == 0 { return true }
        let mask = UInt8(truncatingIfNeeded: 0xFF << (8 - rest))
        return address.bytes[whole] & mask == base.bytes[whole] & mask
    }
}
