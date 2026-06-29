#if os(iOS)
import SwiftUI
#if canImport(iPhoneVideoSyncKit)
import iPhoneVideoSyncKit
#endif

struct ContentView: View {
    @EnvironmentObject private var service: iPhoneVideoSyncService

    var body: some View {
        NavigationStack {
            Form {
                Section("Status") {
                    LabeledContent("Network", value: service.status)
                    LabeledContent("Pairing code", value: service.pairingStore.pairingCode)
                    LabeledContent("Paired", value: service.pairingStore.isPaired ? "Yes" : "No")
                    LabeledContent("Keep awake", value: service.keepsScreenAwake ? "Yes" : "No")
                    LabeledContent("Preview", value: service.previewStatus)
                    LabeledContent("Recording", value: service.capture.isRecording ? "Yes" : "No")
                    LabeledContent("Profile", value: service.capture.currentProfile.displayName)
                    Button("Reset pairing") {
                        service.resetPairing()
                    }
                }

                if let error = service.lastError ?? service.capture.lastError {
                    Section("Last error") {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }

                Section("Recordings") {
                    if service.store.recordings.isEmpty {
                        Text("No recordings yet.")
                    } else {
                        ForEach(service.store.recordings) { recording in
                            VStack(alignment: .leading) {
                                Text(recording.url.lastPathComponent)
                                Text("\(recording.byteCount) bytes - \(recording.state.rawValue)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Video Sync")
        }
    }
}
#endif
