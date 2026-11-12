import SwiftUI
import CatGameCore

@MainActor
struct HabitGuidePicker68: View {
    let store: GameStore
    let cat: CatState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selection: CatMemoryKind?
    @State private var saving = false
    @State private var generation: UUID

    init(store: GameStore, cat: CatState, initialSelection: CatMemoryKind? = nil) {
        self.store = store
        self.cat = cat
        _selection = State(initialValue: initialSelection ?? cat.habits.pinnedMemory)
        _generation = State(initialValue: store.saveSceneGeneration)
    }

    private var currentCat: CatState? { store.snapshot?.cats.first { $0.id == cat.id } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(GameStrings.text("habit67.pinTitle")).font(.title2.weight(.heavy))
                            .accessibilityAddTraits(.isHeader)
                        Text(GameStrings.text("habit67.pinHint")).font(.subheadline.weight(.semibold))
                            .foregroundStyle(RoomTheme.secondary)
                        ForEach(CompanionshipPresentation.pinnableMemories, id: \.self) { memory in
                            guideOption(memory)
                        }
                        if store.hasSaveFailure { SaveStatusBanner(store: store) }
                    }
                    .fixedSize(horizontal: false, vertical: true).padding(18)
                }
                .background(RoomTheme.cream)
                .accessibilityIdentifier("habitGuidePicker")
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { unpinButton; confirmButton }
                    VStack(spacing: 10) { confirmButton; unpinButton }
                }.padding(16).background(RoomTheme.cream)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(GameStrings.text("common.close")) { dismiss() }.disabled(saving)
                }
            }
        }
        .fontDesign(.rounded).foregroundStyle(RoomTheme.ink)
        .presentationBackground(RoomTheme.cream).presentationDragIndicator(.visible)
        .interactiveDismissDisabled(saving || store.isBusy)
        .saveRecoveryAlert(store: store)
        .onAppear { store.isPresentingHabitGuide = true }
        .onDisappear { store.isPresentingHabitGuide = false }
        .onChange(of: store.saveSceneGeneration) { _, _ in dismiss() }
    }

    @ViewBuilder
    private func guideOption(_ memory: CatMemoryKind) -> some View {
        let selected = selection == memory
        let recorded = currentCat?.habits.memories.contains { $0.kind == memory } == true
        if dynamicTypeSize.isAccessibilitySize {
            let title = GameStrings.text(CompanionshipPresentation.guideKey(for: memory))
            let description = CompanionshipPresentation.guidance(for: memory, cat: currentCat ?? cat)
            VStack(alignment: .leading, spacing: 10) {
                Button { selection = memory } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(selected ? RoomTheme.mint : RoomTheme.track)
                            .frame(width: 26, height: 44).accessibilityHidden(true)
                        Text(title).font(.subheadline.weight(.heavy))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(saving || store.isBusy)
                .accessibilityIdentifier("habitPin_\(memory.rawValue)")
                .accessibilityLabel(recorded ? title + ", " + GameStrings.text("habit68.guide.recorded") : title)
                .accessibilityHint(description)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                if recorded {
                    Label(GameStrings.text("habit68.guide.recorded"), systemImage: "checkmark")
                        .font(.caption2.weight(.bold)).foregroundStyle(RoomTheme.darkMint)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(RoomTheme.mint.opacity(0.1), in: Capsule()).accessibilityHidden(true)
                }
                Text(description).font(.caption.weight(.semibold)).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityHidden(true)
            }
            .padding(12).background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(selected ? RoomTheme.mint : .white, lineWidth: selected ? 3 : 2))
        } else {
            Button { selection = memory } label: {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                        .font(.title2).foregroundStyle(selected ? RoomTheme.mint : RoomTheme.track)
                        .frame(width: 26, height: 44).accessibilityHidden(true)
                    Image(systemName: HabitMemorySlot68.symbol(for: memory))
                        .font(.title2.weight(.semibold)).foregroundStyle(HabitMemorySlot68.tint(for: memory))
                        .frame(width: 42, height: 44)
                        .background(HabitMemorySlot68.tint(for: memory).opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(GameStrings.text(CompanionshipPresentation.guideKey(for: memory)))
                            .font(.subheadline.weight(.heavy))
                        if recorded {
                            Label(GameStrings.text("habit68.guide.recorded"), systemImage: "checkmark")
                                .font(.caption2.weight(.bold)).foregroundStyle(RoomTheme.darkMint)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(RoomTheme.mint.opacity(0.1), in: Capsule())
                        }
                        Text(CompanionshipPresentation.guidance(for: memory, cat: currentCat ?? cat))
                            .font(.caption.weight(.semibold)).foregroundStyle(RoomTheme.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                .fixedSize(horizontal: false, vertical: true).padding(12)
                .background(RoomTheme.paper, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(selected ? RoomTheme.mint : .white, lineWidth: selected ? 3 : 2))
                .contentShape(RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain).disabled(saving || store.isBusy)
            .accessibilityIdentifier("habitPin_\(memory.rawValue)")
            .accessibilityAddTraits(selected ? [.isSelected] : [])
        }
    }

    private var unpinButton: some View {
        Button(GameStrings.text("habit67.unpin")) { save(nil) }
            .font(.subheadline.weight(.heavy)).buttonStyle(SoftButtonStyle())
            .disabled(saving || store.isBusy || currentCat?.habits.pinnedMemory == nil)
            .accessibilityIdentifier("habitUnpin")
    }

    private var confirmButton: some View {
        Button { save(selection) } label: {
            Label(GameStrings.text(saving ? "common.saving" : "habit67.pin"), systemImage: "pin.fill")
                .font(.subheadline.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(MintButtonStyle()).disabled(saving || store.isBusy || selection == nil)
        .accessibilityIdentifier("habitPinConfirm")
    }

    private func save(_ memory: CatMemoryKind?) {
        guard !saving, !store.isBusy, generation == store.saveSceneGeneration, currentCat != nil else { return }
        saving = true
        Task {
            let succeeded = await store.pinHabitMemory(catID: cat.id, memory: memory)
            saving = false
            if succeeded, generation == store.saveSceneGeneration { dismiss() }
        }
    }
}
