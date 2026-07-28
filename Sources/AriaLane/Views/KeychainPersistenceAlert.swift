import SwiftUI

struct KeychainPersistenceAlertModifier: ViewModifier {
    @ObservedObject var preferences: AppPreferences

    func body(content: Content) -> some View {
        content.alert(
            preferences.keychainPersistenceIssue?.title
                ?? L10n.string("无法保存到 macOS 钥匙串"),
            isPresented: isPresented
        ) {
            Button(L10n.string("好"), role: .cancel) {
                preferences.dismissKeychainPersistenceIssue()
            }
        } message: {
            Text(
                preferences.keychainPersistenceIssue?.message
                    ?? L10n.string("请稍后重试。")
            )
        }
    }

    private var isPresented: Binding<Bool> {
        Binding(
            get: {
                preferences.keychainPersistenceIssue != nil
            },
            set: { isPresented in
                if !isPresented {
                    preferences.dismissKeychainPersistenceIssue()
                }
            }
        )
    }
}

extension View {
    func keychainPersistenceAlert(
        preferences: AppPreferences
    ) -> some View {
        modifier(
            KeychainPersistenceAlertModifier(
                preferences: preferences
            )
        )
    }
}
