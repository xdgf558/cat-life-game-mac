import Foundation
import CatGameCore

enum CatArtwork {
    static func asset(_ baseName: String, appearance: CatAppearance) -> String {
        switch appearance {
        case .orange: return baseName
        case .cow: return baseName.replacingOccurrences(of: "cat-", with: "cat-cow-")
        case .blue: return baseName.replacingOccurrences(of: "cat-", with: "cat-blue-")
        case .siamese: return baseName.replacingOccurrences(of: "cat-", with: "cat-siamese-")
        case .silver: return baseName.replacingOccurrences(of: "cat-", with: "cat-silver-")
        // 2.5: the Station Cat borrows Milk's sheets until its own art (ArtSource/CatBreeds/station) lands;
        // CatAtlasRegistration and CatActor use Milk's measurements for it until then.
        case .station: return baseName.replacingOccurrences(of: "cat-", with: "cat-cow-")
        }
    }
}
