import Foundation

enum SupportedRuntime {
    static let minimumSyncthingVersion = "2.0.0"

    static func isSupported(version: String) -> Bool {
        SemanticVersion.compare(version, minimumSyncthingVersion) != .orderedAscending
    }
}

enum SemanticVersion {
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsComponents = normalizedComponents(for: lhs)
        let rhsComponents = normalizedComponents(for: rhs)
        let maxCount = max(lhsComponents.count, rhsComponents.count)

        for index in 0..<maxCount {
            let lhsValue = index < lhsComponents.count ? lhsComponents[index] : 0
            let rhsValue = index < rhsComponents.count ? rhsComponents[index] : 0

            if lhsValue < rhsValue {
                return .orderedAscending
            }
            if lhsValue > rhsValue {
                return .orderedDescending
            }
        }

        return .orderedSame
    }

    private static func normalizedComponents(for version: String) -> [Int] {
        version
            .trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            .split(separator: ".")
            .map { component in
                Int(component.filter(\.isNumber)) ?? 0
            }
    }
}
