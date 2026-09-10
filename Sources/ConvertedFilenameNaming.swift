import Foundation

/// Builds the filename proposed for image outputs produced by the shared transform
/// pipeline. The appendage is user-configurable, while `-kechil` preserves the
/// naming used before the preference was introduced.
enum ConvertedFilenameNaming {
    static let defaultAppendage = "-kechil"
    static let maximumAppendageLength = 64

    static func filename(sourceURL: URL, outputExtension: String,
                         appendage: String, includeResolution: Bool = false,
                         width: Int? = nil, height: Int? = nil) -> String {
        let base = sourceURL.deletingPathExtension().lastPathComponent
        let resolution = resolutionAppendage(includeResolution: includeResolution,
                                              width: width, height: height)
        return "\(base)\(sanitisedAppendage(appendage))\(resolution).\(outputExtension)"
    }

    /// Keep the setting useful as filename text without turning it into a path.
    /// Leading/trailing whitespace is accidental in a suffix field, but spaces and
    /// Unicode inside the value remain available for descriptive names.
    static func sanitisedAppendage(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let forbidden = CharacterSet.controlCharacters
            .union(CharacterSet(charactersIn: "/:\\"))
        let scalars = trimmed.unicodeScalars.prefix(maximumAppendageLength).map {
            forbidden.contains($0) ? "-" : String($0)
        }
        return scalars.joined()
    }

    static func resolutionAppendage(includeResolution: Bool,
                                     width: Int?, height: Int?) -> String {
        guard includeResolution, let width, let height, width > 0, height > 0 else {
            return ""
        }
        return "-\(width)x\(height)"
    }
}
