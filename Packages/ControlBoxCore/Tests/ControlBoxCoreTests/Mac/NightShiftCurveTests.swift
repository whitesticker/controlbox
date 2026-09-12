import XCTest
@testable import ControlBoxCore

final class NightShiftCurveTests: XCTestCase {
    func testSnapToEdgeHitsNightShiftMaximum() {
        XCTAssertEqual(NightShiftCurve.snapToEdge(1), 1)
        XCTAssertEqual(NightShiftCurve.snapToEdge(0.97), 1)
        XCTAssertEqual(NightShiftCurve.snapToEdge(0.96), 1)
        XCTAssertEqual(NightShiftCurve.snapToEdge(0.95), 0.95, accuracy: 0.0001)
        XCTAssertEqual(NightShiftCurve.snapToEdge(0), 0)
        XCTAssertEqual(NightShiftCurve.snapToEdge(0.03), 0)
        XCTAssertEqual(NightShiftCurve.snapToEdge(0.05), 0.05, accuracy: 0.0001)
    }

    func testKelvinAtMaxWarmthGoesPastAppleNightShift() {
        let range = NightShift.CCTRange(minKelvin: 2700, maxKelvin: 6000)
        XCTAssertEqual(NightShiftCurve.kelvin(warmth: 1, range: range), Int(NightShift.extraMinKelvin.rounded()))
        XCTAssertEqual(NightShiftCurve.kelvin(warmth: 0.995, range: range), Int(NightShift.extraMinKelvin.rounded()))
        XCTAssertEqual(NightShiftCurve.kelvin(warmth: 0, range: range), 6000)
        XCTAssertLessThan(NightShiftCurve.kelvin(warmth: 1, range: range), 2700)
    }

    func testExtraGammaAtMaxIsWarmerThanIdentity() {
        let rest = NightShiftGamma.rgbScale(warmth: 0)
        XCTAssertEqual(rest.r, 1, accuracy: 0.001)
        XCTAssertEqual(rest.g, 1, accuracy: 0.001)
        XCTAssertEqual(rest.b, 1, accuracy: 0.001)
        let max = NightShiftGamma.rgbScale(warmth: 1)
        XCTAssertEqual(max.r, 1, accuracy: 0.02)
        XCTAssertLessThan(max.g, 0.92)
        XCTAssertLessThan(max.b, 0.30)
        XCTAssertGreaterThanOrEqual(max.b, NightShiftGamma.blueFloor - 0.001)
    }

    func testFactoryNightPlateauStaysAtMaximum() {
        let curve = NightShiftCurve.factory
        XCTAssertGreaterThanOrEqual(curve.warmth(atMinutes: 23 * 60), 0.98)
        XCTAssertGreaterThanOrEqual(curve.warmth(atMinutes: 2 * 60), 0.98)
        XCTAssertGreaterThanOrEqual(curve.warmth(atMinutes: 5 * 60), 0.98)
    }

    func testFactoryDayIsCool() {
        let curve = NightShiftCurve.factory
        XCTAssertLessThanOrEqual(curve.warmth(atMinutes: 12 * 60), 0.08)
        XCTAssertLessThanOrEqual(curve.warmth(atMinutes: 14 * 60), 0.08)
        XCTAssertLessThan(curve.warmth(atMinutes: 8 * 60 + 30), 0.35)
    }

    func testSuggestedAddPrefersRequestedTime() {
        var curve = NightShiftCurve.factory
        let slot = curve.suggestedAdd(preferring: 13 * 60)
        XCTAssertNotNil(slot)
        XCTAssertEqual(slot?.minutes ?? -1, 13 * 60, accuracy: 0.5)
        let id = curve.add(minutes: slot!.minutes, warmth: slot!.warmth)
        XCTAssertNotNil(id)
        XCTAssertEqual(curve.points.count, NightShiftCurve.factory.points.count + 1)
    }

    func testSuggestedAddUsesLargestGapWhenCrowded() {
        var curve = NightShiftCurve.factory
        let existing = curve.sorted[0].minutes
        let slot = curve.suggestedAdd(preferring: existing)
        XCTAssertNotNil(slot)
        XCTAssertGreaterThan(abs(NightShiftCurve.shortestDelta(slot!.minutes, existing)), 11)
        XCTAssertNotNil(curve.add(minutes: slot!.minutes, warmth: slot!.warmth))
    }

    func testRemoveStopsAtMinimumPoints() {
        var curve = NightShiftCurve.factory
        let extra = curve.suggestedAdd(preferring: 13 * 60)!
        XCTAssertNotNil(curve.add(minutes: extra.minutes, warmth: extra.warmth))
        while curve.points.count > NightShiftCurve.minPoints {
            XCTAssertTrue(curve.remove(id: curve.points[0].id))
        }
        XCTAssertFalse(curve.remove(id: curve.points[0].id))
        XCTAssertEqual(curve.points.count, NightShiftCurve.minPoints)
    }

    func testShippingV3IsNotTheNewFactory() {
        XCTAssertFalse(NightShiftCurve.factory.matchesShape(of: .shippingV3))
        XCTAssertTrue(NightShiftCurve.shippingV3.matchesShape(of: .shippingV3))
    }
}
