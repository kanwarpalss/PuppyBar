import Foundation

/// A 40-line stand-in for XCTest, because XCTest requires a full Xcode install.
/// Exits non-zero when anything fails, so build.sh can gate on it. (GATE-01)
enum T {
    nonisolated(unsafe) static var checks = 0
    nonisolated(unsafe) static var failures: [String] = []
    nonisolated(unsafe) static var currentGroup = ""

    static func group(_ name: String, _ body: () -> Void) {
        currentGroup = name
        body()
    }

    static func check(_ condition: Bool, _ message: String, line: Int = #line) {
        checks += 1
        if !condition {
            failures.append("[\(currentGroup):\(line)] \(message)")
        }
    }

    static func eq<V: Equatable>(_ actual: V, _ expected: V, _ message: String, line: Int = #line) {
        checks += 1
        if actual != expected {
            failures.append("[\(currentGroup):\(line)] \(message) — expected \(expected), got \(actual)")
        }
    }

    static func near(_ actual: Double?, _ expected: Double, _ tolerance: Double, _ message: String, line: Int = #line) {
        checks += 1
        let got: String = actual == nil ? "nil" : "\(actual!)"
        guard let actual, abs(actual - expected) <= tolerance else {
            failures.append("[\(currentGroup):\(line)] \(message) — expected ~\(expected), got \(got)")
            return
        }
    }

    static func isNil(_ value: Any?, _ message: String, line: Int = #line) {
        checks += 1
        if value != nil {
            failures.append("[\(currentGroup):\(line)] \(message) — expected nil, got \(value!)")
        }
    }

    static func notNil(_ value: Any?, _ message: String, line: Int = #line) {
        checks += 1
        if value == nil {
            failures.append("[\(currentGroup):\(line)] \(message) — expected a value, got nil")
        }
    }

    static func report() -> Never {
        if failures.isEmpty {
            print("\n✅ \(checks) checks passed.")
            exit(0)
        }
        print("\n❌ \(failures.count) of \(checks) checks FAILED:")
        for f in failures { print("   \(f)") }
        exit(1)
    }
}
