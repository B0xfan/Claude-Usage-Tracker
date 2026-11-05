//
//  TopShelfTests.swift
//  Claude UsageTests
//
//  Top Shelf's own self-test (from John's Top Shelf app, SelfTest.swift), run as XCTest inside the tracker.
//  Every check uses temporary folders, a throwaway settings store and a spare port: nothing here touches
//  the real ~/.claude/settings.json, the Keychain, real logins or the separate Top Shelf app's settings.
//

import XCTest
import AppKit
import SwiftUI
@testable import Claude_Usage

@MainActor
final class TopShelfTests: XCTestCase {
    // Each test gets a throwaway settings store and the spare port.
    nonisolated(unsafe) private var suite = ""

    nonisolated override func setUp() {
        super.setUp()
        let name = "TopShelfTests-\(UUID().uuidString)"
        suite = name
        MainActor.assumeIsolated {
            TopShelfDefaults.store = UserDefaults(suiteName: name)!
            Agents.listenPort = 47823
        }
    }

    nonisolated override func tearDown() {
        let name = suite
        MainActor.assumeIsolated {
            TopShelfDefaults.store.removePersistentDomain(forName: name)
            TopShelfDefaults.store = UserDefaults(suiteName: TopShelfDefaults.suiteName) ?? .standard
            Agents.listenPort = Agents.port
        }
        super.tearDown()
    }

    func testSettingsStoreIsNotTheRealOne() {
        XCTAssertFalse(TopShelfDefaults.store === UserDefaults.standard)
        XCTAssertNotEqual(suite, TopShelfDefaults.suiteName)
    }

    func testSounds() { SelfTest.soundTests() }
    func testSettings() { SelfTest.settingsTests() }
    func testSettingsWindow() { SelfTest.settingsWindowTests() }
    func testShelf() { SelfTest.shelfTests() }
    func testMusic() { SelfTest.musicTests() }
    func testCalendarWeather() { SelfTest.calendarWeatherTests() }
    func testFiles() { SelfTest.filesTests() }
    func testClipboard() { SelfTest.clipboardTests() }
    func testAgents() { SelfTest.agentsTests() }
    func testListener() { SelfTest.listenerTest() }

    // MARK: starburst (Agent Monitor's agent-pulse)

    func testStarburstDots() {
        let expected: [(Double, Double, Double)] = [
            (10, 8, 0), (18, 6, 0.12), (26, 8, 0.24), (6, 16, 0.08), (14, 14, 0.2), (22, 14, 0.32),
            (30, 16, 0.16), (10, 24, 0.28), (18, 22, 0.4), (26, 24, 0.36), (14, 30, 0.48), (22, 30, 0.44),
        ]
        XCTAssertEqual(Starburst.dots.count, 12)
        for (d, e) in zip(Starburst.dots, expected) {
            XCTAssertEqual(d.x, e.0)
            XCTAssertEqual(d.y, e.1)
            XCTAssertEqual(d.delay, e.2, accuracy: 1e-9)
        }
        XCTAssertEqual(Starburst.box, 36)
        XCTAssertEqual(Starburst.radius, 2.1)
        XCTAssertEqual(Starburst.period, 1.35)
        XCTAssertEqual(Starburst.peakAt, 0.45)
    }

    func testStarburstKeyframes() {
        let start = Starburst.state(at: 0, delay: 0)
        XCTAssertEqual(start.opacity, 0.35, accuracy: 1e-6)
        XCTAssertEqual(start.scale, 0.75, accuracy: 1e-6)
        let peak = Starburst.state(at: 0.45 * 1.35, delay: 0)
        XCTAssertEqual(peak.opacity, 1, accuracy: 1e-6)
        XCTAssertEqual(peak.scale, 1.15, accuracy: 1e-6)
        let end = Starburst.state(at: 1.35 - 1e-9, delay: 0)
        XCTAssertEqual(end.opacity, 0.35, accuracy: 1e-4)
        XCTAssertEqual(end.scale, 0.75, accuracy: 1e-4)
        let loop = Starburst.state(at: 1.35 * 3 + 0.2, delay: 0)
        let once = Starburst.state(at: 0.2, delay: 0)
        XCTAssertEqual(loop.opacity, once.opacity, accuracy: 1e-6, "repeats every 1.35 s")
        let late = Starburst.state(at: 0.48, delay: 0.48)
        XCTAssertEqual(late.opacity, 0.35, accuracy: 1e-6, "each dot starts its loop after its own delay")
    }

    func testStarburstEasing() {
        // CSS ease-in-out: halfway in time is halfway in value, slow at both ends.
        XCTAssertEqual(Starburst.easeInOut(0), 0, accuracy: 1e-6)
        XCTAssertEqual(Starburst.easeInOut(0.5), 0.5, accuracy: 1e-6)
        XCTAssertEqual(Starburst.easeInOut(1), 1, accuracy: 1e-6)
        XCTAssertLessThan(Starburst.easeInOut(0.1), 0.1)
        XCTAssertGreaterThan(Starburst.easeInOut(0.9), 0.9)
        let mid = Starburst.state(at: 0.45 * 1.35 / 2, delay: 0)
        XCTAssertEqual(mid.opacity, (0.35 + 1) / 2, accuracy: 1e-6)
        XCTAssertEqual(mid.scale, (0.75 + 1.15) / 2, accuracy: 1e-6)
    }

    func testStarburstColor() {
        let c = NSColor(Starburst.orange).usingColorSpace(.sRGB)!
        XCTAssertEqual(c.redComponent, 1, accuracy: 0.01)
        XCTAssertEqual(c.greenComponent, 0x7a / 255.0, accuracy: 0.01)
        XCTAssertEqual(c.blueComponent, 0x33 / 255.0, accuracy: 0.01)
    }
}

/// Top Shelf's checks, as written for its own --selftest; `check` reports through XCTest.
@MainActor
enum SelfTest {
    static func check(_ name: String, _ ok: Bool, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(ok, name, file: file, line: line)
    }

    static func shelfTests() {
        let g = ShelfNotchGeometry(screenWidth: 1512, leftWidth: 662, rightWidth: 662, topInset: 32, menuBarHeight: 37)
        check("notch: width is the gap between the two side areas", g.hasNotch && g.notchWidth == 188 && g.notchHeight == 32)
        let flat = ShelfNotchGeometry(screenWidth: 2560, leftWidth: nil, rightWidth: nil, topInset: 0, menuBarHeight: 25)
        check("no notch: a 200 pt capsule as tall as the menu bar", !flat.hasNotch && flat.notchWidth == 200 && flat.notchHeight == 25)
        let odd = ShelfNotchGeometry(screenWidth: 1000, leftWidth: 600, rightWidth: 600, topInset: 32, menuBarHeight: 24)
        check("nonsense side areas fall back to the capsule", !odd.hasNotch)

        let m = ShelfModel()
        m.open(.clipboard)
        check("open goes to the asked page", m.isOpen && m.page == .clipboard && !m.openedByHover)
        m.toggle(.clipboard)
        check("toggling the open page closes", !m.isOpen)
        m.open(.tray, byHover: true); m.toggle(.files)
        check("toggling another page switches to it", m.isOpen && m.page == .files && !m.openedByHover)
        check("open size matches Bartender's (611 x 174)", m.openSize == CGSize(width: 611, height: 174))
        check("closed with nothing going on: exactly the notch", m.collapsedSize.width == m.geometry.notchWidth)
        func agentPost(_ json: String) { _ = SelfTest.post(m.agents, json) }
        agentPost(#"{"session_id":"w","hook_event_name":"UserPromptSubmit","cwd":"/x/p"}"#)
        check("closed: a working session shows, with no music or meeting", m.hasBanners && m.agents.activeState == .working && m.agents.activeCount == 1)
        check("closed: Bartender's width, 37.5 pt a side plus a 4.5 pt flare (263 pt with a 179 pt notch)",
              m.collapsedSize.width == m.geometry.notchWidth + 84)
        agentPost(#"{"session_id":"n","hook_event_name":"Notification","notification_type":"permission_prompt","cwd":"/x/q"}"#)
        check("closed: waiting for John wins over working, and both count", m.agents.activeState == .attention && m.agents.activeCount == 2)
        agentPost(#"{"session_id":"n","hook_event_name":"Stop","cwd":"/x/q"}"#)
        agentPost(#"{"session_id":"w","hook_event_name":"Stop","cwd":"/x/p"}"#)
        check("closed: idle sessions do not count", m.agents.activeCount == 0 && !m.hasBanners)
        m.music.apply(["title": "Song", "playing": true])
        check("closed: music alone shows, same width", m.hasBanners && m.collapsedSize.width == m.geometry.notchWidth + 84)
    }
}

extension SelfTest {
    static func musicTests() {
        let m = NowPlaying(resources: nil)
        let png = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { r in NSColor.red.setFill(); r.fill(); return true }
        let art = NSBitmapImageRep(data: png.tiffRepresentation!)!.representation(using: .png, properties: [:])!.base64EncodedString()
        m.apply(["title": "Song", "artist": "Artist", "playing": true, "bundle": "com.spotify.client", "art": art])
        check("music: a helper line fills the card", m.hasTrack && m.isPlaying && m.artist == "Artist" && m.playerID == "com.spotify.client" && m.artwork != nil)
        m.apply(["title": "Song", "playing": false])
        check("music: a pause and a missing picture clear both", !m.isPlaying && m.artwork == nil && m.artist == nil)
        m.apply(["error": "missing MRMediaRemoteSendCommand"])
        check("music: a helper error marks controls unavailable", !m.available)
        check("music: without the helper files the service says unavailable",
              !NowPlaying(resources: URL(fileURLWithPath: "/nonexistent")).available)
    }

    static func calendarWeatherTests() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func ev(_ t: String, _ s: Double, _ e: Double) -> CalendarService.Event {
            .init(title: t, start: now.addingTimeInterval(s * 60), end: now.addingTimeInterval(e * 60))
        }
        let list = [ev("Later", 90, 120), ev("Done", -60, -1), ev("Soon", 11, 41)]
        check("calendar: picks the next event, skipping finished ones", CalendarService.pick(list, now: now)?.title == "Soon")
        check("calendar: an event under way wins", CalendarService.pick(list + [ev("Now", -5, 25)], now: now)?.title == "Now")
        check("calendar: nothing left today", CalendarService.pick([ev("Done", -60, -1)], now: now) == nil)
        check("calendar: in 11 minutes", CalendarService.when(ev("Soon", 11, 41), now: now) == "in 11 minutes")
        check("calendar: in 1 minute (rounded up, singular)", CalendarService.when(ev("x", 0.5, 30), now: now) == "in 1 minute")
        check("calendar: an hour or more away shows the time", CalendarService.when(ev("x", 90, 120), now: now).hasPrefix("at "))
        check("calendar: under way says now", CalendarService.when(ev("x", -5, 25), now: now).hasPrefix("now, until"))

        let w = WeatherService.parse(Data(#"{"current":{"time":"2026-10-16T15:00","temperature_2m":24.1,"weather_code":2}}"#.utf8))
        check("weather: reads Open-Meteo's answer", w?.0.value == 24.1 && w?.1 == 2)
        check("weather: a broken answer is ignored", WeatherService.parse(Data("{}".utf8)) == nil)
        check("weather: code 2 is partly cloudy, unknown codes say Weather", WeatherService.describe(2) == "Partly cloudy" && WeatherService.describe(1234) == "Weather")
        let found = WeatherService.parsePlaces(Data(#"{"results":[{"name":"Tamarindo","admin1":"Guanacaste Province","country":"Costa Rica","latitude":10.29913,"longitude":-85.84107},{"name":"Nowhere","latitude":1,"longitude":2}],"generationtime_ms":0.5}"#.utf8))
        check("weather search: reads city, region and country", found?.first?.label == "Tamarindo, Guanacaste Province, Costa Rica" && found?.last?.label == "Nowhere")
        check("weather search: no results is an empty list, a broken answer is nil",
              WeatherService.parsePlaces(Data(#"{"generationtime_ms":0.3}"#.utf8))?.isEmpty == true && WeatherService.parsePlaces(Data("oops".utf8)) == nil)
        check("weather search: the name is sent safely", WeatherService.searchURL("San José & co")?.absoluteString.contains("name=San%20Jos%C3%A9%20%26%20co") == true)
        let ws = WeatherService(live: false)
        check("weather: current location is the default", ws.source == .current && ws.chosen == nil)
        check("weather: with no place chosen it says to choose one", CalendarCard.weatherNote({ ws.source = .place; return ws }()) == "Choose a place in Settings for the weather.")
        ws.chosen = found?.first
        let again = WeatherService(live: false)
        check("weather: the picked place is kept after a relaunch", again.source == .place && again.chosen?.name == "Tamarindo" && again.chosen?.country == "Costa Rica")
        check("weather: it uses the picked place's coordinates", again.target.map { $0.latitude == 10.29913 && $0.longitude == -85.84107 } == true
              && WeatherService.forecastURL(again.target!.latitude, again.target!.longitude)?.absoluteString.contains("latitude=10.299&longitude=-85.841") == true)
        again.source = .current; again.locationOff = true
        check("weather: location off says so and points to choosing a place", CalendarCard.weatherNote(again) == "Location is off. Choose a place in Settings.")
        again.locationOff = false; again.offline = true
        check("weather: no connection says so", CalendarCard.weatherNote(again) == "No weather: no internet connection.")
        for k in ["weatherSource", "weatherPlace"] { TopShelfDefaults.store.removeObject(forKey: k) }
    }
}

extension SelfTest {
    static func soundTests() {
        let d = tempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let a = Agents(dir: d, live: false)
        var heard: [Agents.Sound] = []
        a.onSound = { heard.append($0) }
        let t0 = Date()
        func send(_ json: String, at seconds: Double = 0) {
            let body = Data(json.utf8)
            let raw = "POST /event HTTP/1.1\r\nX-Top-Shelf-Token: \(a.token)\r\nContent-Length: \(body.count)\r\n\r\n"
            if case .complete(let req) = Agents.parse(Data(raw.utf8) + body) { _ = a.handle(req, now: t0.addingTimeInterval(seconds)) }
        }
        func heardNow() -> [Agents.Sound] { defer { heard = [] }; return heard }

        // Questions
        send(#"{"session_id":"c","hook_event_name":"UserPromptSubmit","cwd":"/x/p"}"#)
        send(#"{"session_id":"c","hook_event_name":"PermissionRequest","tool_name":"Bash","cwd":"/x/p"}"#, at: 1)
        check("sounds: a permission prompt plays the question sound at once", heardNow() == [.question])
        send(#"{"session_id":"c","hook_event_name":"PermissionRequest","tool_name":"Edit","cwd":"/x/p"}"#, at: 3)
        check("sounds: a second question within a few seconds stays quiet", heardNow().isEmpty)
        send(#"{"session_id":"c","hook_event_name":"Notification","notification_type":"permission_prompt","cwd":"/x/p"}"#, at: 9)
        check("sounds: the delayed 'needs you' notice for the same prompt plays nothing", heardNow().isEmpty)
        send(#"{"session_id":"c","hook_event_name":"PostToolUse","tool_name":"Bash","cwd":"/x/p"}"#, at: 10)
        check("sounds: answering plays nothing", heardNow().isEmpty)
        send(#"{"session_id":"c","hook_event_name":"PreToolUse","tool_name":"AskUserQuestion","cwd":"/x/p"}"#, at: 15)
        check("sounds: Claude's multiple-choice question plays, once the gap has passed", heardNow() == [.question])
        send(#"{"session_id":"e","hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"/x/p"}"#)
        send(#"{"session_id":"e","hook_event_name":"Notification","notification_type":"elicitation_dialog","cwd":"/x/p"}"#)
        check("sounds: other tools are quiet; a connected tool's form plays", heardNow() == [.question])
        send(#"{"session_id":"c","hook_event_name":"PermissionRequest","agent_id":"h1","agent_type":"Explore","tool_name":"Bash","cwd":"/x/p"}"#, at: 30)
        check("sounds: a helper's question stays quiet", heardNow().isEmpty)

        // Finished
        send(#"{"session_id":"c","hook_event_name":"Stop","cwd":"/x/p"}"#, at: 31)
        check("sounds: a main chat finishing plays the finished sound", heardNow() == [.finished])
        send(#"{"session_id":"c","hook_event_name":"Stop","cwd":"/x/p"}"#, at: 32)
        send(#"{"session_id":"c","hook_event_name":"Notification","notification_type":"idle_prompt","cwd":"/x/p"}"#, at: 90)
        check("sounds: at most once per message, and the idle notice is quiet", heardNow().isEmpty)
        send(#"{"session_id":"c","hook_event_name":"UserPromptSubmit","cwd":"/x/p"}"#, at: 100)
        send(#"{"session_id":"c","hook_event_name":"SubagentStart","agent_id":"h2","agent_type":"general-purpose","cwd":"/x/p"}"#, at: 101)
        send(#"{"session_id":"c","hook_event_name":"Stop","cwd":"/x/p","background_tasks":[{"id":"t","type":"subagent","status":"running"}]}"#, at: 102)
        send(#"{"session_id":"c","hook_event_name":"Stop","agent_id":"h2","cwd":"/x/p"}"#, at: 103)
        send(#"{"session_id":"c","hook_event_name":"SubagentStop","agent_id":"h2","agent_type":"general-purpose","cwd":"/x/p"}"#, at: 104)
        check("sounds: quiet while its helpers work, and helpers' own events are quiet", heardNow().isEmpty)
        send(#"{"session_id":"c","hook_event_name":"Stop","cwd":"/x/p","background_tasks":[{"id":"t","type":"subagent","status":"in_progress"},{"id":"s","type":"shell","status":"running"}]}"#, at: 104.5)
        check("sounds: any unfinished helper holds it back; a background shell does not count as a helper", heardNow().isEmpty)
        send(#"{"session_id":"c","hook_event_name":"PostToolUse","tool_name":"Read","cwd":"/x/p"}"#, at: 105)
        send(#"{"session_id":"c","hook_event_name":"Stop","cwd":"/x/p","background_tasks":[]}"#, at: 106)
        check("sounds: plays once when the chat's reply after its last helper is done", heardNow() == [.finished])
        Agents.finishFallbackDelay = 0.2
        send(#"{"session_id":"c","hook_event_name":"UserPromptSubmit","cwd":"/x/p"}"#, at: 200)
        send(#"{"session_id":"c","hook_event_name":"SubagentStart","agent_id":"h3","agent_type":"Explore","cwd":"/x/p"}"#, at: 201)
        send(#"{"session_id":"c","hook_event_name":"Stop","cwd":"/x/p"}"#, at: 202)
        send(#"{"session_id":"c","hook_event_name":"SubagentStop","agent_id":"h3","agent_type":"Explore","cwd":"/x/p"}"#, at: 203)
        wait(1) { !heard.isEmpty }
        check("sounds: if the chat stays quiet after its last helper, it plays anyway (once)", heardNow() == [.finished])
        Agents.finishFallbackDelay = 30

        // One-off background runs (claude -p, scripts, tests) are not John's chats
        func sendAs(_ entry: String, _ json: String, at seconds: Double) {
            let body = Data(json.utf8)
            let raw = "POST /event HTTP/1.1\r\nX-Top-Shelf-Token: \(a.token)\r\nX-Claude-Entrypoint: \(entry)\r\nContent-Length: \(body.count)\r\n\r\n"
            if case .complete(let req) = Agents.parse(Data(raw.utf8) + body) { _ = a.handle(req, now: t0.addingTimeInterval(seconds)) }
        }
        sendAs("sdk-cli", #"{"session_id":"bg","hook_event_name":"UserPromptSubmit","cwd":"/x/p"}"#, at: 300)
        sendAs("sdk-cli", #"{"session_id":"bg","hook_event_name":"PermissionRequest","tool_name":"Write","cwd":"/x/p"}"#, at: 301)
        sendAs("sdk-cli", #"{"session_id":"bg","hook_event_name":"Stop","cwd":"/x/p","background_tasks":[]}"#, at: 302)
        check("sounds: one-off background runs make no sound", heardNow().isEmpty)
        sendAs("cli", #"{"session_id":"chat","hook_event_name":"Stop","cwd":"/x/p","background_tasks":[]}"#, at: 303)
        check("sounds: a chat window still does", heardNow() == [.finished])

        // The list and the saved choices
        let own = d.appendingPathComponent("Sounds")
        try? FileManager.default.createDirectory(at: own, withIntermediateDirectories: true)
        try? Data("not a real sound".utf8).write(to: own.appendingPathComponent("Doorbell.aiff"))
        try? Data("another".utf8).write(to: own.appendingPathComponent("Doorbell.wav"))   // same name twice: listed once
        try? FileManager.default.copyItem(at: AlertSounds.systemFolder.appendingPathComponent("Sosumi.aiff"),
                                          to: own.appendingPathComponent("cmux-system-notification-sound-Sosumi.aiff"))
        let list = AlertSounds.all(userFolder: own)
        check("sound list: 14 built-in under their System Settings names plus Doorbell, the copy of Sosumi left out, in order",
              list.count == 15 && list.map(\.name).prefix(5) == ["Boop", "Breeze", "Bubble", "Crystal", "Doorbell"]
              && !list.contains { $0.name.hasPrefix("cmux") } && list.first { $0.name == "Crystal" }?.file == "Glass")
        check("sound list: every built-in sound exists on this Mac", AlertSounds.builtIn.keys.allSatisfy { NSSound(named: NSSound.Name($0)) != nil })
        let m = ShelfModel()
        check("sounds: defaults are on, Crystal and Heroine", m.soundFile(.question) == "Glass" && m.soundFile(.finished) == "Hero")
        m.questionSoundOn = false; m.finishedSound = "Ping"
        let m2 = ShelfModel()
        check("sounds: choices are kept after a relaunch, and off means silent", m2.soundFile(.question) == nil && m2.soundFile(.finished) == "Ping")
        for k in ["questionSoundOn", "questionSound", "finishedSoundOn", "finishedSound"] { TopShelfDefaults.store.removeObject(forKey: k) }
    }

    static func settingsWindowTests() {
        let m = ShelfModel()
        let w = SettingsWindow.make(m)
        let short = NSRect(x: 0, y: 70, width: 1280, height: 560)   // a short screen: menu bar and Dock taken off
        SettingsWindow.fit(w, model: m, visible: short)
        let ideal = NSHostingView(rootView: TopShelfSettingsView(model: m).fixedSize(horizontal: false, vertical: true)).fittingSize.height
        check("settings window: on a short screen it fits inside the visible area (content \(Int(ideal)) pt tall, window \(Int(w.frame.height)) pt)",
              ideal > short.height && short.contains(w.frame) && w.frame.height <= short.height)
        let tall = NSRect(x: 0, y: 0, width: 1728, height: 1400)
        SettingsWindow.fit(w, model: m, visible: tall)
        check("settings window: on a tall screen it is just as tall as its content", abs(w.contentLayoutRect.height - ideal) < 2 && tall.contains(w.frame))
        SettingsWindow.fit(w, model: m, visible: short)
        let scrolls = w.contentView.map { v in
            v.layoutSubtreeIfNeeded()
            func find(_ v: NSView) -> NSScrollView? { (v as? NSScrollView) ?? v.subviews.lazy.compactMap(find).first }
            return find(v).map { $0.documentView.map { $0.frame.height > $0.visibleRect.height + 1 } ?? false } ?? false
        } ?? false
        check("settings window: the content scrolls when it doesn't fit", scrolls)
        w.close()
    }

    static func settingsTests() {
        let m = ShelfModel()
        check("settings: defaults are Both, 0.3 s, 0.5 s, 1 day, 1 week, menu bar icon on",
              m.openMode == .both && m.hoverDelay == 0.3 && m.hoverCloseDelay == 0.5 && m.keepFilesFor == 86400 && m.keepClipsFor == 604800 && m.showMenuBarIcon)
        var iconCalls = 0
        m.menuBarIconChanged = { iconCalls += 1 }
        m.showMenuBarIcon = false
        check("settings: turning the menu bar icon off applies at once and is kept", iconCalls == 1 && !ShelfModel().showMenuBarIcon)
        m.openMode = .click; m.hoverDelay = 0.2; m.hoverCloseDelay = 0.3; m.keepFilesFor = 3600; m.keepClipsFor = 86400
        let again = ShelfModel()
        check("settings: kept after a relaunch", again.openMode == .click && again.hoverDelay == 0.2 && again.hoverCloseDelay == 0.3
              && again.keepFilesFor == 3600 && again.keepClipsFor == 86400 && again.files.keepFor == 3600 && again.clipboard.keepFor == 86400)

        let hover = HoverLogic(model: m)
        hover.moved(inNotch: true)
        wait(0.6) { m.isOpen }
        check("settings: in Click mode hovering never opens the shelf", !m.isOpen)
        m.open(.tray)   // a click opening
        hover.left()
        wait(0.1) { !m.isOpen }
        let clickClosedEarly = !m.isOpen
        wait(1) { !m.isOpen }
        check("settings: in Click mode it closes after the 0.3 s close delay once the pointer leaves", !clickClosedEarly && !m.isOpen)
        m.openMode = .both
        m.open(.tray)
        hover.left()
        wait(0.6) { !m.isOpen }
        check("settings: in Both mode a click opening stays after the pointer leaves", m.isOpen)
        m.close(); hover.moved(inNotch: false)   // pointer away, ready to hover again
        m.openMode = .click
        m.open(.tray); hover.left(); m.close(); hover.closed(pointerInNotch: false)   // closed by hand while a close was pending
        m.open(.tray)
        wait(0.6) { !m.isOpen }
        check("settings: a close pending from before does not shut the next opening", m.isOpen)
        m.close(); hover.closed(pointerInNotch: false); m.openMode = .both; hover.moved(inNotch: false)   // re-arm in a mode where hover counts
        hover.moved(inNotch: true)
        wait(0.05) { m.isOpen }
        let openedEarly = m.isOpen
        wait(1) { m.isOpen }
        check("settings: the 0.2 s open delay is honoured (closed at 0.05 s, open after)", !openedEarly && m.isOpen && m.openedByHover)
        hover.left()
        wait(0.1) { !m.isOpen }
        let closedEarly = !m.isOpen
        wait(1) { !m.isOpen }
        check("settings: the 0.3 s close delay is honoured (open at 0.1 s, closed after)", !closedEarly && !m.isOpen)
        m.open(.tray); m.close(); hover.closed(pointerInNotch: true)   // closed by a click while the pointer stays on the notch
        hover.moved(inNotch: true)
        wait(0.5) { m.isOpen }
        check("settings: closing with the pointer still on the notch does not reopen it", !m.isOpen)
        // John's report: after the shelf closes because the pointer left, hovering again must open it (no move away from the notch is seen)
        hover.left()   // the pointer leaves, re-arming for the setup below
        hover.moved(inNotch: true)
        wait(1) { m.isOpen }
        hover.left()
        wait(1.5) { !m.isOpen }
        m.close(); hover.closed(pointerInNotch: false)   // what the window reports when the hover close fires with the pointer away
        hover.moved(inNotch: true)   // straight back onto the notch
        wait(1) { m.isOpen }
        check("hover: after closing because the pointer left, hovering the notch again opens it", m.isOpen && m.openedByHover)
        m.close(); hover.closed(pointerInNotch: true)
        hover.moved(inNotch: true)
        wait(0.6) { m.isOpen }
        check("hover: closing with the pointer on the notch still waits for it to leave", !m.isOpen)
        hover.left()

        let d = tempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let f = d.appendingPathComponent("kept.txt")
        FileManager.default.createFile(atPath: f.path, contents: Data())
        m.files.add([f], now: Date().addingTimeInterval(-2 * 3600))
        m.keepFilesFor = 3600
        check("settings: 1 hour drops a file dropped 2 hours ago", m.files.items.isEmpty)
        m.files.add([f], now: Date().addingTimeInterval(-400 * 86400))
        m.keepFilesFor = 0
        check("settings: Until removed keeps even a year-old file", m.files.items.count == 1 && m.files.keepFor == nil)
        m.keepFilesFor = 604800
        check("settings: switching to 1 week applies at once", m.files.items.isEmpty)
        let old = ClipboardHistory.Clip(kind: .text, text: "old", key: "old", last: Date().addingTimeInterval(-2 * 86400))
        m.clipboard.add(old)
        m.keepClipsFor = 2592000
        check("settings: 1 month keeps a 2-day-old clip", m.clipboard.clips.contains { $0.key == "old" })
        m.keepClipsFor = 86400
        check("settings: 1 day drops it at once", !m.clipboard.clips.contains { $0.key == "old" })
            }

    static func tempDir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("topshelf-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// Lets main-queue work (listener, text recognition) run, up to `seconds`, until `done` is true.
    static func wait(_ seconds: Double, until done: () -> Bool) {
        let end = Date().addingTimeInterval(seconds)
        while !done() && Date() < end {
            _ = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: false) { _ in }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    static func filesTests() {
        let d = tempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let urls = (1...8).map { d.appendingPathComponent("f\($0).txt") }
        for u in urls { FileManager.default.createFile(atPath: u.path, contents: Data("x".utf8)) }
        let store = d.appendingPathComponent("files.json")
        let t = FilesTray(store: store)
        let refused = t.add(Array(urls.prefix(7)))
        check("files: six fit, the seventh is refused", t.items.count == 6 && refused == 1)
        t.add([urls[0]])
        check("files: adding a file again moves it to the front, no duplicate", t.items.count == 6 && t.items.first?.path == urls[0].path)
        t.remove(t.items[0])
        check("files: removed after a drag out", t.items.count == 5 && !t.items.contains { $0.path == urls[0].path })
        check("files: the tray survives a restart", FilesTray(store: store).items.count == 5)
        check("files: saved for John's account only", (try? FileManager.default.attributesOfItem(atPath: store.path)[.posixPermissions] as? Int) == 0o600)
        try? FileManager.default.removeItem(at: urls[1])
        t.prune(now: Date())
        check("files: a deleted file leaves the tray", !t.items.contains { $0.path == urls[1].path })
        t.prune(now: Date().addingTimeInterval(24 * 3600 + 1))
        check("files: everything expires after a day", t.items.isEmpty)
    }

    static func clipboardTests() {
        let d = tempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let pb = NSPasteboard(name: NSPasteboard.Name("TopShelfTest-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        let h = ClipboardHistory(dir: d, live: false)
        func copy(_ fill: () -> Void) { pb.clearContents(); fill(); h.poll(pb) }

        copy { pb.setString("hello", forType: .string) }
        copy { pb.setString("hello", forType: .string) }
        check("clipboard: a repeat is merged with a count", h.clips.count == 1 && h.clips[0].count == 2 && h.clips[0].kind == .text)
        copy { pb.declareTypes([.string, NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")], owner: nil); pb.setString("secret", forType: .string) }
        check("clipboard: password-manager copies are never kept", !h.clips.contains { $0.text == "secret" })
        copy { pb.declareTypes([.string, NSPasteboard.PasteboardType("org.nspasteboard.TransientType")], owner: nil); pb.setString("temp", forType: .string) }
        check("clipboard: temporary copies are skipped", !h.clips.contains { $0.text == "temp" })
        copy { pb.setData(Data("{\\rtf1 bold}".utf8), forType: .rtf); pb.setString("bold", forType: .string) }
        check("clipboard: rich text keeps its formatting", h.clips[0].kind == .rich && h.clips[0].rtf != nil)
        copy { pb.writeObjects([URL(fileURLWithPath: "/tmp/Report.pdf") as NSURL]) }
        check("clipboard: copied files are kept as references", h.clips[0].kind == .files && h.clips[0].text == "Report.pdf")

        let img = NSImage(size: NSSize(width: 600, height: 120), flipped: false) { r in
            NSColor.white.setFill(); r.fill()
            ("INVOICE NUMBER 4471" as NSString).draw(at: NSPoint(x: 20, y: 40), withAttributes: [.font: NSFont.systemFont(ofSize: 40), .foregroundColor: NSColor.black])
            return true
        }
        copy { pb.writeObjects([img]) }
        check("clipboard: a picture is stored", h.clips[0].kind == .image && h.image(h.clips[0]) != nil)
        wait(90) { h.clips.contains { $0.text.contains("4471") } }   // reading a picture can be slow the first time, with the whole suite running
        h.query = "invoice"
        check("clipboard: words inside a picture can be searched", h.visible.first?.kind == .image)
        h.query = ""

        let hello = h.clips.first { $0.text == "hello" }!
        h.togglePin(hello)
        check("clipboard: pinned clips come first", h.visible.first?.text == "hello")
        h.copy(hello, to: pb); h.poll(pb)
        check("clipboard: copying back puts it on the clipboard", pb.string(forType: .string) == "hello")
        check("clipboard: the history survives a restart", ClipboardHistory(dir: d, live: false).clips.count == h.clips.count)
        let picture = h.clips.first { $0.kind == .image }!.imageFile!
        h.prune(now: Date().addingTimeInterval(7 * 86400 + 1))
        check("clipboard: after a week only pinned clips stay", h.clips.map(\.text) == ["hello"])
        check("clipboard: an expired picture is deleted from disk",
              !FileManager.default.fileExists(atPath: d.appendingPathComponent("clipboard-images/" + picture).path))
        for i in 0..<(ClipboardHistory.maxClips + 5) { h.add(.init(kind: .text, text: "n\(i)", key: "k\(i)", last: Date())) }
        check("clipboard: at most 200 unpinned clips plus pinned ones", h.clips.count == ClipboardHistory.maxClips + 1)
    }

    static func send(_ a: Agents, _ json: String, token: String? = nil, path: String = "/event") -> Agents.Handling {
        let body = Data(json.utf8)
        let raw = "POST \(path) HTTP/1.1\r\nHost: 127.0.0.1\r\nX-Top-Shelf-Token: \(token ?? a.token)\r\nContent-Length: \(body.count)\r\n\r\n"
        guard case .complete(let req) = Agents.parse(Data(raw.utf8) + body) else { return .done(-1) }
        return a.handle(req, now: Date())
    }

    static func post(_ a: Agents, _ json: String, token: String? = nil, path: String = "/event") -> Int {
        switch send(a, json, token: token, path: path) {
        case .done(let status): return status
        case .answer: return 200
        case .wait: return 202
        }
    }

    static func agentsTests() {
        let d = tempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let a = Agents(dir: d, live: false)
        check("agents: a 64-character secret is made on first run", a.token.count == 64)
        check("agents: the secret file is for John's account only",
              (try? FileManager.default.attributesOfItem(atPath: d.appendingPathComponent("agent-header").path)[.posixPermissions] as? Int) == 0o600)
        check("agents: the same secret after a restart", Agents(dir: d, live: false).token == a.token)
        check("agents: a fresh install gets a different secret", Agents(dir: tempDir(), live: false).token != a.token)

        check("agents: a wrong secret is refused", post(a, #"{"session_id":"s1","hook_event_name":"Stop"}"#, token: String(repeating: "0", count: 64)) == 401)
        check("agents: other paths are refused", post(a, "{}", path: "/other") == 404)
        check("agents: junk is refused", post(a, "not json") == 400)
        check("agents: nothing was recorded from refused posts", a.sessions.isEmpty && a.lastSignal == nil)

        _ = post(a, #"{"session_id":"s1","hook_event_name":"UserPromptSubmit","cwd":"/Users/x/sample-project"}"#)
        check("agents: a prompt marks the session working", a.sessions.first?.state == .working && a.sessions.first?.name == "sample-project" && a.lastSignal != nil)
        _ = post(a, #"{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"Edit","cwd":"/Users/x/sample-project"}"#)
        check("agents: tool use says what it is doing", a.sessions.first?.detail == "Claude Code, editing files")
        _ = post(a, #"{"session_id":"s1","hook_event_name":"Notification","notification_type":"permission_prompt","message":"Claude needs your permission to use Bash","cwd":"/Users/x/sample-project"}"#)
        check("agents: a permission prompt needs attention", a.activeState == .attention && a.sessions.count == 1)
        _ = post(a, #"{"session_id":"s1","hook_event_name":"Notification","notification_type":"auth_success","cwd":"/x"}"#)
        check("agents: unrelated notices change nothing", a.activeState == .attention)
        _ = post(a, #"{"session_id":"s1","hook_event_name":"PostToolUse","tool_name":"Bash","cwd":"/Users/x/sample-project"}"#)
        check("agents: once approved it is working again", a.sessions.first?.state == .working && a.activeState == .working)
        _ = post(a, #"{"session_id":"s1","hook_event_name":"Stop","cwd":"/Users/x/sample-project"}"#)
        check("agents: stop means idle, and no dot", a.sessions.first?.state == .idle && a.activeState == nil)
        _ = post(a, #"{"session_id":"s1","hook_event_name":"SessionEnd"}"#)
        check("agents: an ended session leaves the list", a.sessions.isEmpty)

        // Subagents: their own rows under the session, counted while they work.
        _ = post(a, #"{"session_id":"m","hook_event_name":"UserPromptSubmit","cwd":"/x/main-project"}"#)
        _ = post(a, #"{"session_id":"m","hook_event_name":"SubagentStart","agent_id":"a1","agent_type":"Explore","cwd":"/x/main-project"}"#)
        _ = post(a, #"{"session_id":"m","hook_event_name":"SubagentStart","agent_id":"a2","agent_type":"general-purpose","cwd":"/x/main-project"}"#)
        check("subagents: a session waiting on two subagents counts 2, not 3", a.activeCount == 2 && a.sessions.first { $0.id == "m" }?.state == .idle)
        check("subagents: listed under their session", a.ordered.map(\.id) == ["m", "a2", "a1"] && a.ordered[1].parent == "m")
        _ = post(a, #"{"session_id":"m","hook_event_name":"PostToolUse","agent_id":"a1","agent_type":"Explore","tool_name":"Grep","cwd":"/x/main-project"}"#)
        check("subagents: their tool use updates their own row, not the session's", a.sessions.first { $0.id == "a1" }?.detail == "Explore, reading files"
              && a.sessions.first { $0.id == "m" }?.state == .idle && a.activeCount == 2)
        _ = post(a, #"{"session_id":"m","hook_event_name":"PostToolUse","tool_name":"Read","cwd":"/x/main-project"}"#)
        check("subagents: the session working itself alongside counts again", a.activeCount == 3)
        _ = post(a, #"{"session_id":"m","hook_event_name":"Stop","cwd":"/x/main-project"}"#)
        _ = post(a, #"{"session_id":"m","hook_event_name":"PostToolUse","agent_id":"a2","agent_type":"general-purpose","tool_name":"Bash","cwd":"/x/main-project"}"#)
        check("subagents: an idle chat counts only its working subagents (the reported bug)", a.activeCount == 2
              && a.sessions.first { $0.id == "m" }?.state == .idle)
        _ = post(a, #"{"session_id":"m","hook_event_name":"SubagentStop","agent_id":"a1","agent_type":"Explore"}"#)
        check("subagents: a finished one leaves", a.activeCount == 1 && !a.sessions.contains { $0.id == "a1" })
        _ = post(a, #"{"session_id":"m","hook_event_name":"PostToolUse","agent_id":"a1","agent_type":"Explore","tool_name":"Grep","cwd":"/x/main-project"}"#)
        check("subagents: a late report from a finished one does not bring it back", a.activeCount == 1 && !a.sessions.contains { $0.id == "a1" })
        _ = post(a, #"{"session_id":"m","hook_event_name":"SubagentStop","agent_id":"","agent_type":""}"#)
        check("subagents: Claude's own helpers stopping change nothing", a.activeCount == 1)
        _ = post(a, #"{"session_id":"z","hook_event_name":"SubagentStart","agent_id":"z1","agent_type":"Plan","cwd":"/x/other"}"#)
        check("subagents: an unseen session appears, waiting", a.sessions.first { $0.id == "z" }?.state == .idle && a.activeCount == 2)
        let tmp = NSTemporaryDirectory() + "remember-summarizer-cwd-abc"
        _ = post(a, "{\"session_id\":\"h\",\"hook_event_name\":\"UserPromptSubmit\",\"cwd\":\"\(tmp)\"}")
        check("agents: helper sessions in the temporary folder are not counted", !a.sessions.contains { $0.id == "h" } && a.activeCount == 2)
        _ = post(a, #"{"session_id":"m","hook_event_name":"SessionEnd"}"#)
        check("subagents: leave with their session", !a.sessions.contains { $0.id == "a2" || $0.id == "m" })
        _ = post(a, #"{"session_id":"z","hook_event_name":"SessionEnd"}"#)
        _ = post(a, #"{"session_id":"s2","hook_event_name":"Stop","cwd":"/x/y"}"#)
        a.prune(now: Date().addingTimeInterval(3601))
        check("agents: quiet sessions leave after an hour", a.sessions.isEmpty)

        // Permission requests: Claude's hook waits for John's answer, which the shelf sends back.
        let q = Agents(dir: tempDir(), live: false)
        let ask = #"{"session_id":"p1","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"rm -rf build && npm run build"},"cwd":"/Users/x/sample-project"}"#
        func waiting(_ json: String) -> String? { if case .wait(let id) = send(q, json) { return id }; return nil }
        func asks(_ id: String) -> String { ask.replacingOccurrences(of: "\"p1\"", with: "\"\(id)\"") }
        let first = waiting(ask)
        check("approval: a permission request waits for John", first != nil && q.pending.count == 1)
        check("approval: the card names the project, what it wants to do and the command",
              q.pending.first?.project == "sample-project" && q.pending.first?.action == "run a command"
              && q.pending.first?.detail == "rm -rf build && npm run build")
        check("approval: the chat shows as waiting, with what it wants to do",
              q.sessions.first?.state == .attention && q.sessions.first?.detail == "wants to run a command: rm -rf build && npm run build")
        let allowBody = first.flatMap { q.decide($0, .allow) } ?? ""
        check("approval: allow returns Claude's permission decision",
              allowBody.contains(#""hookEventName":"PermissionRequest""#) && allowBody.contains(#""behavior":"allow""#))
        check("approval: an answered request leaves the shelf", q.pending.isEmpty)
        check("approval: answering twice does nothing", first.flatMap { q.decide($0, .deny) } == nil)

        let second = waiting(asks("p2"))
        let denyBody = second.flatMap { q.decide($0, .deny) } ?? ""
        check("approval: deny says so, in words", denyBody.contains(#""behavior":"deny""#) && denyBody.contains("Denied in Top Shelf"))

        let third = waiting(asks("p3"))
        _ = third.flatMap { q.decide($0, .always) }
        check("approval: always lets the same call through without asking", {
            if case .answer(let b) = send(q, asks("p4")) { return b.contains(#""behavior":"allow""#) }
            return false
        }())
        check("approval: always does not cover a different command", {
            if case .wait = send(q, asks("p5").replacingOccurrences(of: "rm -rf build && npm run build", with: "git push")) { return true }
            return false
        }())
        _ = post(q, #"{"session_id":"p5","hook_event_name":"PostToolUse","tool_name":"Bash","cwd":"/Users/x/sample-project"}"#)
        check("approval: a tool that ran clears anything still waiting for that chat", q.pending.isEmpty)

        let suggested = #"{"session_id":"p8","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"npm test"},"cwd":"/Users/x/sample-project","permission_suggestions":[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"npm test"}],"behavior":"allow","destination":"localSettings"},{"type":"setMode","mode":"auto","destination":"session"}]}"#
        let alwaysBody = waiting(suggested).flatMap { q.decide($0, .always) } ?? ""
        check("approval: always applies Claude's own allow rule, and never a mode change",
              alwaysBody.contains(#""updatedPermissions""#) && alwaysBody.contains(#""ruleContent":"npm test""#)
              && !alwaysBody.contains("setMode"))

        let oldTimeout = Agents.answerTimeout
        Agents.answerTimeout = 0.05
        let timed = waiting(asks("p6").replacingOccurrences(of: "rm -rf build && npm run build", with: "make clean"))   // a command not already on the "always" list
        wait(1) { q.pending.isEmpty }
        check("approval: with no answer it gives up, so Claude asks in the terminal", timed != nil && q.pending.isEmpty)
        Agents.answerTimeout = oldTimeout
        check("approval: a helper's tool call reads as a command, a file, an address",
              Agents.detail("Bash", ["command": "ls"]) == "ls" && Agents.detail("Edit", ["file_path": "/a/b.swift"]) == "/a/b.swift"
              && Agents.detail("WebFetch", ["url": "https://example.com"]) == "https://example.com"
              && Agents.detail("mcp__thing__do", ["x": 1]) == #"{"x":1}"#)
        check("approval: a request from a helper folder is left to the terminal",
              post(q, #"{"session_id":"p7","hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"ls"},"cwd":"\#(NSTemporaryDirectory())remember-summarizer"}"#) == 200
              && q.pending.isEmpty)

        check("agents: a partial request waits for the rest", { if case .incomplete = Agents.parse(Data("POST /event HTTP/1.1\r\nContent-Length: 10\r\n\r\n{}".utf8)) { return true }; return false }())
        check("agents: an oversized request is refused", { if case .bad = Agents.parse(Data("POST /event HTTP/1.1\r\nContent-Length: 99999999\r\n\r\n".utf8)) { return true }; return false }())
        check("agents: secrets compare correctly", Agents.same("abc", "abc") && !Agents.same("abc", "abd") && !Agents.same("abc", "ab"))

        // One-click install, on a copy in a temporary folder (never the real ~/.claude).
        let settings = d.appendingPathComponent("claude/settings.json")
        try? FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = #"{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}"#
        try! Data(original.utf8).write(to: settings)
        let backup = try? Agents.installHooks(settings: settings)
        let after = (try? JSONSerialization.jsonObject(with: Data(contentsOf: settings))) as? [String: Any]
        let hooks = after?["hooks"] as? [String: Any]
        check("install: a backup of the old settings is made first", backup.flatMap { try? String(contentsOf: $0, encoding: .utf8) } == original)
        check("install: John's own settings and hooks are kept", after?["model"] as? String == "opus" && (hooks?["Stop"] as? [Any])?.count == 2)
        check("install: every event is connected, subagents included", Agents.events.allSatisfy { (hooks?[$0] as? [Any])?.isEmpty == false })
        check("install: Claude's question tool is matched, permission requests are connected",
              ((hooks?["PreToolUse"] as? [[String: Any]])?.first?["matcher"] as? String) == "AskUserQuestion"
              && (hooks?["PermissionRequest"] as? [[String: Any]])?.first?["matcher"] == nil)
        check("install: shows as installed", Agents.hooksInstalled(settings: settings))
        let permissionHooks = (hooks?["PermissionRequest"] as? [[String: Any]])?.flatMap { $0["hooks"] as? [[String: Any]] ?? [] } ?? []
        let permission = permissionHooks.first { ($0["command"] as? String)?.contains(Agents.marker) == true }
        check("install: the permission hook waits for an answer instead of firing and forgetting",
              permission?["command"] as? String == Agents.approvalCommand && permission?["async"] == nil
              && (permission?["timeout"] as? Int ?? 0) > 500)
        let stopHooks = (hooks?["Stop"] as? [[String: Any]])?.flatMap { $0["hooks"] as? [[String: Any]] ?? [] } ?? []
        let stopHook = stopHooks.first { ($0["command"] as? String)?.contains(Agents.marker) == true }
        check("install: every other hook still fires and forgets",
              stopHook?["command"] as? String == Agents.hookCommand && stopHook?["async"] as? Bool == true)
        check("install: the secret is not in Claude's settings", !((try? String(contentsOf: settings, encoding: .utf8)) ?? "").contains(a.token))
        Thread.sleep(forTimeInterval: 1.1)   // backups are named by the second
        _ = try? Agents.installHooks(settings: settings)
        let again = (try? JSONSerialization.jsonObject(with: Data(contentsOf: settings))) as? [String: Any]
        check("install: a second click adds nothing twice", ((again?["hooks"] as? [String: Any])?["Stop"] as? [Any])?.count == 2)
        let broken = d.appendingPathComponent("broken/settings.json")
        try? FileManager.default.createDirectory(at: broken.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! Data("{ not json".utf8).write(to: broken)
        check("install: an unreadable settings file is left untouched",
              (try? Agents.installHooks(settings: broken)) == nil && (try? String(contentsOf: broken, encoding: .utf8)) == "{ not json")
        func perms(_ u: URL?) -> Int? { u.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.posixPermissions] as? Int } }
        let fresh = d.appendingPathComponent("none/settings.json")
        let freshBackup: URL?? = try? Agents.installHooks(settings: fresh)
        check("install: works when Claude Code has no settings file yet (no backup needed)",
              freshBackup != nil && freshBackup! == nil && Agents.hooksInstalled(settings: fresh))
        check("install: a new settings file is private (0600)", perms(fresh) == 0o600)
        for mode in [0o600, 0o640] {
            let s = d.appendingPathComponent("mode\(mode)/settings.json")
            try? FileManager.default.createDirectory(at: s.deletingLastPathComponent(), withIntermediateDirectories: true)
            FileManager.default.createFile(atPath: s.path, contents: Data("{}".utf8), attributes: [.posixPermissions: mode])
            let b = try? Agents.installHooks(settings: s)
            check("install: settings and backup keep the original permissions (\(String(mode, radix: 8)))",
                  perms(s) == mode && perms(b ?? nil) == mode)
        }
        let s0 = d.appendingPathComponent("inplace/settings.json")
        try? FileManager.default.createDirectory(at: s0.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: s0.path, contents: Data("{}".utf8), attributes: [.posixPermissions: 0o644])
        func inode(_ u: URL) -> Int? { (try? FileManager.default.attributesOfItem(atPath: u.path)[.systemFileNumber]) as? Int }
        let before = inode(s0)
        _ = try? Agents.installHooks(settings: s0)
        check("install: the settings file is rewritten in place (same file), so open sessions notice",
              before != nil && inode(s0) == before && Agents.hooksInstalled(settings: s0) && perms(s0) == 0o644)
        let old = d.appendingPathComponent("old/settings.json")
        try? FileManager.default.createDirectory(at: old.deletingLastPathComponent(), withIntermediateDirectories: true)
        let oldCommand = "curl -s -m 2 -o /dev/null -H @x http://127.0.0.1:7823/event || true"
        try! JSONSerialization.data(withJSONObject: ["hooks": ["Stop": [["hooks": [["type": "command", "command": oldCommand]]]],
                                                              "PreToolUse": [["matcher": "Bash", "hooks": [["type": "command", "command": "my-own-check"]]]]]]).write(to: old)
        check("install: an older install shows as needing the update", !Agents.hooksInstalled(settings: old))
        _ = try? Agents.installHooks(settings: old)
        let up = ((try? JSONSerialization.jsonObject(with: Data(contentsOf: old))) as? [String: Any])?["hooks"] as? [String: Any]
        let stops = (up?["Stop"] as? [[String: Any]])?.flatMap { $0["hooks"] as? [[String: Any]] ?? [] } ?? []
        check("install: an older install is updated in place, not added twice, and John's own hooks stay",
              stops.count == 1 && stops.first?["command"] as? String == Agents.hookCommand && Agents.hooksInstalled(settings: old)
              && (up?["PreToolUse"] as? [[String: Any]])?.contains { $0["matcher"] as? String == "Bash" } == true)
        let oldPermission = d.appendingPathComponent("oldpermission/settings.json")
        try? FileManager.default.createDirectory(at: oldPermission.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! JSONSerialization.data(withJSONObject: ["hooks": ["PermissionRequest": [["hooks": [["type": "command", "command": oldCommand, "async": true, "timeout": 5]]]]]]).write(to: oldPermission)
        _ = try? Agents.installHooks(settings: oldPermission)
        let upgraded = ((try? JSONSerialization.jsonObject(with: Data(contentsOf: oldPermission))) as? [String: Any])?["hooks"] as? [String: Any]
        let asks = (upgraded?["PermissionRequest"] as? [[String: Any]])?.flatMap { $0["hooks"] as? [[String: Any]] ?? [] } ?? []
        check("install: an older permission hook becomes the waiting one, not a second entry",
              asks.count == 1 && asks.first?["command"] as? String == Agents.approvalCommand
              && asks.first?["async"] == nil && (asks.first?["timeout"] as? Int ?? 0) > 500)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: settings.deletingLastPathComponent().path)) ?? []
        check("install: no half-written files are left behind", !leftovers.contains { $0.hasPrefix(".settings.json.top-shelf-") })
    }

    /// The real listener with the real hook command (curl), on a spare test port so a running Top Shelf is untouched.
    static func listenerTest() {
        let d = tempDir(); defer { try? FileManager.default.removeItem(at: d) }
        let a = Agents(dir: d, live: true)
        wait(1) { false }
        func curl(_ header: String) -> Int32 {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = ["-c", "printf '%s' '{\"session_id\":\"live\",\"hook_event_name\":\"UserPromptSubmit\",\"cwd\":\"/tmp/live-check\"}' | curl -s -m 2 -o /dev/null -w '%{http_code}' -H @\"$H\" --data-binary @- http://127.0.0.1:\(Agents.listenPort)/event > \"$OUT\""]
            let out = d.appendingPathComponent("code-\(UUID().uuidString)")
            p.environment = ["H": header, "OUT": out.path, "PATH": "/usr/bin:/bin"]
            try? p.run()
            wait(5) { !p.isRunning }
            return Int32((try? String(contentsOf: out, encoding: .utf8)) ?? "") ?? -1
        }
        let good = d.appendingPathComponent("agent-header").path
        let badFile = d.appendingPathComponent("bad-header")
        try! Data("X-Top-Shelf-Token: \(String(repeating: "f", count: 64))\n".utf8).write(to: badFile)
        check("listener: a hook with a wrong secret gets 401", curl(badFile.path) == 401 && a.sessions.isEmpty)
        check("listener: the real hook command is accepted", curl(good) == 200)
        check("listener: and the session shows as working", a.sessions.first?.name == "live-check" && a.sessions.first?.state == .working)

        // The waiting permission hook: curl stays connected until John answers, then prints Claude's decision.
        let answerFile = d.appendingPathComponent("decision.json")
        let ask = Process()
        ask.executableURL = URL(fileURLWithPath: "/bin/sh")
        ask.arguments = ["-c", "printf '%s' '{\"session_id\":\"live-ask\",\"hook_event_name\":\"PermissionRequest\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"ls -la\"},\"cwd\":\"/tmp/live-check\"}' | curl -s -m 20 -H @\"$H\" --data-binary @- http://127.0.0.1:\(Agents.listenPort)/event > \"$OUT\""]
        ask.environment = ["H": good, "OUT": answerFile.path, "PATH": "/usr/bin:/bin"]
        try? ask.run()
        wait(5) { !a.pending.isEmpty }
        check("listener: a permission request waits on the shelf", a.pending.count == 1 && a.pending.first?.detail == "ls -la")
        check("listener: the hook is still waiting for the answer", ask.isRunning)
        _ = a.pending.first.flatMap { a.decide($0.id, .allow) }
        wait(5) { !ask.isRunning }
        let decision = (try? String(contentsOf: answerFile, encoding: .utf8)) ?? ""
        check("listener: the waiting hook prints Claude's decision and returns", !ask.isRunning
              && decision.contains(#""hookEventName":"PermissionRequest""#) && decision.contains(#""behavior":"allow""#))
        check("listener: the answer leaves the shelf", a.pending.isEmpty)
    }
}


