#if os(iOS)
import SwiftUI
#if canImport(iPhoneVideoSyncKit)
import iPhoneVideoSyncKit
#endif

@main
struct iPhoneVideoSyncApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var service = AppServiceFactory.make()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(service)
                .task {
                    service.startNetworkServices()
                    await service.prepare()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .active:
                        service.applicationBecameActive()
                    case .inactive, .background:
                        service.applicationResignedActive()
                    @unknown default:
                        break
                    }
                }
        }
    }
}

@MainActor
private enum AppServiceFactory {
    static func make() -> iPhoneVideoSyncService {
        do {
            return try iPhoneVideoSyncService()
        } catch {
            fatalError("Could not create iPhoneVideoSyncService: \(error)")
        }
    }
}
#endif
