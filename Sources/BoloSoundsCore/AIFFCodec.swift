import AVFoundation
import Foundation

/// The `PNGCodec.swift` analogue: writes a `SampleBuffer` to an AIFF file on disk via
/// `AVAudioFile`. Unlike `PNGCodec.swift`'s pure `[UInt8] -> Data` shape, `AVAudioFile`'s API is
/// URL-based rather than in-memory -- writing directly to a file URL is simpler here since
/// `BoloSounds/main.swift` already targets an output directory (disclosed deviation from the
/// glyph precedent, per the C.3 pre-brief's own note).
///
/// Format: 44.1kHz, mono, 16-bit signed PCM, big-endian -- matches the reference's own on-disk
/// AIFF format exactly (confirmed via `afinfo` against `explosion.aiff`).
public enum AIFFCodec {
    public static func write(_ buffer: SampleBuffer, to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: buffer.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: true,
            AVLinearPCMIsFloatKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatInt16, interleaved: false)

        guard let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: buffer.sampleRate, channels: 1, interleaved: false) else {
            throw NSError(domain: "BoloSoundsCore.AIFFCodec", code: 1, userInfo: [NSLocalizedDescriptionKey: "could not create PCM format"])
        }
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(buffer.samples.count)) else {
            throw NSError(domain: "BoloSoundsCore.AIFFCodec", code: 2, userInfo: [NSLocalizedDescriptionKey: "could not allocate PCM buffer"])
        }
        pcmBuffer.frameLength = AVAudioFrameCount(buffer.samples.count)
        guard let channelData = pcmBuffer.int16ChannelData else {
            throw NSError(domain: "BoloSoundsCore.AIFFCodec", code: 3, userInfo: [NSLocalizedDescriptionKey: "PCM buffer has no int16 channel data"])
        }
        for (i, sample) in buffer.samples.enumerated() {
            let clamped = max(-1.0, min(1.0, sample))
            channelData[0][i] = Int16((clamped * Float(Int16.max)).rounded())
        }

        try file.write(from: pcmBuffer)
    }
}
