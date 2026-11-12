import SwiftUI

/// Startup repair stays separate from the normal welcome journey and never enters automatically.
@MainActor
struct WelcomeSaveRecoveryView: View {
    @Bindable var store: GameStore
    let restored: Bool
    let busy: Bool
    let availableHeight: CGFloat
    let version: String
    let onRestore: () -> Void
    let onRetry: () -> Void

    private var compact: Bool { availableHeight < 700 }
    private var working: Bool { busy || store.isLoading || store.isBusy || store.saveTransferInProgress }
    private var ready: Bool { restored && !working && !store.loadFailed && store.snapshot != nil }

    var body: some View {
        ScrollView {
            VStack(spacing: compact ? 22 : 32) {
                identity.padding(.top, compact ? 12 : 24)
                Spacer(minLength: compact ? 0 : 12)
                if restored { restoredCard } else { failureCard }
                Spacer(minLength: compact ? 4 : 24)
                if restored { enterButton }
                Text(GameStrings.format("welcome.version", version))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(RoomTheme.secondary.opacity(0.75))
                    .accessibilityIdentifier("welcomeVersion")
                    .accessibilityValue(version)
            }
            .padding(.horizontal, 16).padding(.bottom, 14)
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity, minHeight: availableHeight)
        }
        .scrollBounceBehavior(.basedOnSize).scrollIndicators(.hidden)
        .foregroundStyle(RoomTheme.ink).fontDesign(.rounded)
    }

    private var identity: some View {
        VStack(spacing: 16) {
            Image("app-icon-preview").resizable().scaledToFit()
                .frame(width: compact ? 100 : 120, height: compact ? 100 : 120)
                .clipShape(RoundedRectangle(cornerRadius: 29))
                .overlay(RoundedRectangle(cornerRadius: 29).strokeBorder(.white, lineWidth: 4))
                .shadow(color: RoomTheme.ink.opacity(0.15), radius: 12, y: 8)
                .accessibilityHidden(true)
            Text(GameStrings.text("home.name"))
                .font(.title.weight(.heavy))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("welcomeTitle")
        }
    }

    private var failureCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                GameIconTile(symbol: store.needsNewerVersion ? "arrow.down.app" : "doc.badge.ellipsis",
                             tint: store.needsNewerVersion ? RoomTheme.gold : RoomTheme.coral,
                             background: store.needsNewerVersion ? RoomTheme.gold.opacity(0.14) : RoomTheme.paleCoral,
                             size: 46)
                VStack(alignment: .leading, spacing: 4) {
                    Text(GameStrings.text(store.needsNewerVersion ? "save.newerVersionTitle" : "saveTransfer.welcomeFailedTitle"))
                        .font(.title3.weight(.heavy))
                    Text(GameStrings.text("saveTransfer.welcomeOriginalSafe"))
                        .font(.footnote.weight(.bold)).foregroundStyle(RoomTheme.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            Text(GameStrings.text(store.needsNewerVersion ? "saveTransfer.failureNewerIntro" : "saveTransfer.failureIntro"))
                .font(.subheadline.weight(.semibold)).foregroundStyle(RoomTheme.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("welcomeLoadError")

            if working {
                ProgressView(GameStrings.text("welcome.loadingSave"))
                    .font(.subheadline.weight(.semibold)).tint(RoomTheme.darkMint)
                    .accessibilityIdentifier("welcomeLoading")
            }
            if store.needsNewerVersion {
                SaveTransferUpdateButton()
                    .disabled(working)
                    .accessibilityIdentifier("welcomeUpdateButton")
            }
            if store.needsNewerVersion {
                retryButton.buttonStyle(SoftButtonStyle())
            } else {
                retryButton.buttonStyle(MintButtonStyle())
            }
            restoreButton.buttonStyle(SoftButtonStyle())
            Text(GameStrings.text("saveTransfer.failureScope"))
                .font(.caption.weight(.semibold)).foregroundStyle(RoomTheme.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .gameCard(cornerRadius: 30)
    }

    private var retryButton: some View {
        Button(action: onRetry) {
            Label(GameStrings.text("saveTransfer.welcomeRetry"), systemImage: "arrow.clockwise")
                .font(.headline).frame(maxWidth: .infinity, minHeight: 28)
        }
        .disabled(working)
        .accessibilityIdentifier("welcomeRetryButton")
    }

    private var restoreButton: some View {
        Button(action: onRestore) {
            Label(GameStrings.text("saveTransfer.failureEntry"), systemImage: "doc.badge.arrow.up")
                .font(.headline).frame(maxWidth: .infinity, minHeight: 28)
                .fixedSize(horizontal: false, vertical: true)
        }
        .disabled(working)
        .accessibilityIdentifier("welcomeRestoreBackupButton")
    }

    private var restoredCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark")
                .font(.system(size: 42, weight: .heavy))
                .foregroundStyle(RoomTheme.darkMint)
                .frame(width: 88, height: 88)
                .background(RoomTheme.paleMint, in: Circle())
                .overlay(Circle().strokeBorder(.white, lineWidth: 4))
                .accessibilityHidden(true)
            Text(GameStrings.text("saveTransfer.welcomeRestoredTitle"))
                .font(.title2.weight(.heavy)).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("welcomeRecoverySuccess")
            Text(GameStrings.text("saveTransfer.welcomeRestoredBody"))
                .font(.subheadline.weight(.semibold)).foregroundStyle(RoomTheme.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("welcomeNotice")
            if let snapshot = store.snapshot {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { summaryBadges(level: snapshot.player.level, cats: snapshot.cats.count) }
                        .fixedSize(horizontal: true, vertical: false)
                    VStack(spacing: 8) { summaryBadges(level: snapshot.player.level, cats: snapshot.cats.count) }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("welcomeRecoverySummary")
            }
        }
        .padding(22).frame(maxWidth: .infinity)
        .gameCard(cornerRadius: 30)
    }

    @ViewBuilder private func summaryBadges(level: Int, cats: Int) -> some View {
        badge(GameStrings.format("career.level", level), color: RoomTheme.gold)
        badge(GameStrings.format("saveTransfer.catCount", cats), color: RoomTheme.coralDeep)
        badge(GameStrings.text("saveTransfer.welcomeSettled"), color: RoomTheme.darkMint)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text).font(.caption.weight(.heavy))
            .foregroundStyle(color).padding(.horizontal, 10).padding(.vertical, 7)
            .background(color.opacity(0.14), in: Capsule())
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
    }

    private var enterButton: some View {
        Button { store.enterHome() } label: {
            Label(GameStrings.text("welcome.enter"), systemImage: "house.fill")
                .font(.title3.weight(.heavy)).frame(maxWidth: .infinity, minHeight: 28)
        }
        .buttonStyle(MintButtonStyle()).disabled(!ready)
        .accessibilityIdentifier("welcomeEnterButton")
    }
}
