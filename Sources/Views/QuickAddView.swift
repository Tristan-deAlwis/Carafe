import SwiftUI

/// Logging controls: one prominent action for the common case, everything else
/// tucked behind a menu.
///
/// The overwhelmingly frequent interaction is "I drank my usual glass", so that
/// gets the full-width button and every other amount goes in the overflow menu
/// rather than crowding the panel with a row of near-identical buttons.
struct QuickAddView: View {
    @Environment(HydrationStore.self) private var store

    private let controlHeight: CGFloat = 26
    private let cornerRadius: CGFloat = 6

    var body: some View {
        HStack(spacing: 8) {
            logControl
            overflowMenu
        }
    }

    // MARK: - Joined + / − control

    /// Log and remove as a single segmented box.
    ///
    /// Built by hand rather than from two `.borderedProminent` buttons: those carry
    /// their own backgrounds and insets, so butting them together still shows a seam.
    /// Here one shared background is drawn behind both segments, the buttons are
    /// `.plain`, and a hairline divider separates them.
    private var logControl: some View {
        HStack(spacing: 0) {
            Button {
                store.logGlass()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("Log \(store.unitSystem.format(millilitres: store.glassMillilitres))")
                        .font(.system(size: 13, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .frame(height: controlHeight)
                // Without this the gaps between glyph and text are not clickable.
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Log one glass")

            Rectangle()
                .fill(.white.opacity(0.28))
                .frame(width: 1, height: controlHeight)

            Button {
                store.undoLastEntry()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 30, height: controlHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!store.canUndo)
            // A shared background means the disabled segment cannot dim itself, so
            // dim it explicitly.
            .opacity(store.canUndo ? 1 : 0.4)
            .help("Remove the last drink, refilling the carafe")
        }
        .foregroundStyle(.white)
        .background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.accentColor)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    // MARK: - Overflow

    private var overflowMenu: some View {
        Menu {
            Section("Log a different amount") {
                ForEach(otherPresets, id: \.self) { amount in
                    Button(store.unitSystem.format(millilitres: amount)) {
                        store.log(millilitres: amount)
                    }
                }
            }

            Divider()

            Button("Reset today", role: .destructive) {
                store.resetToday()
            }
            .disabled(!store.canUndo)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 24, height: controlHeight)
        .help("More amounts")
    }

    /// Presets excluding the configured glass size, which already has its own button.
    private var otherPresets: [Double] {
        store.unitSystem.glassPresetsMillilitres
            .filter { abs($0 - store.glassMillilitres) > 1 }
    }
}
