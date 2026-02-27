import Foundation

struct CategoryItem: Codable, Identifiable, Equatable {
    var name: String
    var color: String // "#82b5d6"
    var textColor: String // "#2a2a2a"

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, color
        case textColor = "text_color"
    }
}
