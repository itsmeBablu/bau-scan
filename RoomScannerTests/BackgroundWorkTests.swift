import XCTest
@testable import RoomScanner

final class BackgroundWorkTests: XCTestCase {
    private enum Failure: Error { case disk }

    func testWorkerReturnsBytesAndPreservesTheOriginalError() async throws {
        let bytes = try await BackgroundWork.run { Data("fixture".utf8) }
        XCTAssertEqual(bytes, Data("fixture".utf8))
        do {
            let _: Data = try await BackgroundWork.run { throw Failure.disk }
            XCTFail("Expected the original I/O error")
        } catch Failure.disk {} catch { throw error }
    }

    func testCancellationReachesRunningWorker() async throws {
        let started = AsyncStream<Void>.makeStream()
        let job = Task {
            try await BackgroundWork.run {
                started.continuation.yield(())
                try await Task.sleep(for: .seconds(10))
                return 1
            }
        }
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()
        job.cancel()
        defer { started.continuation.finish() }
        do { _ = try await job.value; XCTFail("Cancelled operation returned success") }
        catch is CancellationError {} catch { throw error }
    }

    func testWorkerThatCatchesCancellationCannotPublishLateSuccess() async throws {
        let started = AsyncStream<Void>.makeStream()
        let job = Task {
            try await BackgroundWork.run {
                started.continuation.yield(())
                do { try await Task.sleep(for: .seconds(10)) } catch is CancellationError {}
                return 7
            }
        }
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()
        job.cancel()
        defer { started.continuation.finish() }
        do { _ = try await job.value; XCTFail("Late successful result must be discarded") }
        catch is CancellationError {} catch { throw error }
    }
}
