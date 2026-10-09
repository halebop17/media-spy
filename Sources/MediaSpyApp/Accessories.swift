import AVFoundation
import ImageIO
import SwiftUI

// Preview machinery beyond libmediainfo (which never decodes) — see plan §12:
// thumbnails and waveforms come from AVFoundation, with graceful fallbacks
// for containers it can't open (MKV & friends). Info only — no playback.

// MARK: - Thumbnail

/// Static preview frame, aspect-adaptive: landscape fills width-first,
/// portrait fills height-first, with the file info flowing beside it.
struct ThumbnailView: View {
    let url: URL
    let aspect: CGFloat  // width / height from the *report* (no decode needed)
    let caption: String?
    let chip: String?

    @State private var image: CGImage?
    @State private var failed = false

    private var thumbSize: CGSize {
        let maxHeight: CGFloat = 190
        let maxWidth: CGFloat = 300
        var width = maxHeight * aspect
        var height = maxHeight
        if width > maxWidth {
            width = maxWidth
            height = maxWidth / aspect
        }
        return CGSize(width: max(width, 84), height: height)
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.black.opacity(0.5))

                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: thumbSize.width, height: thumbSize.height)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                } else {
                    // Not decodable (e.g. MKV) or still loading: quiet tile.
                    Image(systemName: failed ? "film" : "photo")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(Ember.label.opacity(failed ? 1 : 0.4))
                }
            }
            .frame(width: thumbSize.width, height: thumbSize.height)
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Ember.hairline))
            .overlay(alignment: .topLeading) {
                if let chip {
                    Text(chip)
                        .font(Ember.mono(8.5, .bold))
                        .foregroundStyle(Ember.textSecondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
                        .padding(6)
                }
            }

            if let caption {
                Text(caption)
                    .font(Ember.mono(9))
                    .foregroundStyle(Ember.label)
            }
        }
        .task(id: url) {
            image = await ThumbnailLoader.frame(for: url)
            failed = image == nil
        }
    }
}

enum ThumbnailLoader {
    /// A representative preview: for video, a frame ~10% in (avoids black leader
    /// frames); for stills, the decoded image itself.
    static func frame(for url: URL) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        if let duration = try? await asset.load(.duration), duration.seconds > 0 {
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 720, height: 720)
            let time = CMTime(seconds: duration.seconds * 0.1, preferredTimescale: 600)
            if let frame = try? await generator.image(at: time).image { return frame }
        }
        // Still image (JPEG/PNG/HEIC/…): decode a downsized thumbnail directly.
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 720,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

// MARK: - Waveform (audio files, screen 2c)

/// Full-width waveform header for audio-only files, with a time ruler.
struct WaveformHero: View {
    let url: URL
    @State private var analysis: AudioAnalysis?

    var body: some View {
        Card {
            VStack(spacing: 8) {
                Group {
                    if let analysis {
                        WaveformBars(peaks: analysis.peaks, tint: Ember.amber)
                    } else {
                        DecorativeWaveform(seed: 7, tint: Ember.amber.opacity(0.35))
                    }
                }
                .frame(height: 88)

                if let analysis {
                    HStack {
                        Text("00:00")
                        Spacer()
                        Text(timestamp(analysis.duration / 2))
                        Spacer()
                        Text(timestamp(analysis.duration))
                    }
                    .font(Ember.mono(8.5))
                    .foregroundStyle(Ember.label)
                }
            }
        }
        .task(id: url) {
            analysis = await AudioAnalyzer.analyze(url: url, bins: 110)
        }
    }

    private func timestamp(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// Peak bars renderer (uniform rounded bars like the design).
struct WaveformBars: View {
    let peaks: [Float]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let count = max(peaks.count, 1)
            let step = proxy.size.width / CGFloat(count)
            let barWidth = min(max(step * 0.62, 1.5), step)  // never wider than its slot
            HStack(alignment: .center, spacing: max(step - barWidth, 0)) {
                ForEach(peaks.indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .fill(tint)
                        .frame(
                            width: barWidth,
                            height: max(3, proxy.size.height * CGFloat(peaks[index]))
                        )
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }
}

/// Seeded pseudo-random bars for streams we deliberately don't decode.
struct DecorativeWaveform: View {
    let seed: Int
    let tint: Color

    var body: some View {
        let peaks: [Float] = {
            var value = UInt64(seed &* 2654435761 &+ 1)
            return (0..<72).map { _ in
                value = value &* 6364136223846793005 &+ 1442695040888963407
                return 0.18 + Float(value >> 33 & 0xFFFF) / 65535 * 0.62
            }
        }()
        WaveformBars(peaks: peaks, tint: tint.opacity(0.55))
    }
}

// MARK: - Channel meters (audio files, screen 2c)

struct ChannelMeters: View {
    let url: URL
    @State private var analysis: AudioAnalysis?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let analysis {
                ForEach(Array(analysis.channelPeaksDB.enumerated()), id: \.offset) { index, decibels in
                    HStack(spacing: 9) {
                        Text(channelName(index, of: analysis.channelPeaksDB.count))
                            .font(Ember.mono(9, .semibold))
                            .foregroundStyle(Ember.label)
                            .frame(width: 16, alignment: .leading)

                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.06))
                                Capsule()
                                    .fill(LinearGradient(
                                        colors: [Ember.amber, Ember.coral, Ember.purple],
                                        startPoint: .leading, endPoint: .trailing
                                    ))
                                    .frame(width: proxy.size.width * normalized(decibels))
                            }
                        }
                        .frame(height: 5)

                        Text(String(format: "%.1f dB", decibels))
                            .font(Ember.mono(9))
                            .foregroundStyle(Ember.textTertiary)
                            .frame(width: 54, alignment: .trailing)
                    }
                }
            }
        }
        .task(id: url) {
            analysis = await AudioAnalyzer.analyze(url: url, bins: 110)
        }
    }

    /// Map −60…0 dBFS onto 0…1.
    private func normalized(_ decibels: Float) -> CGFloat {
        CGFloat(min(max((decibels + 60) / 60, 0), 1))
    }

    private func channelName(_ index: Int, of count: Int) -> String {
        switch count {
        case 1: return "M"
        case 2: return index == 0 ? "L" : "R"
        default: return "C\(index + 1)"
        }
    }
}

// MARK: - Decode + measure

struct AudioAnalysis: Sendable {
    let peaks: [Float]           // per-bin |peak|, normalized 0…1
    let channelPeaksDB: [Float]  // per-channel peak in dBFS
    let duration: Double
}

/// Memoises audio analyses by URL and coalesces concurrent requests for the
/// same file into a single decode — an audio-only report renders both a waveform
/// and channel meters, which would otherwise decode the whole file twice.
private actor AudioAnalysisCache {
    static let shared = AudioAnalysisCache()
    private var tasks: [URL: Task<AudioAnalysis?, Never>] = [:]

    func analysis(for url: URL, bins: Int) async -> AudioAnalysis? {
        if let existing = tasks[url] { return await existing.value }
        let task = Task.detached(priority: .utility) { AudioAnalyzer.decode(url: url, bins: bins) }
        tasks[url] = task
        return await task.value
    }
}

enum AudioAnalyzer {
    /// Chunked one-pass read: waveform bins + per-channel peak levels.
    /// Returns nil for containers AVFoundation can't open (callers fall back
    /// to the decorative pattern). Cached + coalesced per URL.
    static func analyze(url: URL, bins: Int) async -> AudioAnalysis? {
        await AudioAnalysisCache.shared.analysis(for: url, bins: bins)
    }

    /// Synchronous decode. Runs on a background task owned by the cache.
    fileprivate static func decode(url: URL, bins: Int) -> AudioAnalysis? {
        return { () -> AudioAnalysis? in
            guard let file = try? AVAudioFile(forReading: url) else { return nil }
            let format = file.processingFormat
            let totalFrames = AVAudioFramePosition(file.length)
            guard totalFrames > 0 else { return nil }

            let channels = Int(format.channelCount)
            let framesPerBin = max(Int(totalFrames) / bins, 1)
            let chunkSize: AVAudioFrameCount = 1 << 16
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkSize) else { return nil }

            var binPeaks = [Float](repeating: 0, count: bins)
            var channelPeaks = [Float](repeating: 0, count: channels)
            var frameCursor = 0

            while file.framePosition < totalFrames {
                guard (try? file.read(into: buffer)) != nil, buffer.frameLength > 0 else { break }
                guard let data = buffer.floatChannelData else { break }
                let frames = Int(buffer.frameLength)

                for channel in 0..<channels {
                    let samples = data[channel]
                    for frame in 0..<frames {
                        let magnitude = abs(samples[frame])
                        if magnitude > channelPeaks[channel] { channelPeaks[channel] = magnitude }
                        let bin = min((frameCursor + frame) / framesPerBin, bins - 1)
                        if magnitude > binPeaks[bin] { binPeaks[bin] = magnitude }
                    }
                }
                frameCursor += frames
            }

            let ceiling = max(binPeaks.max() ?? 1, 0.0001)
            return AudioAnalysis(
                peaks: binPeaks.map { $0 / ceiling },
                channelPeaksDB: channelPeaks.map { 20 * log10(max($0, 0.000001)) },
                duration: Double(totalFrames) / format.sampleRate
            )
        }()
    }
}
