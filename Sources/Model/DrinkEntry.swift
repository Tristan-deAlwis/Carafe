import Foundation

/// A single logged drink.
///
/// Volumes are stored in millilitres everywhere in the model layer; conversion
/// to the user's preferred unit happens only at display time. See `UnitSystem`.
struct DrinkEntry: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let millilitres: Double

    init(id: UUID = UUID(), timestamp: Date, millilitres: Double) {
        self.id = id
        self.timestamp = timestamp
        self.millilitres = millilitres
    }
}
