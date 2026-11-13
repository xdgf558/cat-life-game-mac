import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct HabitStudySettingsView: View {
    @Bindable var store: GameStore
    @State private var document: HabitStudyDocument?
    @State private var exporting = false
    @State private var failed = false
    @State private var clearing = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Toggle(GameStrings.text("catHabits.studyMode"), isOn: $store.habitStudyMode)
                    .font(.headline.weight(.heavy)).tint(RoomTheme.mint).accessibilityIdentifier("habitStudyToggle")
                Text(GameStrings.text("catHabits.studyHint")).font(.subheadline).foregroundStyle(RoomTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(GameStrings.text("catHabits.h1Pending")).font(.subheadline.weight(.bold)).foregroundStyle(RoomTheme.coralDeep)
                    .fixedSize(horizontal: false, vertical: true).padding(14).background(RoomTheme.rewardPaper, in: RoundedRectangle(cornerRadius: 18))
                Button {
                    Task {
                        do { document = HabitStudyDocument(data: try await store.habitStudyLog.export()); exporting = true }
                        catch { failed = true }
                    }
                } label: {
                    Label(GameStrings.text("catHabits.exportLog"), systemImage: "square.and.arrow.up")
                        .font(.headline).frame(maxWidth: .infinity)
                }.buttonStyle(MintButtonStyle()).accessibilityIdentifier("habitStudyExport")
                Button(GameStrings.text("catHabits.clearLog")) { clearing = true }.buttonStyle(SoftButtonStyle())
                    .accessibilityIdentifier("habitStudyClear")
                if store.habitStudyError {
                    Text(GameStrings.text("catHabits.logFailed")).font(.footnote).foregroundStyle(RoomTheme.coralDeep)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }.padding(20).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }.background(RoomTheme.cream).accessibilityIdentifier("habitStudyScroll")
            .navigationTitle(GameStrings.text("catHabits.studyTitle")).navigationBarTitleDisplayMode(.inline)
            .fileExporter(isPresented: $exporting, document: document, contentType: .json,
                defaultFilename: SaveArchiveFiles.backupFilename(exportedAt: Date()).replacingOccurrences(of: "Backup", with: "HabitStudy")) { result in
                    if case .failure = result { failed = true }
                }
            .alert(GameStrings.text("catHabits.logFailed"), isPresented: $failed) { Button(GameStrings.text("common.done"), role: .cancel) {} }
            .confirmationDialog(GameStrings.text("catHabits.clearLog"), isPresented: $clearing, titleVisibility: .visible) {
                Button(GameStrings.text("catHabits.clearLog"), role: .destructive) {
                    Task { do { try await store.habitStudyLog.clear(); store.habitStudyError = false } catch { failed = true } }
                }
            }
    }
}

struct HabitStudyDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

@MainActor
struct HabitIntroBanner: View {
    let store: GameStore
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(GameStrings.text("catHabits.intro")).font(.subheadline.weight(.heavy)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button(GameStrings.text("catHabits.later")) { store.dismissHabitIntro() }.buttonStyle(SoftButtonStyle())
                    .accessibilityIdentifier("habitIntroLater")
                Button { Task { _ = await store.openPlayTogether() } } label: {
                    Text(GameStrings.text("catHabits.playTogether")).font(.subheadline.weight(.heavy)).frame(maxWidth: .infinity)
                }.buttonStyle(MintButtonStyle()).accessibilityIdentifier("habitIntroPlay")
            }.disabled(store.isBusy)
        }.padding(14).gameCard(cornerRadius: 22).accessibilityElement(children: .contain)
            .accessibilityIdentifier("habitIntroBanner")
    }
}
