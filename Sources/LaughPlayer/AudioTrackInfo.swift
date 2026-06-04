import AVFoundation
import Foundation

/// Maps ISO language codes to localized display names (e.g. `en` → English).
enum AudioTrackLanguageDisplay {
    private static let iso639_2To639_1: [String: String] = [
        "eng": "en", "deu": "de", "ger": "de", "fra": "fr", "fre": "fr",
        "spa": "es", "ita": "it", "jpn": "ja", "por": "pt", "rus": "ru",
        "kor": "ko", "zho": "zh", "chi": "zh", "dut": "nl", "nld": "nl",
        "pol": "pl", "swe": "sv", "dan": "da", "nor": "no", "fin": "fi",
        "hun": "hu", "ces": "cs", "cze": "cs", "ell": "el", "gre": "el",
        "heb": "he", "ara": "ar", "hin": "hi", "tha": "th", "vie": "vi",
        "tur": "tr", "ukr": "uk", "rum": "ro", "ron": "ro"
    ]

    static func displayName(for raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let lower = raw.lowercased()
        if lower == "und" || lower == "undefined" || lower == "unknown" {
            return nil
        }

        if !isLikelyLanguageCode(raw) {
            return raw
        }

        let primary = lower.split(separator: "-").first.map(String.init) ?? lower
        if let name = localizedName(forISOCode: primary) {
            return name
        }
        if primary.count == 3, let iso1 = iso639_2To639_1[primary], let name = localizedName(forISOCode: iso1) {
            return name
        }
        return raw
    }

    private static func isLikelyLanguageCode(_ raw: String) -> Bool {
        let t = raw.lowercased()
        if t.count == 2, t.allSatisfy(\.isLetter) { return true }
        if t.count == 3, t.allSatisfy(\.isLetter) { return true }
        if t.range(of: #"^[a-z]{2,3}(-[a-z]{2,3})?$"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private static func localizedName(forISOCode code: String) -> String? {
        guard let name = Locale.current.localizedString(forLanguageCode: code) else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != code.lowercased() else { return nil }
        return trimmed
    }
}

/// One selectable embedded audio stream in the current file.
struct AudioTrackInfo: Equatable {
    enum BackendID: Equatable {
        case avFoundation(optionIndex: Int)
        case mpv(trackID: Int)
    }

    let backendID: BackendID
    /// 1-based index shown in the picker.
    let displayIndex: Int
    let language: String?
    let channelCount: Int?
    let codec: String?
    let bitrateKbps: Int?

    var menuTitle: String {
        var parts = ["#\(displayIndex)"]
        if let language, !language.isEmpty {
            parts.append(language)
        }
        if let channelCount, channelCount > 0 {
            parts.append("\(channelCount) ch")
        }
        if let codec, !codec.isEmpty {
            parts.append(codec)
        }
        if let bitrateKbps, bitrateKbps > 0 {
            parts.append("\(bitrateKbps) kbps")
        }
        return parts.joined(separator: " · ")
    }
}

enum AudioTrackCatalog {
    static func tracks(from asset: AVAsset) async throws -> [AudioTrackInfo] {
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard !audioTracks.isEmpty else { return [] }

        if let group = try await asset.loadMediaSelectionGroup(for: .audible), !group.options.isEmpty {
            var result: [AudioTrackInfo] = []
            for (index, option) in group.options.enumerated() {
                let details = index < audioTracks.count
                    ? try await detailsForTrack(audioTracks[index])
                    : (language: nil as String?, codec: nil as String?, channels: nil as Int?, bitrateKbps: nil as Int?)
                let rawLanguage = option.locale?.identifier ?? option.displayName
                result.append(
                    AudioTrackInfo(
                        backendID: .avFoundation(optionIndex: index),
                        displayIndex: index + 1,
                        language: AudioTrackLanguageDisplay.displayName(for: rawLanguage),
                        channelCount: details.channels,
                        codec: details.codec,
                        bitrateKbps: details.bitrateKbps
                    )
                )
            }
            return result
        }

        var result: [AudioTrackInfo] = []
        for (index, track) in audioTracks.enumerated() {
            let details = try await detailsForTrack(track)
            result.append(
                AudioTrackInfo(
                    backendID: .avFoundation(optionIndex: index),
                    displayIndex: index + 1,
                    language: AudioTrackLanguageDisplay.displayName(for: details.language),
                    channelCount: details.channels,
                    codec: details.codec,
                    bitrateKbps: details.bitrateKbps
                )
            )
        }
        return result
    }

    static func tracks(fromMpvTrackList data: Any?) -> [AudioTrackInfo] {
        guard let list = data as? [[String: Any]] else { return [] }
        var result: [AudioTrackInfo] = []
        var audioIndex = 0
        for entry in list {
            guard (entry["type"] as? String) == "audio" else { continue }
            guard let id = MpvJSONValue.int(from: entry["id"]) else { continue }
            audioIndex += 1
            let lang = (entry["lang"] as? String) ?? (entry["language"] as? String)
            let channels = entry["demux-channel-count"] as? Int
                ?? (entry["demux-channel-count"] as? NSNumber)?.intValue
            let codec = entry["codec"] as? String
            let bitrate = entry["demux-bitrate"] as? Int
                ?? (entry["demux-bitrate"] as? NSNumber)?.intValue
            let bitrateKbps = bitrate.map { max(1, $0 / 1000) }
            result.append(
                AudioTrackInfo(
                    backendID: .mpv(trackID: id),
                    displayIndex: audioIndex,
                    language: AudioTrackLanguageDisplay.displayName(for: lang),
                    channelCount: channels,
                    codec: codec,
                    bitrateKbps: bitrateKbps
                )
            )
        }
        return result
    }

    static func selectedMpvTrackID(fromMpvTrackList data: Any?) -> Int? {
        guard let list = data as? [[String: Any]] else { return nil }
        for entry in list {
            guard (entry["type"] as? String) == "audio" else { continue }
            let selected = (entry["selected"] as? Bool) == true
                || (entry["selected"] as? NSNumber)?.boolValue == true
            if selected, let id = MpvJSONValue.int(from: entry["id"]) { return id }
        }
        return nil
    }

    private static func detailsForTrack(_ track: AVAssetTrack) async throws -> (
        language: String?,
        codec: String?,
        channels: Int?,
        bitrateKbps: Int?
    ) {
        let formats = try await track.load(.formatDescriptions)
        var codec: String?
        var channels: Int?
        if let first = formats.first {
            let subType = CMFormatDescriptionGetMediaSubType(first)
            codec = fourCCString(subType)
            if let desc = CMAudioFormatDescriptionGetStreamBasicDescription(first)?.pointee {
                channels = Int(desc.mChannelsPerFrame)
            }
        }
        let language = try await track.load(.languageCode)
        let estimated = try await track.load(.estimatedDataRate)
        let bitrateKbps = estimated > 0 ? Int(estimated / 1000) : nil
        return (language, codec, channels, bitrateKbps)
    }

    private static func fourCCString(_ code: FourCharCode) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xff),
            UInt8((code >> 16) & 0xff),
            UInt8((code >> 8) & 0xff),
            UInt8(code & 0xff)
        ]
        let printable = bytes.allSatisfy { $0 >= 32 && $0 < 127 }
        if printable {
            return String(bytes: bytes, encoding: .ascii) ?? String(format: "%08x", code)
        }
        return String(format: "%08x", code)
    }
}

enum AudioTrackPickerOption {
    static let noneMenuTitle = "None"
}

enum NativeAudioTrackSelection {
    @MainActor
    static func disableAudio(on playerItem: AVPlayerItem) async -> Bool {
        do {
            let asset = playerItem.asset
            if let group = try await asset.loadMediaSelectionGroup(for: .audible) {
                playerItem.select(nil, in: group)
            }
            return true
        } catch {
            return false
        }
    }

    @MainActor
    static func isAudioDisabled(for playerItem: AVPlayerItem) async -> Bool {
        do {
            let asset = playerItem.asset
            guard let group = try await asset.loadMediaSelectionGroup(for: .audible) else {
                return false
            }
            return playerItem.currentMediaSelection.selectedMediaOption(in: group) == nil
        } catch {
            return false
        }
    }

    @MainActor
    static func select(track: AudioTrackInfo, on playerItem: AVPlayerItem) async -> Bool {
        guard case .avFoundation(let optionIndex) = track.backendID else { return false }
        do {
            let asset = playerItem.asset
            guard let group = try await asset.loadMediaSelectionGroup(for: .audible),
                  optionIndex >= 0, optionIndex < group.options.count else {
                return false
            }
            let option = group.options[optionIndex]
            playerItem.select(option, in: group)
            return true
        } catch {
            return false
        }
    }

    @MainActor
    static func selectedOptionIndex(for playerItem: AVPlayerItem) async -> Int? {
        do {
            let asset = playerItem.asset
            guard let group = try await asset.loadMediaSelectionGroup(for: .audible),
                  let selected = playerItem.currentMediaSelection.selectedMediaOption(in: group),
                  let index = group.options.firstIndex(of: selected) else {
                return nil
            }
            return index
        } catch {
            return nil
        }
    }
}
