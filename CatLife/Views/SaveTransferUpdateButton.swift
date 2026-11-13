import SwiftUI

struct SaveTransferUpdateButton: View {
    @Environment(\.openURL) private var openURL
    @State private var cannotOpen = false

    private let updateURL = URL(string: "https://github.com/xdgf558/cat-life-game-mac/releases")!
    private let updateTitleKey = "mac.update.project"
    private let unavailableTitleKey = "mac.update.unavailable"
    private let helpTitleKey = "mac.update.retry"
    var body: some View {
        Button {
            openURL(updateURL) { accepted in cannotOpen = !accepted }
        } label: {
            Label(GameStrings.text(updateTitleKey), systemImage: "arrow.down.app.fill")
                .font(.headline).frame(maxWidth: .infinity, minHeight: 44)
                .padding(.horizontal, 16).padding(.vertical, 8)
                .foregroundStyle(.white)
                .background(RoomTheme.gold, in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(.white.opacity(0.4), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .alert(GameStrings.text(unavailableTitleKey), isPresented: $cannotOpen) {
            Button(GameStrings.text(helpTitleKey)) {
                openURL(updateURL)
            }
            Button(GameStrings.text("common.close"), role: .cancel) {}
        } message: {
            Text(GameStrings.text("mac.update.manual"))
        }
    }
}
