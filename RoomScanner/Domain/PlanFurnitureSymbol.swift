import Foundation

/// Smart-Bau's equipmentPlanStrokes conventions, mapped from local X/Z to plan X/-Z.
/// The enclosing footprint always uses the scan's measured width, depth and rotation.
struct PlanFurnitureSymbol {
    let footprint: [Point2D]
    let detail: [Segment2D]

    init(_ object: PlacedObject) {
        let transform = Transform2D(translation: object.center, rotation: object.angle)
        func point(_ x: Double, _ z: Double) -> Point2D {
            transform.apply(.init(x: x * object.size.width, y: -z * object.size.depth))
        }
        func line(_ x: Double, _ z: Double, _ endX: Double, _ endZ: Double) -> Segment2D {
            .init(start: point(x,z), end: point(endX,endZ))
        }
        footprint = [point(-0.5,-0.5), point(0.5,-0.5), point(0.5,0.5), point(-0.5,0.5)]
        switch object.category.lowercased() {
        case "chair", "dining-chair":
            detail = [line(-0.5,-0.3,0.5,-0.3)]
        case "sofa", "sofa-2", "sofa-3", "armchair":
            var strokes = [line(-0.37,0.5,-0.37,-0.26), line(-0.37,-0.26,0.37,-0.26), line(0.37,-0.26,0.37,0.5)]
            let family = object.category.lowercased()
            let seats: Int
            switch family {
            case "armchair": seats = 1
            case "sofa-2": seats = 2
            case "sofa-3": seats = 3
            default: seats = object.size.width > 2 ? 3 : 2
            }
            for i in 1..<seats {
                let x = 0.74 * Double(i) / Double(seats) - 0.37
                strokes.append(line(x,-0.26,x,0.5))
            }
            detail = strokes
        default:
            detail = []
        }
    }
}
