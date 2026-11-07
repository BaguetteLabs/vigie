import ModuleKit
import Observation

/// A Vigie surface that can hold keyboard focus: the expanded notch, the notes panel, the Settings window...
/// The host's panels conform (the NotchPanel in Story 2.10).
@MainActor
public protocol KeySurface: AnyObject {
    /// Stable identifier, unique among live surfaces.
    var surfaceID: String { get }
    /// Make the surface key (take keyboard focus).
    func makeKey()
    /// Give up key status without closing.
    func resignKey()
    /// Close the surface. The policy forgets it.
    func close()
}

/// The single arbiter of keyboard focus across Vigie surfaces (AD-13, NFR2, UX-DR45).
///
/// - A surface becomes key only when presented with a `UserIntent`; without one it is shown without focus.
/// - At most one surface is key: making one key resigns the previous key surface first.
/// - Esc closes only the key surface.
@MainActor @Observable
public final class FocusPolicy {
    /// The surface that holds keyboard focus, if any.
    public private(set) var keySurfaceID: String?
    /// Surfaces presented and not dismissed, in presentation order.
    public private(set) var presentedSurfaceIDs: [String] = []

    private final class WeakSurface {
        weak var surface: (any KeySurface)?
        init(_ surface: any KeySurface) { self.surface = surface }
    }

    @ObservationIgnored private var surfaces: [String: WeakSurface] = [:]

    public init() {}

    /// Records `surface` as presented (the caller shows it). With `focus`, the surface becomes the key surface,
    /// after the previous key surface resigns. Without it, nothing takes focus and the current key surface keeps it.
    public func present(_ surface: any KeySurface, focus: UserIntent?) {
        let id = surface.surfaceID
        surfaces[id] = WeakSurface(surface)
        if !presentedSurfaceIDs.contains(id) { presentedSurfaceIDs.append(id) }
        guard focus != nil else { return }
        if let current = keySurfaceID, current != id {
            surfaces[current]?.surface?.resignKey()
        }
        surface.makeKey()
        keySurfaceID = id
    }

    /// Esc: closes the key surface, if any, and returns true (Esc consumed). Returns false when no surface
    /// is key; other surfaces are never closed by Esc.
    @discardableResult
    public func handleEscape() -> Bool {
        guard let id = keySurfaceID else { return false }
        let surface = surfaces[id]?.surface
        forget(id)
        surface?.close()
        return surface != nil
    }

    /// The surface was closed (by the user, the host or itself). Focus does not move to another surface.
    public func dismissed(_ surface: any KeySurface) {
        forget(surface.surfaceID)
    }

    /// The surface lost key status outside the policy (e.g. the user clicked another app).
    public func surfaceDidResignKey(_ surface: any KeySurface) {
        if keySurfaceID == surface.surfaceID { keySurfaceID = nil }
    }

    public func isKey(_ surface: any KeySurface) -> Bool { keySurfaceID == surface.surfaceID }

    private func forget(_ id: String) {
        surfaces[id] = nil
        presentedSurfaceIDs.removeAll { $0 == id }
        if keySurfaceID == id { keySurfaceID = nil }
    }
}
