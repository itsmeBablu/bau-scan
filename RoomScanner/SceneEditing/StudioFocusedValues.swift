import SwiftUI

struct StudioSessionKey: FocusedValueKey {
    typealias Value = SceneEditSession
}

extension FocusedValues {
    var studioViewportSession: SceneEditSession? {
        get { self[StudioViewportSessionKey.self] }
        set { self[StudioViewportSessionKey.self] = newValue }
    }
    var studioSession: SceneEditSession? {
        get { self[StudioSessionKey.self] }
        set { self[StudioSessionKey.self] = newValue }
    }
}
struct StudioViewportSessionKey: FocusedValueKey { typealias Value = SceneEditSession }
