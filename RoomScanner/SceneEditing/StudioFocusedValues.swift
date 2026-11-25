import SwiftUI

struct StudioSessionKey: FocusedValueKey {
    typealias Value = SceneEditSession
}

extension FocusedValues {
    var studioSession: SceneEditSession? {
        get { self[StudioSessionKey.self] }
        set { self[StudioSessionKey.self] = newValue }
    }
}
