import Foundation
import Observation
import CatGameCore

@Observable
@MainActor
final class GameLocalization {
    static let shared = GameLocalization()
    var language: GameLanguage = .preferred(in: Locale.preferredLanguages)

    private init() {}
}

@MainActor
enum GameStrings {
    static func text(_ key: String) -> String {
        let dictionary: [String: String]
        switch GameLocalization.shared.language {
        case .simplifiedChinese: dictionary = chinese
        case .traditionalChinese: dictionary = traditionalChinese
        case .english: dictionary = english
        }
        return dictionary[key] ?? chinese[key] ?? key
    }

    static func format(_ key: String, _ values: CVarArg...) -> String {
        String(format: text(key), locale: Locale(identifier: GameLocalization.shared.language.rawValue), arguments: values)
    }

    static func furnitureName(_ item: FurnitureItem) -> String {
        if item.id == "plantLarge" { return text("furniture.plantLarge") }
        if item.id == "plantSmall" { return text("furniture.plantSmall") }
        return text(FurnitureCatalog.metadata(for: item.kind).nameKey)
    }

    static func catName(_ cat: CatState) -> String {
        if let customName = cat.customName { return customName }
        if cat.id == CatCatalog.initialCatID, cat.name == "小橘" { return text("cat.defaultName") }
        if let offer = CatCatalog.adoptionOffer(catID: cat.id), cat.name == offer.name { return catAdoptionName(offer) }
        return cat.name
    }

    static func catAdoptionName(_ offer: CatAdoptionOffer) -> String {
        text(offer.appearance == .orange ? "cat.defaultName" : "cat.\(offer.appearance.rawValue)Name")
    }

    static func catDescription(_ appearance: CatAppearance) -> String {
        text("cat.\(appearance.rawValue)Description")
    }
}
