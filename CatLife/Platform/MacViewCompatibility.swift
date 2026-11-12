#if os(macOS)
import SwiftUI

// These mobile navigation decorations have no counterpart in a desktop sheet.
enum MacTitleDisplayMode { case inline, large, automatic }
enum MacTextCapitalization { case never, sentences, words, characters }
extension View {
    func navigationBarTitleDisplayMode(_ mode: MacTitleDisplayMode) -> some View { self }
    func textInputAutocapitalization(_ value: MacTextCapitalization?) -> some View { self }
    func fullScreenCover<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
                                       @ViewBuilder content: @escaping () -> Content) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
    }
}
extension ToolbarPlacement {
    static var navigationBar: ToolbarPlacement { .windowToolbar }
}
extension ToolbarItemPlacement {
    static var topBarLeading: ToolbarItemPlacement { .navigation }
    static var topBarTrailing: ToolbarItemPlacement { .primaryAction }
    static var navigationBarLeading: ToolbarItemPlacement { .navigation }
    static var navigationBarTrailing: ToolbarItemPlacement { .primaryAction }
}
#endif
