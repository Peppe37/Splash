import Foundation
import Testing
@testable import SplashPlatform

/// A small store shaped like the real one (macOS 26): the display defaults, and per Space a default entry and per-display entries.
/// One Space shows our picture (what `setDesktopImageURL` wrote); the others still show the system's Aerial wallpaper.
@Suite("WallpaperStore")
struct WallpaperStoreTests {
    static let picture = "/Users/test/Library/Application Support/Splash/Stills/dusk-1.png"

    static func configuration(for path: String) -> Data {
        let encoded = URL(fileURLWithPath: path).absoluteString
        let plist: [String: Any] = ["type": "imageFile", "url": ["relative": encoded]]
        return try! PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
    }

    static func pictureEntry(_ path: String, date: Date) -> [String: Any] {
        let choice: [String: Any] = ["Provider": "com.apple.wallpaper.choice.image", "Files": [Any](), "Configuration": configuration(for: path)]
        let desktop: [String: Any] = ["LastSet": date, "LastUse": date,
                                      "Content": ["Choices": [choice], "Shuffle": "$null", "EncodedOptionValues": Data([1])]]
        let idle: [String: Any] = ["LastSet": date, "LastUse": date,
                                   "Content": ["Choices": [["Provider": "com.apple.wallpaper.choice.aerials", "Files": [Any](), "Configuration": Data([2])]],
                                               "Shuffle": "$null", "EncodedOptionValues": "$null"]]
        return ["Type": "individual", "Desktop": desktop, "Idle": idle]
    }

    static func aerialEntry(date: Date) -> [String: Any] {
        let choice: [String: Any] = ["Provider": "com.apple.wallpaper.choice.aerials", "Files": [Any](), "Configuration": Data([3])]
        return ["Type": "linked", "Linked": ["LastSet": date, "LastUse": date,
                                              "Content": ["Choices": [choice], "Shuffle": "$null", "EncodedOptionValues": "$null"]]]
    }

    static func store(picture: String? = picture) -> [String: Any] {
        let old = Date(timeIntervalSince1970: 1_000), new = Date(timeIntervalSince1970: 2_000)
        let current: [String: Any] = [
            "Default": picture.map { pictureEntry($0, date: new) } ?? aerialEntry(date: old),
            "Displays": ["DISPLAY-A": picture.map { pictureEntry($0, date: new) } ?? aerialEntry(date: old)],
        ]
        func aerialSpace(_ displays: [String]) -> [String: Any] {
            ["Default": aerialEntry(date: old), "Displays": Dictionary(uniqueKeysWithValues: displays.map { ($0, aerialEntry(date: old)) })]
        }
        return [
            "AllSpacesAndDisplays": "$null",
            "SystemDefault": aerialEntry(date: old),
            "Spaces": ["SPACE-1": current, "SPACE-2": aerialSpace(["DISPLAY-A"]), "SPACE-3": aerialSpace(["DISPLAY-A", "DISPLAY-B"])],
            "Displays": ["DISPLAY-A": aerialEntry(date: old), "DISPLAY-B": aerialEntry(date: old)],
        ]
    }

    @Test func everySpaceGetsThePicture() throws {
        let before = WallpaperStore.spacesShowing(Self.picture, in: Self.store())
        #expect(before.showing == 1 && before.total == 3)

        let result = try #require(WallpaperStore.spread(Self.store(), imagePath: Self.picture))
        let after = WallpaperStore.spacesShowing(Self.picture, in: result.root)
        #expect(result.spaces == 3)
        #expect(after.showing == 3 && after.total == 3)
    }

    @Test func everyDisplayInEverySpaceGetsIt() throws {
        let result = try #require(WallpaperStore.spread(Self.store(), imagePath: Self.picture))
        let spaces = try #require(result.root["Spaces"] as? [String: Any])
        for (_, value) in spaces {
            let displays = try #require((value as? [String: Any])?["Displays"] as? [String: Any])
            for (_, entry) in displays {
                #expect(WallpaperStore.isPicture(try #require(entry as? [String: Any]), at: Self.picture))
            }
        }
        // A display that only some Spaces had (DISPLAY-B) gets the picture too, by borrowing the reference entry.
        let third = try #require((spaces["SPACE-3"] as? [String: Any])?["Displays"] as? [String: Any])
        #expect(third.keys.sorted() == ["DISPLAY-A", "DISPLAY-B"])
    }

    @Test func theDisplayDefaultsFollowSoNewSpacesMatch() throws {
        let result = try #require(WallpaperStore.spread(Self.store(), imagePath: Self.picture))
        let displays = try #require(result.root["Displays"] as? [String: Any])
        #expect(displays.count == 2)
        for (_, entry) in displays { #expect(WallpaperStore.isPicture(try #require(entry as? [String: Any]), at: Self.picture)) }
    }

    @Test func everythingElseInTheFileIsLeftAlone() throws {
        let result = try #require(WallpaperStore.spread(Self.store(), imagePath: Self.picture))
        #expect(result.root["AllSpacesAndDisplays"] as? String == "$null")
        #expect((result.root["SystemDefault"] as? [String: Any])?["Type"] as? String == "linked")
        #expect(Set(result.root.keys) == Set(Self.store().keys))
    }

    @Test func nothingChangesIfMacOSDidNotWriteTheEntry() {
        // The picture asked for is not the one in the store.
        #expect(WallpaperStore.spread(Self.store(), imagePath: "/somewhere/else.png") == nil)
        // No Space shows a picture at all.
        #expect(WallpaperStore.spread(Self.store(picture: nil), imagePath: Self.picture) == nil)
        // A layout this code does not know.
        #expect(WallpaperStore.spread(["Something": "else"], imagePath: Self.picture) == nil)
        #expect(WallpaperStore.spread([:], imagePath: Self.picture) == nil)
    }

    @Test func theNewestEntryIsTheReference() throws {
        var store = Self.store()
        var spaces = try #require(store["Spaces"] as? [String: Any])
        // An older Space that also points at the same file, but with a different colour option, must not win.
        var older = try #require(spaces["SPACE-2"] as? [String: Any])
        var entry = Self.pictureEntry(Self.picture, date: Date(timeIntervalSince1970: 500))
        var desktop = try #require(entry["Desktop"] as? [String: Any])
        var content = try #require(desktop["Content"] as? [String: Any])
        content["EncodedOptionValues"] = Data([9, 9, 9])
        desktop["Content"] = content
        entry["Desktop"] = desktop
        older["Default"] = entry
        spaces["SPACE-2"] = older
        store["Spaces"] = spaces

        let result = try #require(WallpaperStore.spread(store, imagePath: Self.picture))
        let resultSpaces = try #require(result.root["Spaces"] as? [String: Any])
        let first = try #require((resultSpaces["SPACE-3"] as? [String: Any])?["Default"] as? [String: Any])
        let options = (((first["Desktop"] as? [String: Any])?["Content"]) as? [String: Any])?["EncodedOptionValues"] as? Data
        #expect(options == Data([1]))
    }

    @Test func theResultIsAValidPropertyList() throws {
        let result = try #require(WallpaperStore.spread(Self.store(), imagePath: Self.picture))
        let data = try PropertyListSerialization.data(fromPropertyList: result.root, format: .binary, options: 0)
        let back = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(WallpaperStore.spacesShowing(Self.picture, in: back).showing == 3)
    }
}
