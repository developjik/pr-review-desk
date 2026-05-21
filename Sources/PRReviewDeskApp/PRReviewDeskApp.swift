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
    }
}
