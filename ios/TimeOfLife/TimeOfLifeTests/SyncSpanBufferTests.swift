import Foundation
import Testing
@testable import TimeOfLife

@Suite("SyncSpanBuffer")
struct SyncSpanBufferTests {
    @Test("appends read back in order")
    func appendsReadBackInOrder() async {
        let buffer = SyncSpanBuffer(directory: temporaryDirectory(), maxSpans: 200)
        await buffer.append(makeSpan(outcome: .success, pushed: 1))
        await buffer.append(makeSpan(outcome: .failed, pushed: 2))
        let spans = await buffer.spans()
        #expect(spans.count == 2)
        #expect(spans[0].pushedCount == 1)
        #expect(spans[1].pushedCount == 2)
        #expect(await buffer.bufferedCount == 2)
        #expect(await buffer.droppedSpans == 0)
    }

    @Test("past the cap the incoming span tail-drops and the counter grows")
    func tailDropPastCap() async {
        let buffer = SyncSpanBuffer(directory: temporaryDirectory(), maxSpans: 5)
        for index in 0 ..< 7 {
            await buffer.append(makeSpan(outcome: .success, pushed: index))
        }
        let spans = await buffer.spans()
        // Classic tail-drop: the oldest buffered spans are kept, the two
        // arrivals past the cap are lost — but counted, never silent.
        #expect(spans.count == 5)
        #expect(spans.map(\.pushedCount) == [0, 1, 2, 3, 4])
        #expect(await buffer.droppedSpans == 2)
    }

    @Test("spans and the dropped counter survive a new instance")
    func persistsAcrossInstances() async {
        let directory = temporaryDirectory()
        let first = SyncSpanBuffer(directory: directory, maxSpans: 2)
        await first.append(makeSpan(outcome: .success, pushed: 1))
        await first.append(makeSpan(outcome: .success, pushed: 2))
        await first.append(makeSpan(outcome: .success, pushed: 3))
        let second = SyncSpanBuffer(directory: directory, maxSpans: 2)
        #expect(await second.bufferedCount == 2)
        #expect(await second.droppedSpans == 1)
        #expect(await second.spans().map(\.pushedCount) == [1, 2])
    }

    @Test("dropFirst removes only the sent prefix")
    func dropFirstRemovesPrefix() async {
        let buffer = SyncSpanBuffer(directory: temporaryDirectory(), maxSpans: 200)
        for index in 0 ..< 3 {
            await buffer.append(makeSpan(outcome: .success, pushed: index))
        }
        await buffer.dropFirst(2)
        #expect(await buffer.spans().map(\.pushedCount) == [2])
    }

    @Test("default directory is a telemetry folder outside the account DB")
    func defaultDirectoryIsOutsideAccountDB() {
        let directory = SyncSpanBuffer.defaultDirectory()
        #expect(directory.lastPathComponent == "telemetry")
        #expect(directory.pathExtension.isEmpty)
        #expect(!directory.path.contains(".db"))
        #expect(!directory.lastPathComponent.hasPrefix("lifio_"))
    }

    private func makeSpan(outcome: SyncSessionOutcome, pushed: Int) -> SyncSessionSpan {
        SyncSessionSpan.build(
            start: Date(), end: Date(), outcome: outcome,
            counts: SyncSessionSpanCounts(pushed: pushed)
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
