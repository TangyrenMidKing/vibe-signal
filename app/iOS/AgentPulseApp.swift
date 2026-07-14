import SwiftUI

@main
struct AgentPulseApp: App {
    @StateObject private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                .onAppear {
                    appModel.start()
                }
        }
    }
}
