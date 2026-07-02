#if os(iOS)
import SwiftUI
#if canImport(ReaShootKit)
import ReaShootKit
#endif

@main
struct ReaShootApp: App {
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
    static func make() -> ReaShootService {
        do {
            return try ReaShootService()
        } catch {
            fatalError("Could not create ReaShootService: \(error)")
        }
    }
}
#endif
