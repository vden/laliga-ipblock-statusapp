// Offline checks for the verdict rule, list parsing and Cloudflare range
// matching. Nothing here touches the network.
//
//   ./test.sh
import Foundation

var failures = 0

@MainActor func expect(_ condition: Bool, _ name: String) {
    print(condition ? "ok   " : "FAIL ", name)
    if !condition { failures += 1 }
}

// MARK: - Cloudflare ranges

expect(Cloudflare.owns("188.114.96.5"), "188.114.96.5 is Cloudflare")
expect(Cloudflare.owns("188.114.111.255"), "last address of 188.114.96.0/20")
expect(!Cloudflare.owns("188.114.112.0"), "first address past 188.114.96.0/20")
expect(Cloudflare.owns("104.23.255.255"), "last address of 104.16.0.0/13")
expect(Cloudflare.owns("2a06:98c1:3120::5"), "IPv6 inside 2a06:98c0::/29")
expect(!Cloudflare.owns("2a06:98c8::1"), "IPv6 past 2a06:98c0::/29")
expect(!Cloudflare.owns("192.124.249.25"), "a blocked non-Cloudflare IP")
expect(!Cloudflare.owns("not an ip"), "garbage is not Cloudflare")
expect(Network("10.0.0.0/33") == nil, "IPv4 prefix over 32 is rejected")
expect(Network("0.0.0.0/0")!.contains(IPAddress("8.8.8.8")!), "/0 contains everything")
expect(!Network("0.0.0.0/0")!.contains(IPAddress("::1")!), "IPv4 range never contains IPv6")

// MARK: - Verdict

func lists(_ sets: Set<String>...) -> [Set<String>] {
    sets + Array(repeating: [], count: 5 - sets.count)
}
let cloudflare11 = Set((1...11).map { "104.21.0.\($0)" })
let cloudflare10 = Set((1...10).map { "104.21.0.\($0)" })
let other20 = Set((1...20).map { "192.124.249.\($0)" })

expect(!StatusChecker.verdict(lists()), "nothing blocked")
expect(StatusChecker.verdict(lists(["188.114.96.5", "188.114.97.5"])), "both canaries on one ISP")
expect(StatusChecker.verdict(lists(["188.114.96.5"], ["188.114.97.5"])), "canaries split across ISPs")
expect(!StatusChecker.verdict(lists(["188.114.96.5"])), "a single canary")
expect(StatusChecker.verdict(lists(cloudflare11, cloudflare11, cloudflare11)), "11 Cloudflare IPs on 3 ISPs")
expect(!StatusChecker.verdict(lists(cloudflare10, cloudflare10, cloudflare10, cloudflare10, cloudflare10)),
       "10 Cloudflare IPs is not more than 10")
expect(!StatusChecker.verdict(lists(cloudflare11, cloudflare11)), "2 ISPs is not more than 2")
expect(!StatusChecker.verdict(lists(other20, other20, other20, other20, other20)), "non-Cloudflare IPs don't count")

// MARK: - Parsing

expect((try? StatusChecker.parseList("", name: "t")) == [], "empty list between matches")
expect((try? StatusChecker.parseList("1.2.3.4\n\n 2a06:98c1:3120::5 \r\n", name: "t"))
       == ["1.2.3.4", "2a06:98c1:3120::5"], "blank lines, spaces and CRLF")
expect((try? StatusChecker.parseList("<html>moved</html>", name: "t")) == nil, "a page instead of a list throws")

print(failures == 0 ? "all passed" : "\(failures) failed")
exit(failures == 0 ? 0 : 1)
