import CatGameCore

/// Browsing only: filtering never changes ownership, price, or purchase eligibility.
enum ShopBrowser {
    enum Filter: String { case all, floor, wall, standard, premium }
    static let newFurnitureIDs: Set<String> = ["oak_bookcase", "rattan_chair", "round_side_table", "sunrise_art"]

    static func filters(for category: ShopCategory) -> [Filter] {
        switch category {
        case .supplies: [.all, .standard, .premium]
        case .furniture: [.all, .floor, .wall, .standard, .premium]
        case .equipment: []
        }
    }

    @MainActor
    static func products(in category: ShopCategory, filter: Filter) -> [ShopListing] {
        let products = ShopListing.list(category)
        let filter = filters(for: category).contains(filter) ? filter : .all
        switch category {
        case .supplies:
            let premium = products.filter {
                if case .supply(let kind) = $0.kind { return kind.isPremium }
                return false
            }
            let standard = products.filter {
                if case .supply(let kind) = $0.kind { return !kind.isPremium }
                return false
            }
            return filter == .premium ? premium : filter == .standard ? standard : premium + standard
        case .furniture:
            // The shipped catalog has no premium tier; do not invent products or price-based rarity.
            if filter == .premium { return [] }
            let matching = products.filter { product in
                guard filter == .floor || filter == .wall else { return true }
                guard let offer = ShopCatalog.furnitureOffer(id: product.id) else { return false }
                return FurnitureCatalog.metadata(for: offer.kind).isWall == (filter == .wall)
            }
            return matching.filter { newFurnitureIDs.contains($0.id) } + matching.filter { !newFurnitureIDs.contains($0.id) }
        case .equipment: return products
        }
    }

    static func pageSize(accessibility: Bool) -> Int { accessibility ? 2 : 6 }

    static func pageCount(for count: Int, pageSize: Int) -> Int {
        count > 0 ? (count - 1) / max(1, pageSize) + 1 : 1
    }

    static func clampedPage(_ page: Int, count: Int, pageSize: Int) -> Int {
        min(max(0, page), pageCount(for: count, pageSize: pageSize) - 1)
    }

    static func pageRange(_ page: Int, count: Int, pageSize: Int) -> Range<Int> {
        let count = max(0, count)
        let size = max(1, pageSize)
        let lower = clampedPage(page, count: count, pageSize: size) * size
        return lower..<(lower + min(size, count - lower))
    }
}
