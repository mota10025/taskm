import Foundation

enum TaskCategory: String, CaseIterable, Codable, Sendable {
    case specra = "SPECRA"
    case contract = "業務委託"
    case personal = "個人"
}
