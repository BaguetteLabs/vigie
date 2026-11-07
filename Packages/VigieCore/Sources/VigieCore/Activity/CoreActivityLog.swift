import Foundation
import ModuleKit

/// `context.activity` for one module: stamps the module id (whatever the module put is overridden), redacts
/// `detail`, and forwards to the store. Fire and forget; ordered through the store actor.
public struct CoreActivityLog: ActivityLog {
    let moduleID: ModuleID
    let store: ActivityStore

    public init(moduleID: ModuleID, store: ActivityStore) {
        self.moduleID = moduleID
        self.store = store
    }

    public func record(_ entry: ActivityEntry) {
        var e = entry.redacted()
        e.module = moduleID
        let store = store
        Task { await store.append(e) }
    }
}

/// For core components (Notifier, Focus): records as given (module id kept as set, possibly nil), redacted.
public struct CoreActivityRecorder: ActivityLog {
    let store: ActivityStore

    public init(store: ActivityStore) { self.store = store }

    public func record(_ entry: ActivityEntry) {
        let e = entry.redacted()
        let store = store
        Task { await store.append(e) }
    }
}
