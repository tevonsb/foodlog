import SwiftUI

struct SettingsView: View {
    @State private var apiKey: String = ""
    @State private var hasKey: Bool = false

    var body: some View {
        Form {
            Section("Claude API Key") {
                SecureField("sk-ant-...", text: $apiKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if hasKey && apiKey.isEmpty {
                    Text("Key saved")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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
            }

            Section {
                Text("Your API key is stored securely in the iOS Keychain. Get a key from console.anthropic.com.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .onAppear {
            hasKey = KeychainService.getAPIKey() != nil
        }
    }
}
