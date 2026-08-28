import SwiftUI

/// Logging controls: one prominent action for the common case, everything else
/// tucked behind a menu.
///
/// The overwhelmingly frequent interaction is "I drank my usual glass", so that
/// gets the full-width button and every other amount goes in the overflow menu
/// rather than crowding the panel with a row of near-identical buttons.
struct QuickAddView: View {
    @Environment(HydrationStore.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            Button {
                store.undoLastEntry()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 28, height: 26)
            }
            .buttonStyle(.bordered)
            .disabled(!store.canUndo)
            .help("Undo the last drink")

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
                .frame(height: 26)
            }
            .buttonStyle(.borderedProminent)
            .help("Log one glass")

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
            .frame(width: 24, height: 26)
            .help("More amounts")
        }
    }

    /// Presets excluding the configured glass size, which already has its own button.
    private var otherPresets: [Double] {
        store.unitSystem.glassPresetsMillilitres
            .filter { abs($0 - store.glassMillilitres) > 1 }
    }
}
