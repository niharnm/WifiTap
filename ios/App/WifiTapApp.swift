import SwiftUI

@main
struct WifiTapApp: App {
    @State private var programModel: ProgramTagModel
    @State private var joinModel: JoinModel
    @State private var showingJoin = false

    init() {
        let config = AppConfig.fromMainBundle()
        _programModel = State(initialValue: ProgramTagModel(config: config))
        _joinModel = State(initialValue: JoinModel(config: config))
    }

    var body: some Scene {
        WindowGroup {
            ProgramTagView(model: programModel)
                .sheet(isPresented: $showingJoin) {
                    JoinView(model: joinModel)
                }
                // With the full app installed, card taps open it instead of the App Clip.
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    showingJoin = true
                    Task { await joinModel.handle(url: url) }
                }
        }
    }
}
