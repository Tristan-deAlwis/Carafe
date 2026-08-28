import XCTest

@testable import Carafe

final class UnitSystemTests: XCTestCase {
    func testMetricConversionIsIdentity() {
        XCTAssertEqual(UnitSystem.metric.fromMillilitres(750), 750)
        XCTAssertEqual(UnitSystem.metric.toMillilitres(750), 750)
    }

    func testUSConversionUsesExactFluidOunce() {
        // One US fluid ounce is exactly 29.5735295625 ml by definition.
        XCTAssertEqual(UnitSystem.us.fromMillilitres(29.5735295625), 1, accuracy: 1e-9)
        XCTAssertEqual(UnitSystem.us.toMillilitres(1), 29.5735295625, accuracy: 1e-9)
    }

    func testConversionRoundTrips() {
        for system in UnitSystem.allCases {
            for millilitres in [0.0, 1, 250, 473.176, 2000, 3785.41] {
                let round = system.toMillilitres(system.fromMillilitres(millilitres))
                XCTAssertEqual(round, millilitres, accuracy: 1e-9, "\(system) failed at \(millilitres)")
            }
        }
    }

    func testGraduationStepsMatchTheDocumentedScale() {
        XCTAssertEqual(UnitSystem.metric.tickStepMillilitres, 250)
        XCTAssertEqual(UnitSystem.metric.labelStepMillilitres, 500)

        // 4 fl oz ticks, labelled every 8 fl oz (one US cup).
        XCTAssertEqual(UnitSystem.us.fromMillilitres(UnitSystem.us.tickStepMillilitres), 4, accuracy: 1e-9)
        XCTAssertEqual(UnitSystem.us.fromMillilitres(UnitSystem.us.labelStepMillilitres), 8, accuracy: 1e-9)
    }

    func testGraduationLabelsAreBareIntegers() {
        XCTAssertEqual(UnitSystem.metric.graduationLabel(forMillilitres: 500), "500")
        XCTAssertEqual(UnitSystem.metric.graduationLabel(forMillilitres: 1500), "1,500")
        XCTAssertEqual(UnitSystem.us.graduationLabel(forMillilitres: 8 * UnitSystem.millilitresPerUSFluidOunce), "8")
    }

    func testFormatIncludesUnitAndHidesNoiseDecimals() {
        XCTAssertEqual(UnitSystem.metric.format(millilitres: 750), "750 ml")
        XCTAssertEqual(UnitSystem.us.format(millilitres: 8 * UnitSystem.millilitresPerUSFluidOunce), "8 fl oz")
    }

    func testMetricReadoutStaysInMillilitresAboveALitre() {
        // Deliberate: the readout must match the graduation labels beside it,
        // so metric never switches to litres.
        XCTAssertEqual(UnitSystem.metric.format(millilitres: 2000), "2,000 ml")
    }

    func testPresetsAreWholeNumbersInTheirOwnUnit() {
        for preset in UnitSystem.us.glassPresetsMillilitres {
            let ounces = UnitSystem.us.fromMillilitres(preset)
            XCTAssertEqual(ounces, ounces.rounded(), accuracy: 1e-9)
        }
        for preset in UnitSystem.metric.glassPresetsMillilitres {
            XCTAssertEqual(preset, preset.rounded(), accuracy: 1e-9)
        }
    }
}
