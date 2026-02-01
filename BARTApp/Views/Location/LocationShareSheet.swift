import SwiftUI
import MapKit

struct LocationShareSheet: View {
    let sessionKey: String

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var gateway: GatewayConnection
    @StateObject private var locationManager = LocationManager()

    @State private var ttlHours: Double = 1
    @State private var isSharing = false
    @State private var showError = false
    @State private var errorMessage = ""

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedGradientBackground()

                ScrollView {
                    VStack(spacing: 24) {
                        mapPreview

                        locationDetails

                        ttlSelector

                        shareButton
                    }
                    .padding()
                }
            }
            .navigationTitle("Share Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                locationManager.requestLocation()
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var mapPreview: some View {
        ZStack {
            Map(position: $position) {
                UserAnnotation()
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
            )

            if locationManager.currentLocation == nil {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)

                VStack(spacing: 12) {
                    ProgressView()
                    Text("Getting location...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var locationDetails: some View {
        GlassCard {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "location.fill")
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(.ultraThinMaterial))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Current Location")
                            .font(.subheadline.bold())

                        if let location = locationManager.currentLocation {
                            Text("\(location.coordinate.latitude, specifier: "%.6f"), \(location.coordinate.longitude, specifier: "%.6f")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Locating...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if let accuracy = locationManager.currentLocation?.horizontalAccuracy {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Accuracy")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text("\(Int(accuracy))m")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !locationManager.isAuthorized {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)

                        Text("Location access required")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Enable") {
                            locationManager.requestAuthorization()
                        }
                        .font(.caption.bold())
                    }
                    .padding(.top, 8)
                }
            }
        }
    }

    private var ttlSelector: some View {
        GlassCard {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "clock.fill")
                        .foregroundStyle(.orange)

                    Text("Share Duration")
                        .font(.subheadline.bold())

                    Spacer()

                    Text(ttlFormatted)
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                        .fontWeight(.semibold)
                }

                Slider(value: $ttlHours, in: 1...24, step: 1)
                    .tint(.accentColor)

                HStack {
                    Text("1 hour")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Spacer()

                    Text("24 hours")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var ttlFormatted: String {
        let hours = Int(ttlHours)
        if hours == 1 {
            return "1 hour"
        }
        return "\(hours) hours"
    }

    private var shareButton: some View {
        Button(action: shareLocation) {
            HStack(spacing: 8) {
                if isSharing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "location.fill")
                }

                Text(isSharing ? "Sharing..." : "Share Location")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .buttonStyle(GlassButton(isProminent: true))
        .disabled(isSharing || locationManager.currentLocation == nil)
    }

    private func shareLocation() {
        guard let locationShare = locationManager.createLocationShare(ttlHours: ttlHours) else {
            errorMessage = "Could not get current location"
            showError = true
            return
        }

        isSharing = true

        Task {
            do {
                try await gateway.sendLocation(locationShare, sessionKey: sessionKey)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                showError = true
                isSharing = false
            }
        }
    }
}

#Preview {
    LocationShareSheet(sessionKey: "main")
        .environmentObject(GatewayConnection(gatewayHost: "localhost", port: 18789, useSSL: false))
}
