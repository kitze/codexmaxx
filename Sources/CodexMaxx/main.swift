import AppKit
import Foundation
import Sparkle
import SwiftUI

enum StatsSource: String, Sendable {
    case combined
    case active
}

enum WindowSelection: String, Sendable {
    case session
    case week
    case both
}

enum LabelStyle: String, Sendable {
    case letters
    case icons
    case none
}

enum BarLayout: String, Sendable {
    case inline
    case stacked
    case circles
}

enum UsageWindowKind: Hashable, Sendable {
    case session
    case week
}

struct DisplaySettings: Sendable {
    var source: StatsSource
    var windows: WindowSelection
    var labels: LabelStyle
    var layout: BarLayout
    var showNumbers: Bool
    var showEmails: Bool

    static func load() -> DisplaySettings {
        let defaults = UserDefaults.standard
        return DisplaySettings(
            source: StatsSource(rawValue: defaults.string(forKey: "display.source") ?? "") ?? .combined,
            windows: WindowSelection(rawValue: defaults.string(forKey: "display.windows") ?? "") ?? .both,
            labels: LabelStyle(rawValue: defaults.string(forKey: "display.labels") ?? "") ?? .letters,
            layout: BarLayout(rawValue: defaults.string(forKey: "display.layout") ?? "") ?? .inline,
            showNumbers: defaults.object(forKey: "display.showNumbers") as? Bool ?? true,
            showEmails: defaults.object(forKey: "display.showEmails") as? Bool ?? true)
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(self.source.rawValue, forKey: "display.source")
        defaults.set(self.windows.rawValue, forKey: "display.windows")
        defaults.set(self.labels.rawValue, forKey: "display.labels")
        defaults.set(self.layout.rawValue, forKey: "display.layout")
        defaults.set(self.showNumbers, forKey: "display.showNumbers")
        defaults.set(self.showEmails, forKey: "display.showEmails")
    }

    static var popup: DisplaySettings {
        DisplaySettings(source: .combined, windows: .both, labels: .letters, layout: .inline, showNumbers: true, showEmails: true)
    }

    func label(for kind: UsageWindowKind) -> String {
        switch self.labels {
        case .letters:
            return kind == .session ? "S" : "W"
        case .icons:
            return kind == .session ? "desktopcomputer" : "calendar"
        case .none:
            return ""
        }
    }
}

enum UsageColor {
    static func color(for remaining: Double) -> Color {
        switch remaining {
        case 70...:
            return .green
        case 40..<70:
            return .yellow
        case 15..<40:
            return .orange
        default:
            return .red
        }
    }

    static func nsColor(for remaining: Double) -> NSColor {
        switch remaining {
        case 70...:
            return .systemGreen
        case 40..<70:
            return .systemYellow
        case 15..<40:
            return .systemOrange
        default:
            return .systemRed
        }
    }
}

enum MenuBarIconRenderer {
    static func image(snapshot: UsageSnapshot, settings: DisplaySettings) -> NSImage {
        let size = self.size(snapshot: snapshot, settings: settings)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        switch settings.layout {
        case .stacked:
            self.drawStackedBars(snapshot: snapshot, settings: settings, size: size)
        case .circles:
            self.drawCircles(snapshot: snapshot, settings: settings, size: size)
        case .inline:
            break
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    static func size(snapshot: UsageSnapshot, settings: DisplaySettings) -> NSSize {
        let count = max(1, self.windows(snapshot, settings: settings).count)
        switch settings.layout {
        case .stacked:
            return NSSize(width: 24, height: 18)
        case .circles:
            let labelWidth: CGFloat = settings.labels == .none ? 0 : 13
            let itemWidth: CGFloat = labelWidth + 15
            let gap: CGFloat = count > 1 ? 4 : 0
            return NSSize(width: CGFloat(count) * itemWidth + gap, height: 18)
        case .inline:
            return NSSize(width: 42, height: 18)
        }
    }

    private static func windows(_ snapshot: UsageSnapshot, settings: DisplaySettings) -> [RateWindow] {
        var windows: [RateWindow] = []
        if settings.windows != .week, let primary = snapshot.primary {
            windows.append(primary)
        }
        if settings.windows != .session, let secondary = snapshot.secondary {
            windows.append(secondary)
        }
        return windows
    }

    private static func drawStackedBars(snapshot: UsageSnapshot, settings: DisplaySettings, size: NSSize) {
        let windows = self.windows(snapshot, settings: settings)
        let barHeight: CGFloat = windows.count > 1 ? 5 : 8
        let gap: CGFloat = 4
        let total = CGFloat(windows.count) * barHeight + CGFloat(max(0, windows.count - 1)) * gap
        var y = (size.height - total) / 2
        for window in windows {
            self.drawBar(rect: NSRect(x: 2, y: y, width: size.width - 4, height: barHeight), remaining: window.remainingPercent)
            y += barHeight + gap
        }
    }

    private static func drawBar(rect: NSRect, remaining: Double) {
        let radius = rect.height / 2
        NSColor.separatorColor.withAlphaComponent(0.45).setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        let fillWidth = max(1, rect.width * CGFloat(max(0, min(100, remaining)) / 100))
        let fill = NSRect(x: rect.minX, y: rect.minY, width: fillWidth, height: rect.height)
        UsageColor.nsColor(for: remaining).setFill()
        NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
    }

    private static func drawCircles(snapshot: UsageSnapshot, settings: DisplaySettings, size: NSSize) {
        let windows = self.windows(snapshot, settings: settings)
        let labelWidth: CGFloat = settings.labels == .none ? 0 : 13
        let itemWidth: CGFloat = labelWidth + 15
        let gap: CGFloat = windows.count > 1 ? 4 : 0
        var x: CGFloat = 0
        for (index, window) in windows.prefix(2).enumerated() {
            let kind: UsageWindowKind = index == 0 && settings.windows != .week ? .session : .week
            if settings.labels != .none {
                self.drawLabel(settings.label(for: kind), at: NSPoint(x: x, y: 2), settings: settings)
            }
            self.drawCircle(
                center: NSPoint(x: x + labelWidth + 7, y: size.height / 2),
                radius: 6.2,
                remaining: window.remainingPercent)
            x += itemWidth + gap
        }
    }

    private static func drawLabel(_ label: String, at point: NSPoint, settings: DisplaySettings) {
        guard !label.isEmpty else { return }
        if settings.labels == .icons {
            let image = NSImage(systemSymbolName: label, accessibilityDescription: nil)
            image?.isTemplate = true
            image?.draw(in: NSRect(x: point.x, y: point.y + 1, width: 11, height: 11))
        } else {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
            ]
            label.draw(at: point, withAttributes: attributes)
        }
    }

    private static func drawCircle(center: NSPoint, radius: CGFloat, remaining: Double) {
        let rect = NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let track = NSBezierPath(ovalIn: rect)
        track.lineWidth = 2.3
        NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
        track.stroke()

        let path = NSBezierPath()
        path.lineWidth = 2.5
        path.lineCapStyle = .round
        path.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 90,
            endAngle: 90 - CGFloat(max(0, min(100, remaining)) / 100) * 360,
            clockwise: true)
        UsageColor.nsColor(for: remaining).setStroke()
        path.stroke()
    }
}

@main
struct CodexMaxxApp {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        _ = delegate
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let controller = UsageController()
    private var settings = DisplaySettings.load()
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil)

    func applicationDidFinishLaunching(_: Notification) {
        self.statusItem.button?.title = "..."
        self.statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        self.statusItem.menu = self.makeMenu()
        Task { await self.controller.refresh(); self.render() }
        Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard self?.controller.canStartAccountAction == true else { return }
                await self?.controller.refresh()
                self?.render()
            }
        }
    }

    private func render(updateMenu: Bool = true) {
        let rows = self.controller.accounts
        if rows.isEmpty {
            self.statusItem.length = NSStatusItem.variableLength
            self.statusItem.button?.image = nil
            self.statusItem.button?.title = "codexmaxx"
        } else {
            let source = self.settings.source == .active
                ? rows.first(where: \.active)?.snapshot
                : UsageMath.combined(rows.map(\.snapshot))
            self.renderStatusItem(snapshot: source)
        }
        if updateMenu {
            self.statusItem.menu = self.makeMenu()
        }
    }

    private func renderStatusItem(snapshot: UsageSnapshot?) {
        guard let snapshot else {
            self.statusItem.length = NSStatusItem.variableLength
            self.statusItem.button?.image = nil
            self.statusItem.button?.title = "S ? W ?"
            return
        }

        switch self.settings.layout {
        case .inline:
            self.statusItem.length = NSStatusItem.variableLength
            self.statusItem.button?.image = nil
            self.statusItem.button?.title = UsageText.menuBarSummary(snapshot, settings: self.settings)
        case .stacked, .circles:
            self.statusItem.button?.title = ""
            let image = MenuBarIconRenderer.image(snapshot: snapshot, settings: self.settings)
            self.statusItem.length = image.size.width + 8
            self.statusItem.button?.image = image
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let top = NSMenuItem()
        top.view = HostingMenuView(rootView: MenuContent(
            controller: self.controller,
            settings: self.settings,
            onSwitch: { [weak self] name in self?.switchAccount(named: name) },
            onEdit: { [weak self] account in self?.editAccount(account) },
            onDelete: { [weak self] account in self?.deleteAccount(account) }))
        menu.addItem(top)
        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "Refresh", action: #selector(refreshNow), keyEquivalent: "r")
        refresh.target = self
        refresh.isEnabled = self.controller.canStartAccountAction
        menu.addItem(refresh)

        let add = NSMenuItem(title: "Add Current Account...", action: #selector(addCurrentAccount), keyEquivalent: "")
        add.target = self
        add.isEnabled = self.controller.canStartAccountAction
        menu.addItem(add)

        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingsItem.submenu = self.makeSettingsMenu()
        menu.addItem(settingsItem)

        let update = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
        update.target = self
        menu.addItem(update)

        let quit = NSMenuItem(title: "Quit CodexMaxx", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    private func makeSettingsMenu() -> NSMenu {
        let menu = NSMenu()
        self.addSetting(menu, "Combined Stats", self.settings.source == .combined, #selector(useCombinedStats))
        self.addSetting(menu, "Active Account Stats", self.settings.source == .active, #selector(useActiveStats))
        menu.addItem(.separator())
        self.addSetting(menu, "Session + Week", self.settings.windows == .both, #selector(showBothWindows))
        self.addSetting(menu, "Session Only", self.settings.windows == .session, #selector(showSessionOnly))
        self.addSetting(menu, "Week Only", self.settings.windows == .week, #selector(showWeekOnly))
        menu.addItem(.separator())
        self.addSetting(menu, "Letters", self.settings.labels == .letters, #selector(useLetters))
        self.addSetting(menu, "Icons", self.settings.labels == .icons, #selector(useIcons))
        self.addSetting(menu, "No Labels", self.settings.labels == .none, #selector(useNoLabels))
        menu.addItem(.separator())
        self.addSetting(menu, "Text", self.settings.layout == .inline, #selector(useTextIcon))
        self.addSetting(menu, "Stack Bars", self.settings.layout == .stacked, #selector(useStackedBarsIcon))
        self.addSetting(menu, "Circle Bars", self.settings.layout == .circles, #selector(useCircleBarsIcon))
        menu.addItem(.separator())
        self.addSetting(menu, "Numbers", self.settings.showNumbers, #selector(toggleNumbers))
        self.addSetting(menu, "Show Emails", self.settings.showEmails, #selector(toggleEmails))
        return menu
    }

    private func addSetting(_ menu: NSMenu, _ title: String, _ checked: Bool, _ action: Selector) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = checked ? .on : .off
        menu.addItem(item)
    }

    @objc private func refreshNow() {
        guard self.controller.canStartAccountAction else { return }
        Task {
            await self.controller.refresh()
            self.render()
        }
    }

    @objc private func switchAccount(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        self.switchAccount(named: name)
    }

    private func switchAccount(named name: String) {
        guard self.controller.canStartAccountAction else { return }
        self.controller.startSwitching(to: name)
        self.render(updateMenu: false)
        Task {
            await self.controller.finishSwitching(to: name)
            self.render(updateMenu: false)
        }
    }

    private func editAccount(_ account: CodexAccountUsage) {
        guard self.controller.canStartAccountAction else { return }
        let alert = NSAlert()
        alert.messageText = "Edit Account"
        alert.informativeText = "Rename the profile and optional label."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 320, height: 62))
        stack.orientation = .vertical
        stack.spacing = 8
        let name = NSTextField(string: account.name)
        let label = NSTextField(string: account.label ?? "")
        name.placeholderString = "Name"
        label.placeholderString = "Label"
        name.frame.size = NSSize(width: 320, height: 24)
        label.frame.size = NSSize(width: 320, height: 24)
        stack.addArrangedSubview(name)
        stack.addArrangedSubview(label)
        alert.accessoryView = stack
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            await self.controller.editAccount(oldName: account.name, newName: name.stringValue, label: label.stringValue)
            self.render()
        }
    }

    private func deleteAccount(_ account: CodexAccountUsage) {
        guard self.controller.canStartAccountAction else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete Profile?"
        alert.informativeText = "This removes '\(account.displayName)' from CodexMaxx. Your current ~/.codex files are not deleted."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            await self.controller.deleteAccount(named: account.name)
            self.render()
        }
    }

    @objc private func addCurrentAccount() {
        guard self.controller.canStartAccountAction else { return }
        let alert = NSAlert()
        alert.messageText = "Add Current Account"
        alert.informativeText = "This stores the currently active Codex credentials as a new CodexMaxx account."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 28))
        let field = NSTextField(string: "")
        field.placeholderString = "Account name"
        field.frame = NSRect(x: 0, y: 2, width: 320, height: 24)
        container.addSubview(field)
        alert.accessoryView = container
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            await self.controller.addCurrentAccount(named: field.stringValue)
            self.render()
        }
    }

    @objc private func useCombinedStats() { self.updateSettings { $0.source = .combined } }
    @objc private func useActiveStats() { self.updateSettings { $0.source = .active } }
    @objc private func showBothWindows() { self.updateSettings { $0.windows = .both } }
    @objc private func showSessionOnly() { self.updateSettings { $0.windows = .session } }
    @objc private func showWeekOnly() { self.updateSettings { $0.windows = .week } }
    @objc private func useLetters() { self.updateSettings { $0.labels = .letters } }
    @objc private func useIcons() { self.updateSettings { $0.labels = .icons } }
    @objc private func useNoLabels() { self.updateSettings { $0.labels = .none; $0.showNumbers = false; $0.layout = .stacked } }
    @objc private func useTextIcon() { self.updateSettings { $0.layout = .inline } }
    @objc private func useStackedBarsIcon() { self.updateSettings { $0.layout = .stacked } }
    @objc private func useCircleBarsIcon() { self.updateSettings { $0.layout = .circles } }
    @objc private func toggleNumbers() { self.updateSettings { $0.showNumbers.toggle() } }
    @objc private func toggleEmails() { self.updateSettings { $0.showEmails.toggle() } }

    @objc private func checkForUpdates() {
        self.updaterController.checkForUpdates(nil)
    }

    private func updateSettings(_ mutate: (inout DisplaySettings) -> Void) {
        mutate(&self.settings)
        self.settings.save()
        self.render()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

final class HostingMenuView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
        self.frame = NSRect(x: 0, y: 0, width: 340, height: 238)
    }

    @available(*, unavailable)
    @MainActor dynamic required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

struct MenuContent: View {
    @ObservedObject var controller: UsageController
    let settings: DisplaySettings
    let onSwitch: (String) -> Void
    let onEdit: (CodexAccountUsage) -> Void
    let onDelete: (CodexAccountUsage) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("codexmaxx")
                    .font(.headline)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                    Text(UsageText.time(controller.updatedAt))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            if controller.isRefreshing {
                Text("refreshing...")
                    .foregroundStyle(.secondary)
            }

            if let message = controller.statusMessage {
                HStack(spacing: 5) {
                    if controller.switchingAccountName != nil {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.55)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = controller.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let combined = UsageMath.combined(controller.accounts.map(\.snapshot)) {
                CombinedUsageView(snapshot: combined)
            }

            Divider()

            ForEach(controller.accounts) { account in
                AccountRow(
                    account: account,
                    settings: settings,
                    switchingAccountName: controller.switchingAccountName,
                    actionsDisabled: !controller.canStartAccountAction,
                    onSwitch: onSwitch,
                    onEdit: onEdit,
                    onDelete: onDelete)
                if account.id != controller.accounts.last?.id {
                    Divider()
                }
            }
        }
        .padding(.top, 4)
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .frame(width: 340, alignment: .leading)
    }
}

struct CombinedUsageView: View {
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            UsageBars(snapshot: snapshot, dimmed: false, combined: true, settings: .popup, forceInline: true)
        }
    }
}

struct AccountRow: View {
    let account: CodexAccountUsage
    let settings: DisplaySettings
    let switchingAccountName: String?
    let actionsDisabled: Bool
    let onSwitch: (String) -> Void
    let onEdit: (CodexAccountUsage) -> Void
    let onDelete: (CodexAccountUsage) -> Void

    var body: some View {
        let wasted = account.isWasted
        let isSwitching = switchingAccountName == account.name
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Button(action: { onSwitch(account.name) }) {
                    HStack(spacing: 8) {
                        if isSwitching {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.6)
                                .frame(width: 16, height: 16)
                        } else if account.active {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Image(systemName: wasted ? "clock" : "circle")
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text(account.displayName)
                                .font(.subheadline.weight(.semibold))
                            if settings.showEmails, !account.emailOrPlan.isEmpty {
                                Text(account.emailOrPlan)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(actionsDisabled || account.active)

                Spacer()

                Text(isSwitching ? "switching" : account.statusText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(isSwitching || wasted ? .secondary : .primary)

                HStack(spacing: 4) {
                    Button(action: { onEdit(account) }) {
                        Image(systemName: "pencil")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .disabled(actionsDisabled)
                    .help("Edit profile")

                    Button(action: { onDelete(account) }) {
                        Image(systemName: "trash")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .disabled(actionsDisabled)
                    .foregroundStyle(.red)
                    .help("Delete profile")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if let snapshot = account.snapshot {
                UsageBars(snapshot: snapshot, dimmed: wasted, combined: false, settings: .popup, forceInline: true)
            } else {
                Text(account.error ?? "No usage")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .contextMenu {
            Button("Edit Name/Label") { onEdit(account) }
                .disabled(actionsDisabled)
            Button("Delete Profile", role: .destructive) { onDelete(account) }
                .disabled(actionsDisabled)
        }
        .opacity(wasted && !isSwitching ? 0.45 : 1)
    }
}

struct UsageBars: View {
    let snapshot: UsageSnapshot
    let dimmed: Bool
    let combined: Bool
    let settings: DisplaySettings
    let forceInline: Bool

    var body: some View {
        let bars = self.visibleBars
        Group {
            if settings.layout == .stacked && !forceInline {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(bars) { bar in
                        BareUsageBar(window: bar.window, dimmed: dimmed)
                    }
                }
            } else {
                HStack(spacing: 14) {
                    ForEach(bars) { bar in
                        UsageBar(label: bar.label, window: bar.window, dimmed: dimmed, combined: combined, settings: settings)
                    }
                }
            }
        }
    }

    private var visibleBars: [VisibleUsageBar] {
        var bars: [VisibleUsageBar] = []
        if settings.windows != .week, let primary = snapshot.primary {
            bars.append(VisibleUsageBar(kind: .session, label: settings.label(for: .session), window: primary))
        }
        if settings.windows != .session, let secondary = snapshot.secondary {
            bars.append(VisibleUsageBar(kind: .week, label: settings.label(for: .week), window: secondary))
        }
        return bars
    }
}

struct UsageBar: View {
    let label: String
    let window: RateWindow
    let dimmed: Bool
    let combined: Bool
    let settings: DisplaySettings

    var body: some View {
        HStack(spacing: 6) {
            if !label.isEmpty {
                if settings.labels == .icons {
                    Image(systemName: label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                } else {
                    Text(label)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 10)
                }
            }
            ProgressView(value: max(0, min(100, window.remainingPercent)), total: 100)
                .tint(dimmed ? .gray : UsageColor.color(for: window.remainingPercent))
                .frame(width: 76)
            if settings.showNumbers {
                Text(combined ? UsageText.capacity(window) : UsageText.remaining(window))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .trailing)
            }
        }
    }
}

struct BareUsageBar: View {
    let window: RateWindow
    let dimmed: Bool

    var body: some View {
        ProgressView(value: max(0, min(100, window.remainingPercent)), total: 100)
            .tint(dimmed ? .gray : UsageColor.color(for: window.remainingPercent))
            .frame(width: 170)
    }
}

struct VisibleUsageBar: Identifiable {
    let kind: UsageWindowKind
    let label: String
    let window: RateWindow

    var id: UsageWindowKind { kind }
}

@MainActor
final class UsageController: ObservableObject {
    @Published private(set) var accounts: [CodexAccountUsage] = []
    @Published private(set) var updatedAt = Date()
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?
    @Published private(set) var switchingAccountName: String?
    @Published private(set) var statusMessage: String?

    var canStartAccountAction: Bool {
        !self.isRefreshing && self.switchingAccountName == nil
    }

    func refresh() async {
        self.isRefreshing = true
        defer { self.isRefreshing = false }
        do {
            let profiles = try CodexProfileStore.loadProfiles()
            self.accounts = await withTaskGroup(of: CodexAccountUsage.self) { group in
                for profile in profiles {
                    group.addTask {
                        await CodexUsageLoader.load(profile: profile)
                    }
                }
                var rows: [CodexAccountUsage] = []
                for await row in group {
                    rows.append(row)
                }
                return rows.sorted { lhs, rhs in
                    if lhs.active != rhs.active { return lhs.active && !rhs.active }
                    return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                }
            }
            self.updatedAt = Date()
            self.lastError = nil
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    func switchToAccount(named name: String) async {
        self.startSwitching(to: name)
        await self.finishSwitching(to: name)
    }

    func startSwitching(to name: String) {
        let displayName = self.displayName(for: name)
        self.switchingAccountName = name
        self.lastError = nil
        self.statusMessage = "Switching to \(displayName)..."
        self.markActiveAccount(named: name)
    }

    func finishSwitching(to name: String) async {
        do {
            try CodexProfileStore.switchToProfile(named: name)
            await self.refresh()
            self.statusMessage = "Switched to \(self.displayName(for: name))"
        } catch {
            await self.refresh()
            self.lastError = error.localizedDescription
            self.statusMessage = nil
        }
        self.switchingAccountName = nil
    }

    private func markActiveAccount(named name: String) {
        self.accounts = self.accounts
            .map { $0.withActive($0.name == name) }
            .sorted { lhs, rhs in
                if lhs.active != rhs.active { return lhs.active && !rhs.active }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    private func displayName(for name: String) -> String {
        if let account = self.accounts.first(where: { $0.name == name }) {
            return account.displayName
        }
        return name
    }

    func editAccount(oldName: String, newName: String, label: String) async {
        do {
            try CodexProfileStore.editProfile(
                oldName: oldName,
                newName: newName.trimmingCharacters(in: .whitespacesAndNewlines),
                label: label.trimmingCharacters(in: .whitespacesAndNewlines))
            await self.refresh()
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    func addCurrentAccount(named name: String) async {
        do {
            try CodexProfileStore.addCurrentProfile(named: name.trimmingCharacters(in: .whitespacesAndNewlines))
            await self.refresh()
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    func deleteAccount(named name: String) async {
        do {
            try CodexProfileStore.deleteProfile(named: name)
            await self.refresh()
        } catch {
            self.lastError = error.localizedDescription
        }
    }
}

struct CodexProfile: Sendable {
    let name: String
    let label: String?
    let homeURL: URL
    let active: Bool
}

struct CodexAccountUsage: Identifiable, Sendable {
    var id: String { self.name }
    let name: String
    let label: String?
    let active: Bool
    let snapshot: UsageSnapshot?
    let error: String?

    var displayName: String {
        guard let label, !label.isEmpty else { return self.name }
        return label
    }

    var emailOrPlan: String {
        let identity = self.snapshot?.identity
        return identity?.accountEmail ?? identity?.loginMethod ?? ""
    }

    var isWasted: Bool {
        guard let snapshot else { return true }
        let windows = [snapshot.primary, snapshot.secondary].compactMap { $0 }
        guard !windows.isEmpty else { return true }
        return windows.contains { $0.remainingPercent <= 0.5 }
    }

    var statusText: String {
        guard let snapshot else { return "offline" }
        if self.isWasted {
            return UsageText.comeback(snapshot) ?? "wasted"
        }
        return UsageText.summary(snapshot)
    }

    func withActive(_ active: Bool) -> CodexAccountUsage {
        CodexAccountUsage(name: self.name, label: self.label, active: active, snapshot: self.snapshot, error: self.error)
    }
}

enum CodexProfileStore {
    private static let managedRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codexmaxx")
    private static let codexProfilesRoot = managedRoot.appendingPathComponent("profiles/codex")
    private static let liveCodexHome = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex")
    private static let backupRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codexmaxx/backups")
    private static let switchedFiles = [
        "auth.json",
        "config.toml",
        "models_cache.json",
        "installation_id",
        "version.json",
    ]

    static func loadProfiles() throws -> [CodexProfile] {
        let root = Self.codexProfilesRoot
        let config = (try? Self.loadConfig()) ?? CodexMaxxConfig.empty
        let active = Self.activeProfileName()
        let urls = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])

        return urls.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            guard FileManager.default.fileExists(atPath: url.appendingPathComponent("auth.json").path) else { return nil }
            let name = url.lastPathComponent
            return CodexProfile(name: name, label: config.profiles[name]?.label, homeURL: url, active: name == active)
        }
    }

    static func switchToProfile(named name: String) throws {
        let targetHome = Self.codexProfilesRoot.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: targetHome.appendingPathComponent("auth.json").path) else {
            throw NSError(domain: "CodexMaxx", code: 10, userInfo: [
                NSLocalizedDescriptionKey: "Codex profile '\(name)' has no auth.json",
            ])
        }

        let current = Self.activeProfileName()
        if let current, current != name {
            let currentHome = Self.codexProfilesRoot.appendingPathComponent(current)
            if Self.profilesHaveMatchingIdentity(Self.liveCodexHome, currentHome) {
                try Self.copySwitchedFiles(from: Self.liveCodexHome, to: currentHome)
            }
        }

        try Self.backupLiveCodexHome()
        try Self.copySwitchedFiles(from: targetHome, to: Self.liveCodexHome)
        try Self.updateActiveProfileName(name)
    }

    static func editProfile(oldName: String, newName: String, label: String) throws {
        let finalName = newName.isEmpty ? oldName : Self.safeProfileName(newName)
        let source = Self.codexProfilesRoot.appendingPathComponent(oldName)
        let destination = Self.codexProfilesRoot.appendingPathComponent(finalName)
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        if oldName != finalName {
            guard !FileManager.default.fileExists(atPath: destination.path) else {
                throw NSError(domain: "CodexMaxx", code: 11, userInfo: [NSLocalizedDescriptionKey: "Account '\(finalName)' already exists"])
            }
            try FileManager.default.moveItem(at: source, to: destination)
        }
        var config = (try? Self.loadConfig()) ?? CodexMaxxConfig.empty
        let previous = config.profiles.removeValue(forKey: oldName)
        config.profiles[finalName] = CodexMaxxProfile(
            addedAt: previous?.addedAt ?? ISO8601DateFormatter().string(from: Date()),
            label: label.isEmpty ? nil : label)
        if config.active == oldName {
            config.active = finalName
        }
        try Self.saveConfig(config)
    }

    static func addCurrentProfile(named name: String) throws {
        let finalName = Self.safeProfileName(name.isEmpty ? "account" : name)
        let destination = Self.availableProfileURL(named: finalName)
        try Self.copySwitchedFiles(from: Self.liveCodexHome, to: destination)
        var config = (try? Self.loadConfig()) ?? CodexMaxxConfig.empty
        config.profiles[destination.lastPathComponent] = CodexMaxxProfile(
            addedAt: ISO8601DateFormatter().string(from: Date()),
            label: nil)
        try Self.saveConfig(config)
    }

    static func deleteProfile(named name: String) throws {
        let target = Self.codexProfilesRoot.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: target.path) else { return }
        try FileManager.default.removeItem(at: target)

        var config = (try? Self.loadConfig()) ?? CodexMaxxConfig.empty
        config.profiles.removeValue(forKey: name)
        if config.active == name {
            config.active = nil
        }
        try Self.saveConfig(config)
    }

    private static func backupLiveCodexHome() throws {
        let stamp = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let destination = Self.backupRoot.appendingPathComponent(stamp)
        try Self.copySwitchedFiles(from: Self.liveCodexHome, to: destination)
    }

    private static func copySwitchedFiles(from source: URL, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for file in Self.switchedFiles {
            let sourceURL = source.appendingPathComponent(file)
            let destinationURL = destination.appendingPathComponent(file)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else { continue }
            _ = try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
            if file == "auth.json" || file == "config.toml" {
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destinationURL.path)
            }
        }
    }

    private static func profilesHaveMatchingIdentity(_ lhs: URL, _ rhs: URL) -> Bool {
        guard let lhsIdentity = Self.profileIdentity(at: lhs),
              let rhsIdentity = Self.profileIdentity(at: rhs) else {
            return true
        }
        return lhsIdentity == rhsIdentity
    }

    private static func profileIdentity(at home: URL) -> String? {
        let url = home.appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any] else {
            return nil
        }
        if let accountId = Self.nonEmptyString(tokens["account_id"]) ?? Self.nonEmptyString(tokens["accountId"]) {
            return "account:\(accountId)"
        }
        if let email = Self.email(fromIDToken: Self.nonEmptyString(tokens["id_token"]) ?? Self.nonEmptyString(tokens["idToken"])) {
            return "email:\(email.lowercased())"
        }
        return nil
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        (value as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func email(fromIDToken token: String?) -> String? {
        guard let token else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let profile = json["https://api.openai.com/profile"] as? [String: Any]
        return json["email"] as? String ?? profile?["email"] as? String
    }

    private static func activeProfileName() -> String? {
        let config = (try? Self.loadConfig()) ?? CodexMaxxConfig.empty
        return config.active
    }

    private static func updateActiveProfileName(_ name: String) throws {
        var config = (try? Self.loadConfig()) ?? CodexMaxxConfig.empty
        config.active = name
        try Self.saveConfig(config)
    }

    private static func loadConfig() throws -> CodexMaxxConfig {
        let url = Self.managedRoot.appendingPathComponent("config.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CodexMaxxConfig.self, from: data)
    }

    private static func saveConfig(_ config: CodexMaxxConfig) throws {
        let url = Self.managedRoot.appendingPathComponent("config.json")
        try FileManager.default.createDirectory(at: Self.managedRoot, withIntermediateDirectories: true)
        let data = try JSONEncoder.pretty.encode(config)
        try data.write(to: url, options: .atomic)
    }

    private static func safeProfileName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = name.lowercased().unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let value = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return value.isEmpty ? "account" : value
    }

    private static func availableProfileURL(named name: String) -> URL {
        var candidate = Self.codexProfilesRoot.appendingPathComponent(name)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = Self.codexProfilesRoot.appendingPathComponent("\(name)-\(index)")
            index += 1
        }
        return candidate
    }
}

struct CodexMaxxConfig: Codable, Sendable {
    var version: Int
    var active: String?
    var profiles: [String: CodexMaxxProfile]

    static let empty = CodexMaxxConfig(version: 1, active: nil, profiles: [:])
}

struct CodexMaxxProfile: Codable, Sendable {
    var addedAt: String?
    var label: String?

    enum CodingKeys: String, CodingKey {
        case addedAt = "added_at"
        case label
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

enum CodexUsageLoader {
    static func load(profile: CodexProfile) async -> CodexAccountUsage {
        do {
            var env = ProcessInfo.processInfo.environment
            env["CODEX_HOME"] = profile.homeURL.path
            var credentials = try CodexOAuthCredentialsStore.load(env: env)
            if credentials.needsRefresh, !credentials.refreshToken.isEmpty {
                credentials = try await CodexTokenRefresher.refresh(credentials)
                try CodexOAuthCredentialsStore.save(credentials, env: env)
            }
            let response = try await CodexOAuthUsageFetcher.fetchUsage(
                accessToken: credentials.accessToken,
                accountId: credentials.accountId,
                env: env)
            let snapshot = CodexReconciledState
                .fromOAuth(response: response, credentials: credentials)
            return CodexAccountUsage(
                name: profile.name,
                label: profile.label,
                active: profile.active,
                snapshot: snapshot,
                error: snapshot == nil ? "No rate limits returned" : nil)
        } catch {
            return CodexAccountUsage(
                name: profile.name,
                label: profile.label,
                active: profile.active,
                snapshot: nil,
                error: error.localizedDescription)
        }
    }
}

enum UsageMath {
    static func combined(_ snapshots: [UsageSnapshot?]) -> UsageSnapshot? {
        let primary = self.combineUsableSession(snapshots.compactMap { $0 })
        let secondary = self.combine(snapshots.compactMap(\.?.secondary))
        guard primary != nil || secondary != nil else { return nil }
        return UsageSnapshot(primary: primary, secondary: secondary, updatedAt: Date(), identity: nil)
    }

    private static func combineUsableSession(_ snapshots: [UsageSnapshot]) -> RateWindow? {
        let usable = snapshots.compactMap { snapshot -> RateWindow? in
            guard let primary = snapshot.primary else { return nil }
            guard (snapshot.secondary?.remainingPercent ?? 100) > 0.5 else { return nil }
            return primary
        }
        return self.combine(usable)
    }

    private static func combine(_ windows: [RateWindow]) -> RateWindow? {
        guard !windows.isEmpty else { return nil }
        let remaining = windows.map(\.remainingPercent).reduce(0, +)
        let used = 100 - remaining
        return RateWindow(
            usedPercent: used,
            windowMinutes: windows.first?.windowMinutes,
            resetsAt: windows.compactMap(\.resetsAt).max(),
            resetDescription: nil)
    }
}

enum UsageText {
    static func remaining(_ window: RateWindow) -> String {
        "\(Int(window.remainingPercent.rounded()))%"
    }

    static func capacity(_ window: RateWindow) -> String {
        "\(Int(window.remainingPercent.rounded()))%"
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    static func summary(_ snapshot: UsageSnapshot) -> String {
        let primary = snapshot.primary.map(Self.capacity) ?? "--"
        let secondary = snapshot.secondary.map(Self.capacity) ?? "--"
        return "\(primary) / \(secondary)"
    }

    static func labeledSummary(_ snapshot: UsageSnapshot) -> String {
        let primary = snapshot.primary.map(Self.capacity) ?? "--"
        let secondary = snapshot.secondary.map(Self.capacity) ?? "--"
        return "S \(primary)  W \(secondary)"
    }

    static func menuBarSummary(_ snapshot: UsageSnapshot, settings: DisplaySettings) -> String {
        var parts: [String] = []
        if settings.windows != .week {
            parts.append("\(settings.label(for: .session).isEmpty ? "S" : settings.label(for: .session)) \(snapshot.primary.map(Self.capacity) ?? "?")")
        }
        if settings.windows != .session {
            parts.append("\(settings.label(for: .week).isEmpty ? "W" : settings.label(for: .week)) \(snapshot.secondary.map(Self.capacity) ?? "?")")
        }
        return parts.joined(separator: " ")
    }

    static func comeback(_ snapshot: UsageSnapshot) -> String? {
        let resets = [snapshot.primary, snapshot.secondary]
            .compactMap { window -> Date? in
                guard let window, window.remainingPercent <= 0.5 else { return nil }
                return window.resetsAt
            }
            .filter { $0 > Date() }
            .sorted()
        guard let reset = resets.first else { return nil }
        return Self.countdown(to: reset)
    }

    static func countdown(to date: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSinceNow))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}

struct RateWindow: Codable, Equatable, Sendable {
    let usedPercent: Double
    let windowMinutes: Int?
    let resetsAt: Date?
    let resetDescription: String?

    var remainingPercent: Double {
        max(0, 100 - self.usedPercent)
    }
}

struct ProviderIdentitySnapshot: Codable, Sendable {
    let accountEmail: String?
    let loginMethod: String?
}

struct UsageSnapshot: Codable, Sendable {
    let primary: RateWindow?
    let secondary: RateWindow?
    let updatedAt: Date
    let identity: ProviderIdentitySnapshot?

    init(primary: RateWindow?, secondary: RateWindow?, updatedAt: Date, identity: ProviderIdentitySnapshot? = nil) {
        self.primary = primary
        self.secondary = secondary
        self.updatedAt = updatedAt
        self.identity = identity
    }
}

struct CodexOAuthCredentials: Sendable {
    let accessToken: String
    let refreshToken: String
    let idToken: String?
    let accountId: String?
    let lastRefresh: Date?

    var needsRefresh: Bool {
        guard let lastRefresh else { return true }
        return Date().timeIntervalSince(lastRefresh) > 8 * 24 * 60 * 60
    }
}

enum CodexOAuthCredentialsStore {
    static func load(env: [String: String]) throws -> CodexOAuthCredentials {
        let home = env["CODEX_HOME"].flatMap { $0.isEmpty ? nil : $0 }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
        let data = try Data(contentsOf: URL(fileURLWithPath: home).appendingPathComponent("auth.json"))
        return try self.parse(data: data)
    }

    static func save(_ credentials: CodexOAuthCredentials, env: [String: String]) throws {
        let home = env["CODEX_HOME"].flatMap { $0.isEmpty ? nil : $0 }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
        let url = URL(fileURLWithPath: home).appendingPathComponent("auth.json")
        var json: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            json = existing
        }
        var tokens: [String: Any] = [
            "access_token": credentials.accessToken,
            "refresh_token": credentials.refreshToken,
        ]
        if let idToken = credentials.idToken { tokens["id_token"] = idToken }
        if let accountId = credentials.accountId { tokens["account_id"] = accountId }
        json["tokens"] = tokens
        json["last_refresh"] = ISO8601DateFormatter().string(from: Date())
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private static func parse(data: Data) throws -> CodexOAuthCredentials {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any],
              let accessToken = Self.string(tokens, "access_token", "accessToken") else {
            throw NSError(domain: "CodexMaxx", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing Codex OAuth tokens"])
        }
        return CodexOAuthCredentials(
            accessToken: accessToken,
            refreshToken: Self.string(tokens, "refresh_token", "refreshToken") ?? "",
            idToken: Self.string(tokens, "id_token", "idToken"),
            accountId: Self.string(tokens, "account_id", "accountId"),
            lastRefresh: Self.parseLastRefresh(json["last_refresh"]))
    }

    private static func string(_ dict: [String: Any], _ snake: String, _ camel: String) -> String? {
        (dict[snake] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? (dict[camel] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func parseLastRefresh(_ raw: Any?) -> Date? {
        guard let value = raw as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

struct CodexUsageResponse: Decodable, Sendable {
    let planType: String?
    let rateLimit: RateLimit?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
    }

    struct RateLimit: Decodable, Sendable {
        let primaryWindow: Window?
        let secondaryWindow: Window?

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    struct Window: Decodable, Sendable {
        let usedPercent: Int
        let resetAt: Int
        let limitWindowSeconds: Int

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case resetAt = "reset_at"
            case limitWindowSeconds = "limit_window_seconds"
        }
    }
}

enum CodexOAuthUsageFetcher {
    static func fetchUsage(accessToken: String, accountId: String?, env: [String: String]) async throws -> CodexUsageResponse {
        let base = Self.chatGPTBaseURL(env: env)
        let path = base.contains("/backend-api") ? "/wham/usage" : "/api/codex/usage"
        guard let url = URL(string: base + path) else {
            throw NSError(domain: "CodexMaxx", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid usage URL"])
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("CodexMaxx", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "CodexMaxx", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        guard (200...299).contains(http.statusCode) else {
            throw NSError(domain: "CodexMaxx", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Usage API returned \(http.statusCode)"])
        }
        return try JSONDecoder().decode(CodexUsageResponse.self, from: data)
    }

    private static func chatGPTBaseURL(env: [String: String]) -> String {
        let home = env["CODEX_HOME"].flatMap { $0.isEmpty ? nil : $0 }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path
        let config = URL(fileURLWithPath: home).appendingPathComponent("config.toml")
        let configured = (try? String(contentsOf: config)).flatMap(Self.parseChatGPTBaseURL)
        var base = configured ?? "https://chatgpt.com/backend-api"
        while base.hasSuffix("/") { base.removeLast() }
        if (base.hasPrefix("https://chatgpt.com") || base.hasPrefix("https://chat.openai.com")),
           !base.contains("/backend-api") {
            base += "/backend-api"
        }
        return base
    }

    private static func parseChatGPTBaseURL(_ contents: String) -> String? {
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.split(separator: "#", maxSplits: 1).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard parts.count == 2, parts[0] == "chatgpt_base_url" else { continue }
            return parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return nil
    }
}

enum CodexTokenRefresher {
    static func refresh(_ credentials: CodexOAuthCredentials) async throws -> CodexOAuthCredentials {
        guard !credentials.refreshToken.isEmpty else { return credentials }
        var request = URLRequest(url: URL(string: "https://auth.openai.com/oauth/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "client_id": "app_EMoamEEZ73f0CkXaXp7hrann",
            "grant_type": "refresh_token",
            "refresh_token": credentials.refreshToken,
            "scope": "openid profile email",
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "CodexMaxx", code: 4, userInfo: [NSLocalizedDescriptionKey: "Token refresh failed"])
        }
        return CodexOAuthCredentials(
            accessToken: json["access_token"] as? String ?? credentials.accessToken,
            refreshToken: json["refresh_token"] as? String ?? credentials.refreshToken,
            idToken: json["id_token"] as? String ?? credentials.idToken,
            accountId: credentials.accountId,
            lastRefresh: Date())
    }
}

enum CodexReconciledState {
    static func fromOAuth(response: CodexUsageResponse, credentials: CodexOAuthCredentials) -> UsageSnapshot? {
        let primary = Self.window(response.rateLimit?.primaryWindow)
        let secondary = Self.window(response.rateLimit?.secondaryWindow)
        guard primary != nil || secondary != nil else { return nil }
        return UsageSnapshot(
            primary: primary,
            secondary: secondary,
            updatedAt: Date(),
            identity: ProviderIdentitySnapshot(
                accountEmail: Self.email(from: credentials.idToken),
                loginMethod: response.planType))
    }

    private static func window(_ window: CodexUsageResponse.Window?) -> RateWindow? {
        guard let window else { return nil }
        let reset = Date(timeIntervalSince1970: TimeInterval(window.resetAt))
        return RateWindow(
            usedPercent: Double(window.usedPercent),
            windowMinutes: window.limitWindowSeconds / 60,
            resetsAt: reset,
            resetDescription: Self.resetDescription(reset))
    }

    private static func resetDescription(_ date: Date) -> String {
        let interval = Int(date.timeIntervalSinceNow)
        if interval <= 0 { return "resets now" }
        let hours = interval / 3600
        let minutes = (interval % 3600) / 60
        if hours > 0 { return "resets in \(hours)h \(minutes)m" }
        return "resets in \(minutes)m"
    }

    private static func email(from token: String?) -> String? {
        guard let token else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let profile = json["https://api.openai.com/profile"] as? [String: Any]
        return json["email"] as? String ?? profile?["email"] as? String
    }
}
