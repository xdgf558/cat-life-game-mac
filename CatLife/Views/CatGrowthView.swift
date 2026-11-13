import SwiftUI
import CatGameCore

@MainActor
struct CatGrowthView: View {
    @Bindable var store: GameStore
    let catID: String
    @Binding var isSaving: Bool
    let home: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var browsingCatID: String?
    private var displayedCatID: String { browsingCatID ?? catID }
    private var cat: CatState? { store.snapshot?.cats.first { $0.id == displayedCatID } }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                catSwitcher
                if let cat, let growth = cat.growthState, let now = store.snapshot?.meta.lastSyncAt {
                    identity(cat)
                    growthCard(growth, now: now)
                    bondCard(cat)
                    historyCard(growth, now: now)
                    Button { goHome() } label: {
                        Label(GameStrings.text(isSaving ? "common.saving" : "catGrowth.goHome"), systemImage: "house.fill")
                            .font(.headline).frame(maxWidth: .infinity).fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(MintButtonStyle()).disabled(isSaving || store.isBusy)
                    .accessibilityIdentifier("catGrowthGoHome")
                    Text(GameStrings.text("catGrowth.goHomeHint"))
                        .font(.footnote).foregroundStyle(RoomTheme.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(GameStrings.text("catProfile.missing")).foregroundStyle(RoomTheme.secondary).padding(24)
                }
            }
            .padding(16).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .background(RoomTheme.cream)
        .accessibilityIdentifier("catGrowthScroll").accessibilityValue(displayedCatID)
        .navigationTitle(GameStrings.text("catGrowth.title")).navigationBarTitleDisplayMode(.inline)
    }

    private var catSwitcher: some View {
        ScrollViewReader { proxy in
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.snapshot?.cats ?? []) { cat in
                    Button { browsingCatID = cat.id; store.playNavigationSound() } label: {
                        HStack(spacing: 6) {
                            GameIcon(asset: CatArtwork.asset("cat-avatar", appearance: cat.appearance), symbol: "cat.fill", size: 24)
                            Text(verbatim: GameStrings.catName(cat)).font(.subheadline.weight(.heavy))
                        }.padding(.horizontal, 12).frame(minHeight: 44)
                            .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 16))
                            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(
                                displayedCatID == cat.id ? RoomTheme.mint : RoomTheme.wood.opacity(0.5), lineWidth: 2))
                            .contentShape(RoundedRectangle(cornerRadius: 16))
                    }.buttonStyle(.plain).disabled(isSaving || store.isBusy)
                        .accessibilityIdentifier("catGrowthSwitch_\(cat.id)").accessibilityAddTraits(displayedCatID == cat.id ? .isSelected : [])
                        .id(cat.id)
                }
            }.padding(2)
        }.accessibilityIdentifier("catGrowthSwitcher")
            .onChange(of: displayedCatID, initial: true) { _, id in proxy.scrollTo(id, anchor: .center) }
        }
    }

    private func identity(_ cat: CatState) -> some View {
        let growth = cat.growthState
        let stage = growth?.stage(at: store.snapshot?.meta.lastSyncAt ?? store.now) ?? .kitten
        let artSize: CGFloat = stage == .kitten ? 64 : stage == .junior ? 78 : 92
        return HStack(spacing: 14) {
            GameIcon(asset: CatArtwork.asset("cat-idle", appearance: cat.appearance), symbol: "cat.fill", size: artSize, tint: RoomTheme.gold)
                .frame(width: 100, height: 104).background(RoomTheme.paper, in: Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 3)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: GameStrings.catName(cat)).font(.title2.weight(.heavy))
                    .accessibilityIdentifier("catGrowthName").accessibilityValue(Text(verbatim: GameStrings.catName(cat)))
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 5) { identityBadges(cat, stage: stage) }.fixedSize()
                    VStack(alignment: .leading, spacing: 5) { identityBadges(cat, stage: stage) }
                }.font(.caption.weight(.heavy))
            }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }.padding(16).background {
            RoundedRectangle(cornerRadius: 26).fill(LinearGradient(colors: [RoomTheme.paper, RoomTheme.gold.opacity(0.2)],
                startPoint: .leading, endPoint: .trailing))
        }.overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(.white, lineWidth: 3))
    }

    @ViewBuilder private func identityBadges(_ cat: CatState, stage: CatGrowthStage) -> some View {
        Text(GameStrings.text("hospital.coat.\(cat.appearance.rawValue)"))
            .foregroundStyle(RoomTheme.secondary).padding(.horizontal, 8).padding(.vertical, 5).background(RoomTheme.paper, in: Capsule())
        if let growth = cat.growthState {
            Text(GameStrings.text("catGrowth.sex.\(growth.sex.rawValue)"))
                .foregroundStyle(growth.sex == .male ? RoomTheme.sky : RoomTheme.friendshipDeep)
                .padding(.horizontal, 8).padding(.vertical, 5).background(RoomTheme.paper, in: Capsule())
                .accessibilityIdentifier("catGrowthSex").accessibilityValue(GameStrings.text("catGrowth.sex.\(growth.sex.rawValue)"))
        }
        Text(GameStrings.text("catGrowth.stage.\(stage.rawValue)"))
            .foregroundStyle(.white).padding(.horizontal, 8).padding(.vertical, 5).background(RoomTheme.mint, in: Capsule())
            .accessibilityIdentifier("catGrowthStage").accessibilityValue(GameStrings.text("catGrowth.stage.\(stage.rawValue)"))
    }

    private func growthCard(_ growth: CatGrowthState, now: Date) -> some View {
        let age = growth.ageDays(at: now)
        let stage = growth.stage(at: now)
        return section("catGrowth.growth", symbol: "leaf.fill", trailing: GameStrings.text("catGrowth.gameAge")) {
            Text(CatGrowthPresentation.age(age)).font(.system(size: 26, weight: .heavy, design: .rounded))
                .foregroundStyle(RoomTheme.darkMint).fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(GameStrings.text("catGrowth.gameAge")).accessibilityValue(CatGrowthPresentation.age(age))
                .accessibilityIdentifier("catGrowthAge")
            CatGrowthTimeline(age: age, stage: stage)
            Text(CatGrowthPresentation.nextGrowth(growth, at: now))
                .font(.subheadline.weight(.semibold)).foregroundStyle(RoomTheme.darkMint)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("catGrowthNextStage")
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoomTheme.mint.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))
            Text(GameStrings.format("catGrowth.clockHint", CatGrowthCatalog.ageMultiplier))
                .font(.footnote).foregroundStyle(RoomTheme.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bondCard(_ cat: CatState) -> some View {
        let stage = CatBondStage.stage(for: cat.intimacy)
        return section("catGrowth.bond", symbol: "heart.fill", tint: RoomTheme.friendshipDeep,
                       trailing: GameStrings.format("catGrowth.bondSummary", cat.intimacy),
                       trailingAccessibility: (GameStrings.text("stat.bond"), "\(cat.intimacy) / 100", "catGrowthBondValue")) {
            HStack(alignment: .top, spacing: 5) {
                ForEach(CatBondStage.allCases, id: \.self) { item in
                    VStack(spacing: 7) {
                        GeometryReader { geometry in
                            Capsule().fill(RoomTheme.friendshipBorder.opacity(0.45)).overlay(alignment: .leading) {
                                Capsule().fill(RoomTheme.friendship).frame(width: geometry.size.width * CGFloat(min(25, max(0, cat.intimacy - item.minimumIntimacy))) / 25)
                            }
                        }.frame(height: 9).accessibilityHidden(true)
                        Text(GameStrings.text("catGrowth.bond.\(item.rawValue)"))
                            .font(.caption2.weight(.heavy)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(stage == item ? RoomTheme.friendshipDeep : RoomTheme.secondary)
                            .accessibilityIdentifier(stage == item ? "catGrowthBondStage" : "catGrowthBond_\(item.rawValue)")
                            .accessibilityValue(GameStrings.text("catGrowth.bond.\(item.rawValue)"))
                    }.frame(maxWidth: .infinity)
                }
            }
            Text(CatGrowthPresentation.nextBond(cat.intimacy))
                .font(.subheadline.weight(.semibold)).foregroundStyle(RoomTheme.friendshipDeep)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("catGrowthNextBond")
                .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(RoomTheme.friendshipPaper, in: RoundedRectangle(cornerRadius: 15))
            Text(GameStrings.text("catGrowth.bondHint"))
                .font(.footnote).foregroundStyle(RoomTheme.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func historyCard(_ growth: CatGrowthState, now: Date) -> some View {
        section("catGrowth.memory", symbol: "calendar") {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) { memoryFields(growth, now: now) }
            } else {
                HStack(alignment: .top, spacing: 12) { memoryFields(growth, now: now) }
            }
            field("catGrowth.recordedSince", value: CatGrowthPresentation.date(growth.recordedSince), identifier: "catGrowthRecordedSince")
            Text(GameStrings.text(growth.isLegacyRecord ? "catGrowth.legacyHint" : "catGrowth.newHint"))
                .font(.footnote).foregroundStyle(RoomTheme.secondary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("catGrowthRecordHint")
                .accessibilityValue(growth.isLegacyRecord ? "legacy" : "adopted")
                .padding(growth.isLegacyRecord ? 12 : 0).frame(maxWidth: .infinity, alignment: .leading)
                .background(growth.isLegacyRecord ? RoomTheme.rewardPaper : .clear, in: RoundedRectangle(cornerRadius: 15))
        }
    }

    @ViewBuilder private func memoryFields(_ growth: CatGrowthState, now: Date) -> some View {
        memoryField("catGrowth.joined", value: growth.adoptedAt.map(CatGrowthPresentation.date) ?? GameStrings.text("catGrowth.joinedEarlier"), identifier: "catGrowthJoined")
        memoryField("catGrowth.companionship", value: GameStrings.format("catGrowth.days", growth.companionshipDays(at: now)), identifier: "catGrowthCompanionship")
    }

    private func memoryField(_ key: String, value: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(GameStrings.text(key)).font(.caption.weight(.bold)).foregroundStyle(RoomTheme.secondary)
            Text(verbatim: value).font(.subheadline.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(RoomTheme.cream, in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .ignore).accessibilityLabel(GameStrings.text(key)).accessibilityValue(value).accessibilityIdentifier(identifier)
    }

    private func section<Content: View>(_ title: String, symbol: String, tint: Color = RoomTheme.darkMint,
                                       trailing: String? = nil,
                                       trailingAccessibility: (label: String, value: String, identifier: String)? = nil,
                                       @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionHeading(title, symbol: symbol, tint: tint, trailing: trailing, accessibility: trailingAccessibility)
            content()
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .gameCard(cornerRadius: 26)
    }

    private func sectionHeading(_ title: String, symbol: String, tint: Color, trailing: String?,
                                accessibility: (label: String, value: String, identifier: String)?) -> some View {
        let heading = Label(GameStrings.text(title), systemImage: symbol)
            .font(.headline.weight(.heavy)).foregroundStyle(tint).accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("\(title)Heading")
        return Group {
            if dynamicTypeSize.isAccessibilitySize, let trailing {
                VStack(alignment: .leading, spacing: 8) {
                    heading
                    sectionSummary(trailing, tint: tint, accessibility: accessibility)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                HStack(alignment: .firstTextBaseline) {
                    heading
                    if let trailing {
                        Spacer(minLength: 4)
                        sectionSummary(trailing, tint: tint, accessibility: accessibility)
                    }
                }
            }
        }
    }

    private func sectionSummary(_ text: String, tint: Color,
                                accessibility: (label: String, value: String, identifier: String)?) -> some View {
        Text(text).font(.caption.weight(.bold)).foregroundStyle(accessibility == nil ? RoomTheme.secondary : tint)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(accessibility?.label ?? text).accessibilityValue(accessibility?.value ?? "")
            .accessibilityIdentifier(accessibility?.identifier ?? "catGrowthGameAgeHeading")
    }

    private func field(_ title: String, value: String, identifier: String) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 5) { fieldTitle(title); fieldValue(value) }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) { fieldTitle(title); Spacer(minLength: 8); fieldValue(value) }
                    VStack(alignment: .leading, spacing: 5) { fieldTitle(title); fieldValue(value) }
                }
            }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel(GameStrings.text(title)).accessibilityValue(value)
        .accessibilityIdentifier(identifier)
    }

    private func fieldTitle(_ key: String) -> some View {
        Text(GameStrings.text(key)).font(.subheadline).foregroundStyle(RoomTheme.secondary).fixedSize(horizontal: false, vertical: true)
    }
    private func fieldValue(_ value: String) -> some View {
        Text(verbatim: value).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
    }

    private func goHome() {
        guard !isSaving, !store.isBusy, cat != nil else { return }
        let catID = displayedCatID
        if store.cat?.id == catID { home(); return }
        let generation = store.saveSceneGeneration
        isSaving = true
        Task {
            let succeeded = await store.selectCompanion(catID: catID)
            isSaving = false
            if succeeded, store.saveSceneGeneration == generation, store.cat?.id == catID { home() }
        }
    }
}

struct CatGrowthTimeline: View {
    let age: Int
    let stage: CatGrowthStage
    var body: some View {
        CatGrowthTimelineNodes {
            ForEach(CatGrowthStage.allCases, id: \.self) { item in
                VStack(spacing: 7) {
                    Image(systemName: item == .kitten ? "drop.fill" : item == .junior ? "pawprint.fill" : "crown.fill")
                        .font(.system(size: 16, weight: .bold)).foregroundStyle(age >= item.minimumAgeDays ? .white : RoomTheme.secondary)
                        .frame(width: 32, height: 32).background(age >= item.minimumAgeDays ? RoomTheme.mint : RoomTheme.paper, in: Circle())
                        .overlay(Circle().strokeBorder(stage == item ? RoomTheme.gold : RoomTheme.track, lineWidth: 3))
                    Text(GameStrings.text("catGrowth.stage.\(item.rawValue)"))
                        .font(.caption2.weight(.heavy)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(stage == item ? RoomTheme.darkMint : RoomTheme.secondary)
                    Text("\(item.minimumAgeDays)").font(.caption2.weight(.bold)).foregroundStyle(RoomTheme.secondary)
                }
            }
        }
        .background(alignment: .top) {
            GeometryReader { geometry in
                let axis = CatGrowthTimelineGeometry(width: geometry.size.width)
                Capsule().fill(RoomTheme.track).overlay(alignment: .leading) {
                    Capsule().fill(RoomTheme.mint.gradient).frame(width: axis.x(forAge: age) - axis.startX)
                }
                .frame(width: axis.length).offset(x: axis.startX)
                Image(systemName: "arrowtriangle.down.fill").font(.system(size: 10)).foregroundStyle(RoomTheme.gold)
                    .position(x: axis.x(forAge: age), y: -10)
            }.frame(height: 7).padding(.top, 12)
        }.padding(.top, 12).accessibilityHidden(true)
    }
}

struct CatGrowthTimelineGeometry {
    let width: CGFloat
    var columnWidth: CGFloat { max(0, width) / CGFloat(CatGrowthStage.allCases.count) }
    var startX: CGFloat { columnWidth / 2 }
    var length: CGFloat { columnWidth * CGFloat(CatGrowthStage.allCases.count - 1) }
    func x(forAge age: Int) -> CGFloat {
        let last = CatGrowthStage.adult.minimumAgeDays
        return startX + length * CGFloat(min(max(0, age), last)) / CGFloat(last)
    }
}

private struct CatGrowthTimelineNodes: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = max(0, proposal.width ?? subviews.reduce(0) { $0 + $1.sizeThatFits(.unspecified).width })
        let axis = CatGrowthTimelineGeometry(width: width)
        let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: axis.columnWidth, height: nil)).height }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let axis = CatGrowthTimelineGeometry(width: bounds.width)
        for (subview, stage) in zip(subviews, CatGrowthStage.allCases) {
            subview.place(at: CGPoint(x: bounds.minX + axis.x(forAge: stage.minimumAgeDays), y: bounds.minY),
                          anchor: .top, proposal: ProposedViewSize(width: axis.columnWidth, height: nil))
        }
    }
}

@MainActor
enum CatGrowthPresentation {
    static func age(_ days: Int) -> String {
        let months = days / 30
        if months >= 12 {
            return GameStrings.format("catGrowth.yearsAndMonths", months / 12, months % 12)
        }
        return GameStrings.format("catGrowth.monthsAndDays", months, days % 30)
    }
    static func nextGrowth(_ growth: CatGrowthState, at date: Date) -> String {
        guard let next = growth.stage(at: date).next else { return GameStrings.text("catGrowth.adultHint") }
        return GameStrings.format("catGrowth.nextStage", next.minimumAgeDays - growth.ageDays(at: date),
                                  GameStrings.text("catGrowth.stage.\(next.rawValue)"))
    }
    static func nextBond(_ intimacy: Int) -> String {
        guard let next = CatBondStage.stage(for: intimacy).next else { return GameStrings.text("catGrowth.closestHint") }
        return GameStrings.format("catGrowth.nextBond", next.minimumIntimacy - intimacy,
                                  GameStrings.text("catGrowth.bond.\(next.rawValue)"))
    }
    static func date(_ value: Date) -> String {
        value.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted)
            .locale(Locale(identifier: GameLocalization.shared.language.rawValue)))
    }
}
