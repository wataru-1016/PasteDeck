import Foundation

/// XCTest / swift-testing が使えない環境向けの最小テストハーネス
final class TestHarness {
    private(set) var testCount = 0
    private(set) var failureCount = 0
    private var currentTestFailures = 0

    struct RequireError: Error {
        let label: String
    }

    func run(_ name: String, _ body: (TestHarness) throws -> Void) {
        testCount += 1
        currentTestFailures = 0
        do {
            try body(self)
        } catch {
            currentTestFailures += 1
            failureCount += 1
            print("    例外が発生: \(error)")
        }
        print(currentTestFailures == 0 ? "  ✓ \(name)" : "  ✗ \(name)")
    }

    func expect(
        _ condition: Bool,
        _ label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard !condition else { return }
        currentTestFailures += 1
        failureCount += 1
        print("    失敗: \(label) (\(file):\(line))")
    }

    func require<T>(_ value: T?, _ label: String) throws -> T {
        guard let value else { throw RequireError(label: label) }
        return value
    }

    func finish() -> Never {
        print("")
        if failureCount == 0 {
            print("全 \(testCount) 件のテストが成功しました")
            exit(0)
        }
        print("\(failureCount) 件の失敗があります")
        exit(1)
    }
}
