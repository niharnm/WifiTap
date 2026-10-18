import SwiftUI

struct ProgramTagView: View {
    @Bindable var model: ProgramTagModel

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Wi-Fi Card")
                            .font(.largeTitle.bold())
                        Text("Write your network to an NFC card. Guests tap it to join.")
                            .foregroundStyle(Theme.secondaryText)
                    }

                    if let configError = model.configError {
                        notice(configError, color: Theme.error)
                    } else if model.usesLocalTestNetwork {
                        notice("Test build: cards get a random link, and the App Clip joins the network from Local.xcconfig.", color: Theme.warning)
                    }

                    field("Network name (SSID)") {
                        TextField("", text: $model.ssid)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textContentType(.none)
                    }

                    Picker("Security", selection: $model.security) {
                        Text("WPA2 / WPA3").tag(WiFiSecurity.wpa2)
                        Text("Open").tag(WiFiSecurity.open)
                    }
                    .pickerStyle(.segmented)

                    if model.security == .wpa2 {
                        field("Password") {
                            SecureField("", text: $model.password)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Card mode")
                            .font(.headline)
                        Picker("Card mode", selection: $model.mode) {
                            Text("iPhone + Android").tag(CardMode.urlAndWifi)
                            Text("Link only").tag(CardMode.urlOnly)
                        }
                        .pickerStyle(.segmented)
                        Text(modeExplanation)
                            .font(.footnote)
                            .foregroundStyle(Theme.secondaryText)
                    }

                    statusView

                    Button {
                        Task { await model.create() }
                    } label: {
                        Text(model.isWorking ? "Working…" : "Create")
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 16))
                            .foregroundStyle(.black)
                    }
                    .disabled(model.isWorking || model.configError != nil)
                }
                .padding(20)
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
    }

    private var modeExplanation: String {
        switch model.mode {
        case .urlAndWifi:
            "iPhones join through the App Clip. Android phones join with no app because the password is also stored on the card, so anyone with an NFC reader app can read it, and Android taps can't be revoked, expired or counted."
        case .urlOnly:
            "The password stays on the server, so revoke and expiry work for everyone. Android guests without the app see a web page instead of joining."
        }
    }

    @ViewBuilder
    private var statusView: some View {
        switch model.status {
        case .idle:
            EmptyView()
        case .working(let text):
            HStack(spacing: 10) {
                ProgressView().tint(Theme.accent)
                Text(text)
            }
        case .written(let text):
            notice(text, color: Theme.accent)
        case .failed(let text):
            notice(text, color: Theme.error)
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
            content()
                .padding(14)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func notice(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}
