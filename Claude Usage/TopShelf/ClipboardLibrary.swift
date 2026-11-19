import AppKit
import SwiftUI

/// The clipboard library: the whole history in a big window, sorted by type in a sidebar, grouped by day,
/// with a larger preview beside it (approved mockup, 2026-11-19). The clipboard shortcut still opens the shelf's quick view.
struct ClipboardLibraryView: View {
    let model: ShelfModel
    /// Hands typing back to the app John was in, then pastes there (set by the window).
    var paste: (ClipboardHistory.Clip) -> Void = { _ in }

    enum Filter: Hashable { case all, pinned, type(ClipboardHistory.Clip.Category) }
    @State private var filter = Filter.all
    @State private var query = ""
    @State private var selectedID: ClipboardHistory.Clip.ID?
    @FocusState private var searchFocused: Bool
    static let columns = 3
    private let grid = Array(repeating: GridItem(.flexible(), spacing: 10), count: Self.columns)

    static let dots: [ClipboardHistory.Clip.Category: Color] = [
        .text: .white, .pictures: Color(red: 90 / 255, green: 200 / 255, blue: 250 / 255), .links: Look.blue,
        .files: Color(red: 1, green: 214 / 255, blue: 10 / 255), .code: Look.green, .colors: Color(red: 191 / 255, green: 90 / 255, blue: 242 / 255),
    ]

    /// The clips shown for a sidebar choice and search, newest first.
    static func shown(_ clips: [ClipboardHistory.Clip], _ filter: Filter, _ query: String) -> [ClipboardHistory.Clip] {
        ClipboardHistory.matching(clips, query).filter { c in
            switch filter {
            case .all: true
            case .pinned: c.pinned
            case .type(let t): c.category == t
            }
        }.sorted { $0.last > $1.last }
    }

    struct Day: Identifiable { let title: String; var clips: [ClipboardHistory.Clip]; var id: String { title } }

    /// Clips cut into day groups ("Today", "Yesterday", then the date), keeping their order.
    static func days(_ clips: [ClipboardHistory.Clip], now: Date = Date(), calendar: Calendar = .current) -> [Day] {
        var out: [Day] = []
        for c in clips {
            let title = calendar.isDate(c.last, inSameDayAs: now) ? "Today"
                : calendar.isDate(c.last, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: now) ?? now) ? "Yesterday"
                : calendar.isDate(c.last, equalTo: now, toGranularity: .year) ? c.last.formatted(.dateTime.weekday(.wide).month(.wide).day())
                : c.last.formatted(.dateTime.month(.wide).day().year())   // pinned clips can be older than a year
            if out.last?.title == title { out[out.count - 1].clips.append(c) } else { out.append(Day(title: title, clips: [c])) }
        }
        return out
    }

    /// The place after an arrow key when the tiles sit in day groups, each group starting a new row `columns` wide.
    /// Up and down keep the column, landing on the nearest real tile of the row above or below.
    static func moved(_ i: Int, _ key: KeyEquivalent, groups: [Int], columns: Int) -> Int {
        let count = groups.reduce(0, +)
        guard count > 0 else { return 0 }
        let i = min(max(i, 0), count - 1)
        // every row as (first place, length), in order
        var rows: [(start: Int, length: Int)] = []
        var start = 0
        for g in groups where g > 0 {
            for r in stride(from: 0, to: g, by: columns) { rows.append((start + r, min(columns, g - r))) }
            start += g
        }
        let row = rows.lastIndex { $0.start <= i } ?? 0
        let col = i - rows[row].start
        switch key {
        case .leftArrow: return max(i - 1, 0)
        case .rightArrow: return min(i + 1, count - 1)
        case .upArrow: guard row > 0 else { return i }; return rows[row - 1].start + min(col, rows[row - 1].length - 1)
        case .downArrow: guard row + 1 < rows.count else { return i }; return rows[row + 1].start + min(col, rows[row + 1].length - 1)
        default: return i
        }
    }

    var body: some View {
        let all = model.clipboard.clips
        let shown = Self.shown(all, filter, query)
        let groups = Self.days(shown)
        let selected = shown.first { $0.id == selectedID } ?? shown.first
        HStack(spacing: 0) {
            sidebar(all).frame(width: 200)
            Divider()
            VStack(spacing: 12) {
                searchField(shown, groups: groups, selected: selected)
                if shown.isEmpty {
                    Text(all.isEmpty ? "Things you copy show up here." : "Nothing matches.")
                        .font(.system(size: 13)).foregroundStyle(Look.dim).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    list(groups, selected: selected)
                }
            }
            .padding(16)
            .frame(minWidth: 420, maxWidth: .infinity)
            Divider()
            detail(selected).frame(width: 300)
        }
        .foregroundStyle(.white)
        .background(Color(white: 20 / 255))
        .onAppear { searchFocused = true }
        .onChange(of: filter) { selectedID = nil }
        .onChange(of: query) { selectedID = nil }
    }

    // MARK: sidebar

    private func sidebar(_ all: [ClipboardHistory.Clip]) -> some View {
        let counts = Dictionary(grouping: all, by: \.category).mapValues(\.count)
        return VStack(alignment: .leading, spacing: 2) {
            heading("Library")
            nav("All", all.count, Color(white: 165 / 255), .all)
            nav("Pinned", all.filter(\.pinned).count, Look.orange, .pinned)
            heading("Types").padding(.top, 12)
            ForEach(ClipboardHistory.Clip.Category.allCases, id: \.self) { t in nav(t.rawValue, counts[t] ?? 0, Self.dots[t] ?? .white, .type(t)) }
            Spacer()
            Text("Keeping up to \(model.keepClipsMax.formatted()) clips for \(Self.keepText(model.keepClipsFor)). Change in Settings.")
                .font(Look.small).foregroundStyle(Look.dim).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(white: 28 / 255))
    }

    static func keepText(_ t: TimeInterval) -> String { t <= 86400 ? "1 day" : t <= 604800 ? "1 week" : "1 month" }

    private func heading(_ s: String) -> some View {
        Text(s).font(.system(size: 11, weight: .semibold)).foregroundStyle(Look.dim).padding(.horizontal, 10).padding(.bottom, 4)
    }

    private func nav(_ name: String, _ n: Int, _ dot: Color, _ f: Filter) -> some View {
        Button { filter = f } label: {
            HStack(spacing: 8) {
                Circle().fill(dot).frame(width: 8, height: 8)
                Text(name).font(.system(size: 13))
                Spacer()
                Text(n.formatted()).font(.system(size: 12)).monospacedDigit().foregroundStyle(Look.dim)
            }
            .padding(.horizontal, 10).frame(height: 30)
            .background(filter == f ? Color(white: 58 / 255) : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name), \(n) clips")
        .accessibilityAddTraits(filter == f ? .isSelected : [])
    }

    // MARK: list

    private func searchField(_ shown: [ClipboardHistory.Clip], groups: [Day],
                             selected: ClipboardHistory.Clip?) -> some View {
        TextField("Search clips, including words in pictures", text: $query)
            .textFieldStyle(.plain).font(.system(size: 13))
            .padding(.horizontal, 12).frame(height: 32)
            .background(Look.button, in: Capsule())
            .focused($searchFocused)
            // the same keys as the shelf: arrows move, Return pastes (⌥Return copies), ⌘1 to ⌘9 paste the first nine
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
                if [.leftArrow, .rightArrow].contains(press.key) && !query.isEmpty { return .ignored }
                let i = selected.flatMap { s in shown.firstIndex { $0.id == s.id } } ?? 0
                let j = Self.moved(i, press.key, groups: groups.map(\.clips.count), columns: Self.columns)
                if shown.indices.contains(j) { selectedID = shown[j].id }
                return .handled
            }
            .onKeyPress(keys: [.return]) { press in
                guard let selected else { return .ignored }
                if press.modifiers.contains(.option) { model.clipboard.copy(selected) } else { paste(selected) }
                return .handled
            }
            .onKeyPress(characters: .decimalDigits) { press in
                guard press.modifiers.subtracting([.capsLock, .numericPad]) == .command, let n = Int(press.characters), n > 0, shown.indices.contains(n - 1)
                else { return .ignored }
                paste(shown[n - 1])
                return .handled
            }
    }

    private func list(_ groups: [Day], selected: ClipboardHistory.Clip?) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(groups) { g in
                        Text(g.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Look.dim)
                        LazyVGrid(columns: grid, spacing: 10) {
                            ForEach(g.clips) { c in tile(c, selected: c.id == selected?.id) }
                        }
                    }
                }
            }
            .scrollIndicators(.automatic)
            .onChange(of: selectedID) { _, id in if let id { proxy.scrollTo(id) } }
        }
    }

    private func tile(_ c: ClipboardHistory.Clip, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content(c).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).clipped()
            HStack {
                Text(c.category.rawValue).foregroundStyle(Self.dots[c.category] ?? .white)
                Spacer()
                Text(c.pinned ? "pinned" : c.count > 1 ? "x\(c.count)" : c.last.formatted(date: .omitted, time: .shortened))
                    .foregroundStyle(Look.dim)
            }
            .font(.system(size: 10)).padding(.horizontal, 10).padding(.bottom, 7)
        }
        .frame(height: 150)
        .background(Look.cardGradient)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? Look.blue : c.pinned ? Look.orange : .clear, lineWidth: 1.5))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture(count: 2) { paste(c) }
        .onTapGesture { selectedID = c.id; searchFocused = true }
        .contextMenu { actions(c) }
        .id(c.id)
        .help("Click to see it, double-click to paste")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((c.pinned ? "Pinned " : "") + c.category.rawValue + ": " + (c.text.isEmpty ? "Picture" : c.text))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { paste(c) }
    }

    @ViewBuilder private func content(_ c: ClipboardHistory.Clip, big: Bool = false) -> some View {
        let size: CGFloat = big ? 13 : 12
        if c.kind == .image, let img = model.clipboard.image(c) {
            Image(nsImage: img).resizable().aspectRatio(contentMode: big ? .fit : .fill)
                .clipShape(RoundedRectangle(cornerRadius: 8)).padding(8)
        } else if c.category == .colors {
            RoundedRectangle(cornerRadius: 8).fill(Self.color(c.text) ?? .gray)
                .overlay(alignment: .bottomLeading) { Text(c.text).font(.system(size: size, weight: .semibold)).padding(8) }
                .padding(8)
        } else {
            Text(c.kind == .files ? "Files: " + c.text : c.text)
                .font(c.category == .code ? .system(size: size - 1, design: .monospaced) : .system(size: size))
                .foregroundStyle(c.category == .code ? Look.green : c.category == .links ? Color(red: 127 / 255, green: 203 / 255, blue: 1) : .white)
                .lineSpacing(2).padding(10)
        }
    }

    /// A swatch for a copied hex color (#rgb, #rrggbb, #rrggbbaa); other color forms show gray.
    static func color(_ s: String) -> Color? {
        var h = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard h.hasPrefix("#") else { return nil }
        h.removeFirst()
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6 || h.count == 8, let v = UInt64(h, radix: 16) else { return nil }
        let rgb = h.count == 8 ? v >> 8 : v
        let a = h.count == 8 ? Double(v & 0xff) / 255 : 1
        return Color(red: Double(rgb >> 16 & 0xff) / 255, green: Double(rgb >> 8 & 0xff) / 255, blue: Double(rgb & 0xff) / 255, opacity: a)
    }

    // MARK: detail

    @ViewBuilder private func detail(_ c: ClipboardHistory.Clip?) -> some View {
        if let c {
            VStack(alignment: .leading, spacing: 14) {
                ScrollView { content(c, big: true).frame(maxWidth: .infinity, alignment: .topLeading) }
                    .frame(maxHeight: .infinity)
                    .background(Look.cardGradient, in: RoundedRectangle(cornerRadius: 14))
                VStack(spacing: 6) {
                    info("Kind", c.category.rawValue)
                    info("Copied", Self.days([c]).first.map { $0.title + ", " + c.last.formatted(date: .omitted, time: .shortened) } ?? "")
                    info("Copied this many times", "\(c.count)")
                    info("Size", c.kind == .image ? "Picture" : c.kind == .files ? "\(c.paths?.count ?? 0) files" : "\(c.text.count.formatted()) characters")
                }
                HStack(spacing: 8) {
                    Button("Paste") { paste(c) }
                    Button("Copy") { model.clipboard.copy(c) }
                    Button(c.pinned ? "Unpin" : "Pin") { model.clipboard.togglePin(c) }
                    Button("Delete", role: .destructive) { model.clipboard.remove(c) }
                }
                .controlSize(.large)
                Text("Return pastes into the app you were in. ⌥ Return only copies. Arrow keys move. ⌘1 to ⌘9 paste the first nine.")
                    .font(Look.small).foregroundStyle(Look.dim).fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
        } else {
            Text("Pick a clip to see it here.").font(.system(size: 13)).foregroundStyle(Look.dim)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func info(_ label: String, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(Look.dim); Spacer(); Text(value) }.font(.system(size: 12))
    }

    @ViewBuilder private func actions(_ c: ClipboardHistory.Clip) -> some View {
        Button("Paste") { paste(c) }
        Button("Copy") { model.clipboard.copy(c) }
        Button(c.pinned ? "Unpin" : "Pin") { model.clipboard.togglePin(c) }
        Button("Delete", role: .destructive) { model.clipboard.remove(c) }
    }
}

/// One library window, opened from its shortcut, the menu bar and the shelf's "Open library" button.
enum ClipboardLibraryWindow {
    private static var window: NSWindow?
    /// The app John was typing in when the library opened; pasting goes back there.
    private static var previousApp: NSRunningApplication?

    private static var watcher: NSObjectProtocol?

    static func show(_ model: ShelfModel) {
        if let front = NSWorkspace.shared.frontmostApplication, front != .current { previousApp = front }
        // keep following the last other app John used, so a window left open pastes where he was just typing
        watcher = watcher ?? NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { n in
            if let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app != .current { previousApp = app }
        }
        if window == nil {
            let host = NSHostingController(rootView: ClipboardLibraryView(model: model, paste: { [weak model] c in model.map { paste(c, model: $0) } }))
            host.sizingOptions = []
            let w = NSWindow(contentViewController: host)
            w.title = "Clipboard"
            w.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            w.appearance = NSAppearance(named: .darkAqua)   // the shelf's dark look
            w.isReleasedWhenClosed = false
            w.setContentSize(NSSize(width: 1100, height: 680))
            w.contentMinSize = NSSize(width: 920, height: 480)
            w.center()
            w.setFrameAutosaveName("ClipboardLibrary")
            window = w
        }
        model.close()
        NSApp.activate(ignoringOtherApps: true)   // no Dock icon; bring the window forward
        window?.makeKeyAndOrderFront(nil)
    }

    /// Puts the clip on the clipboard, hides the library, goes back to the app John was in and pastes there.
    static func paste(_ c: ClipboardHistory.Clip, model: ShelfModel) {
        window?.orderOut(nil)
        previousApp?.activate()
        model.use(c, paste: true, wait: 0.3)
    }
}
