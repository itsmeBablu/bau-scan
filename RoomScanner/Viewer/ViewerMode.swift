import Foundation
import Observation

/// Gesture values are relative to each gesture's start, not the previous event.
struct ViewerPlanNavigation {
    private(set) var pan: CGSize = .zero
    private(set) var zoom: CGFloat = 1
    private var committedPan: CGSize = .zero
    private var committedZoom: CGFloat = 1
    mutating func drag(_ translation: CGSize) {
        pan = CGSize(width: committedPan.width+translation.width,height: committedPan.height+translation.height)
    }
    mutating func endDrag(_ translation: CGSize) { drag(translation); committedPan = pan }
    mutating func magnify(_ scale: CGFloat) { zoom = min(max(committedZoom*scale,0.4),6) }
    mutating func endMagnify(_ scale: CGFloat) { magnify(scale); committedZoom = zoom }
}

/// Viewer modes: 3D orbit, 2D top-down view, AR (iOS).
enum ViewerMode: String, CaseIterable, Identifiable {
    case threeD, twoD, ar
    var id: String { rawValue }

    var titleKey: String {
        switch self { case .threeD: "viewer.mode.3d"; case .twoD: "viewer.mode.2d"; case .ar: "viewer.mode.ar" }
    }

    static var available: [ViewerMode] {
        #if os(iOS)
        return [.threeD, .twoD, .ar]
        #else
        return [.threeD, .twoD]
        #endif
    }
}

/// AR tabletop model scale factor.
enum ARScale: Double, CaseIterable, Identifiable {
    case oneToTwenty = 0.05
    case oneToFifty = 0.02
    case real = 1
    var id: Double { rawValue }
    var label: String {
        switch self { case .oneToTwenty: "1:20"; case .oneToFifty: "1:50"; case .real: "1:1" }
    }
}

/// Shared viewer state (controls ↔ scene).
@Observable
@MainActor
final class ViewerState {
    var mode: ViewerMode = .threeD
    var showDimensions = false
    var showObjects = true
    var isMeasuring = false
    var arScale: ARScale = .oneToFifty
    /// Incremented to request recentering or anchor reset.
    var resetToken = 0
}
