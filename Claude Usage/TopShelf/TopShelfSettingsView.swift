import AppKit
import SwiftUI

/// Top Shelf Settings, laid out as the approved settings mockup (settings-mockup.html), in the Mac's own grouped style.
struct TopShelfSettingsView: View {
    @Bindable var model: ShelfModel
    /// Set only in the Usage Shelf Settings window, where the shelf may be missing from the notch.
    var showShelf: (() -> Void)? = nil
    @State private var shrinkTo: Int?
    @State private var combos: [ShortcutAction: KeyCombo?] = Dictionary(uniqueKeysWithValues:
        [ShortcutAction.shelfTray, .shelfClipboard, .shelfLibrary, .moveScreenshots].map { ($0, ShortcutManager.shared.shortcuts[$0]) })
    @State private var shortcutWarning: String?

    var body: some View {
        Form {
            if let showShelf {
                Section("Shelf") {
                    LabeledContent("Shelf missing from the notch?") {
                        Button("Show the shelf", action: showShelf)
                    }
                }
            }
            Section("Opening") {
                Picker("Open the shelf by", selection: $model.openMode) {
                    ForEach(ShelfModel.OpenMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                delay("Hover open delay", "Pointer waits on the notch before it opens", $model.hoverDelay, upTo: 1.5)
                    .disabled(model.openMode == .click)   // hover never opens it in Click mode
                delay("Hover close delay", "Time after the pointer leaves before it closes", $model.hoverCloseDelay, upTo: 3)
            }
            Section("Menu bar") {
                Toggle("Show menu bar icon", isOn: $model.showMenuBarIcon)
                    .toggleStyle(.switch)
                LabeledContent("Quit Usage Shelf") {   // Top Shelf now lives inside the tracker
                    Button("Quit") { NSApp.terminate(nil) }
                }
            }
            WeatherSettings(weather: model.weather)
            SoundSettings(model: model)
            Section("Claude Code") {
                Toggle("Open the shelf when a chat needs permission", isOn: $model.openForApproval)
                    .toggleStyle(.switch)
                Text("Answer Allow, Always or Deny from the shelf, so the chat carries on without the terminal.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Keeping things") {
                Picker("Keep dropped files for", selection: $model.keepFilesFor) {
                    Text("1 hour").tag(3600.0); Text("1 day").tag(86400.0); Text("1 week").tag(604800.0); Text("Until removed").tag(0.0)
                }
                Picker("Keep clipboard items for", selection: $model.keepClipsFor) {
                    Text("1 day").tag(86400.0); Text("1 week").tag(604800.0); Text("1 month").tag(2592000.0)
                }
                Picker(selection: Binding(get: { model.keepClipsMax }, set: { n in
                    // a smaller size deletes clips for good, so ask first when it would
                    if model.clipboard.clips.filter({ !$0.pinned }).count > n { shrinkTo = n } else { model.keepClipsMax = n }
                })) {
                    Text("200").tag(200); Text("1,000").tag(1000); Text("5,000").tag(5000)
                } label: {
                    Text("Keep up to")
                    Text("Pinned clips never count toward this.")
                }
                .pickerStyle(.segmented)
                .confirmationDialog("Delete older clips?", isPresented: Binding(get: { shrinkTo != nil }, set: { if !$0 { shrinkTo = nil } })) {
                    Button("Delete \(((model.clipboard.clips.filter { !$0.pinned }.count) - (shrinkTo ?? 0)).formatted()) clips", role: .destructive) {
                        if let n = shrinkTo { model.keepClipsMax = n }
                        shrinkTo = nil
                    }
                } message: {
                    Text("Only the newest \((shrinkTo ?? 0).formatted()) are kept. Pinned clips stay. This can't be undone.")
                }
            }
            ScreenshotSettings(shots: model.screenshots)
            Section {
                shortcut(.shelfTray)
                shortcut(.shelfClipboard)
                shortcut(.shelfLibrary)
                shortcut(.moveScreenshots)
                if let shortcutWarning { Text(shortcutWarning).font(.caption).foregroundStyle(.orange) }
            } header: {
                Text("Keyboard shortcuts")
            } footer: {
                Text("Click a shortcut, then press the keys you want. Clear it to turn it off.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)   // a grouped Form scrolls by itself when the window is shorter than its content
        .frame(width: 520)
        .frame(minHeight: 200)
    }

    private func delay(_ title: String, _ hint: String, _ value: Binding<Double>, upTo max: Double) -> some View {
        LabeledContent {
            HStack(spacing: 10) {
                Slider(value: value, in: 0...max, step: 0.1).frame(width: 200).labelsHidden()
                Text(String(format: "%.1f s", value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
            }
        } label: {
            Text(title)
            Text(hint)
        }
    }

    /// Same recorder and clash check as the tracker's own Shortcuts page.
    private func shortcut(_ action: ShortcutAction) -> some View {
        LabeledContent(action.displayName) {
            ShortcutRecorderView(keyCombo: Binding(
                get: { combos[action] ?? nil },
                set: { newValue in
                    let result = ShortcutManager.shared.setShortcut(newValue, for: action)
                    shortcutWarning = resultWarning(result, combo: newValue ?? KeyCombo(keyCode: 0, modifierFlags: []))
                    combos[action] = ShortcutManager.shared.shortcuts[action]
                }
            ))
        }
    }
}

/// Weather for the current location or a picked place, as in the approved settings mockup.
struct WeatherSettings: View {
    @Bindable var weather: WeatherService
    @State private var query = ""
    @State private var results: [WeatherService.Place]?
    @State private var searchFailed = false

    var body: some View {
        Section("Weather") {
            Picker("Weather for", selection: $weather.source) {
                Text("Use current location").tag(WeatherService.Source.current)
                Text("Choose a place").tag(WeatherService.Source.place)
            }
            .pickerStyle(.segmented)
            if weather.source == .current && weather.locationOff {
                Text("Location access is off for Usage Shelf, so it can't tell where you are. Choose a place instead, or allow Usage Shelf in System Settings, Privacy & Security, Location Services.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if weather.source == .place {
                LabeledContent("Place") {
                    Text(weather.chosen?.label ?? "None chosen yet").foregroundStyle(weather.chosen == nil ? .secondary : .primary)
                }
                TextField("Search for a city", text: $query, prompt: Text("Search for a city")).textFieldStyle(.roundedBorder).labelsHidden()
                if searchFailed {
                    Text("Can't search right now. Check the internet connection.").font(.callout).foregroundStyle(.secondary)
                } else if let results, results.isEmpty {
                    Text("No places found").font(.callout).foregroundStyle(.secondary)
                } else if let results {
                    ForEach(results, id: \.self) { p in
                        Button { weather.chosen = p; query = "" } label: {
                            HStack(spacing: 6) {
                                Text(p.name)
                                Text([p.region, p.country].filter { !$0.isEmpty }.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .task(id: query) {   // searches shortly after typing stops
            let q = query.trimmingCharacters(in: .whitespaces)
            guard q.count >= 2 else { results = nil; searchFailed = false; return }
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            let found = await WeatherService.search(q)
            guard !Task.isCancelled else { return }
            results = found; searchFailed = found == nil
        }
    }
}

/// Sounds for John's main chats, as in the approved settings mockup.
struct SoundSettings: View {
    @Bindable var model: ShelfModel
    @State private var choices: [AlertSounds.Choice] = []   // filled when Settings opens, not on every redraw

    var body: some View {
        Section {
            Toggle("When a chat has a question", isOn: $model.questionSoundOn).toggleStyle(.switch)
            row($model.questionSound, on: model.questionSoundOn, label: "When a chat has a question")
            Toggle("When a chat finishes", isOn: $model.finishedSoundOn).toggleStyle(.switch)
            row($model.finishedSound, on: model.finishedSoundOn, label: "When a chat finishes")
        } header: {
            Text("Sounds")
        } footer: {
            Text("Only your main chats make sounds. Their helpers (subagents) stay quiet.").font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { choices = AlertSounds.all() }   // picks up sounds added to ~/Library/Sounds since
    }

    private func row(_ file: Binding<String>, on: Bool, label: String) -> some View {
        LabeledContent("Sound") {
            HStack(spacing: 8) {
                Picker("Sound", selection: file) {
                    ForEach(choices, id: \.file) { Text($0.name).tag($0.file) }
                    if !choices.isEmpty, !choices.contains(where: { $0.file == file.wrappedValue }) {
                        Text("\(file.wrappedValue) (missing)").tag(file.wrappedValue)   // a saved sound that was deleted
                    }
                }
                .labelsHidden().fixedSize()
                .accessibilityLabel("Sound: \(label)")
                Button { AlertSounds.play(file.wrappedValue) } label: { Image(systemName: "play.fill") }
                    .buttonStyle(.borderless).help("Play").accessibilityLabel("Play")
            }
        }
        .disabled(!on)
    }
}

/// Screenshot naming, shrinking and moving (from File Sorter and Clop), as in the approved screenshot settings mockup.
struct ScreenshotSettings: View {
    @Bindable var shots: Screenshots
    @State private var newWord = ""
    @State private var adding = false
    @State private var moved: Int?

    var body: some View {
        Section {
            Toggle(isOn: $shots.nameOn) {
                Text("Name new screenshots with Apple Intelligence")
                Text("Like \u{201C}Login page (2026-11-19 12.39.10).png\u{201D}")
            }
            .toggleStyle(.switch)
            Toggle(isOn: $shots.shrinkOn) {
                Text("Shrink new screenshots")
                Text("Named and shrunk in one step, so the file is saved only once")
            }
            .toggleStyle(.switch)
            Toggle(isOn: $shots.shrinkCopiedOn) {
                Text("Shrink copied pictures")
                Text("A picture you copy is made smaller before you paste it")
            }
            .toggleStyle(.switch)
            Picker(selection: $shots.level) {
                ForEach(ShrinkLevel.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            } label: {
                Text("Shrink by")
                Text(shots.level.help)
            }
            .pickerStyle(.segmented)
            .disabled(!shots.shrinkOn && !shots.shrinkCopiedOn)
            folderRow("Watch for screenshots in", shots.watchFolder) { shots.watchFolder = $0 }
            LabeledContent {
                HStack(spacing: 6) {
                    ForEach(shots.words, id: \.self) { w in
                        HStack(spacing: 3) {
                            Text(w)
                            Button { shots.words.removeAll { $0 == w } } label: { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)) }
                                .buttonStyle(.borderless).accessibilityLabel("Remove \(w)")
                        }
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(.quaternary))
                    }
                    if adding {
                        TextField("Word", text: $newWord).frame(width: 90).textFieldStyle(.roundedBorder)
                            .onSubmit {
                                let w = newWord.trimmingCharacters(in: .whitespaces)
                                if !w.isEmpty, !shots.words.contains(where: { $0.caseInsensitiveCompare(w) == .orderedSame }) { shots.words.append(w) }
                                newWord = ""; adding = false
                            }
                    } else {
                        Button("+ Add") { adding = true }.buttonStyle(.borderless)
                    }
                }
            } label: {
                Text("Files that count as screenshots")
                Text("A file whose name contains any of these words")
            }
        } header: {
            Text("Screenshots")
        } footer: {
            Text("Names come from Apple Intelligence on this Mac. Nothing leaves your Mac. Without Apple Intelligence, screenshots are only shrunk.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Moving screenshots") {
            folderRow("Move screenshots to", shots.moveFolder) { shots.moveFolder = $0 }
            LabeledContent("Move them now") {
                HStack(spacing: 8) {
                    if let moved { Text(moved == 1 ? "Moved 1" : "Moved \(moved)").foregroundStyle(.secondary) }
                    Button("Move") { moved = shots.moveAll() }
                }
            }
        }
    }

    /// A folder shown the Finder way ("Pictures › Screenshots"), with a Choose… button.
    private func folderRow(_ title: String, _ url: URL, set: @escaping (URL) -> Void) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                Text(Self.shown(url)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                Button("Choose…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
                    panel.directoryURL = url
                    if panel.runModal() == .OK, let picked = panel.url { set(picked) }
                }
            }
        }
    }

    static func shown(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path.hasPrefix(home + "/") ? String(url.path.dropFirst(home.count + 1)) : url.path
        return path.split(separator: "/").joined(separator: " \u{203A} ")
    }
}
