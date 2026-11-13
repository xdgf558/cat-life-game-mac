import SwiftUI
import CatGameCore

@MainActor
enum WorkJobPresentation {
    static func isNew(_ id: String) -> Bool { id == "job_pet_photographer" || id == "job_pet_brand_designer" }
    static func name(_ id: String) -> String {
        GameStrings.text(WorkCatalog.job(id: id) == nil ? "work.name" : "jobs.\(id).name")
    }

    static func duration(_ seconds: Int) -> String {
        seconds % 60 == 0 ? GameStrings.format("work.durationMinutes", seconds / 60)
            : GameStrings.format("work.durationSeconds", seconds / 60, seconds % 60)
    }

    static func asset(_ id: String) -> String {
        switch id {
        case "job_flyer": "job-flyer-cartoon"
        case "job_store": "job-store-cartoon"
        case "job_petshop": "job-petshop-cartoon"
        case "job_it_engineer": "job-it-cartoon"
        case "job_cat_cafe_manager": "job-cafe-cartoon"
        case "job_pet_photographer": "job-photographer-cartoon"
        case "job_pet_brand_designer": "job-designer-cartoon"
        default: ""
        }
    }

    static func symbol(_ id: String) -> String {
        switch id {
        case "job_store": "storefront.fill"
        case "job_petshop": "pawprint.fill"
        case "job_it_engineer": "laptopcomputer"
        case "job_cat_cafe_manager": "cup.and.saucer.fill"
        case "job_pet_photographer": "camera.fill"
        case "job_pet_brand_designer": "paintpalette.fill"
        default: "newspaper.fill"
        }
    }
}

/// A bounded two-column career tile shared by the quick picker and searchable directory.
@MainActor
struct WorkCareerCard: View {
    let job: WorkJob
    var quote: WorkQuote? = nil
    let selected: Bool
    let unlocked: Bool
    var playerLevel: Int = 1
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var accent: Color {
        switch job.id {
        case "job_store": RoomTheme.gold
        case "job_petshop": RoomTheme.coral
        case "job_it_engineer": RoomTheme.sky
        case "job_cat_cafe_manager": RoomTheme.lilac
        case "job_pet_photographer": RoomTheme.coral
        case "job_pet_brand_designer": RoomTheme.sky
        default: RoomTheme.darkMint
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top) {
                    GameIconTile(asset: WorkJobPresentation.asset(job.id),
                                 symbol: WorkJobPresentation.symbol(job.id),
                                 tint: unlocked ? accent : RoomTheme.secondary,
                                 background: unlocked ? accent.opacity(0.16) : RoomTheme.track,
                        size: 46, iconScale: 0.9)
                        .opacity(unlocked ? 1 : 0.6)
                        .overlay(alignment: .bottomTrailing) {
                            if !unlocked {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 9, weight: .bold)).foregroundStyle(RoomTheme.ink)
                                    .padding(4).background(RoomTheme.paper, in: Circle())
                                    .accessibilityHidden(true)
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            if selected, WorkJobPresentation.isNew(job.id) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(RoomTheme.mint)
                                    .font(.system(size: 19, weight: .bold)).background(RoomTheme.paper, in: Circle())
                                    .offset(x: 5, y: -5).accessibilityHidden(true)
                            }
                        }
                    Spacer(minLength: 0)
                    if selected, !WorkJobPresentation.isNew(job.id) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(RoomTheme.mint)
                            .font(.system(size: 19, weight: .bold)).accessibilityHidden(true)
                    }
                    else if WorkJobPresentation.isNew(job.id) {
                        Text(GameStrings.text("jobs.newBadge")).font(.caption2.weight(.heavy)).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4).background(RoomTheme.friendship, in: Capsule())
                            .accessibilityIdentifier("careerNewBadge_\(job.id)")
                    }
                }
                Text(WorkJobPresentation.name(job.id)).font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(unlocked ? RoomTheme.ink : RoomTheme.secondary)
                    .lineLimit(2).minimumScaleFactor(0.8).frame(minHeight: 38, alignment: .topLeading)
                    .accessibilityIdentifier("careerJobName_\(job.id)")
                Text(GameStrings.text("jobs.\(job.id).detail")).font(.caption.weight(.semibold)).foregroundStyle(RoomTheme.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3).fixedSize(horizontal: false, vertical: true)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2),
                          alignment: .leading, spacing: 6) {
                    stat(WorkJobPresentation.duration(quote?.durationSeconds ?? job.durationMinutes * 60), symbol: "clock.fill", tint: RoomTheme.secondary)
                    stat("−\(quote?.staminaCost ?? job.staminaCost)", symbol: "bolt.fill", tint: RoomTheme.darkMint)
                    stat("+\(job.goldReward)", symbol: "dollarsign.circle.fill", tint: RoomTheme.gold)
                    stat(GameStrings.format("jobs.expPill", job.expReward), symbol: "", tint: RoomTheme.lilac)
                }
                if !unlocked {
                    Label(GameStrings.format("jobs.unlockRemaining", job.unlockLevel, max(0, job.unlockLevel - playerLevel)), systemImage: "lock.fill")
                        .font(.caption.weight(.heavy)).foregroundStyle(RoomTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true).padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoomTheme.track, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .gameCard(cornerRadius: 24)
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(selected ? RoomTheme.mint : .clear, lineWidth: 3))
            .contentShape(RoundedRectangle(cornerRadius: 24))
        }
        .buttonStyle(CareerCardButtonStyle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(WorkJobPresentation.name(job.id))
        .accessibilityValue(unlocked
            ? GameStrings.text(selected ? "career.selected" : "career.available")
            : GameStrings.format("career.unlock", job.unlockLevel))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func stat(_ value: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 3) {
            if !symbol.isEmpty { Image(systemName: symbol) }
            Text(value).lineLimit(1).minimumScaleFactor(0.75)
        }.font(.caption2.weight(.heavy)).foregroundStyle(tint).monospacedDigit()
            .fixedSize(horizontal: false, vertical: true).padding(.horizontal, 6).padding(.vertical, 5)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

/// Disabled requirements stay readable; only the career illustration fades.
private struct CareerCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}
