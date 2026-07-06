#if os(iOS)
import SwiftUI
#if canImport(ReaShootKit)
import ReaShootKit
#endif
#if canImport(ReaShootCore)
import ReaShootCore
#endif

struct ContentView: View {
    @EnvironmentObject private var service: ReaShootService
    @State private var recordingToDelete: RecordingFile?

    var body: some View {
        NavigationStack {
            Form {
                Section("Status") {
                    LabeledContent("Network", value: service.status)
                    LabeledContent("Paired computer", value: service.pairingStore.pairedClientName ?? "None")
                    LabeledContent("Preview", value: service.previewStatus)
                    LabeledContent("Recording", value: recordingStatus)
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
                            HStack(alignment: .top) {
                                VStack(alignment: .leading) {
                                    Text(recording.url.lastPathComponent)
                                    Text("\(Self.formattedByteCount(recording.byteCount)) - \(recording.state.rawValue)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Delete", role: .destructive) {
                                    recordingToDelete = recording
                                }
                            }
                            .swipeActions {
                                Button("Delete", role: .destructive) {
                                    recordingToDelete = recording
                                }
                            }
                        }

                    }
                }
            }
            .navigationTitle("ReaShoot")
            .safeAreaInset(edge: .bottom) {
                Text(buildInfoText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(.bar)
            }
            .confirmationDialog(
                pairingRequestTitle,
                isPresented: isShowingPairingRequest,
                titleVisibility: .visible
            ) {
                Button("Accept", role: .none) {
                    service.acceptPairingRequest()
                }
                Button("Reject", role: .cancel) {
                    service.rejectPairingRequest()
                }
            } message: {
                Text("Only one computer can be paired at a time. Accepting this request replaces the current paired computer.")
            }
            .confirmationDialog(
                "Delete pending video?",
                isPresented: isShowingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                if let recording = recordingToDelete {
                    Button("Delete \(recording.url.lastPathComponent)", role: .destructive) {
                        service.deletePendingRecording(id: recording.id)
                        recordingToDelete = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    recordingToDelete = nil
                }
            } message: {
                Text("This removes the video from the iPhone without downloading it.")
            }
        }
    }

    private var pairingRequestTitle: String {
        "Accept pairing request from \(service.pendingPairingRequest?.clientName ?? "Unknown computer")"
    }

    private var isShowingPairingRequest: Binding<Bool> {
        Binding(
            get: { service.pendingPairingRequest != nil },
            set: { isPresented in
                if !isPresented {
                    service.rejectPairingRequest()
                }
            }
        )
    }

    private var isShowingDeleteConfirmation: Binding<Bool> {
        Binding(
            get: { recordingToDelete != nil },
            set: { isPresented in
                if !isPresented {
                    recordingToDelete = nil
                }
            }
        )
    }

    private var recordingStatus: String {
        if service.capture.isApplyingLook {
            if let progress = service.capture.lookExportProgress {
                return "Encoding \(Int(progress * 100.0))%"
            }
            return "Encoding"
        }
        return service.capture.isRecording ? "Yes" : "No"
    }

    private var buildInfoText: String {
        "Build \(ReaShootBuildInfo.commit) - \(ReaShootBuildInfo.timestampPacific)"
    }

    private static func formattedByteCount(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }
}
#endif
