import Foundation

/// Presets populate existing design fields only; no new serialized finish cases.
enum StudioFloorPresets {
    struct Tile: Identifiable {
        let name: String
        let color: TechnicalPoint3
        let repeatMetres: Double
        var id: String { name }
    }
    static let tiles: [Tile] = [
        .init(name: "Porcelain · ivory", color: .init(x: 0.88, y: 0.86, z: 0.80), repeatMetres: 0.6),
        .init(name: "Concrete · light grey", color: .init(x: 0.69, y: 0.70, z: 0.69), repeatMetres: 0.6),
        .init(name: "Slate · charcoal", color: .init(x: 0.24, y: 0.27, z: 0.29), repeatMetres: 0.3),
        .init(name: "Terracotta · warm", color: .init(x: 0.64, y: 0.36, z: 0.24), repeatMetres: 0.3),
        .init(name: "Limestone · sand", color: .init(x: 0.73, y: 0.67, z: 0.54), repeatMetres: 0.9),
        .init(name: "Porcelain · white", color: .init(x: 0.94, y: 0.94, z: 0.92), repeatMetres: 0.6)
    ]
}
