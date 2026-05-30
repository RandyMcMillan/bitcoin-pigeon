import Foundation

func composeProtocolID(prefix: String, version: String) -> String {
    "\(prefix.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/\(version.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
}
