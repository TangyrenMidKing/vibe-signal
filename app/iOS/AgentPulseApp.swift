import SwiftUI

@main
struct AgentPulseApp: App {
    @StateObject private var appModel = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                .onAppear {
                    appModel.start()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                appModel.handleBecameActive()
            case .inactive, .background:
                appModel.handleEnteringBackground()
            @unknown default:
                break
            }
        }
    }
}
