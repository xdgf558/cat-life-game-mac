import SwiftUI

/// A session entry screen. Loading and saving belong to GameStore;
/// entering the home never creates or reloads a save.
@MainActor
struct WelcomeView: View {
    @Bindable var store: GameStore
    @State private var isShowingSaveRecovery = false
    @State private var isRecoveryWorking = false
    @State private var isRetryingSaveRead = false
    @State private var didRecoverSave = false
    @State private var retryAfterRecoveryDismiss = false
    #if DEBUG
    var releaseTestLoad: (() -> Void)?
    #endif
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var ready: Bool { !store.isLoading && !store.loadFailed && store.snapshot != nil }
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
    private var percentage: String { "\(Int((store.startupProgress * 100).rounded()))%" }

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 700
            if store.loadFailed || didRecoverSave || isRetryingSaveRead {
                WelcomeSaveRecoveryView(store: store, restored: didRecoverSave,
                                        busy: isRecoveryWorking || isRetryingSaveRead,
                                        availableHeight: geometry.size.height,
                                        version: "\(version) (\(build))",
                                        onRestore: { isShowingSaveRecovery = true },
                                        onRetry: retrySaveRead)
            } else {
                ScrollView {
                    VStack(spacing: compact ? 14 : 20) {
                        VStack(spacing: 0) {
                            HomeNamePlaque(name: GameStrings.text("home.name"), height: compact ? 88 : 108)
                                .accessibilityIdentifier("welcomeTitle")
                            Text("Cat Life Diary").font(.system(size: 12, weight: .heavy))
                                .foregroundStyle(RoomTheme.secondary).padding(.top, -14)
                        }
                        .rotationEffect(.degrees(-1.5))
                        Image("welcome-homecoming").resizable().scaledToFill()
                            .frame(height: compact ? 204 : min(318, geometry.size.height * 0.41))
                            .frame(maxWidth: .infinity).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 32))
                            .overlay(RoundedRectangle(cornerRadius: 32).strokeBorder(.white, lineWidth: 5))
                            .shadow(color: RoomTheme.ink.opacity(0.12), radius: 0, y: 6)
                            .accessibilityLabel(GameStrings.text("welcome.hero"))
                            .accessibilityIdentifier("welcomeHero")
                        Text(GameStrings.text("welcome.subtitle"))
                            .font(.system(size: compact ? 13 : 15, weight: .bold))
                            .foregroundStyle(RoomTheme.secondary).multilineTextAlignment(.center)
                        entry(compact: compact)
                    }
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .frame(maxWidth: 500).frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
                .scrollBounceBehavior(.basedOnSize).scrollIndicators(.hidden)
            }
        }
        .background(LinearGradient(colors: [RoomTheme.wood.opacity(0.58), RoomTheme.cream, RoomTheme.cream],
                                   startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .accessibilityIdentifier("welcomeScreen")
        .sheet(isPresented: $isShowingSaveRecovery, onDismiss: {
            if retryAfterRecoveryDismiss {
                retryAfterRecoveryDismiss = false
                retrySaveRead()
            }
        }) {
            NavigationStack {
                SaveManagementView(store: store, recoveryOnly: true,
                                   onRecovered: {
                                       didRecoverSave = true
                                       isShowingSaveRecovery = false
                                   }, onWorkingChange: { isRecoveryWorking = $0 },
                                   onRetryLoad: {
                                       retryAfterRecoveryDismiss = true
                                       isShowingSaveRecovery = false
                                   })
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(GameStrings.text("common.cancel")) { isShowingSaveRecovery = false }
                                .disabled(isRecoveryWorking || store.saveTransferInProgress || store.isBusy)
                                .accessibilityIdentifier("saveRecoveryDismissButton")
                        }
                    }
            }
            .fontDesign(.rounded).foregroundStyle(RoomTheme.ink).tint(RoomTheme.darkMint)
            .environment(\.locale, Locale(identifier: store.language.rawValue))
            .interactiveDismissDisabled(isRecoveryWorking || store.saveTransferInProgress || store.isBusy)
        }
    }

    private func retrySaveRead() {
        guard !isRetryingSaveRead, !store.isBusy else { return }
        isRetryingSaveRead = true
        Task {
            await store.load()
            isRetryingSaveRead = false
        }
    }

    private var journey: some View {
        HStack(spacing: 8) {
            GameIconTile(symbol: "briefcase.fill", tint: RoomTheme.gold, background: RoomTheme.gold.opacity(0.2), size: 44)
            GeometryReader { geometry in
                let progress = min(1, max(0, store.startupProgress))
                ZStack(alignment: .leading) {
                    Capsule().fill(RoomTheme.track).frame(height: 8)
                    Capsule().fill(RoomTheme.mint).frame(width: geometry.size.width * progress, height: 8)
                    ForEach([0.4, 0.75], id: \.self) { point in
                        Circle().fill(progress >= point ? RoomTheme.mint : RoomTheme.paper)
                            .frame(width: 16, height: 16).overlay(Circle().strokeBorder(.white, lineWidth: 3))
                            .offset(x: geometry.size.width * point - 8)
                    }
                    GameIcon(asset: "cat-avatar", symbol: "cat.fill", size: 30, tint: RoomTheme.gold)
                        .padding(3).background(RoomTheme.paper, in: Circle())
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .offset(x: max(0, geometry.size.width - 36) * progress)
                }
                .frame(height: 44)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: progress)
            }.frame(height: 44)
            GameIconTile(symbol: "house.fill", tint: ready ? .white : RoomTheme.darkMint,
                         background: ready ? RoomTheme.mint : RoomTheme.paleMint, size: 44)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GameStrings.text("welcome.progress"))
        .accessibilityValue(percentage).accessibilityIdentifier("welcomeProgress")
    }

    private func entry(compact: Bool) -> some View {
        VStack(spacing: compact ? 9 : 10) {
            VStack(spacing: 14) {
                journey
                HStack(alignment: .top) {
                    status
                    if !store.isLoading && !store.loadFailed {
                        Spacer(minLength: 4)
                        Text(percentage).font(.system(size: 13, weight: .heavy)).foregroundStyle(RoomTheme.secondary)
                    }
                }
            }
            .padding(16).gameCard(cornerRadius: 28).padding(.bottom, compact ? 10 : 18)

            Button { store.enterHome() } label: {
                HStack(spacing: 12) {
                    Image(systemName: "house.fill").font(.system(size: 23, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(GameStrings.text(ready ? "welcome.enter" : "welcome.homecoming"))
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right").font(.body.weight(.bold))
                        .accessibilityHidden(true)
                }
                .font(.system(size: compact ? 20 : 22, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: compact ? 24 : 28)
            }
            .buttonStyle(MintButtonStyle())
            .disabled(!ready)
            .opacity(ready ? 1 : 0.6)
            .accessibilityIdentifier("welcomeEnterButton")

            #if DEBUG
            if let releaseTestLoad {
                // Only present in the explicitly held, isolated UI test.
                Button("Release test load", action: releaseTestLoad)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("welcomeReleaseLoadButton")
            }
            #endif

            Text(GameStrings.format("welcome.version", "\(version) (\(build))"))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(RoomTheme.secondary)
                .padding(.top, compact ? 7 : 10)
                .accessibilityIdentifier("welcomeVersion")
                .accessibilityValue("\(version) (\(build))")
        }
    }

    @ViewBuilder private var status: some View {
        if store.isLoading {
            HStack(spacing: 8) {
                Text(GameStrings.text(store.startupPhase))
                Spacer(minLength: 4)
                Text(percentage).monospacedDigit()
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(RoomTheme.darkMint)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("welcomeLoading")
        } else {
            Label(store.startupNotice ?? GameStrings.text("welcome.ready"),
                  systemImage: store.startupNotice == nil ? "checkmark.circle.fill" : "bell.badge.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(RoomTheme.darkMint)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("welcomeNotice")
        }
    }
}
