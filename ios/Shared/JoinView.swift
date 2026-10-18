import SwiftUI

struct JoinView: View {
    let model: JoinModel

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: symbol)
                    .font(.system(size: 56, weight: .semibold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(detail)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)
                if isBusy {
                    ProgressView().tint(Theme.accent)
                }
                if model.usesLocalTestNetwork {
                    Text("Test build: joining the network from Local.xcconfig, not the card's server record.")
                        .font(.footnote)
                        .foregroundStyle(Theme.warning)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(32)
        }
        .preferredColorScheme(.dark)
    }

    private var isBusy: Bool {
        switch model.state {
        case .fetching, .joining: true
        default: false
        }
    }

    private var symbol: String {
        switch model.state {
        case .waiting, .fetching, .joining: "wifi"
        case .requested, .alreadyConnected: "checkmark.circle.fill"
        case .declined: "xmark.circle"
        case .unavailable: "wifi.slash"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch model.state {
        case .failed: Theme.error
        case .unavailable, .declined: Theme.secondaryText
        default: Theme.accent
        }
    }

    private var title: String {
        switch model.state {
        case .waiting: "Hold your iPhone near the card"
        case .fetching: "Reading card"
        case .joining(let ssid): "Joining \(ssid)"
        case .requested(let ssid): "Joining \(ssid)"
        case .alreadyConnected(let ssid): "Already on \(ssid)"
        case .declined(let ssid): "Didn't join \(ssid)"
        case .unavailable: "Card unavailable"
        case .failed: "Couldn't join"
        }
    }

    private var detail: String {
        switch model.state {
        case .waiting: "Tap the notification that appears to join the network."
        case .fetching: "Getting the network details."
        case .joining: "Tap Join when iOS asks."
        case .requested: "If iOS asked, tap Join. Check the Wi-Fi icon in the status bar to confirm you're connected."
        case .alreadyConnected: "This iPhone is already connected to this network."
        case .declined: "You can tap the card again to join later."
        case .unavailable(let reason): reason
        case .failed(let reason): reason
        }
    }
}
