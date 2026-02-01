import SwiftUI

struct ManualPairingView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var gateway: GatewayConnection

    @State private var gatewayUrl = ""
    @State private var gatewayToken = ""
    @State private var isConnecting = false
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        NavigationView {
            Form {
                Section {
                    Text("On your Mac, run:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("openclaw devices pair --show-url")
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6))
                        .cornerRadius(6)
                } header: {
                    Text("Setup Instructions")
                }

                Section {
                    TextField("ws://192.168.x.x:18789", text: $gatewayUrl)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    SecureField("Gateway Token", text: $gatewayToken)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                } header: {
                    Text("Connection Details")
                } footer: {
                    Text("Enter the URL and token displayed on your Mac")
                }

                Section {
                    Button {
                        connectToGateway()
                    } label: {
                        HStack {
                            Spacer()
                            if isConnecting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Connect")
                            }
                            Spacer()
                        }
                    }
                    .disabled(gatewayUrl.isEmpty || isConnecting)
                }
            }
            .navigationTitle("Manual Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Connection Failed", isPresented: $showingError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }

    private func connectToGateway() {
        isConnecting = true

        // Validate URL format
        guard gatewayUrl.hasPrefix("ws://") || gatewayUrl.hasPrefix("wss://") else {
            errorMessage = "URL must start with ws:// or wss://"
            showingError = true
            isConnecting = false
            return
        }

        // Parse URL to extract host and port
        guard let url = URL(string: gatewayUrl),
              let host = url.host else {
            errorMessage = "Invalid URL format"
            showingError = true
            isConnecting = false
            return
        }

        let useSSL = url.scheme == "wss"
        let port = url.port ?? (useSSL ? 443 : 18789)

        // Store the token for connection
        gateway.setGatewayToken(gatewayToken)
        gateway.updateConnectionConfig(host: host, port: port, useSSL: useSSL)

        // Connect
        gateway.connect()

        // Dismiss after initiating connection
        dismiss()
    }
}

#Preview {
    ManualPairingView()
        .environmentObject(GatewayConnection(gatewayHost: "localhost"))
}
