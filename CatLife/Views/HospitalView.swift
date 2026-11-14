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
                HospitalHeader(gold: store.snapshot?.player.gold ?? 0) { heading }
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

    /// The scene banner above already names the hospital; this row says what to do and how many need care.
    private var heading: some View {
        HStack(spacing: 8) {
            Text(GameStrings.text("hospital.selectCat")).font(.system(size: 13, weight: .heavy))
                .lineLimit(1).minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("hospitalPageTitle")
            Label(GameStrings.format("hospital.summary", sickCount, cats.count),
                  systemImage: sickCount > 0 ? "cross.case.fill" : "checkmark.shield.fill")
                .font(.system(size: 11, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(sickCount > 0 ? .white : RoomTheme.darkMint)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(sickCount > 0 ? RoomTheme.coral : RoomTheme.paleMint, in: Capsule())
                .accessibilityIdentifier("hospitalSummary").accessibilityValue("\(sickCount)/\(cats.count)")
        }
    }

    private var directory: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if cats.isEmpty {
                    Text(GameStrings.text("hospital.empty"))
                        .font(.body).foregroundStyle(RoomTheme.secondary)
                        .padding(24).frame(maxWidth: .infinity).gameCard()
                        .accessibilityIdentifier("hospitalEmpty")
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                              spacing: 10) {
                        ForEach(visibleCats) { cat in
                            Button { path.append(cat.id) } label: { catRow(cat) }
                                .buttonStyle(.plain).accessibilityIdentifier("hospitalCat_\(cat.id)")
                        }
                    }
                    if pageCount > 1 { pagination }
                    prevention
                }
                Text(GameStrings.text("hospital.gentleHint"))
                    .font(.system(size: 10.5, weight: .medium)).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 16)
            .frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(RoomTheme.cream).accessibilityIdentifier("hospitalDirectoryScroll")
    }

    private func catRow(_ cat: CatState) -> some View {
        let sick = cat.healthState?.illness != nil
        return HStack(spacing: 10) {
            HospitalCatPortrait(cat: cat, size: 50, status: true)
            VStack(alignment: .leading, spacing: 5) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        catName(cat)
                        Text(GameStrings.text("hospital.coat.\(cat.appearance.rawValue)"))
                            .font(.system(size: 10.5, weight: .bold)).foregroundStyle(RoomTheme.secondary)
                    }
                    catName(cat)
                }
                HStack(spacing: 6) {
                    HospitalStatusPill(cat: cat, now: store.now).lineLimit(1)
                    Spacer(minLength: 0)
                    if let illness = cat.healthState?.illness {
                        Label("\(CatHealthCatalog.definition(for: illness).treatmentCost)", systemImage: "dollarsign.circle.fill")
                            .font(.system(size: 11, weight: .heavy)).foregroundStyle(RoomTheme.gold).fixedSize()
                    }
                }
                HStack(spacing: 5) {
                    Image(systemName: "heart.fill").foregroundStyle(sick ? RoomTheme.coral : RoomTheme.mint)
                        .font(.system(size: 9)).accessibilityHidden(true)
                    ProgressView(value: Double(cat.health), total: 100).tint(sick ? RoomTheme.coral : RoomTheme.mint)
                        .controlSize(.small)
                    Text("\(cat.health)").font(.system(size: 10.5, weight: .heavy)).monospacedDigit()
                        .foregroundStyle(RoomTheme.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                .foregroundStyle(RoomTheme.secondary).accessibilityHidden(true)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading).gameCard(cornerRadius: 18)
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(sick ? RoomTheme.coralBorder : .clear, lineWidth: 2))
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }

    private func catName(_ cat: CatState) -> some View {
        Text(verbatim: GameStrings.catName(cat)).font(.system(size: 15, weight: .heavy)).lineLimit(1)
    }

    private var prevention: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label(GameStrings.text("hospital.prevention"), systemImage: "lightbulb.fill")
                    .font(.system(size: 13, weight: .heavy)).fixedSize()
                Text(GameStrings.text("hospital.preventionHint"))
                    .font(.system(size: 10.5, weight: .medium)).foregroundStyle(RoomTheme.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                ForEach(HospitalCareNeed.allCases, id: \.self) { need in
                    if let cat = cats.min(by: { need.value($0) < need.value($1) }) { preventionChip(need, cat: cat) }
                }
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).gameCard(cornerRadius: 20)
    }

    private func preventionChip(_ need: HospitalCareNeed, cat: CatState) -> some View {
        let value = need.value(cat)
        let low = value < CatHealthCatalog.lowNeedThreshold
        return HStack(spacing: 7) {
            GameIconTile(symbol: need.symbol, tint: need.tint, background: need.tint.opacity(0.16), size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(GameStrings.text(need.nameKey)).font(.system(size: 11, weight: .heavy))
                Text(GameStrings.text(CatHealthCatalog.definition(for: need.illness).nameKey))
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(RoomTheme.secondary)
            }.lineLimit(1)
            Spacer(minLength: 2)
            Text(verbatim: "\(GameStrings.catName(cat)) \(value)")
                .font(.system(size: 10.5, weight: .heavy)).lineLimit(1).minimumScaleFactor(0.75)
                .foregroundStyle(low ? RoomTheme.coralDeep : RoomTheme.darkMint)
                .padding(.horizontal, 7).padding(.vertical, 4)
                .background(low ? RoomTheme.paleCoral : value < 50 ? RoomTheme.gold.opacity(0.2) : RoomTheme.paleMint, in: Capsule())
        }
        .padding(7).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("hospitalPrevention_\(need.rawValue)")
        .accessibilityValue("\(cat.id):\(value)")
    }

    private var pagination: some View {
        HStack(spacing: 10) {
            Button { page = max(0, currentPage - 1) } label: {
                Label(GameStrings.text("catDirectory.previous"), systemImage: "chevron.left")
                    .frame(maxWidth: .infinity, minHeight: 30)
            }.disabled(currentPage == 0).accessibilityIdentifier("hospitalPagePrevious")
            Text(GameStrings.format("catDirectory.page", currentPage + 1, pageCount))
                .font(.footnote.monospacedDigit()).fixedSize()
                .accessibilityIdentifier("hospitalPageSummary").accessibilityValue("\(currentPage + 1)/\(pageCount)")
            Button { page = min(pageCount - 1, currentPage + 1) } label: {
                HStack(spacing: 5) {
                    Text(GameStrings.text("catDirectory.next"))
                    Image(systemName: "chevron.right")
                }.frame(maxWidth: .infinity, minHeight: 30)
            }.disabled(currentPage == pageCount - 1).accessibilityIdentifier("hospitalPageNext")
        }
        .font(.footnote.weight(.semibold)).buttonStyle(.plain).foregroundStyle(RoomTheme.darkMint)
    }
}
