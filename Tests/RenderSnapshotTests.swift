import SwiftUI
import XCTest

@testable import Carafe

/// Renders the carafe artwork to PNGs so it can be inspected by eye.
///
/// Not assertions about pixels — SwiftUI output shifts between OS versions and
/// pixel-comparison snapshots would be brittle. These exist so a human (or an
/// agent) can look at the shape while tuning it. Set `CARAFE_RENDER_DIR` to
/// choose the output directory; otherwise they render to a temporary directory
/// and simply verify that rendering produces a non-empty image.
@MainActor
final class RenderSnapshotTests: XCTestCase {
    private var outputDirectory: URL!

    override func setUp() {
        super.setUp()
        if let custom = ProcessInfo.processInfo.environment["CARAFE_RENDER_DIR"] {
            outputDirectory = URL(fileURLWithPath: custom, isDirectory: true)
        } else {
            outputDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("carafe-render-\(UUID().uuidString)", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Rendering helper

    @discardableResult
    private func render(_ name: String, scale: CGFloat = 2, @ViewBuilder content: () -> some View) -> URL? {
        let renderer = ImageRenderer(content: content())
        renderer.scale = scale
        renderer.isOpaque = true

        guard let image = renderer.cgImage else {
            XCTFail("ImageRenderer produced no image for \(name)")
            return nil
        }
        XCTAssertGreaterThan(image.width, 0)
        XCTAssertGreaterThan(image.height, 0)

        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            XCTFail("Could not encode PNG for \(name)")
            return nil
        }
        let url = outputDirectory.appendingPathComponent("\(name).png")
        try? data.write(to: url)
        return url
    }

    /// A contact sheet on the given background, so both appearances can be checked.
    private func sheet<Content: View>(
        scheme: ColorScheme,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(24)
            .background(scheme == .dark ? Color(white: 0.13) : Color(white: 0.97))
            .environment(\.colorScheme, scheme)
    }

    // MARK: - Snapshots

    func testRenderGaugeAcrossFillLevels() {
        for scheme in [ColorScheme.light, .dark] {
            render("gauge-levels-\(scheme == .dark ? "dark" : "light")") {
                sheet(scheme: scheme) {
                    HStack(spacing: 16) {
                        ForEach([1.0, 0.75, 0.5, 0.25, 0.0], id: \.self) { level in
                            VStack(spacing: 6) {
                                CarafeGaugeView(
                                    fillFraction: level,
                                    goalMillilitres: 2000,
                                    unitSystem: .metric
                                )
                                .frame(width: 108, height: 150)

                                Text(UnitSystem.metric.format(millilitres: level * 2000))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    func testRenderFluidOunceGraduations() {
        render("gauge-fluid-ounces") {
            sheet(scheme: .light) {
                CarafeGaugeView(
                    fillFraction: 0.62,
                    goalMillilitres: 64 * UnitSystem.millilitresPerUSFluidOunce,
                    unitSystem: .us
                )
                .frame(width: 150, height: 210)
            }
        }
    }

    func testRenderMenuBarIconSizes() {
        render("menubar-icon", scale: 4) {
            sheet(scheme: .light) {
                HStack(alignment: .bottom, spacing: 18) {
                    ForEach([16.0, 18.0, 22.0, 44.0], id: \.self) { height in
                        CarafeShape()
                            .strokeBorder(.primary, lineWidth: height < 24 ? 1 : 2)
                            .frame(width: height * CarafeShape.aspectRatio, height: height)
                    }
                }
            }
        }
    }

    /// The whole panel, exactly as it appears when the menu bar icon is clicked.
    func testRenderPopoverPanel() {
        for scheme in [ColorScheme.light, .dark] {
            let store = seededStore()
            render("popover-\(scheme == .dark ? "dark" : "light")") {
                PopoverRootView()
                    .environment(store)
                    .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.99))
                    .environment(\.colorScheme, scheme)
            }
        }
    }

    /// The past-day editor, reached by clicking a bar in the history strip.
    func testRenderDayEditor() {
        for scheme in [ColorScheme.light, .dark] {
            let store = seededStore()
            let threeDaysAgo = TestFixtures.calendar.date(
                byAdding: .day, value: -3, to: TestFixtures.date(2026, 8, 28)
            )!

            render("day-editor-\(scheme == .dark ? "dark" : "light")") {
                sheet(scheme: scheme) {
                    DayEditorView(date: threeDaysAgo)
                        .environment(store)
                        .frame(width: 256)
                }
            }
        }
    }

    /// A store with a week of history, a streak, and part of today already drunk.
    private func seededStore() -> HydrationStore {
        let calendar = TestFixtures.calendar
        let clock = MutableClock(TestFixtures.date(2026, 8, 28, hour: 14))
        let fileURL = TestFixtures.temporaryFileURL()

        let today = TestFixtures.date(2026, 8, 28)
        func daysAgo(_ count: Int) -> Date {
            calendar.date(byAdding: .day, value: -count, to: today)!
        }

        HistoryStore(fileURL: fileURL).save([
            TestFixtures.day(daysAgo(6), consumed: 1200),
            TestFixtures.day(daysAgo(5), consumed: 2000),
            TestFixtures.day(daysAgo(4), consumed: 800),
            TestFixtures.day(daysAgo(3), consumed: 2200),
            TestFixtures.day(daysAgo(2), consumed: 2000),
            TestFixtures.day(daysAgo(1), consumed: 2100),
        ])

        let store = HydrationStore(
            historyStore: HistoryStore(fileURL: fileURL),
            defaults: TestFixtures.isolatedDefaults(),
            calendar: calendar,
            now: clock.provider
        )
        store.log(millilitres: 750)
        return store
    }

    func testRenderOutlineLarge() {
        render("outline-large") {
            sheet(scheme: .light) {
                CarafeShape()
                    .strokeBorder(.primary.opacity(0.7), lineWidth: 2)
                    .frame(width: 200, height: 278)
            }
        }
    }
}
