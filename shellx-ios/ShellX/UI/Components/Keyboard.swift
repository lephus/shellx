import SwiftUI
import UIKit

extension View {
    /// A tap here closes the keyboard, whichever field has it. The tap still reaches the buttons and
    /// links under it, and scrolling is untouched.
    func dismissesKeyboardOnTap() -> some View {
        simultaneousGesture(TapGesture().onEnded { Keyboard.dismiss() })
    }

    /// Sets `isUp` as the keyboard comes and goes, animated with it.
    func tracksKeyboard(_ isUp: Binding<Bool>) -> some View {
        onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.snappy(duration: 0.25)) { isUp.wrappedValue = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.snappy(duration: 0.25)) { isUp.wrappedValue = false }
        }
    }
}

enum Keyboard {
    @MainActor static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
