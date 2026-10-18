import SwiftUI

@main
struct WifiTapClipApp: App {
    @State private var model = JoinModel(config: AppConfig.fromMainBundle())

    var body: some Scene {
        WindowGroup {
            JoinView(model: model)
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    guard let url = activity.webpageURL else { return }
                    Task { await model.handle(url: url) }
                }
        }
    }
}
