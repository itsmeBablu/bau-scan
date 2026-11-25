import XCTest
import AVFoundation
@testable import RoomScanner

final class VoiceNotesExportTests: XCTestCase {
    func testSyntheticAACAndTextOnlyArchivesHaveCorrectMediaSelection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let clip = root.appendingPathComponent("synthetic.m4a")
        do {
            let file = try AVAudioFile(forWriting:clip,settings:[AVFormatIDKey:kAudioFormatMPEG4AAC,AVSampleRateKey:22050,AVNumberOfChannelsKey:1,AVEncoderBitRateKey:32000])
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat:file.processingFormat,frameCapacity:22050))
            buffer.frameLength = 22050
            if let channels = buffer.floatChannelData {
                for channel in 0..<Int(buffer.format.channelCount) { channels[channel].initialize(repeating:0,count:Int(buffer.frameLength)) }
            } else { XCTFail("Expected floating-point PCM buffer"); return }
            try file.write(from:buffer)
        }
        let source = ProjectReference(kind:.room,itemID:UUID(),library:"local"),project = UUID()
        var note = ARNote(projectID:project,reference:source,number:1,level:nil,roomID:source.itemID,position:nil,planPosition:nil,language:"de-DE")
        note.title = "Pumpe"; note.audioFileName = "note-01.m4a"; note.audioDuration = 1
        let bytes = try Data(contentsOf:clip)
        try ARNoteStore.update(root:root,projectID:project,audio:[note.id:bytes]) { $0.notes.append(note) }
        for audio in [false,true] {
            let archive = root.appendingPathComponent(audio ? "audio.zip" : "text.zip")
            try VoiceNotesExporter.export(root:root,projectID:project,references:[source],includeAudio:audio,to:archive)
            let paths = try ZipInspector.listEntries(in:archive)
            XCTAssertEqual(paths.contains(where:{ $0.hasSuffix(".m4a") }),audio)
            XCTAssertTrue(paths.contains(where:{ $0.hasSuffix("voice-notes-index.json") }))
            XCTAssertTrue(paths.contains(where:{ $0.hasSuffix("voice-notes-index.csv") }))
        }
        let unrelated = root.appendingPathComponent("unrelated.zip")
        try VoiceNotesExporter.export(root:root,projectID:project,references:[],includeAudio:true,to:unrelated)
        XCTAssertFalse(try ZipInspector.listEntries(in:unrelated).contains { $0.hasSuffix(".m4a") })
    }
}
