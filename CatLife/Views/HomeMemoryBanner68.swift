import SwiftUI
import CatGameCore

@MainActor
struct CompanionMemoryCard68: View {
    let cat: CatState
    let memory: CatMemory
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            GameIcon(asset: CatArtwork.asset("cat-avatar", appearance: cat.appearance), symbol: "photo", size: 48)
                .frame(width: 58, height: 60).background(RoomTheme.friendshipPaper)
                .padding(5).padding(.bottom, 10).background(.white)
                .rotationEffect(.degrees(-5)).shadow(color: RoomTheme.ink.opacity(0.12), radius: 3, y: 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(GameStrings.text("design68.memory.new")).font(.caption.weight(.bold)).foregroundStyle(RoomTheme.friendshipDeep)
                Text(GameStrings.text(memory.kind.titleKey)).font(.subheadline.weight(.heavy))
                Text(CompanionshipPresentation.memoryBody(for: memory.kind, cat: cat))
                    .font(.caption).foregroundStyle(RoomTheme.secondary)
            }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(RoomTheme.friendshipDeep)
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(RoomTheme.friendshipBorder, lineWidth: 2))
    }
}

@MainActor
struct HomeMemoryBanner68: View {
    let store: GameStore
    let isActive: Bool
    let available: CGRect
    @State private var contentHeight: CGFloat = 125
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    private var notice: CompanionMemoryNotice68? {
        store.companionMemories.current.flatMap { $0.generation == store.saveSceneGeneration ? $0 : nil }
    }
    private var presentedID: UUID? { isActive ? notice?.id : nil }

    var body: some View {
        Group {
            if isActive, available.width > 150, available.height > 80, let notice,
               let cat = store.snapshot?.cats.first(where: { $0.id == notice.catID }) {
                ScrollView {
                    Button {
                        guard notice.generation == store.saveSceneGeneration else { return }
                        store.companionMemories.dismiss(notice.id)
                        store.inspectCat(catID: notice.catID)
                        store.inspectedMemoryCatID = notice.catID
                    } label: {
                        CompanionMemoryCard68(cat: cat, memory: notice.memory)
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier("newCatMemoryBanner")
                        .accessibilityValue(notice.catID + "|" + notice.memory.id)
                        .background {
                            GeometryReader { geometry in
                                Color.clear.onAppear { contentHeight = geometry.size.height }
                                    .onChange(of: geometry.size.height) { _, height in contentHeight = height }
                            }.allowsHitTesting(false)
                        }
                }.scrollBounceBehavior(.basedOnSize)
                    .frame(width: available.width, height: min(contentHeight, available.height))
                    .position(x: available.midX, y: available.minY + min(contentHeight, available.height) / 2)
                    .transition(reducedMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(reducedMotion ? nil : .easeOut(duration: 0.25), value: presentedID)
        .task(id: presentedID) {
            guard let id = presentedID else { return }
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            guard !Task.isCancelled, isActive, presentedID == id else { return }
            store.companionMemories.dismiss(id)
        }
    }
}
