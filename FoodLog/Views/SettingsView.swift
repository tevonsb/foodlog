import SwiftUI

struct SettingsView: View {
    @State private var apiKey: String = ""
    @State private var hasKey: Bool = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor.gradient)
                            .frame(width: 36, height: 36)
                        Image(systemName: "key.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Claude API Key")
                            .font(.subheadline.weight(.semibold))
                        Text(hasKey ? "Key saved securely" : "Not configured")
                            .font(.caption)
                            .foregroundStyle(hasKey ? .green : .secondary)
                    }
                }
                .padding(.vertical, 2)

                SecureField("sk-ant-...", text: $apiKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if !apiKey.isEmpty {
                    Button("Save Key") {
                        KeychainService.saveAPIKey(apiKey)
                        hasKey = true
                        apiKey = ""
                    }
                } else if hasKey {
                    Button("Remove Key", role: .destructive) {
                        KeychainService.deleteAPIKey()
                        hasKey = false
                    }
                }
            } footer: {
                Text("Your API key is stored securely in the iOS Keychain. Get a key from [console.anthropic.com](https://console.anthropic.com).")
            }

            Section("Data Sources") {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red.gradient)
                            .frame(width: 36, height: 36)
                        Image(systemName: "heart.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Apple Health")
                            .font(.subheadline.weight(.medium))
                        Text("Nutrition data synced automatically")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)

                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.gradient)
                            .frame(width: 36, height: 36)
                        Image(systemName: "server.rack")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("USDA FNDDS Database")
                            .font(.subheadline.weight(.medium))
                        Text("Bundled food composition data")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("AI Models")
                    Spacer()
                    Text("Haiku & Sonnet")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            hasKey = KeychainService.getAPIKey() != nil
        }
    }
}
