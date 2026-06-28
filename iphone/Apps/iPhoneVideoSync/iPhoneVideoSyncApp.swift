#if os(iOS)
import SwiftUI
#if canImport(iPhoneVideoSyncKit)
import iPhoneVideoSyncKit
#endif

@main
struct iPhoneVideoSyncApp: App {
    @StateObject private var service = AppServiceFactory.make()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(service)
                .task {
                    await service.prepare()
                    service.startNetworkServices()
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
