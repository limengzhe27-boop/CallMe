import AVFoundation
import Foundation

enum ConversionError: Error {
    case invalidArguments
    case unsupportedFormat
    case conversionFailed(String)
}

guard CommandLine.arguments.count == 3 else {
    throw ConversionError.invalidArguments
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
// Decode compressed input into a stable PCM client format first. Some MP3 files
// expose a packet format that AVAudioConverter cannot accept directly.
let inputFile = try AVAudioFile(
    forReading: inputURL,
    commonFormat: .pcmFormatFloat32,
    interleaved: false
)
let inputFormat = inputFile.processingFormat

guard let outputFormat = AVAudioFormat(
    commonFormat: .pcmFormatInt16,
    sampleRate: 44_100,
    channels: 1,
    interleaved: false
), let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
    throw ConversionError.unsupportedFormat
}

let inputBuffer = AVAudioPCMBuffer(
    pcmFormat: inputFormat,
    frameCapacity: AVAudioFrameCount(inputFile.length)
)!
try inputFile.read(into: inputBuffer)

let estimatedFrames = AVAudioFrameCount(
    ceil(Double(inputBuffer.frameLength) * outputFormat.sampleRate / inputFormat.sampleRate)
) + 1_024
try? FileManager.default.removeItem(at: outputURL)
var outputFile: AVAudioFile? = try AVAudioFile(
    forWriting: outputURL,
    settings: outputFormat.settings,
    commonFormat: .pcmFormatInt16,
    interleaved: false
)
var suppliedInput = false
var totalFrames: AVAudioFramePosition = 0

for _ in 0..<10 {
    let outputBuffer = AVAudioPCMBuffer(
        pcmFormat: outputFormat,
        frameCapacity: estimatedFrames
    )!
    var conversionError: NSError?
    let status = converter.convert(to: outputBuffer, error: &conversionError) { _, inputStatus in
        if suppliedInput {
            inputStatus.pointee = .endOfStream
            return nil
        }
        suppliedInput = true
        inputStatus.pointee = .haveData
        return inputBuffer
    }

    if let conversionError {
        throw conversionError
    }
    guard status != .error else {
        throw ConversionError.conversionFailed("AVAudioConverter returned an error")
    }
    if outputBuffer.frameLength > 0 {
        try outputFile?.write(from: outputBuffer)
        totalFrames += AVAudioFramePosition(outputBuffer.frameLength)
    }
    if status == .endOfStream {
        break
    }
}

guard totalFrames > 0 else {
    throw ConversionError.conversionFailed("No audio frames were produced")
}
outputFile = nil
print("Converted \(inputURL.lastPathComponent) -> \(outputURL.lastPathComponent)")
