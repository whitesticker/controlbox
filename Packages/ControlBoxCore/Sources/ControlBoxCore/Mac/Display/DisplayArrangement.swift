import AppKit
import CoreGraphics
import Foundation

/// One screen in a saved or live arrangement. Origins are Quartz global coordinates
/// (`CGDisplayBounds`): main display at `(0, 0)`, Y down. Do not persist `CGDirectDisplayID`.
public struct ArrangedScreen: Codable, Equatable, Identifiable, Sendable {
    public var identity: String
    public var name: String
    public var isBuiltIn: Bool
    public var x: Int32
    public var y: Int32
    public var width: Int32
    public var height: Int32
    public var isMain: Bool
    public var mirrorMaster: String?

    public var id: String { identity }

    public var rect: CGRect {
        CGRect(x: CGFloat(x), y: CGFloat(y), width: CGFloat(width), height: CGFloat(height))
    }

    public init(
        identity: String,
        name: String,
        isBuiltIn: Bool,
        x: Int32,
        y: Int32,
        width: Int32,
        height: Int32,
        isMain: Bool,
        mirrorMaster: String? = nil
    ) {
        self.identity = identity
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.isMain = isMain
        self.mirrorMaster = mirrorMaster
    }
}

public struct NamedDisplayIdentity: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var key: String
    public var name: String
    public var id: String { key }

    public init(key: String, name: String) {
        self.key = key
        self.name = name
    }
}

public struct DisplayCombo: Codable, Equatable, Identifiable, Sendable {
    public var externals: [NamedDisplayIdentity]

    public var id: String { DisplayArrangement.comboID(externalKeys: externals.map(\.key)) }

    public var title: String {
        if externals.isEmpty { return "Built-in only" }
        return externals.map(\.name).joined(separator: " + ")
    }

    public init(externals: [NamedDisplayIdentity]) {
        self.externals = externals.sorted { $0.key < $1.key }
    }
}

public struct ArrangementPreset: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var comboID: String
    public var includesBuiltIn: Bool
    public var screens: [ArrangedScreen]
    public var createdAt: Date

    public var isMirrored: Bool { screens.contains { $0.mirrorMaster != nil } }

    public init(
        id: String = UUID().uuidString,
        name: String,
        comboID: String,
        includesBuiltIn: Bool,
        screens: [ArrangedScreen],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.comboID = comboID
        self.includesBuiltIn = includesBuiltIn
        self.screens = DisplayLayoutMath.normalized(screens)
        self.createdAt = createdAt
    }
}

public struct DisplaySnapshot: Equatable, Sendable {
    public var screens: [ArrangedScreen]
    public var displayIDs: [String: CGDirectDisplayID]
    public var facts: [PanelFacts]
    public var combo: DisplayCombo
    public var includesBuiltIn: Bool

    public var comboID: String { combo.id }
    public var comboTitle: String { combo.title }
}

public struct PanelFacts: Equatable, Sendable {
    public var key: String
    public var name: String
    public var isBuiltIn: Bool
    public var vendor: UInt32
    public var model: UInt32
    public var serials: [String]
    public var uuids: [String]
}

public enum DisplayApplyResult: Equatable, Sendable {
    case applied
    case comboMismatch
    case builtInMismatch
    case missingDisplay(name: String)
    case failed(String)
}

public struct ArrangementStore: Codable, Equatable, Sendable {
    public var version: Int
    public var combos: [DisplayCombo]
    public var presets: [ArrangementPreset]
    public var shortcutEnabled: Bool?
    public var shortcutFlags: UInt64?

    public static let empty = ArrangementStore(version: 1, combos: [], presets: [])
    public static let defaultShortcutFlags =
        CGEventFlags.maskControl.union(.maskAlternate).union(.maskCommand).rawValue

    public var resolvedShortcutEnabled: Bool { shortcutEnabled ?? false }
    public var resolvedShortcutFlags: UInt64 { shortcutFlags ?? Self.defaultShortcutFlags }

    public init(
        version: Int = 1,
        combos: [DisplayCombo],
        presets: [ArrangementPreset],
        shortcutEnabled: Bool? = nil,
        shortcutFlags: UInt64? = nil
    ) {
        self.version = version
        self.combos = combos
        self.presets = presets
        self.shortcutEnabled = shortcutEnabled
        self.shortcutFlags = shortcutFlags
    }
}

public enum DisplayArrangement {
    public static let comboNone = "none"
    private static let serialMissing: UInt32 = 0xFFFF_FFFF

    public static func comboID(externalKeys: [String]) -> String {
        let keys = Set(externalKeys).sorted()
        if keys.isEmpty { return comboNone }
        return keys.joined(separator: "\u{1e}")
    }

    public static func snapshot() -> DisplaySnapshot {
        let ids = onlineDisplayIDs()
        let matches = Arm64DDC.serviceMatches(for: ids)
        var screens: [ArrangedScreen] = []
        var displayIDs: [String: CGDirectDisplayID] = [:]
        var facts: [PanelFacts] = []
        var seen: Set<String> = []

        for displayID in ids {
            let name = screenName(displayID)
            if shouldIgnore(displayID, name: name) { continue }
            let identity = identityKey(displayID: displayID, name: name, matches: matches)
            if seen.contains(identity) { continue }
            seen.insert(identity)
            let bounds = CGDisplayBounds(displayID)
            let mirrorMasterID = CGDisplayMirrorsDisplay(displayID)
            let mirrorMaster: String?
            if mirrorMasterID != kCGNullDirectDisplay, mirrorMasterID != displayID {
                mirrorMaster = identityKey(displayID: mirrorMasterID, name: screenName(mirrorMasterID), matches: matches)
            } else {
                mirrorMaster = nil
            }
            let screen = ArrangedScreen(
                identity: identity,
                name: name,
                isBuiltIn: CGDisplayIsBuiltin(displayID) != 0,
                x: Int32(bounds.origin.x.rounded()),
                y: Int32(bounds.origin.y.rounded()),
                width: Int32(bounds.width.rounded()),
                height: Int32(bounds.height.rounded()),
                isMain: CGDisplayIsMain(displayID) != 0,
                mirrorMaster: mirrorMaster
            )
            screens.append(screen)
            displayIDs[identity] = displayID
            facts.append(panelFacts(displayID: displayID, key: identity, name: name, matches: matches))
        }

        screens.sort { $0.identity < $1.identity }
        let externals = screens.filter { !$0.isBuiltIn }.map {
            NamedDisplayIdentity(key: $0.identity, name: $0.name)
        }
        return DisplaySnapshot(
            screens: screens,
            displayIDs: displayIDs,
            facts: facts,
            combo: DisplayCombo(externals: externals),
            includesBuiltIn: screens.contains(where: \.isBuiltIn)
        )
    }

    public static func canApply(_ preset: ArrangementPreset, live: DisplaySnapshot) -> Bool {
        guard let aligned = aligned(preset, to: live) else { return false }
        return aligned.includesBuiltIn == live.includesBuiltIn
            && Set(aligned.screens.map(\.identity)) == Set(live.screens.map(\.identity))
    }

    public static func matchesLive(_ preset: ArrangementPreset, live: DisplaySnapshot) -> Bool {
        guard let aligned = aligned(preset, to: live),
              aligned.includesBuiltIn == live.includesBuiltIn else { return false }
        let saved = DisplayLayoutMath.normalized(aligned.screens)
        let current = DisplayLayoutMath.normalized(live.screens)
        for screen in saved {
            guard let liveScreen = current.first(where: { $0.identity == screen.identity }) else {
                return false
            }
            if abs(liveScreen.x - screen.x) > 4 || abs(liveScreen.y - screen.y) > 4 {
                return false
            }
            if liveScreen.isMain != screen.isMain { return false }
            if liveScreen.mirrorMaster != screen.mirrorMaster { return false }
        }
        return true
    }

    public static func apply(_ preset: ArrangementPreset) -> DisplayApplyResult {
        let live = snapshot()
        guard let aligned = aligned(preset, to: live) else { return .comboMismatch }
        guard aligned.includesBuiltIn == live.includesBuiltIn else { return .builtInMismatch }

        let screens = DisplayLayoutMath.normalized(aligned.screens)
        var config: CGDisplayConfigRef?
        let begin = CGBeginDisplayConfiguration(&config)
        guard begin == .success, let config else {
            return .failed("Could not start a display configuration.")
        }

        for screen in screens {
            guard let displayID = live.displayIDs[screen.identity] else {
                CGCancelDisplayConfiguration(config)
                return .missingDisplay(name: screen.name)
            }
            let mirrorTarget: CGDirectDisplayID
            if let master = screen.mirrorMaster, let masterID = live.displayIDs[master] {
                mirrorTarget = masterID
            } else {
                mirrorTarget = kCGNullDirectDisplay
            }
            let mirrorError = CGConfigureDisplayMirrorOfDisplay(config, displayID, mirrorTarget)
            if mirrorError != .success {
                CGCancelDisplayConfiguration(config)
                return .failed("Could not update mirroring for \(screen.name).")
            }
            if screen.mirrorMaster == nil {
                let originError = CGConfigureDisplayOrigin(config, displayID, screen.x, screen.y)
                if originError != .success {
                    CGCancelDisplayConfiguration(config)
                    return .failed("Could not move \(screen.name).")
                }
            }
        }

        let complete = CGCompleteDisplayConfiguration(config, .permanently)
        if complete != .success {
            return .failed("macOS refused this arrangement. Displays have to touch without overlapping.")
        }
        return .applied
    }

    public static func upsertCombo(_ combo: DisplayCombo, into store: inout ArrangementStore) {
        if let index = store.combos.firstIndex(where: { $0.id == combo.id }) {
            store.combos[index] = combo
        } else {
            store.combos.append(combo)
        }
        store.combos.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    public static func pruneEmptyCombos(_ store: inout ArrangementStore) {
        let used = Set(store.presets.map(\.comboID))
        store.combos.removeAll { !used.contains($0.id) }
    }

    /// Rewrite stored panel keys onto the live hardware, then collapse combos that
    /// become the same set of monitors. Same desk saved under an old key format
    /// (or serial vs UUID) otherwise shows up as two groups with the same names.
    public static func reconcile(_ store: inout ArrangementStore, live: DisplaySnapshot) {
        for index in store.presets.indices {
            if let aligned = aligned(store.presets[index], to: live) {
                store.presets[index] = aligned
            }
        }
        var combos: [String: DisplayCombo] = [:]
        for preset in store.presets {
            let externals = preset.screens.filter { !$0.isBuiltIn }.map {
                NamedDisplayIdentity(key: $0.identity, name: $0.name)
            }
            let combo = DisplayCombo(externals: externals)
            combos[combo.id] = combo
        }
        if combos[live.comboID] != nil {
            combos[live.comboID] = live.combo
        }
        store.combos = Array(combos.values).sorted { $0.id < $1.id }
        pruneEmptyCombos(&store)
    }

    public static func aligned(_ preset: ArrangementPreset, to live: DisplaySnapshot) -> ArrangementPreset? {
        let storedExternals = preset.screens.filter { !$0.isBuiltIn }
        let liveExternals = live.facts.filter { !$0.isBuiltIn }
        guard storedExternals.count == liveExternals.count else { return nil }

        let map: [String: String]
        if storedExternals.isEmpty {
            map = [:]
        } else {
            let stored = storedExternals.map { (key: $0.identity, name: $0.name) }
            guard let matched = matchIdentities(stored: stored, live: liveExternals) else { return nil }
            map = matched
        }

        var next = preset
        next.comboID = live.comboID
        next.screens = preset.screens.map { screen in
            var rewritten = screen
            if screen.isBuiltIn {
                rewritten.identity = "builtin"
                if let liveName = live.screens.first(where: \.isBuiltIn)?.name {
                    rewritten.name = liveName
                }
                return rewritten
            }
            let liveKey = map[screen.identity] ?? screen.identity
            rewritten.identity = liveKey
            if let liveScreen = live.screens.first(where: { $0.identity == liveKey }) {
                rewritten.name = liveScreen.name
            }
            if let master = screen.mirrorMaster {
                if master == "builtin" || preset.screens.contains(where: { $0.identity == master && $0.isBuiltIn }) {
                    rewritten.mirrorMaster = "builtin"
                } else {
                    rewritten.mirrorMaster = map[master] ?? master
                }
            }
            return rewritten
        }
        return next
    }

    private static func shouldIgnore(_ displayID: CGDirectDisplayID, name: String) -> Bool {
        Arm64DDC.isDummyScreen(name: name, displayID: displayID) || Arm64DDC.isVirtual(displayID)
    }

    private static func onlineDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        if count == 0 { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return Array(ids.prefix(Int(count)))
    }

    private static func screenName(_ displayID: CGDirectDisplayID) -> String {
        if CGDisplayIsBuiltin(displayID) != 0 {
            if let name = nsScreenName(displayID) { return name }
            return "Built-in"
        }
        if let name = nsScreenName(displayID) { return name }
        if let name = Arm64DDC.productName(for: displayID), !name.isEmpty { return name }
        return "Display"
    }

    private static func nsScreenName(_ displayID: CGDirectDisplayID) -> String? {
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  CGDirectDisplayID(truncating: number) == displayID else { continue }
            return screen.localizedName
        }
        return nil
    }

    private static func identityKey(
        displayID: CGDirectDisplayID,
        name: String,
        matches: [Arm64DDC.Match]
    ) -> String {
        if CGDisplayIsBuiltin(displayID) != 0 { return "builtin" }

        let vendor = CGDisplayVendorNumber(displayID)
        let model = CGDisplayModelNumber(displayID)
        let serial = panelSerials(displayID: displayID, matches: matches).first
        if let serial {
            return "panel:\(vendor)-\(model)-\(serial)"
        }
        if let uuid = uuidString(for: displayID) {
            return "panel:\(vendor)-\(model)-uuid:\(uuid)"
        }
        return "panel:\(vendor)-\(model)-\(name)"
    }

    private static func panelFacts(
        displayID: CGDirectDisplayID,
        key: String,
        name: String,
        matches: [Arm64DDC.Match]
    ) -> PanelFacts {
        if CGDisplayIsBuiltin(displayID) != 0 {
            return PanelFacts(
                key: key,
                name: name,
                isBuiltIn: true,
                vendor: 0,
                model: 0,
                serials: [],
                uuids: []
            )
        }
        return PanelFacts(
            key: key,
            name: name,
            isBuiltIn: false,
            vendor: CGDisplayVendorNumber(displayID),
            model: CGDisplayModelNumber(displayID),
            serials: panelSerials(displayID: displayID, matches: matches),
            uuids: panelUUIDs(displayID: displayID, matches: matches)
        )
    }

    private static func panelSerials(displayID: CGDirectDisplayID, matches: [Arm64DDC.Match]) -> [String] {
        var serials: [String] = []
        if let match = matches.first(where: { $0.displayID == displayID }) {
            let details = match.details
            if !details.alphanumericSerialNumber.isEmpty {
                serials.append(details.alphanumericSerialNumber)
            }
            if details.serialNumber != 0 {
                serials.append("\(details.serialNumber)")
            }
        }
        let serial = CGDisplaySerialNumber(displayID)
        if serial != 0, serial != serialMissing {
            serials.append("\(serial)")
        }
        var seen: Set<String> = []
        return serials.filter { seen.insert($0.uppercased()).inserted }
    }

    private static func panelUUIDs(displayID: CGDirectDisplayID, matches: [Arm64DDC.Match]) -> [String] {
        var uuids: [String] = []
        if let match = matches.first(where: { $0.displayID == displayID }),
           !match.details.edidUUID.isEmpty {
            uuids.append(match.details.edidUUID)
        }
        if let uuid = uuidString(for: displayID) {
            uuids.append(uuid)
        }
        var seen: Set<String> = []
        return uuids.filter { seen.insert(normalizedUUID($0)).inserted }
    }

    private static func uuidString(for displayID: CGDirectDisplayID) -> String? {
        let uuid = CGDisplayCreateUUIDFromDisplayID(displayID).takeRetainedValue()
        return CFUUIDCreateString(nil, uuid) as String?
    }

    private static func matchIdentities(
        stored: [(key: String, name: String)],
        live: [PanelFacts]
    ) -> [String: String]? {
        var remaining = live
        var map: [String: String] = [:]

        func assign(_ storedKey: String, where predicate: (PanelFacts) -> Bool) {
            guard map[storedKey] == nil else { return }
            guard let index = remaining.firstIndex(where: predicate) else { return }
            map[storedKey] = remaining[index].key
            remaining.remove(at: index)
        }

        for item in stored {
            assign(item.key) { $0.key == item.key }
        }
        for item in stored {
            let tokens = tokens(from: item.key)
            assign(item.key) { facts in
                compatible(facts, tokens: tokens) && serialOverlap(tokens, facts)
            }
        }
        for item in stored {
            let tokens = tokens(from: item.key)
            assign(item.key) { facts in
                compatible(facts, tokens: tokens) && uuidOverlap(tokens, facts)
            }
        }
        for item in stored {
            let hits = remaining.filter { $0.name == item.name }
            if hits.count == 1 {
                assign(item.key) { $0.key == hits[0].key }
            }
        }
        for item in stored {
            let tokens = tokens(from: item.key)
            guard let vendor = tokens.vendor, let model = tokens.model,
                  vendor != 0, model != 0, vendor != serialMissing, model != serialMissing else { continue }
            let hits = remaining.filter { $0.vendor == vendor && $0.model == model }
            if hits.count == 1 {
                assign(item.key) { $0.key == hits[0].key }
            }
        }

        guard map.count == stored.count, remaining.isEmpty else { return nil }
        return map
    }

    private struct StoredIdentityTokens {
        var serials: Set<String> = []
        var uuids: Set<String> = []
        var vendor: UInt32?
        var model: UInt32?
    }

    private static func tokens(from key: String) -> StoredIdentityTokens {
        var result = StoredIdentityTokens()
        if key == "builtin" { return result }

        if key.hasPrefix("panel:") {
            let rest = String(key.dropFirst("panel:".count))
            if let uuidRange = rest.range(of: "-uuid:") {
                parseVendorModel(rest[..<uuidRange.lowerBound], into: &result)
                ingestIdentityTail(String(rest[uuidRange.upperBound...]), into: &result)
                return result
            }
            let parts = rest.split(separator: "-", maxSplits: 2, omittingEmptySubsequences: false)
            if parts.count >= 2 {
                result.vendor = UInt32(parts[0])
                result.model = UInt32(parts[1])
            }
            if parts.count >= 3 {
                ingestIdentityTail(String(parts[2]), into: &result)
            }
            return result
        }

        if key.hasPrefix("edid:") {
            ingestIdentityTail(String(key.dropFirst(5)), into: &result)
            if let last = key.split(separator: "-").last {
                ingestIdentityTail(String(last), into: &result)
            }
            return result
        }

        if key.hasPrefix("cg:") {
            let rest = String(key.dropFirst(3))
            parseVendorModel(rest, into: &result)
            let parts = rest.split(separator: "-", maxSplits: 2, omittingEmptySubsequences: false)
            if parts.count >= 3 {
                ingestIdentityTail(String(parts[2]), into: &result)
            }
            return result
        }

        if key.hasPrefix("uuid:") {
            ingestIdentityTail(String(key.dropFirst(5)), into: &result)
            return result
        }

        if key.hasPrefix("name:") {
            let rest = String(key.dropFirst(5))
            parseVendorModel(rest, into: &result)
            return result
        }

        ingestIdentityTail(key, into: &result)
        return result
    }

    private static func parseVendorModel(_ text: some StringProtocol, into tokens: inout StoredIdentityTokens) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return }
        tokens.vendor = UInt32(parts[0])
        tokens.model = UInt32(parts[1])
    }

    private static func ingestIdentityTail(_ tail: String, into tokens: inout StoredIdentityTokens) {
        if looksLikeUUID(tail) {
            tokens.uuids.insert(tail)
            return
        }
        if looksLikeSerial(tail) {
            tokens.serials.insert(tail)
        }
    }

    private static func looksLikeUUID(_ value: String) -> Bool {
        let hex = normalizedUUID(value)
        return hex.count == 32 && hex.allSatisfy(\.isHexDigit)
    }

    private static func looksLikeSerial(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.contains(" ") { return false }
        return true
    }

    private static func compatible(_ facts: PanelFacts, tokens: StoredIdentityTokens) -> Bool {
        if let vendor = tokens.vendor, vendor != 0, vendor != serialMissing,
           facts.vendor != 0, facts.vendor != serialMissing, vendor != facts.vendor {
            return false
        }
        if let model = tokens.model, model != 0, model != serialMissing,
           facts.model != 0, facts.model != serialMissing, model != facts.model {
            return false
        }
        return true
    }

    private static func serialOverlap(_ tokens: StoredIdentityTokens, _ facts: PanelFacts) -> Bool {
        let stored = Set(tokens.serials.map { $0.uppercased() })
        let live = Set(facts.serials.map { $0.uppercased() })
        return !stored.isDisjoint(with: live)
    }

    private static func uuidOverlap(_ tokens: StoredIdentityTokens, _ facts: PanelFacts) -> Bool {
        let stored = Set(tokens.uuids.map(normalizedUUID))
        let live = Set(facts.uuids.map(normalizedUUID))
        return !stored.isDisjoint(with: live)
    }

    private static func normalizedUUID(_ value: String) -> String {
        value.replacingOccurrences(of: "-", with: "").uppercased()
    }
}

public enum DisplayLayoutMath {
    public static func normalized(_ screens: [ArrangedScreen]) -> [ArrangedScreen] {
        guard let main = screens.first(where: \.isMain) ?? screens.first else { return screens }
        let dx = main.x
        let dy = main.y
        return screens.map { screen in
            var next = screen
            next.x -= dx
            next.y -= dy
            next.isMain = screen.identity == main.identity
            return next
        }
    }

    public static func union(of screens: [ArrangedScreen]) -> CGRect {
        let visible = visibleScreens(screens)
        guard let first = visible.first else { return CGRect(x: 0, y: 0, width: 16, height: 9) }
        return visible.dropFirst().reduce(first.rect) { $0.union($1.rect) }
    }

    /// Bounding box as if mirroring were off, so canvas scale stays the same
    /// when only the main display is drawn.
    public static func scaleUnion(of screens: [ArrangedScreen]) -> CGRect {
        var copy = screens
        if copy.contains(where: { $0.mirrorMaster != nil }) {
            setMirrored(&copy, mirrored: false)
        }
        return union(of: copy)
    }

    public static func visibleScreens(_ screens: [ArrangedScreen]) -> [ArrangedScreen] {
        screens.filter { $0.mirrorMaster == nil }
    }

    public static func makeMain(_ screens: inout [ArrangedScreen], identity: String) {
        guard screens.contains(where: { $0.identity == identity }) else { return }
        for index in screens.indices {
            screens[index].isMain = screens[index].identity == identity
            if screens[index].identity == identity {
                screens[index].mirrorMaster = nil
            }
        }
    }

    public static func setMirrored(_ screens: inout [ArrangedScreen], mirrored: Bool) {
        guard let main = screens.first(where: \.isMain) ?? screens.first else { return }
        if mirrored {
            for index in screens.indices where screens[index].identity != main.identity {
                screens[index].mirrorMaster = main.identity
                screens[index].x = main.x
                screens[index].y = main.y
                screens[index].isMain = false
            }
            return
        }
        var cursorX = main.x + main.width
        for index in screens.indices where screens[index].identity != main.identity {
            screens[index].mirrorMaster = nil
            screens[index].x = cursorX
            screens[index].y = main.y
            cursorX += screens[index].width
        }
    }

    public static func move(
        _ screens: inout [ArrangedScreen],
        identity: String,
        origin: CGPoint,
        snapDistance: CGFloat,
        finalize: Bool
    ) {
        guard let index = screens.firstIndex(where: { $0.identity == identity }) else { return }
        if screens[index].mirrorMaster != nil { return }
        var x = origin.x
        var y = origin.y
        let others = screens.filter { $0.identity != identity && $0.mirrorMaster == nil }
        if !others.isEmpty {
            let snapped = snap(
                x: x,
                y: y,
                moving: screens[index],
                others: others,
                threshold: max(snapDistance, 32)
            )
            x = snapped.x
            y = snapped.y
        }
        screens[index].x = Int32(x.rounded())
        screens[index].y = Int32(y.rounded())
        separateOverlap(&screens, identity: identity)
        if finalize, !isConnected(screens) {
            attachToNearest(&screens, identity: identity)
        }
    }

    public static func isConnected(_ screens: [ArrangedScreen]) -> Bool {
        let visible = visibleScreens(screens)
        guard let first = visible.first else { return true }
        var seen: Set<String> = [first.identity]
        var queue = [first.identity]
        while let currentID = queue.first {
            queue.removeFirst()
            guard let current = visible.first(where: { $0.identity == currentID }) else { continue }
            for other in visible where !seen.contains(other.identity) {
                if sharesEdge(current.rect, other.rect) {
                    seen.insert(other.identity)
                    queue.append(other.identity)
                }
            }
        }
        return seen.count == visible.count
    }

    private static func snap(
        x: CGFloat,
        y: CGFloat,
        moving: ArrangedScreen,
        others: [ArrangedScreen],
        threshold: CGFloat
    ) -> CGPoint {
        let width = CGFloat(moving.width)
        let height = CGFloat(moving.height)
        let lastX = CGFloat(moving.x)
        let lastY = CGFloat(moving.y)
        var xCandidates: [SnapCandidate] = []
        var yCandidates: [SnapCandidate] = []
        for other in others {
            let ox = CGFloat(other.x)
            let oy = CGFloat(other.y)
            let ow = CGFloat(other.width)
            let oh = CGFloat(other.height)
            xCandidates.append(SnapCandidate(value: ox + ow, flush: true))
            xCandidates.append(SnapCandidate(value: ox - width, flush: true))
            xCandidates.append(SnapCandidate(value: ox, flush: false))
            xCandidates.append(SnapCandidate(value: ox + ow - width, flush: false))
            xCandidates.append(SnapCandidate(value: ox + (ow - width) / 2, flush: false))
            yCandidates.append(SnapCandidate(value: oy + oh, flush: true))
            yCandidates.append(SnapCandidate(value: oy - height, flush: true))
            yCandidates.append(SnapCandidate(value: oy, flush: false))
            yCandidates.append(SnapCandidate(value: oy + oh - height, flush: false))
            yCandidates.append(SnapCandidate(value: oy + (oh - height) / 2, flush: false))
        }
        return CGPoint(
            x: pickSnap(proposed: x, last: lastX, candidates: xCandidates, threshold: threshold),
            y: pickSnap(proposed: y, last: lastY, candidates: yCandidates, threshold: threshold)
        )
    }

    private struct SnapCandidate {
        var value: CGFloat
        var flush: Bool
    }

    private static func pickSnap(
        proposed: CGFloat,
        last: CGFloat,
        candidates: [SnapCandidate],
        threshold: CGFloat
    ) -> CGFloat {
        var best: (candidate: SnapCandidate, distance: CGFloat)?
        for candidate in candidates {
            let sticky = abs(last - candidate.value) <= 2
            let allowed = sticky ? threshold * 1.8 : threshold
            let distance = abs(proposed - candidate.value)
            guard distance <= allowed else { continue }
            if let current = best {
                if candidate.flush && !current.candidate.flush {
                    best = (candidate, distance)
                } else if candidate.flush == current.candidate.flush, distance < current.distance {
                    best = (candidate, distance)
                }
            } else {
                best = (candidate, distance)
            }
        }
        return best?.candidate.value ?? proposed
    }

    private static func separateOverlap(_ screens: inout [ArrangedScreen], identity: String) {
        guard let index = screens.firstIndex(where: { $0.identity == identity }) else { return }
        for other in screens where other.identity != identity && other.mirrorMaster == nil {
            let a = screens[index].rect
            let b = other.rect
            guard a.intersects(b) else { continue }
            let inter = a.intersection(b)
            if inter.width <= 0 || inter.height <= 0 { continue }
            if inter.width < inter.height {
                screens[index].x = Int32((a.midX >= b.midX ? b.maxX : b.minX - a.width).rounded())
            } else {
                screens[index].y = Int32((a.midY >= b.midY ? b.maxY : b.minY - a.height).rounded())
            }
        }
    }

    private static func attachToNearest(_ screens: inout [ArrangedScreen], identity: String) {
        guard let index = screens.firstIndex(where: { $0.identity == identity }) else { return }
        let moving = screens[index]
        var best: (distance: CGFloat, x: Int32, y: Int32)?
        for other in screens where other.identity != identity && other.mirrorMaster == nil {
            for candidate in flushOrigins(moving, against: other) {
                let distance = hypot(CGFloat(candidate.x - moving.x), CGFloat(candidate.y - moving.y))
                if best == nil || distance < best!.distance {
                    best = (distance, candidate.x, candidate.y)
                }
            }
        }
        if let best {
            screens[index].x = best.x
            screens[index].y = best.y
        }
    }

    private static func flushOrigins(_ moving: ArrangedScreen, against other: ArrangedScreen) -> [(x: Int32, y: Int32)] {
        let left = other.x - moving.width
        let right = other.x + other.width
        let top = other.y - moving.height
        let bottom = other.y + other.height
        let xAlign = [other.x, other.x + (other.width - moving.width) / 2, other.x + other.width - moving.width]
        let yAlign = [other.y, other.y + (other.height - moving.height) / 2, other.y + other.height - moving.height]
        var result: [(x: Int32, y: Int32)] = []
        for y in yAlign {
            result.append((left, y))
            result.append((right, y))
        }
        for x in xAlign {
            result.append((x, top))
            result.append((x, bottom))
        }
        return result
    }

    private static func sharesEdge(_ a: CGRect, _ b: CGRect) -> Bool {
        let epsilon: CGFloat = 1.5
        let overlapX = min(a.maxX, b.maxX) - max(a.minX, b.minX)
        let overlapY = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        if abs(a.maxX - b.minX) <= epsilon || abs(b.maxX - a.minX) <= epsilon {
            return overlapY > 8
        }
        if abs(a.maxY - b.minY) <= epsilon || abs(b.maxY - a.minY) <= epsilon {
            return overlapX > 8
        }
        return false
    }
}
