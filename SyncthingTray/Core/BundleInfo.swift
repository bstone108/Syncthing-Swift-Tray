import Foundation

extension Bundle {
    var appVersionString: String {
        if let version = object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String, version.isEmpty == false {
            return version
        }

        if let build = object(forInfoDictionaryKey: "CFBundleVersion") as? String, build.isEmpty == false {
            return build
        }

        return "dev"
    }
}
