import SwiftUI
import CatGameCore

@MainActor
struct HospitalView: View {
    @Bindable var store: GameStore
    @State private var path: [String]
    @State private var page = 0
    @State private var isSaving = false
    private let pageSize = 4

    private var cats: [CatState] {
        (store.snapshot?.cats ?? []).enumerated().sorted {
            let firstSick = $0.element.healthState?.illness != nil
            let secondSick = $1.element.healthState?.illness != nil
            return firstSick == secondSick ? $0.offset < $1.offset : firstSick
        }.map(\.element)
    }
    private var pageCount: Int { max(1, (cats.count + pageSize - 1) / pageSize) }
    private var currentPage: Int { min(page, pageCount - 1) }
    private var visibleCats: [CatState] { Array(cats.dropFirst(currentPage * pageSize).prefix(pageSize)) }
    private var sickCount: Int { cats.filter { $0.healthState?.illness != nil }.count }

    init(store: GameStore, initialCatID: String? = nil) {
        self.store = store
        _path = State(initialValue: initialCatID.map { [$0] } ?? [])
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                HospitalHeader(title: "hospital.title", back: "tab.town", gold: store.snapshot?.player.gold ?? 0,
                               backID: "hospitalBackToTown") { store.activeSheet = .town }
                directory
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: String.self) { catID in
                HospitalCatDetailView(store: store, catID: catID, isSaving: $isSaving,
                                      onBack: { if !path.isEmpty { path.removeLast() } },
                                      onDirectory: { path.removeAll() }) {
                    store.activeSheet = .work
                }
            }
        }
        .fontDesign(.rounded).foregroundStyle(RoomTheme.ink).tint(RoomTheme.darkMint)
        .environment(\.locale, Locale(identifier: store.language.rawValue))
        .onChange(of: cats.count) { _, _ in page = currentPage }
    }

    private var directory: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                Text(GameStrings.text("hospital.selectCat"))
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                if cats.isEmpty {
                    Text(GameStrings.text("hospital.empty"))
                        .font(.body).foregroundStyle(RoomTheme.secondary)
                        .padding(24).frame(maxWidth: .infinity).gameCard()
                        .accessibilityIdentifier("hospitalEmpty")
                } else {
                    ForEach(visibleCats) { cat in
                        Button { path.append(cat.id) } label: { catRow(cat) }
                            .buttonStyle(.plain).accessibilityIdentifier("hospitalCat_\(cat.id)")
                    }
                    if pageCount > 1 { pagination }
                    prevention
                }
                Text(GameStrings.text("hospital.gentleHint"))
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(RoomTheme.cream).accessibilityIdentifier("hospitalDirectoryScroll")
    }

    private var hero: some View {
        Color.clear.frame(height: 148)
            .overlay {
                GeometryReader { geometry in
                    Image(decorative: "hospital-reception").resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
            }
            .overlay(alignment: .bottomLeading) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .bottom, spacing: 6) {
                        heroSummary.fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 0)
                        if sickCount > 0 { sickBadge.fixedSize() }
                    }
                    heroSummary.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26))
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(.white, lineWidth: 3))
            .compositingGroup()
            .shadow(color: RoomTheme.ink.opacity(0.08), radius: 0, y: 4)
            .accessibilityElement(children: .contain)
    }

    private var heroSummary: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(GameStrings.text("hospital.subtitle")).font(.system(size: 14, weight: .heavy))
            Text(GameStrings.format("hospital.summary", sickCount, cats.count))
                .font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                .accessibilityIdentifier("hospitalSummary").accessibilityValue("\(sickCount)/\(cats.count)")
        }
        .fixedSize(horizontal: false, vertical: true).padding(10)
        .background(RoomTheme.paper.opacity(0.96), in: RoundedRectangle(cornerRadius: 17))
    }

    private var sickBadge: some View {
        Label(GameStrings.format("hospital.awaitingCount", sickCount), systemImage: "cross.case.fill")
            .font(.system(size: 11, weight: .heavy)).foregroundStyle(.white)
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(RoomTheme.coral, in: Capsule())
            .overlay(Capsule().strokeBorder(.white, lineWidth: 2))
    }

    private func catRow(_ cat: CatState) -> some View {
        let sick = cat.healthState?.illness != nil
        return HStack(spacing: 12) {
            HospitalCatPortrait(cat: cat, size: 58, status: true)
            VStack(alignment: .leading, spacing: 7) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        catName(cat)
                        Text(GameStrings.text("hospital.coat.\(cat.appearance.rawValue)"))
                            .font(.system(size: 11, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                    }
                    catName(cat)
                }
                HospitalStatusPill(cat: cat, now: store.now)
                HStack(spacing: 6) {
                    Image(systemName: "heart.fill").foregroundStyle(sick ? RoomTheme.coral : RoomTheme.mint)
                        .font(.system(size: 10)).accessibilityHidden(true)
                    ProgressView(value: Double(cat.health), total: 100).tint(sick ? RoomTheme.coral : RoomTheme.mint)
                    Text("\(cat.health)").font(.system(size: 11, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(RoomTheme.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 8) {
                if let illness = cat.healthState?.illness {
                    Label("\(CatHealthCatalog.definition(for: illness).treatmentCost)", systemImage: "dollarsign.circle.fill")
                        .font(.system(size: 12, weight: .heavy)).foregroundStyle(RoomTheme.gold).fixedSize()
                }
                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(RoomTheme.secondary)
            }.accessibilityHidden(true)
        }
        .padding(14).frame(maxWidth: .infinity, minHeight: 100, alignment: .leading).gameCard(cornerRadius: 24)
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(sick ? RoomTheme.coralBorder : .clear, lineWidth: 2))
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .accessibilityElement(children: .combine)
    }

    private func catName(_ cat: CatState) -> some View {
        Text(verbatim: GameStrings.catName(cat)).font(.system(size: 17, weight: .heavy))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var prevention: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(GameStrings.text("hospital.prevention"), systemImage: "lightbulb.fill")
                .font(.system(size: 15, weight: .heavy))
            Text(GameStrings.text("hospital.preventionHint"))
                .font(.system(size: 11, weight: .medium)).foregroundStyle(RoomTheme.secondary)
            ForEach(HospitalCareNeed.allCases, id: \.self) { need in
                if let cat = cats.min(by: { need.value($0) < need.value($1) }) {
                    HStack(spacing: 8) {
                        GameIconTile(symbol: need.symbol, tint: need.tint, background: need.tint.opacity(0.16), size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(GameStrings.text(need.nameKey)).font(.system(size: 12, weight: .heavy))
                            Text(GameStrings.text(CatHealthCatalog.definition(for: need.illness).nameKey))
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(RoomTheme.secondary)
                        }
                        Spacer(minLength: 4)
                        Text(verbatim: "\(GameStrings.catName(cat)) \(need.value(cat))")
                            .font(.system(size: 11, weight: .heavy)).lineLimit(2)
                            .foregroundStyle(need.value(cat) < CatHealthCatalog.lowNeedThreshold ? RoomTheme.coralDeep : RoomTheme.darkMint)
                            .padding(.horizontal, 9).padding(.vertical, 6)
                            .background(need.value(cat) < CatHealthCatalog.lowNeedThreshold ? RoomTheme.paleCoral
                                        : need.value(cat) < 50 ? RoomTheme.gold.opacity(0.2) : RoomTheme.paleMint, in: Capsule())
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("hospitalPrevention_\(need.rawValue)")
                    .accessibilityValue("\(cat.id):\(need.value(cat))")
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading).gameCard()
    }

    private var pagination: some View {
        HStack(spacing: 10) {
            Button { page = max(0, currentPage - 1) } label: {
                Label(GameStrings.text("catDirectory.previous"), systemImage: "chevron.left")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }.disabled(currentPage == 0).accessibilityIdentifier("hospitalPagePrevious")
            Text(GameStrings.format("catDirectory.page", currentPage + 1, pageCount))
                .font(.footnote.monospacedDigit()).fixedSize()
                .accessibilityIdentifier("hospitalPageSummary").accessibilityValue("\(currentPage + 1)/\(pageCount)")
            Button { page = min(pageCount - 1, currentPage + 1) } label: {
                HStack(spacing: 5) {
                    Text(GameStrings.text("catDirectory.next"))
                    Image(systemName: "chevron.right")
                }.frame(maxWidth: .infinity, minHeight: 44)
            }.disabled(currentPage == pageCount - 1).accessibilityIdentifier("hospitalPageNext")
        }
        .font(.footnote.weight(.semibold)).buttonStyle(.plain).foregroundStyle(RoomTheme.darkMint)
    }
}
