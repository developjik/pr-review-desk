import SwiftUI
import PRReviewDeskCore

@main
struct PRReviewDeskApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            MainView(model: model)
                .frame(minWidth: 1180, minHeight: 720)
                .task {
                    model.loadStoredToken()
                }
        }
        .windowStyle(.titleBar)
        .commands {
            CommandMenu("Review") {
                Button("Refresh") {
                    Task {
                        await model.refreshActiveScope()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(!model.canRefreshActiveScope)

                Button("Generate Review") {
                    model.startGenerateReview()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!model.canGenerateReview)

                Divider()

                Button("Submit Review") {
                    model.requestSubmitReview()
                }
                .disabled(!model.canSubmitReview)
            }
        }

        Settings {
            SettingsView(model: model)
        }
    }
}
