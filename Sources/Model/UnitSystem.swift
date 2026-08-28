import Foundation

/// Display units. The model stores millilitres exclusively; this type is the only
/// place conversion and formatting happen, so switching units never mutates data.
enum UnitSystem: String, CaseIterable, Codable, Sendable {
    case metric
    case us

    /// Exact definition of the US fluid ounce.
    static let millilitresPerUSFluidOunce = 29.573_529_562_5

    var displayName: String {
        switch self {
        case .metric: "Millilitres (ml)"
        case .us: "Fluid ounces (fl oz)"
        }
    }

    var shortSuffix: String {
        switch self {
        case .metric: "ml"
        case .us: "fl oz"
        }
    }

    // MARK: - Conversion

    func fromMillilitres(_ millilitres: Double) -> Double {
        switch self {
        case .metric: millilitres
        case .us: millilitres / Self.millilitresPerUSFluidOunce
        }
    }

    func toMillilitres(_ value: Double) -> Double {
        switch self {
        case .metric: value
        case .us: value * Self.millilitresPerUSFluidOunce
        }
    }

    // MARK: - Graduations

    /// Spacing between unlabelled tick marks, in millilitres.
    /// 250 ml for metric; 4 fl oz for US.
    var tickStepMillilitres: Double {
        switch self {
        case .metric: 250
        case .us: 4 * Self.millilitresPerUSFluidOunce
        }
    }

    /// Spacing between *labelled* tick marks, in millilitres.
    /// 500 ml for metric; 8 fl oz (one US cup) for US.
    var labelStepMillilitres: Double {
        switch self {
        case .metric: 500
        case .us: 8 * Self.millilitresPerUSFluidOunce
        }
    }

    // MARK: - Formatting

    /// A bare number for a graduation label, with no unit suffix — the suffix is
    /// shown once on the scale rather than repeated on every tick.
    func graduationLabel(forMillilitres millilitres: Double) -> String {
        let value = fromMillilitres(millilitres)
        return value.formatted(.number.precision(.fractionLength(0)))
    }

    /// A full readout with unit, e.g. "750 ml" or "25 fl oz".
    ///
    /// Metric deliberately stays in millilitres rather than switching to litres above
    /// 1000, so the readout always matches the graduation labels beside it.
    func format(millilitres: Double) -> String {
        let value = fromMillilitres(millilitres)
        let rounded = value.rounded()
        let digits = abs(value - rounded) < 0.05 ? 0 : 1
        let number = value.formatted(.number.precision(.fractionLength(digits)))
        return "\(number) \(shortSuffix)"
    }

    /// Common glass sizes offered in settings, in millilitres.
    var glassPresetsMillilitres: [Double] {
        switch self {
        case .metric: [200, 250, 330, 500]
        case .us: [8, 12, 16, 20].map { $0 * Self.millilitresPerUSFluidOunce }
        }
    }

    /// Daily goal options offered in settings, in millilitres.
    var goalPresetsMillilitres: [Double] {
        switch self {
        case .metric: [1500, 2000, 2500, 3000, 3500]
        case .us: [50, 64, 80, 100, 120].map { $0 * Self.millilitresPerUSFluidOunce }
        }
    }
}
