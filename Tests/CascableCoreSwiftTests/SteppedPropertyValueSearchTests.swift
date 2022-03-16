import CascableCore
@testable import CascableCoreSwift
import XCTest

class TestPropertyStepper: SteppedPropertyValueProvider {

    enum WrapBehaviour {
        case wrap
        case stop
    }

    var index: Int
    let values: [UniversalExposurePropertyValue]
    let wrapBehaviour: WrapBehaviour

    init(values: [UniversalExposurePropertyValue], currentIndex: Int, wrapBehaviour: WrapBehaviour) {
        self.values = values
        self.index = max(0, min(values.count - 1, currentIndex))
        self.wrapBehaviour = wrapBehaviour
    }

    // MARK: - API

    private func incrementValue() async throws -> UniversalExposurePropertyValue {
        var newIndex = index + 1
        let didOverflow = (newIndex >= values.count)
        if didOverflow {
            switch wrapBehaviour {
            case .wrap: newIndex = 0
            case .stop: newIndex = values.count - 1
            }
        }
        index = newIndex
        let value = currentUniversalCommonValue!
        if didOverflow {
            print("Value overflowed on increment, now \(value.succinctDescription)")
        } else {
            print("Value incremented one step to \(value.succinctDescription)")
        }
        return value
    }

    private func decrementValue() async throws -> UniversalExposurePropertyValue {
        var newIndex = index - 1
        let didOverflow = (newIndex < 0)
        if didOverflow {
            switch wrapBehaviour {
            case .wrap: newIndex = values.count - 1
            case .stop: newIndex = 0
            }
        }
        index = newIndex
        let value = currentUniversalCommonValue!
        if didOverflow {
            print("Value overflowed on decrement, now \(value.succinctDescription)")
        } else {
            print("Value decremented one step to \(value.succinctDescription)")
        }
        return value
    }

    func step(in direction: SteppedPropertyDirection) async throws -> UniversalExposurePropertyValue {
        // Hold for 0.05s to simulate a real camera (though they tend to be much slower)
        try await Task.sleep(nanoseconds: 50_000_000)
        switch direction {
        case .increment: return try await incrementValue()
        case .decrement: return try await decrementValue()
        }
    }

    var currentUniversalCommonValue: UniversalExposurePropertyValue? {
        return values[index]
    }
}

// MARK: -

class SteppedPropertyValueSearchTests: XCTestCase {

    // MARK: - Invalid Input Tests

    func testInvalidStates() async throws {
        let readOnlyStepper = TestPropertyStepper(values: [ISOValue.iso100], currentIndex: 0, wrapBehaviour: .wrap)
        let finder = SteppedPropertyValueSearch<ISOValue>(readOnlyStepper)
        let result = try await finder.stepToValue(closestTo: ISOValue(numericISOValue: 200)!)
        XCTAssertEqual(result.commonValue, ISOValue.iso100)
        XCTAssertEqual(result.matchType, .reachedEndOfRange)
    }

    // MARK: - Specific Bug Regression Tests

    func testLessThanOneStopChange() async throws {
        // We had a rounding bug that caused gaps of <= 1.0 stop to fail with an overrun error.
        let shutterSpeeds = shutterSpeedValuesAllDeterministic
        let startValue = ShutterSpeedValue(approximateDuration: 1.0/250.0)!
        let endValue = ShutterSpeedValue(approximateDuration: 1.0/500.0)!
        let stepper = TestPropertyStepper(values: shutterSpeeds, currentIndex: shutterSpeeds.firstIndex(of: startValue)!,
                                          wrapBehaviour: .stop)
        let finder = SteppedPropertyValueSearch<ShutterSpeedValue>(stepper)
        let result = try await finder.stepToValue(closestTo: endValue)
        XCTAssertEqual(result.commonValue, endValue)
        XCTAssertEqual(result.matchType, .exact)
    }

    // MARK: - ISO Tests

    var oneStopISOValuesAllDeterministic: [ISOValue] {
        return [ISOValue(numericISOValue: 100),
                ISOValue(numericISOValue: 200),
                ISOValue(numericISOValue: 400),
                ISOValue(numericISOValue: 800),
                ISOValue(numericISOValue: 1600),
                ISOValue(numericISOValue: 3200),
                ISOValue(numericISOValue: 6400)].compactMap({$0})
    }

    var oneStopISOValuesWithAuto: [ISOValue] {
        return [.automaticISO,
                ISOValue(numericISOValue: 100),
                ISOValue(numericISOValue: 200),
                ISOValue(numericISOValue: 400),
                ISOValue(numericISOValue: 800),
                ISOValue(numericISOValue: 1600),
                ISOValue(numericISOValue: 3200),
                ISOValue(numericISOValue: 6400)].compactMap({$0})
    }

    func testISOExactMatches() async throws {
        let stepper = TestPropertyStepper(values: oneStopISOValuesAllDeterministic, currentIndex: 6, wrapBehaviour: .stop)
        let finder = SteppedPropertyValueSearch<ISOValue>(stepper)
        let result = try await finder.stepToValue(closestTo: ISOValue(numericISOValue: 100)!)
        XCTAssertEqual(result.commonValue, ISOValue(numericISOValue: 100))
        XCTAssertEqual(result.matchType, .exact)
    }

    func testISOExactMatchesBreakingAssumptions() async throws {
        let stepper = TestPropertyStepper(values: oneStopISOValuesAllDeterministic.reversed(), currentIndex: 2, wrapBehaviour: .stop)
        let finder = SteppedPropertyValueSearch<ISOValue>(stepper)
        let result = try await finder.stepToValue(closestTo: ISOValue(numericISOValue: 100)!)
        XCTAssertEqual(result.commonValue, ISOValue(numericISOValue: 100))
        XCTAssertEqual(result.matchType, .exact)
    }

    func testISONoExactMatch() async throws {
        let stepper = TestPropertyStepper(values: oneStopISOValuesAllDeterministic, currentIndex: 6, wrapBehaviour: .stop)
        let finder = SteppedPropertyValueSearch<ISOValue>(stepper)
        let result = try await finder.stepToValue(closestTo: ISOValue(numericISOValue: 125)!)
        XCTAssertEqual(result.commonValue, ISOValue(numericISOValue: 100))
        XCTAssertEqual(result.matchType, .inexact)

        let iso160 = ISOValue(numericISOValue: 200)!.adding(ExposureStops(wholeStops: 0, fraction: .oneThird, isNegative: true))!

        let inTheMiddleStepper = TestPropertyStepper(values: oneStopISOValuesAllDeterministic, currentIndex: 4, wrapBehaviour: .stop)
        let inTheMiddleResult = try await SteppedPropertyValueSearch<ISOValue>(inTheMiddleStepper).stepToValue(closestTo: iso160 as! ISOValue)
        XCTAssertEqual(inTheMiddleResult.commonValue, ISOValue(numericISOValue: 200))
        XCTAssertEqual(inTheMiddleResult.matchType, .inexact)

        let atLimitStepper = TestPropertyStepper(values: oneStopISOValuesAllDeterministic, currentIndex: 0, wrapBehaviour: .stop)
        let secondResult = try await SteppedPropertyValueSearch<ISOValue>(atLimitStepper).stepToValue(closestTo: iso160 as! ISOValue)
        XCTAssertEqual(secondResult.commonValue, ISOValue(numericISOValue: 200))
        XCTAssertEqual(secondResult.matchType, .inexact)
    }

    // ---

    func testISOUnderflowFromFarAwayWithStop() async throws {
        let stepper = TestPropertyStepper(values: oneStopISOValuesAllDeterministic, currentIndex: 6, wrapBehaviour: .stop)
        let finder = SteppedPropertyValueSearch<ISOValue>(stepper)
        let result = try await finder.stepToValue(closestTo: ISOValue(numericISOValue: 50)!)
        XCTAssertEqual(result.commonValue, ISOValue(numericISOValue: 100))
        XCTAssertEqual(result.matchType, .reachedEndOfRange)
    }

    func testISOUnderflowFromRangeLimitWithStop() async throws {
        let stepper = TestPropertyStepper(values: oneStopISOValuesAllDeterministic, currentIndex: 1, wrapBehaviour: .stop)
        let finder = SteppedPropertyValueSearch<ISOValue>(stepper)
        let fiftyResult = try await finder.stepToValue(closestTo: ISOValue(numericISOValue: 50)!)
        XCTAssertEqual(fiftyResult.commonValue, ISOValue(numericISOValue: 100))
        XCTAssertEqual(fiftyResult.matchType, .reachedEndOfRange)

        let eightyResult = try await finder.stepToValue(closestTo: ISOValue(numericISOValue: 80)!)
        XCTAssertEqual(eightyResult.commonValue, ISOValue(numericISOValue: 100))
        XCTAssertEqual(eightyResult.matchType, .reachedEndOfRange)
    }

    func testISOUnderflowFromFarAwayWithWrap() async throws {
        let stepper = TestPropertyStepper(values: oneStopISOValuesAllDeterministic, currentIndex: 6, wrapBehaviour: .wrap)
        let finder = SteppedPropertyValueSearch<ISOValue>(stepper)
        let result = try await finder.stepToValue(closestTo: ISOValue(numericISOValue: 50)!)
        XCTAssertEqual(result.commonValue, ISOValue(numericISOValue: 100))
        XCTAssertEqual(result.matchType, .reachedEndOfRange)
    }

    func testISOUnderflowFromRangeLimitWithWrap() async throws {
        let stepper = TestPropertyStepper(values: oneStopISOValuesAllDeterministic, currentIndex: 1, wrapBehaviour: .wrap)
        let finder = SteppedPropertyValueSearch<ISOValue>(stepper)
        let fiftyResult = try await finder.stepToValue(closestTo: ISOValue(numericISOValue: 50)!)
        XCTAssertEqual(fiftyResult.commonValue, ISOValue(numericISOValue: 100))
        XCTAssertEqual(fiftyResult.matchType, .reachedEndOfRange)

        let eightyResult = try await finder.stepToValue(closestTo: ISOValue(numericISOValue: 80)!)
        XCTAssertEqual(eightyResult.commonValue, ISOValue(numericISOValue: 100))
        XCTAssertEqual(eightyResult.matchType, .reachedEndOfRange)
    }

    // ---

    func testISOIntoAutoFromFarAwayWithStop() async throws {
        let stepper = TestPropertyStepper(values: oneStopISOValuesWithAuto, currentIndex: 6, wrapBehaviour: .stop)
        let finder = SteppedPropertyValueSearch<ISOValue>(stepper)
        let result = try await finder.stepToValue(closestTo: ISOValue(numericISOValue: 50)!)
        XCTAssertEqual(result.commonValue, ISOValue(numericISOValue: 100))
        XCTAssertEqual(result.matchType, .reachedEndOfRange)
    }

    func testISOIntoAutoFromRangeLimitWithStop() async throws {
        let stepper = TestPropertyStepper(values: oneStopISOValuesWithAuto, currentIndex: 1, wrapBehaviour: .stop)
        let finder = SteppedPropertyValueSearch<ISOValue>(stepper)
        let fiftyResult = try await finder.stepToValue(closestTo: ISOValue(numericISOValue: 50)!)
        XCTAssertEqual(fiftyResult.commonValue, ISOValue(numericISOValue: 100))
        XCTAssertEqual(fiftyResult.matchType, .reachedEndOfRange)

        let eightyResult = try await finder.stepToValue(closestTo: ISOValue(numericISOValue: 80)!)
        XCTAssertEqual(eightyResult.commonValue, ISOValue(numericISOValue: 100))
        XCTAssertEqual(eightyResult.matchType, .reachedEndOfRange)
    }

    func testISOIntoAutoFromFarAwayWithWrap() async throws {
        let stepper = TestPropertyStepper(values: oneStopISOValuesWithAuto, currentIndex: 6, wrapBehaviour: .wrap)
        let finder = SteppedPropertyValueSearch<ISOValue>(stepper)
        let result = try await finder.stepToValue(closestTo: ISOValue(numericISOValue: 50)!)
        XCTAssertEqual(result.commonValue, ISOValue(numericISOValue: 100))
        XCTAssertEqual(result.matchType, .reachedEndOfRange)
    }

    func testISOIntoAutoFromRangeLimitWithWrap() async throws {
        let stepper = TestPropertyStepper(values: oneStopISOValuesWithAuto, currentIndex: 1, wrapBehaviour: .wrap)
        let finder = SteppedPropertyValueSearch<ISOValue>(stepper)
        let fiftyResult = try await finder.stepToValue(closestTo: ISOValue(numericISOValue: 50)!)
        XCTAssertEqual(fiftyResult.commonValue, ISOValue(numericISOValue: 100))
        XCTAssertEqual(fiftyResult.matchType, .reachedEndOfRange)

        let eightyResult = try await finder.stepToValue(closestTo: ISOValue(numericISOValue: 80)!)
        XCTAssertEqual(eightyResult.commonValue, ISOValue(numericISOValue: 100))
        XCTAssertEqual(eightyResult.matchType, .reachedEndOfRange)
    }

    // ---

    func testISOOverflowFromFarAwayWithStop() async throws {
        let stepper = TestPropertyStepper(values: oneStopISOValuesAllDeterministic, currentIndex: 2, wrapBehaviour: .stop)
        let finder = SteppedPropertyValueSearch<ISOValue>(stepper)
        let result = try await finder.stepToValue(closestTo: ISOValue(numericISOValue: 100000)!)
        XCTAssertEqual(result.commonValue, ISOValue(numericISOValue: 6400))
        XCTAssertEqual(result.matchType, .reachedEndOfRange)
    }

    func testISOOverflowFromRangeLimitWithStop() async throws {
        let isos = oneStopISOValuesAllDeterministic
        let stepper = TestPropertyStepper(values: isos, currentIndex: isos.count - 1, wrapBehaviour: .stop)
        let finder = SteppedPropertyValueSearch<ISOValue>(stepper)
        let fiftyResult = try await finder.stepToValue(closestTo: ISOValue(numericISOValue: 100000)!)
        XCTAssertEqual(fiftyResult.commonValue, ISOValue(numericISOValue: 6400))
        XCTAssertEqual(fiftyResult.matchType, .reachedEndOfRange)

        let eightyResult = try await finder.stepToValue(closestTo: ISOValue(numericISOValue: 80)!)
        XCTAssertEqual(eightyResult.commonValue, ISOValue(numericISOValue: 100))
        XCTAssertEqual(eightyResult.matchType, .reachedEndOfRange)
    }

    func testISOOverflowFromFarAwayWithWrap() async throws {
        let stepper = TestPropertyStepper(values: oneStopISOValuesWithAuto, currentIndex: 2, wrapBehaviour: .wrap)
        let finder = SteppedPropertyValueSearch<ISOValue>(stepper)
        let result = try await finder.stepToValue(closestTo: ISOValue(numericISOValue: 100000)!)
        XCTAssertEqual(result.commonValue, ISOValue(numericISOValue: 6400))
        XCTAssertEqual(result.matchType, .reachedEndOfRange)
    }

    func testISOOverflowFromRangeLimitWithWrap() async throws {
        let isos = oneStopISOValuesWithAuto
        let stepper = TestPropertyStepper(values: isos, currentIndex: isos.count - 1, wrapBehaviour: .wrap)
        let finder = SteppedPropertyValueSearch<ISOValue>(stepper)
        let result = try await finder.stepToValue(closestTo: ISOValue(numericISOValue: 100000)!)
        XCTAssertEqual(result.commonValue, ISOValue(numericISOValue: 6400))
        XCTAssertEqual(result.matchType, .reachedEndOfRange)
    }

    // MARK: - Shutter Speed Tests

    var shutterSpeedValuesAllDeterministic: [ShutterSpeedValue] {
        let thirtySeconds = ShutterSpeedValue(approximateDuration: 30.0)!
        let oneFourThousandth = ShutterSpeedValue(approximateDuration: 1.0 / 4000.0)!

        let stops = ExposureStops.stopsBetween(oneFourThousandth.stopsFromASecond,
                                               and: thirtySeconds.stopsFromASecond,
                                               including: [.oneThird, .twoThirds])!

        // Stop math always returns values in ascending order, but shutter speeds tend to be descending.
        return stops.reversed().compactMap({ ShutterSpeedValue(stopsFromASecond: $0) })
    }

    var shutterSpeedValuesWithNonDeterministicValues: [ShutterSpeedValue] {
        var values: [ShutterSpeedValue] = [.automaticShutterSpeed, .bulbShutterSpeed]
        values.append(contentsOf: shutterSpeedValuesAllDeterministic)
        return values
    }

    func testShutterSpeedExactMatches() async throws {
        let shutterSpeeds = shutterSpeedValuesAllDeterministic
        let index = shutterSpeeds.firstIndex(of: .oneTwoHundredFiftiethShutterSpeed)!
        let target = ShutterSpeedValue(approximateDuration: 1.0 / 40.0)!

        let stepper = TestPropertyStepper(values: shutterSpeeds, currentIndex: index, wrapBehaviour: .wrap)
        let finder = SteppedPropertyValueSearch<ShutterSpeedValue>(stepper)
        let result = try await finder.stepToValue(closestTo: target)
        XCTAssertEqual(result.commonValue, target)
        XCTAssertEqual(result.matchType, .exact)

        let secondTarget = ShutterSpeedValue(approximateDuration: 30.0)!
        let secondResult = try await finder.stepToValue(closestTo: secondTarget)
        XCTAssertEqual(secondResult.commonValue, secondTarget)
        XCTAssertEqual(secondResult.matchType, .exact)

        let thirdTarget = ShutterSpeedValue(approximateDuration: 60.0)!
        let thirdResult = try await finder.stepToValue(closestTo: thirdTarget)
        XCTAssertEqual(thirdResult.commonValue, secondTarget)
        XCTAssertEqual(thirdResult.matchType, .reachedEndOfRange)

        let fourthTarget = ShutterSpeedValue(approximateDuration: 1.0 / 4000.0)!
        let fourthResult = try await finder.stepToValue(closestTo: fourthTarget)
        XCTAssertEqual(fourthResult.commonValue, fourthTarget)
        XCTAssertEqual(fourthResult.matchType, .exact)
    }

    func testShutterSpeedExactMatchesIntoNonDeterministic() async throws {
        let shutterSpeeds = shutterSpeedValuesWithNonDeterministicValues
        let index = shutterSpeeds.firstIndex(of: .oneTwoHundredFiftiethShutterSpeed)!
        let target = ShutterSpeedValue(approximateDuration: 1.0 / 40.0)!

        let stepper = TestPropertyStepper(values: shutterSpeeds, currentIndex: index, wrapBehaviour: .wrap)
        let finder = SteppedPropertyValueSearch<ShutterSpeedValue>(stepper)
        let result = try await finder.stepToValue(closestTo: target)
        XCTAssertEqual(result.commonValue, target)
        XCTAssertEqual(result.matchType, .exact)

        let maxShutterSpeed = ShutterSpeedValue(approximateDuration: 30.0)!

        let secondTarget = ShutterSpeedValue(approximateDuration: 60.0)!
        let secondResult = try await finder.stepToValue(closestTo: secondTarget)
        XCTAssertEqual(secondResult.commonValue, maxShutterSpeed)
        XCTAssertEqual(secondResult.matchType, .reachedEndOfRange)

        let thirdTarget = ShutterSpeedValue(approximateDuration: 60.0)!
        let thirdResult = try await finder.stepToValue(closestTo: thirdTarget)
        XCTAssertEqual(thirdResult.commonValue, maxShutterSpeed)
        XCTAssertEqual(thirdResult.matchType, .reachedEndOfRange)

        let fourthTarget = ShutterSpeedValue(approximateDuration: 1.0 / 4000.0)!
        let fourthResult = try await finder.stepToValue(closestTo: fourthTarget)
        XCTAssertEqual(fourthResult.commonValue, fourthTarget)
        XCTAssertEqual(fourthResult.matchType, .exact)
    }

    func testShutterSpeedExactMatchesWithFalseAssumption() async throws {
        let shutterSpeeds: [ShutterSpeedValue] = shutterSpeedValuesAllDeterministic.reversed()
        let index = shutterSpeeds.firstIndex(of: .oneTwoHundredFiftiethShutterSpeed)!
        let target = ShutterSpeedValue(approximateDuration: 1.0 / 40.0)!

        let stepper = TestPropertyStepper(values: shutterSpeeds, currentIndex: index, wrapBehaviour: .wrap)
        let finder = SteppedPropertyValueSearch<ShutterSpeedValue>(stepper)
        let result = try await finder.stepToValue(closestTo: target)
        XCTAssertEqual(result.commonValue, target)
        XCTAssertEqual(result.matchType, .exact)

        let secondTarget = ShutterSpeedValue(approximateDuration: 30.0)!
        let secondResult = try await finder.stepToValue(closestTo: secondTarget)
        XCTAssertEqual(secondResult.commonValue, secondTarget)
        XCTAssertEqual(secondResult.matchType, .exact)

        let thirdTarget = ShutterSpeedValue(approximateDuration: 60.0)!
        let thirdResult = try await finder.stepToValue(closestTo: thirdTarget)
        XCTAssertEqual(thirdResult.commonValue, secondTarget)
        XCTAssertEqual(thirdResult.matchType, .reachedEndOfRange)

        let fourthTarget = ShutterSpeedValue(approximateDuration: 1.0 / 4000.0)!
        let fourthResult = try await finder.stepToValue(closestTo: fourthTarget)
        XCTAssertEqual(fourthResult.commonValue, fourthTarget)
        XCTAssertEqual(fourthResult.matchType, .exact)
    }

    func testShutterSpeedExactMatchesIntoNonDeterministicWithFalseAssumption() async throws {
        let shutterSpeeds: [ShutterSpeedValue] = shutterSpeedValuesWithNonDeterministicValues.reversed()
        let index = shutterSpeeds.firstIndex(of: .oneTwoHundredFiftiethShutterSpeed)!
        let target = ShutterSpeedValue(approximateDuration: 1.0 / 40.0)!

        let stepper = TestPropertyStepper(values: shutterSpeeds, currentIndex: index, wrapBehaviour: .wrap)
        let finder = SteppedPropertyValueSearch<ShutterSpeedValue>(stepper)
        let result = try await finder.stepToValue(closestTo: target)
        XCTAssertEqual(result.commonValue, target)
        XCTAssertEqual(result.matchType, .exact)

        let maxShutterSpeed = ShutterSpeedValue(approximateDuration: 30.0)!

        let secondTarget = ShutterSpeedValue(approximateDuration: 60.0)!
        let secondResult = try await finder.stepToValue(closestTo: secondTarget)
        XCTAssertEqual(secondResult.commonValue, maxShutterSpeed)
        XCTAssertEqual(secondResult.matchType, .reachedEndOfRange)

        let thirdTarget = ShutterSpeedValue(approximateDuration: 60.0)!
        let thirdResult = try await finder.stepToValue(closestTo: thirdTarget)
        XCTAssertEqual(thirdResult.commonValue, maxShutterSpeed)
        XCTAssertEqual(thirdResult.matchType, .reachedEndOfRange)

        let fourthTarget = ShutterSpeedValue(approximateDuration: 1.0 / 4000.0)!
        let fourthResult = try await finder.stepToValue(closestTo: fourthTarget)
        XCTAssertEqual(fourthResult.commonValue, fourthTarget)
        XCTAssertEqual(fourthResult.matchType, .exact)
    }

}
