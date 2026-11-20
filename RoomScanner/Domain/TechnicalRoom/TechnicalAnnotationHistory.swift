import Foundation

/// Value-based annotation history, independent of either scanner lifecycle.
struct TechnicalAnnotationHistory {
    enum EditError: Error { case alignmentRequired, invalidPipe, duplicateID }
    private(set) var room: TechnicalRoom
    private var undoStack: [TechnicalRoom] = []
    private var redoStack: [TechnicalRoom] = []

    init(room: TechnicalRoom) { self.room = room }

    mutating func addPipe(_ pipe: TechnicalPipeRun, capture: TechnicalCaptureState) throws {
        guard capture.canAnnotate else { throw EditError.alignmentRequired }
        guard pipe.surfaceHits.count >= 2, pipe.outerDiameterMm.value > 0,
              pipe.surfaceHits.allSatisfy({
                  let n = $0.normal.value
                  return n.x.isFinite && n.y.isFinite && n.z.isFinite &&
                      n.x * n.x + n.y * n.y + n.z * n.z > 1e-12
              }) else { throw EditError.invalidPipe }
        guard !room.pipeRuns.contains(where: { $0.id == pipe.id }) else { throw EditError.duplicateID }
        undoStack.append(room)
        redoStack.removeAll()
        room.pipeRuns.append(pipe)
    }

    mutating func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(room)
        room = previous
    }

    mutating func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(room)
        room = next
    }
}
