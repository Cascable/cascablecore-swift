import XCTest

#if !canImport(ObjectiveC)
public func allTests() -> [XCTestCaseEntry] {
    return [
        testCase(cascablecore_swiftTests.allTests),
    ]
}
#endif
