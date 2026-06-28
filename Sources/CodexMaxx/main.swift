import AppKit
import Combine
import Foundation
import Sparkle
import SwiftUI

enum StatsSource: String, CaseIterable, Sendable {
    case combined
    case active

    var title: String {
        switch self {
        case .combined:
            return "Combined"
        case .active:
            return "Active"
        }
    }
}

enum WindowSelection: String, CaseIterable, Sendable {
    case session
    case week
    case both

    var title: String {
        switch self {
        case .session:
            return "Session"
        case .week:
            return "Week"
        case .both:
            return "Both"
        }
    }
}

enum LabelStyle: String, CaseIterable, Sendable {
    case letters
    case icons
    case none

    var title: String {
        switch self {
        case .letters:
            return "Letters"
        case .icons:
            return "Icons"
        case .none:
            return "None"
        }
    }
}

enum BarLayout: String, CaseIterable, Sendable {
    case inline
    case stacked
    case circles

    var title: String {
        switch self {
        case .inline:
            return "Text"
        case .stacked:
            return "Stack Bars"
        case .circles:
            return "Circle Bars"
        }
    }
}

enum LoadBalancerStrategy: String, Codable, CaseIterable, Sendable {
    case capacityWeighted = "capacity_weighted"
    case usageWeighted = "usage_weighted"
    case roundRobin = "round_robin"

    var title: String {
        switch self {
        case .capacityWeighted:
            return "Capacity Weighted"
        case .usageWeighted:
            return "Usage Weighted"
        case .roundRobin:
            return "Round Robin"
        }
    }

    var description: String {
        switch self {
        case .capacityWeighted:
            return "Pick accounts with the most usable capacity more often."
        case .usageWeighted:
            return "Prefer the least-used account that still has capacity."
        case .roundRobin:
            return "Cycle through available accounts in order."
        }
    }
}

enum UsageWindowKind: Hashable, Sendable {
    case session
    case week
}

enum AppInfo {
    static var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "CodexMaxx"
    }
}

struct LoadBalancerSettings: Codable, Sendable {
    var enabled: Bool
    var autoSwitchWhenWasted: Bool
    var strategy: LoadBalancerStrategy
    var preferEarlierReset: Bool

    static let disabled = LoadBalancerSettings(
        enabled: false,
        autoSwitchWhenWasted: true,
        strategy: .capacityWeighted,
        preferEarlierReset: true)

    enum CodingKeys: String, CodingKey {
        case enabled
        case autoSwitchWhenWasted = "auto_switch_when_wasted"
        case strategy
        case preferEarlierReset = "prefer_earlier_reset"
    }
}

struct DisplaySettings: Sendable {
    var source: StatsSource
    var windows: WindowSelection
    var labels: LabelStyle
    var layout: BarLayout
    var showNumbers: Bool
    var showEmails: Bool
    var showSessionMenuBarIcon: Bool
    var blinkSessionIconWhenIdle: Bool
    var beepWhenIdle: Bool

    static func load() -> DisplaySettings {
        let defaults = UserDefaults.standard
        return DisplaySettings(
            source: StatsSource(rawValue: defaults.string(forKey: "display.source") ?? "") ?? .combined,
            windows: WindowSelection(rawValue: defaults.string(forKey: "display.windows") ?? "") ?? .both,
            labels: LabelStyle(rawValue: defaults.string(forKey: "display.labels") ?? "") ?? .letters,
            layout: BarLayout(rawValue: defaults.string(forKey: "display.layout") ?? "") ?? .inline,
            showNumbers: defaults.object(forKey: "display.showNumbers") as? Bool ?? true,
            showEmails: defaults.object(forKey: "display.showEmails") as? Bool ?? true,
            showSessionMenuBarIcon: defaults.object(forKey: "display.showSessionMenuBarIcon") as? Bool ?? true,
            blinkSessionIconWhenIdle: defaults.object(forKey: "display.blinkSessionIconWhenIdle") as? Bool ?? false,
            beepWhenIdle: defaults.object(forKey: "display.beepWhenIdle") as? Bool ?? false)
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(self.source.rawValue, forKey: "display.source")
        defaults.set(self.windows.rawValue, forKey: "display.windows")
        defaults.set(self.labels.rawValue, forKey: "display.labels")
        defaults.set(self.layout.rawValue, forKey: "display.layout")
        defaults.set(self.showNumbers, forKey: "display.showNumbers")
        defaults.set(self.showEmails, forKey: "display.showEmails")
        defaults.set(self.showSessionMenuBarIcon, forKey: "display.showSessionMenuBarIcon")
        defaults.set(self.blinkSessionIconWhenIdle, forKey: "display.blinkSessionIconWhenIdle")
        defaults.set(self.beepWhenIdle, forKey: "display.beepWhenIdle")
    }

    static var popup: DisplaySettings {
        DisplaySettings(
            source: .combined,
            windows: .both,
            labels: .letters,
            layout: .inline,
            showNumbers: true,
            showEmails: true,
            showSessionMenuBarIcon: true,
            blinkSessionIconWhenIdle: false,
            beepWhenIdle: false)
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

struct CodexSessionStatus: Sendable {
    let count: Int
    let sampledAt: Date

    var hasActiveSession: Bool {
        self.count > 0
    }

    var detail: String {
        self.hasActiveSession ? "In progress" : "No active session"
    }

    var menuBarTitle: String {
        "\(self.count)"
    }
}

enum CodexSessionMonitor {
    private static let activityWindowSeconds = 180

    static func load(now: Date = Date()) -> CodexSessionStatus {
        let logsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/logs_2.sqlite")
        guard FileManager.default.fileExists(atPath: logsURL.path) else {
            return CodexSessionStatus(count: 0, sampledAt: now)
        }

        let cutoff = Int(now.timeIntervalSince1970) - self.activityWindowSeconds
        let query = """
        select count(distinct thread_id)
        from logs
        where thread_id is not null
          and ts >= \(cutoff)
          and feedback_log_body like '%:turn{%'
          and feedback_log_body like '%codex.op="user_input_with_turn_context"%';
        """
        return CodexSessionStatus(
            count: max(0, self.sqliteInteger(database: logsURL, query: query) ?? 0),
            sampledAt: now)
    }

    private static func sqliteInteger(database: URL, query: String) -> Int? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            "-readonly",
            "-batch",
            "-cmd",
            ".timeout 100",
            database.path,
            query,
        ]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(text ?? "")
        } catch {
            return nil
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
        app.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let sessionStatusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let controller = UsageController()
    private var settings = DisplaySettings.load()
    private var loadBalancerSettings = CodexProfileStore.loadLoadBalancerSettings()
    private var mainWindowController: NSWindowController?
    private var mainWindowHost: NSHostingController<MainWindowContent>?
    private var settingsWindowController: NSWindowController?
    private var settingsWindowHost: NSHostingController<SettingsWindowContent>?
    private var didStart = false
    private var sessionBlinkVisible = true
    private var lastIdleSessionBeepAt: Date?
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil)

    func applicationDidFinishLaunching(_: Notification) {
        self.start()
    }

    func start() {
        guard !self.didStart else { return }
        self.didStart = true
        NSApp.mainMenu = self.makeMainMenu()
        self.statusItem.button?.title = "..."
        self.statusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        self.statusItem.menu = self.makeMenu()
        self.sessionStatusItem.button?.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        self.sessionStatusItem.button?.imagePosition = .imageLeading
        self.sessionStatusItem.button?.target = self
        self.sessionStatusItem.button?.action = #selector(openMainWindow)
        self.renderSessionStatusItem()
        DispatchQueue.main.async {
            self.showMainWindow()
        }
        Task { await self.refreshAndRender() }
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshSessionStatusAndRender()
            }
        }
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.sessionBlinkVisible.toggle()
                self.renderSessionStatusItem()
            }
        }
        Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshAndRender()
            }
        }
    }

    private func makeMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "About \(AppInfo.displayName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettingsWindow), keyEquivalent: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit \(AppInfo.displayName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Show \(AppInfo.displayName)", action: #selector(openMainWindow), keyEquivalent: "0"))
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        return mainMenu
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        self.showMainWindow()
        return true
    }

    private func refreshAndRender() async {
        guard self.controller.canStartAccountAction else { return }
        await self.controller.refresh()
        await self.controller.refreshSessionStatus()
        await self.controller.autoBalanceIfNeeded(settings: self.loadBalancerSettings)
        self.render()
    }

    private func refreshSessionStatusAndRender() async {
        await self.controller.refreshSessionStatus()
        self.renderSessionStatusItem()
        self.handleIdleSessionSound()
    }

    private func render() {
        let rows = self.controller.accounts
        if rows.isEmpty {
            self.statusItem.length = NSStatusItem.variableLength
            self.statusItem.button?.image = nil
            self.statusItem.button?.title = "codexmaxx"
        } else {
            let activeResetCredits = rows.first(where: \.active)?.resetCredits
            let source = self.settings.source == .active
                ? rows.first(where: \.active)?.snapshot
                : UsageMath.combined(rows.map(\.snapshot))
            self.renderStatusItem(snapshot: source, resetCredits: activeResetCredits)
        }
        self.renderSessionStatusItem()
        self.handleIdleSessionSound()
        self.statusItem.menu = self.makeMenu()
        self.updateWindowContent()
    }

    private func updateWindowContent() {
        self.mainWindowHost?.rootView = self.makeMainWindowContent()
        self.settingsWindowHost?.rootView = self.makeSettingsWindowContent()
    }

    private func renderStatusItem(snapshot: UsageSnapshot?, resetCredits: CodexResetCreditsSnapshot?) {
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
            self.statusItem.button?.title = UsageText.menuBarSummary(snapshot, resetCredits: resetCredits, settings: self.settings)
        case .stacked, .circles:
            self.statusItem.button?.title = ""
            let image = MenuBarIconRenderer.image(snapshot: snapshot, settings: self.settings)
            self.statusItem.length = image.size.width + 8
            self.statusItem.button?.image = image
            self.statusItem.button?.toolTip = resetCredits.map { "Codex resets: \($0.availableCount)" }
        }
    }

    private func renderSessionStatusItem() {
        self.sessionStatusItem.isVisible = self.settings.showSessionMenuBarIcon
        guard self.settings.showSessionMenuBarIcon, let button = self.sessionStatusItem.button else { return }

        let status = self.controller.sessionStatus
        let symbolName = status.hasActiveSession ? "play.circle.fill" : "pause.circle"
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Codex sessions")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        button.title = status.menuBarTitle
        button.toolTip = status.hasActiveSession
            ? "\(status.count) Codex session\(status.count == 1 ? "" : "s") in progress"
            : "No Codex sessions in progress"
        button.alphaValue = self.settings.blinkSessionIconWhenIdle && !status.hasActiveSession && !self.sessionBlinkVisible ? 0.18 : 1
    }

    private func handleIdleSessionSound() {
        guard self.settings.beepWhenIdle else {
            self.lastIdleSessionBeepAt = nil
            return
        }

        guard !self.controller.sessionStatus.hasActiveSession else {
            self.lastIdleSessionBeepAt = nil
            return
        }

        let now = Date()
        if let lastIdleSessionBeepAt, now.timeIntervalSince(lastIdleSessionBeepAt) < 60 {
            return
        }
        NSSound.beep()
        self.lastIdleSessionBeepAt = now
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

        let openWindow = NSMenuItem(title: "Open Window", action: #selector(openMainWindow), keyEquivalent: "o")
        openWindow.target = self
        menu.addItem(openWindow)

        let add = NSMenuItem(title: "Add Current Account...", action: #selector(addCurrentAccount), keyEquivalent: "")
        add.target = self
        add.isEnabled = self.controller.canStartAccountAction
        menu.addItem(add)

        let balance = NSMenuItem(title: "Balance Now", action: #selector(balanceNow), keyEquivalent: "b")
        balance.target = self
        balance.isEnabled = self.loadBalancerSettings.enabled && self.controller.canStartAccountAction
        menu.addItem(balance)

        let settingsItem = NSMenuItem(title: "Settings", action: nil, keyEquivalent: "")
        settingsItem.submenu = self.makeSettingsMenu()
        menu.addItem(settingsItem)

        let settingsWindow = NSMenuItem(title: "Settings Window...", action: #selector(openSettingsWindow), keyEquivalent: ",")
        settingsWindow.target = self
        menu.addItem(settingsWindow)

        let update = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdates), keyEquivalent: "")
        update.target = self
        menu.addItem(update)

        let quit = NSMenuItem(title: "Quit \(AppInfo.displayName)", action: #selector(quit), keyEquivalent: "q")
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
        menu.addItem(.separator())
        self.addSetting(menu, "Show Session Status in Menu Bar", self.settings.showSessionMenuBarIcon, #selector(toggleSessionMenuBarIcon))
        self.addSetting(menu, "Blink When No Session", self.settings.blinkSessionIconWhenIdle, #selector(toggleSessionBlinkWhenIdle))
        self.addSetting(menu, "Beep When No Session", self.settings.beepWhenIdle, #selector(toggleSessionBeepWhenIdle))
        menu.addItem(.separator())
        self.addSetting(menu, "Load Balancer", self.loadBalancerSettings.enabled, #selector(toggleLoadBalancer))
        self.addSetting(
            menu,
            "Auto Switch When Wasted",
            self.loadBalancerSettings.autoSwitchWhenWasted,
            #selector(toggleLoadBalancerAutoSwitch))
        self.addSetting(
            menu,
            "Prefer Earlier Weekly Reset",
            self.loadBalancerSettings.preferEarlierReset,
            #selector(togglePreferEarlierReset))

        let strategyItem = NSMenuItem(title: "Load Balancer Strategy", action: nil, keyEquivalent: "")
        let strategyMenu = NSMenu()
        for strategy in LoadBalancerStrategy.allCases {
            let item = NSMenuItem(title: strategy.title, action: #selector(setLoadBalancerStrategy), keyEquivalent: "")
            item.target = self
            item.representedObject = strategy.rawValue
            item.state = self.loadBalancerSettings.strategy == strategy ? .on : .off
            strategyMenu.addItem(item)
        }
        strategyItem.submenu = strategyMenu
        menu.addItem(strategyItem)
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
        Task { await self.refreshAndRender() }
    }

    @objc private func switchAccount(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        self.switchAccount(named: name)
    }

    private func switchAccount(named name: String) {
        guard self.controller.canStartAccountAction else { return }
        self.controller.startSwitching(to: name)
        self.render()
        Task {
            await self.controller.finishSwitching(to: name)
            self.render()
        }
    }

    @objc private func openMainWindow() {
        self.showMainWindow()
    }

    private func showMainWindow() {
        if self.mainWindowController == nil {
            let host = NSHostingController(rootView: self.makeMainWindowContent())
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false)
            window.contentViewController = host
            window.title = AppInfo.displayName
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.isRestorable = false
            window.tabbingMode = .disallowed
            window.sharingType = .readOnly
            window.backgroundColor = .underPageBackgroundColor
            window.minSize = NSSize(width: 760, height: 500)
            window.center()
            self.mainWindowHost = host
            self.mainWindowController = NSWindowController(window: window)
        }
        self.updateWindowContent()
        self.mainWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.mainWindowController?.window?.makeKeyAndOrderFront(nil)
        self.mainWindowController?.window?.orderFrontRegardless()
        self.mainWindowController?.window?.sharingType = .readOnly
    }

    @objc private func openSettingsWindow() {
        self.showSettingsWindow()
    }

    private func showSettingsWindow() {
        if self.settingsWindowController == nil {
            let host = NSHostingController(rootView: self.makeSettingsWindowContent())
            let window = NSWindow(contentViewController: host)
            window.title = "\(AppInfo.displayName) Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.setContentSize(NSSize(width: 520, height: 700))
            window.minSize = NSSize(width: 480, height: 620)
            window.center()
            self.settingsWindowHost = host
            self.settingsWindowController = NSWindowController(window: window)
        }
        self.updateWindowContent()
        self.settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func balanceNow() {
        guard self.controller.canStartAccountAction else { return }
        Task {
            await self.controller.balanceNow(settings: self.loadBalancerSettings)
            self.render()
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
    @objc private func toggleSessionMenuBarIcon() { self.updateSettings { $0.showSessionMenuBarIcon.toggle() } }
    @objc private func toggleSessionBlinkWhenIdle() { self.updateSettings { $0.blinkSessionIconWhenIdle.toggle() } }
    @objc private func toggleSessionBeepWhenIdle() { self.updateSettings { $0.beepWhenIdle.toggle() } }
    @objc private func toggleLoadBalancer() { self.updateLoadBalancerSettings { $0.enabled.toggle() } }
    @objc private func toggleLoadBalancerAutoSwitch() { self.updateLoadBalancerSettings { $0.autoSwitchWhenWasted.toggle() } }
    @objc private func togglePreferEarlierReset() { self.updateLoadBalancerSettings { $0.preferEarlierReset.toggle() } }

    @objc private func setLoadBalancerStrategy(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let strategy = LoadBalancerStrategy(rawValue: raw) else { return }
        self.updateLoadBalancerSettings { $0.strategy = strategy }
    }

    @objc private func checkForUpdates() {
        self.updaterController.checkForUpdates(nil)
    }

    private func updateSettings(_ mutate: (inout DisplaySettings) -> Void) {
        mutate(&self.settings)
        self.settings.save()
        self.render()
    }

    private func updateLoadBalancerSettings(_ mutate: (inout LoadBalancerSettings) -> Void) {
        mutate(&self.loadBalancerSettings)
        do {
            try CodexProfileStore.saveLoadBalancerSettings(self.loadBalancerSettings)
            self.controller.setError(nil)
        } catch {
            self.controller.setError(error.localizedDescription)
        }
        Task {
            await self.controller.autoBalanceIfNeeded(settings: self.loadBalancerSettings)
            self.render()
        }
    }

    private func makeMainWindowContent() -> MainWindowContent {
        MainWindowContent(
            appName: AppInfo.displayName,
            controller: self.controller,
            settings: self.settings,
            loadBalancerSettings: self.loadBalancerSettings,
            onRefresh: { [weak self] in
                Task { @MainActor in await self?.refreshAndRender() }
            },
            onBalance: { [weak self] in
                Task { @MainActor in
                    guard self?.controller.canStartAccountAction == true else { return }
                    await self?.controller.balanceNow(settings: self?.loadBalancerSettings ?? .disabled)
                    self?.render()
                }
            },
            onSwitch: { [weak self] name in self?.switchAccount(named: name) },
            onEdit: { [weak self] account in self?.editAccount(account) },
            onDelete: { [weak self] account in self?.deleteAccount(account) },
            onOpenSettings: { [weak self] in self?.showSettingsWindow() })
    }

    private func makeSettingsWindowContent() -> SettingsWindowContent {
        SettingsWindowContent(
            displaySettings: self.settings,
            loadBalancerSettings: self.loadBalancerSettings,
            onSetStatsSource: { [weak self] value in self?.updateSettings { $0.source = value } },
            onSetWindows: { [weak self] value in self?.updateSettings { $0.windows = value } },
            onSetLabels: { [weak self] value in self?.updateSettings { $0.labels = value } },
            onSetLayout: { [weak self] value in self?.updateSettings { $0.layout = value } },
            onSetShowNumbers: { [weak self] value in self?.updateSettings { $0.showNumbers = value } },
            onSetShowEmails: { [weak self] value in self?.updateSettings { $0.showEmails = value } },
            onSetShowSessionMenuBarIcon: { [weak self] value in self?.updateSettings { $0.showSessionMenuBarIcon = value } },
            onSetBlinkSessionIconWhenIdle: { [weak self] value in self?.updateSettings { $0.blinkSessionIconWhenIdle = value } },
            onSetBeepWhenIdle: { [weak self] value in self?.updateSettings { $0.beepWhenIdle = value } },
            onSetLoadBalancerEnabled: { [weak self] value in self?.updateLoadBalancerSettings { $0.enabled = value } },
            onSetAutoSwitch: { [weak self] value in self?.updateLoadBalancerSettings { $0.autoSwitchWhenWasted = value } },
            onSetPreferEarlierReset: { [weak self] value in self?.updateLoadBalancerSettings { $0.preferEarlierReset = value } },
            onSetStrategy: { [weak self] value in self?.updateLoadBalancerSettings { $0.strategy = value } })
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

final class HostingMenuView<Content: View>: NSHostingView<Content> {
    required init(rootView: Content) {
        super.init(rootView: rootView)
        self.frame = NSRect(x: 0, y: 0, width: 340, height: 330)
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
                        .lineLimit(1)
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

            SessionMenuStatusRow(status: controller.sessionStatus)

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

struct SessionMenuStatusRow: View {
    let status: CodexSessionStatus

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: status.hasActiveSession ? "play.circle.fill" : "pause.circle")
                .foregroundStyle(status.hasActiveSession ? Color.accentColor : Color.secondary)
            Text("Sessions")
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(status.count)")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
            Text(status.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}

struct MainWindowContent: View {
    let appName: String
    @ObservedObject var controller: UsageController
    let settings: DisplaySettings
    let loadBalancerSettings: LoadBalancerSettings
    let onRefresh: () -> Void
    let onBalance: () -> Void
    let onSwitch: (String) -> Void
    let onEdit: (CodexAccountUsage) -> Void
    let onDelete: (CodexAccountUsage) -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            MainToolbar(
                isRefreshing: controller.isRefreshing,
                updatedAt: controller.updatedAt,
                activeAccountName: self.activeAccountName,
                hasActiveAccount: self.hasActiveAccount,
                loadBalancerEnabled: loadBalancerSettings.enabled,
                loadBalancerStrategyTitle: loadBalancerSettings.strategy.title,
                canBalance: loadBalancerSettings.enabled && !controller.accounts.isEmpty && controller.canStartAccountAction,
                onRefresh: onRefresh,
                onBalance: onBalance,
                onOpenSettings: onOpenSettings)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let error = controller.lastError {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Dashboard Widgets
                    VStack(spacing: 16) {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 250), spacing: 16, alignment: .top)],
                            alignment: .leading,
                            spacing: 16)
                        {
                            SummaryPanel(title: "Sessions", value: "\(controller.sessionStatus.count)", detail: controller.sessionStatus.detail)
                            if let combined = UsageMath.combined(controller.accounts.map(\.snapshot)) {
                                SummaryUsagePanel(snapshot: combined)
                            }
                            if let resetCredits = controller.accounts.first(where: \.active)?.resetCredits {
                                SummaryResetCreditsPanel(snapshot: resetCredits)
                            }
                        }

                        HStack(alignment: .top, spacing: 16) {
                            WeeklyUsageWidget(accounts: controller.accounts, days: controller.activityDays)
                            ActivityGraphWidget(days: controller.activityDays)
                        }
                    }

                    if controller.accounts.isEmpty {
                        EmptyAccountsPanel()
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Accounts")
                                .font(.headline)
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(minimum: 200, maximum: .infinity), spacing: 16, alignment: .top), count: 3),
                                alignment: .leading,
                                spacing: 16)
                            {
                                ForEach(controller.accounts) { account in
                                    MainAccountCard(
                                        account: account,
                                        settings: settings,
                                        switchingAccountName: controller.switchingAccountName,
                                        actionsDisabled: !controller.canStartAccountAction,
                                        onSwitch: onSwitch,
                                        onEdit: onEdit,
                                        onDelete: onDelete)
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }
            .background(Color(nsColor: .underPageBackgroundColor).opacity(0.5))
        }
        .frame(minWidth: 800, minHeight: 600)
    }

    private var activeAccountName: String {
        controller.accounts.first(where: \.active)?.displayName ?? "No active account"
    }

    private var hasActiveAccount: Bool {
        controller.accounts.contains(where: \.active)
    }
}

struct MainToolbar: View {
    let isRefreshing: Bool
    let updatedAt: Date
    let activeAccountName: String
    let hasActiveAccount: Bool
    let loadBalancerEnabled: Bool
    let loadBalancerStrategyTitle: String
    let canBalance: Bool
    let onRefresh: () -> Void
    let onBalance: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ToolbarStatusChip(
                isRefreshing: isRefreshing,
                updatedAt: updatedAt)

            ToolbarDivider()

            ToolbarAccountChip(
                name: activeAccountName,
                isActive: hasActiveAccount)

            ToolbarLoadBalancerChip(
                enabled: loadBalancerEnabled,
                strategyTitle: loadBalancerStrategyTitle)

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Button(action: onRefresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh usage data")
                .disabled(isRefreshing)
                .focusable(false)

                Button(action: onBalance) {
                    Label("Balance", systemImage: "arrow.triangle.2.circlepath")
                }
                .help("Switch to the optimal account now")
                .disabled(!canBalance)
                .focusable(false)
            }
            .buttonStyle(ToolbarActionButtonStyle())

            ToolbarDivider()

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(ToolbarIconButtonStyle())
            .help("Open settings")
            .focusable(false)
        }
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .padding(.vertical, 7)
        .frame(minHeight: 38)
        .background(Color(nsColor: .underPageBackgroundColor))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 1)
        }
    }
}

private struct ToolbarStatusChip: View {
    let isRefreshing: Bool
    let updatedAt: Date

    var body: some View {
        HStack(spacing: 6) {
            if isRefreshing {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.6)
                    .frame(width: 10, height: 10)
                Text("Refreshing")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("Updated \(UsageText.time(updatedAt))")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .fixedSize()
    }
}

private struct ToolbarAccountChip: View {
    let name: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
            Text(name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.05), in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 1))
        .frame(maxWidth: 220)
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct ToolbarLoadBalancerChip: View {
    let enabled: Bool
    let strategyTitle: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "scale.3d")
                .font(.system(size: 11, weight: .medium))
            Text(enabled ? strategyTitle : "Off")
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(enabled ? Color.accentColor : Color.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            (enabled ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.04)),
            in: Capsule())
        .overlay(
            Capsule().stroke(
                enabled ? Color.accentColor.opacity(0.25) : Color.primary.opacity(0.08),
                lineWidth: 1))
        .help(enabled ? "Load balancer: \(strategyTitle)" : "Load balancer is off")
        .fixedSize()
    }
}

private struct ToolbarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 16)
            .padding(.horizontal, 2)
    }
}

private struct ToolbarActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.65))
            .labelStyle(.titleAndIcon)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed ? Color.primary.opacity(0.12) : Color.primary.opacity(0.055)))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.primary.opacity(isEnabled ? 0.10 : 0.06), lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.52)
    }
}

private struct ToolbarIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.secondary)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed ? Color.primary.opacity(0.10) : Color.clear))
    }
}

struct SummaryPanel: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 92, alignment: .topLeading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
    }
}

struct SummaryUsagePanel: View {
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Combined Usage")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            UsageBars(snapshot: snapshot, dimmed: false, combined: true, settings: .popup, forceInline: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 92, alignment: .topLeading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
    }
}

struct SummaryResetCreditsPanel: View {
    let snapshot: CodexResetCreditsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Codex Resets")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(snapshot.availableCount)")
                    .font(.title2.weight(.semibold))
                Text(snapshot.availableCount == 1 ? "available reset" : "available resets")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                if snapshot.expirationLines.isEmpty {
                    Text(snapshot.summaryDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    ForEach(Array(snapshot.expirationLines.prefix(3).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if snapshot.expirationLines.count > 3 {
                        Text("+ \(snapshot.expirationLines.count - 3) more")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 92, alignment: .topLeading)
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
        .help(snapshot.helpText)
    }
}

struct EmptyAccountsPanel: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No stored Codex profiles")
                .font(.headline)
            Text("Use the menu bar item to add the currently active Codex account.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
    }
}

struct MainAccountCard: View {
    let account: CodexAccountUsage
    let settings: DisplaySettings
    let switchingAccountName: String?
    let actionsDisabled: Bool
    let onSwitch: (String) -> Void
    let onEdit: (CodexAccountUsage) -> Void
    let onDelete: (CodexAccountUsage) -> Void
    @State private var isHovered = false

    private var canSelect: Bool {
        account.isLoadBalancerAvailable
    }

    private var isSwitching: Bool {
        self.switchingAccountName == self.account.name
    }

    var body: some View {
        Button(action: {
            if canSelect, !account.active, !actionsDisabled {
                onSwitch(account.name)
            }
        }) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    if isSwitching {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.65)
                            .frame(width: 12, height: 12)
                    } else {
                        Circle()
                            .fill(account.active ? Color.green : Color.secondary.opacity(0.3))
                            .frame(width: 10, height: 10)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.displayName)
                            .font(.headline)
                            .foregroundStyle(account.active ? Color.primary : Color.primary.opacity(0.8))
                            .lineLimit(1)
                        if settings.showEmails, !account.emailOrPlan.isEmpty {
                            Text(account.emailOrPlan)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)

                    Menu {
                        Button("Edit Name/Label") { onEdit(account) }
                            .disabled(actionsDisabled)
                        Button("Delete Profile", role: .destructive) { onDelete(account) }
                            .disabled(actionsDisabled)
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 24)
                }

                if let snapshot = account.snapshot {
                    VStack(alignment: .leading, spacing: 12) {
                        MainUsageMetric(title: "Session", window: snapshot.primary, dimmed: account.isWasted)
                        MainUsageMetric(title: "Week", window: snapshot.secondary, dimmed: account.isWasted)
                    }
                } else {
                    Text(account.error ?? "No usage")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxHeight: .infinity, alignment: .top)
                }

                Spacer(minLength: 0)

                HStack {
                    Text(isSwitching ? "switching" : account.statusText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(isSwitching || account.isWasted ? .secondary : .primary)
                    Spacer()
                    if let resetCredits = account.resetCredits {
                        Text("R \(resetCredits.availableCount)")
                            .font(.system(.caption, design: .monospaced).weight(.semibold))
                            .foregroundStyle(resetCredits.availableCount > 0 ? Color.accentColor : Color.secondary)
                            .help(resetCredits.helpText)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
            .background(account.active && canSelect ? Color.accentColor.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(account.active && canSelect ? Color.accentColor.opacity(0.5) : Color.secondary.opacity(0.15), lineWidth: account.active && canSelect ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = canSelect && !actionsDisabled && hovering
        }
        .scaleEffect(isHovered && !account.active && canSelect && !actionsDisabled ? 1.01 : 1.0)
        .opacity(canSelect || isSwitching ? 1 : 0.58)
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

struct MainUsageMetric: View {
    let title: String
    let window: RateWindow?
    let dimmed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if let window {
                    Text(UsageText.remaining(window))
                        .font(.system(.caption, design: .monospaced).weight(.medium))
                    Text(window.resetDescription ?? "reset unknown")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("No data")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let window {
                ProgressView(value: max(0, min(100, window.remainingPercent)), total: 100)
                    .tint(dimmed ? .gray : UsageColor.color(for: window.remainingPercent))
            }
        }
    }
}

struct ActivityGraphWidget: View {
    let days: [UsageHistoryDay]

    private var visibleDays: [UsageHistoryDay] {
        if days.count >= 112 {
            return Array(days.suffix(112))
        }
        return UsageHistoryAnalytics.days(samples: [], accounts: [], count: 112)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Activity")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                ForEach(0..<16, id: \.self) { week in
                    VStack(spacing: 4) {
                        ForEach(0..<7, id: \.self) { day in
                            let historyDay = visibleDays[week * 7 + day]
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color(for: level(for: historyDay.total)))
                                .frame(width: 12, height: 12)
                                .help(historyDay.helpText)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
    }

    func level(for total: Double) -> Int {
        switch total {
        case ...0:
            return 0
        case 0..<3:
            return 1
        case 3..<10:
            return 2
        default:
            return 3
        }
    }

    func color(for level: Int) -> Color {
        switch level {
        case 0: return Color.secondary.opacity(0.15)
        case 1: return Color.green.opacity(0.4)
        case 2: return Color.green.opacity(0.7)
        case 3: return Color.green
        default: return Color.secondary.opacity(0.15)
        }
    }
}

struct WeeklyUsageWidget: View {
    let accounts: [CodexAccountUsage]
    let days: [UsageHistoryDay]

    private var visibleDays: [UsageHistoryDay] {
        if days.isEmpty {
            return UsageHistoryAnalytics.days(samples: [], accounts: [], count: 7)
        }
        return Array(days.suffix(7))
    }

    private var maxTotal: Double {
        max(1, visibleDays.map(\.total).max() ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last 7 Days")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(alignment: .bottom, spacing: 12) {
                ForEach(visibleDays) { day in
                    VStack(spacing: 6) {
                        if day.segments.isEmpty {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.secondary.opacity(0.15))
                                .frame(width: 18, height: 92)
                        } else {
                            VStack(spacing: 1) {
                                Spacer(minLength: 0)
                                ForEach(day.segments) { segment in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(segment.color)
                                        .frame(width: 18, height: height(for: segment.amount, total: day.total))
                                }
                            }
                            .frame(width: 18, height: 92)
                        }

                        Text(day.shortLabel)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .help(day.helpText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            HStack(spacing: 10) {
                ForEach(accounts.prefix(4)) { account in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(AccountColor.color(for: account.name))
                            .frame(width: 6, height: 6)
                        Text(account.displayName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
    }

    func height(for amount: Double, total: Double) -> CGFloat {
        let totalHeight = max(5, 92 * CGFloat(total / maxTotal))
        return max(3, totalHeight * CGFloat(amount / max(total, 0.1)))
    }
}

enum AccountColor {
    private static let palette: [Color] = [
        .blue,
        .green,
        .orange,
        .pink,
        .teal,
        .indigo,
        .red,
        .cyan,
        .yellow,
    ]

    static func color(for name: String) -> Color {
        let value = name.unicodeScalars.reduce(0) { partial, scalar in
            (partial &* 31 &+ Int(scalar.value)) & 0x7fffffff
        }
        return palette[value % palette.count]
    }
}

struct UsageHistoryDay: Identifiable {
    let date: Date
    let segments: [UsageHistorySegment]
    let total: Double

    var id: Date { Calendar.current.startOfDay(for: date) }

    var shortLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "E"
        return formatter.string(from: date).prefix(1).uppercased()
    }

    var helpText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        if total <= 0 {
            return "\(formatter.string(from: date)): no recorded usage"
        }
        return "\(formatter.string(from: date)): \(Int(total.rounded())) usage points"
    }
}

struct UsageHistorySegment: Identifiable {
    let accountName: String
    let displayName: String
    let amount: Double
    let color: Color

    var id: String { accountName }
}

enum UsageHistoryAnalytics {
    static func days(
        samples: [UsageHistorySample],
        accounts: [CodexAccountUsage],
        count: Int,
        calendar: Calendar = .current,
        now: Date = Date())
        -> [UsageHistoryDay]
    {
        let startToday = calendar.startOfDay(for: now)
        let sorted = samples.sorted { $0.timestamp < $1.timestamp }
        let accountNames = accounts.map(\.name)

        return (0..<count).map { offset in
            let date = calendar.date(byAdding: .day, value: -(count - 1 - offset), to: startToday) ?? startToday
            let nextDate = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            let segments = accountNames.compactMap { name -> UsageHistorySegment? in
                let accountSamples = sorted.filter { $0.accountName == name }
                guard let last = accountSamples.last(where: { $0.timestamp < nextDate }) else { return nil }
                let previous = accountSamples.last { $0.timestamp < date }
                let firstToday = accountSamples.first { $0.timestamp >= date && $0.timestamp < nextDate }
                guard firstToday != nil else { return nil }

                let rawAmount: Double
                if let previous {
                    rawAmount = last.usedPercent >= previous.usedPercent
                        ? last.usedPercent - previous.usedPercent
                        : last.usedPercent
                } else if calendar.isDate(date, inSameDayAs: startToday) {
                    rawAmount = last.usedPercent
                } else if let firstToday {
                    rawAmount = max(0, last.usedPercent - firstToday.usedPercent)
                } else {
                    rawAmount = 0
                }

                let amount = min(100, max(0, rawAmount))
                guard amount > 0 else { return nil }
                let displayName = accounts.first(where: { $0.name == name })?.displayName ?? name
                return UsageHistorySegment(
                    accountName: name,
                    displayName: displayName,
                    amount: amount,
                    color: AccountColor.color(for: name))
            }
            let total = segments.map(\.amount).reduce(0, +)
            return UsageHistoryDay(date: date, segments: segments, total: total)
        }
    }
}

private struct CachedActivityHistory: Codable {
    var version: Int
    var days: [CachedActivityDay]

    static let currentVersion = 2
    static let empty = CachedActivityHistory(version: currentVersion, days: [])
}

private struct CachedActivityDay: Codable {
    let dateKey: String
    let segments: [CachedActivitySegment]

    enum CodingKeys: String, CodingKey {
        case dateKey = "date_key"
        case segments
    }
}

private struct CachedActivitySegment: Codable {
    let accountName: String
    let amount: Double

    enum CodingKeys: String, CodingKey {
        case accountName = "account_name"
        case amount
    }
}

enum CodexActivityStore {
    private static let retentionDays = 120

    static func days(
        accounts: [CodexAccountUsage],
        count: Int = 112,
        calendar: Calendar = .current,
        now: Date = Date())
        -> [UsageHistoryDay]
    {
        let startToday = calendar.startOfDay(for: now)
        let requestedDates = (0..<count).compactMap {
            calendar.date(byAdding: .day, value: -(count - 1 - $0), to: startToday)
        }
        let todayKey = self.key(for: startToday)
        var cache = self.load()
        var cachedByKey = Dictionary(uniqueKeysWithValues: cache.days.map { ($0.dateKey, $0) })
        let requestedKeys = Set(requestedDates.map(self.key))
        var keysToScan = Set<String>()

        for date in requestedDates {
            let key = self.key(for: date)
            if key == todayKey || cachedByKey[key] == nil {
                keysToScan.insert(key)
            }
        }

        if !keysToScan.isEmpty {
            let scanned = self.scanLocalActivity(keys: keysToScan, accounts: accounts, calendar: calendar)
            for key in keysToScan {
                cachedByKey[key] = self.cachedDay(dateKey: key, counts: scanned[key] ?? [:])
            }
            let cutoff = calendar.date(byAdding: .day, value: -retentionDays, to: startToday) ?? startToday
            cache.days = cachedByKey.values
                .filter { requestedKeys.contains($0.dateKey) || (self.date(from: $0.dateKey) ?? .distantPast) >= cutoff }
                .sorted { $0.dateKey < $1.dateKey }
            self.save(cache)
        }

        return requestedDates.map { date in
            let key = self.key(for: date)
            return self.day(from: cachedByKey[key] ?? self.cachedDay(dateKey: key, counts: [:]), date: date, accounts: accounts)
        }
    }

    private static func scanLocalActivity(
        keys: Set<String>,
        accounts: [CodexAccountUsage],
        calendar: Calendar)
        -> [String: [String: Double]]
    {
        var counts: [String: [String: Double]] = [:]
        let historyURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/history.jsonl")
        if let contents = try? String(contentsOf: historyURL, encoding: .utf8) {
            for line in contents.split(whereSeparator: \.isNewline) {
                guard let data = String(line).data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let rawTimestamp = object["ts"] else { continue }
                let timestamp: TimeInterval
                if let value = rawTimestamp as? Double {
                    timestamp = value
                } else if let value = rawTimestamp as? Int {
                    timestamp = TimeInterval(value)
                } else {
                    continue
                }

                let date = Date(timeIntervalSince1970: timestamp)
                let key = self.key(for: calendar.startOfDay(for: date))
                guard keys.contains(key) else { continue }
                let accountName = self.accountName(for: date, accounts: accounts)
                counts[key, default: [:]][accountName, default: 0] += 1
            }
        }

        let sessionIndexURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/session_index.jsonl")
        guard let sessionIndex = try? String(contentsOf: sessionIndexURL, encoding: .utf8) else {
            return counts
        }

        var seenSessions = Set<String>()
        for line in sessionIndex.split(whereSeparator: \.isNewline) {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = object["id"] as? String,
                  let updatedAt = object["updated_at"] as? String,
                  let date = self.parseDate(updatedAt) else { continue }
            let key = self.key(for: calendar.startOfDay(for: date))
            guard keys.contains(key), seenSessions.insert("\(key):\(id)").inserted else { continue }
            let accountName = self.accountName(for: date, accounts: accounts)
            counts[key, default: [:]][accountName, default: 0] += 1
        }

        return counts
    }

    private static func accountName(for date: Date, accounts: [CodexAccountUsage]) -> String {
        let timestamp = date.timeIntervalSince1970
        let selected = accounts
            .compactMap { account -> (CodexAccountUsage, Double)? in
                guard let selectedAt = account.lastSelectedAt, selectedAt <= timestamp else { return nil }
                return (account, selectedAt)
            }
            .max { $0.1 < $1.1 }?
            .0
        return selected?.name
            ?? accounts.first(where: \.active)?.name
            ?? accounts.first?.name
            ?? "codex"
    }

    private static func cachedDay(dateKey: String, counts: [String: Double]) -> CachedActivityDay {
        CachedActivityDay(
            dateKey: dateKey,
            segments: counts
                .filter { $0.value > 0 }
                .map { CachedActivitySegment(accountName: $0.key, amount: $0.value) }
                .sorted { $0.accountName < $1.accountName })
    }

    private static func day(from cached: CachedActivityDay, date: Date, accounts: [CodexAccountUsage]) -> UsageHistoryDay {
        let segments = cached.segments.map { segment in
            UsageHistorySegment(
                accountName: segment.accountName,
                displayName: accounts.first(where: { $0.name == segment.accountName })?.displayName ?? segment.accountName,
                amount: segment.amount,
                color: AccountColor.color(for: segment.accountName))
        }
        return UsageHistoryDay(date: date, segments: segments, total: segments.map(\.amount).reduce(0, +))
    }

    private static func load() -> CachedActivityHistory {
        guard let data = try? Data(contentsOf: CodexProfileStore.activityHistoryURL) else { return .empty }
        guard let cache = try? JSONDecoder().decode(CachedActivityHistory.self, from: data),
              cache.version == CachedActivityHistory.currentVersion else { return .empty }
        return cache
    }

    private static func save(_ cache: CachedActivityHistory) {
        do {
            try FileManager.default.createDirectory(
                at: CodexProfileStore.activityHistoryURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            let data = try JSONEncoder.pretty.encode(cache)
            try data.write(to: CodexProfileStore.activityHistoryURL, options: .atomic)
        } catch {
            NSLog("CodexMaxx failed to save activity history: \(error.localizedDescription)")
        }
    }

    private static func key(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private static func date(from key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

struct UsageWindowDetail: View {
    let title: String
    let window: RateWindow?

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            if let window {
                Text("\(Int(window.remainingPercent.rounded()))% remaining")
                Spacer()
                Text(window.resetDescription ?? "reset unknown")
                    .foregroundStyle(.secondary)
            } else {
                Text("No data")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .font(.caption)
    }
}

struct SettingsWindowContent: View {
    @State private var source: StatsSource
    @State private var windows: WindowSelection
    @State private var labels: LabelStyle
    @State private var layout: BarLayout
    @State private var showNumbers: Bool
    @State private var showEmails: Bool
    @State private var showSessionMenuBarIcon: Bool
    @State private var blinkSessionIconWhenIdle: Bool
    @State private var beepWhenIdle: Bool
    @State private var loadBalancerEnabled: Bool
    @State private var autoSwitch: Bool
    @State private var preferEarlierReset: Bool
    @State private var strategy: LoadBalancerStrategy

    let onSetStatsSource: (StatsSource) -> Void
    let onSetWindows: (WindowSelection) -> Void
    let onSetLabels: (LabelStyle) -> Void
    let onSetLayout: (BarLayout) -> Void
    let onSetShowNumbers: (Bool) -> Void
    let onSetShowEmails: (Bool) -> Void
    let onSetShowSessionMenuBarIcon: (Bool) -> Void
    let onSetBlinkSessionIconWhenIdle: (Bool) -> Void
    let onSetBeepWhenIdle: (Bool) -> Void
    let onSetLoadBalancerEnabled: (Bool) -> Void
    let onSetAutoSwitch: (Bool) -> Void
    let onSetPreferEarlierReset: (Bool) -> Void
    let onSetStrategy: (LoadBalancerStrategy) -> Void

    init(
        displaySettings: DisplaySettings,
        loadBalancerSettings: LoadBalancerSettings,
        onSetStatsSource: @escaping (StatsSource) -> Void,
        onSetWindows: @escaping (WindowSelection) -> Void,
        onSetLabels: @escaping (LabelStyle) -> Void,
        onSetLayout: @escaping (BarLayout) -> Void,
        onSetShowNumbers: @escaping (Bool) -> Void,
        onSetShowEmails: @escaping (Bool) -> Void,
        onSetShowSessionMenuBarIcon: @escaping (Bool) -> Void,
        onSetBlinkSessionIconWhenIdle: @escaping (Bool) -> Void,
        onSetBeepWhenIdle: @escaping (Bool) -> Void,
        onSetLoadBalancerEnabled: @escaping (Bool) -> Void,
        onSetAutoSwitch: @escaping (Bool) -> Void,
        onSetPreferEarlierReset: @escaping (Bool) -> Void,
        onSetStrategy: @escaping (LoadBalancerStrategy) -> Void)
    {
        self._source = State(initialValue: displaySettings.source)
        self._windows = State(initialValue: displaySettings.windows)
        self._labels = State(initialValue: displaySettings.labels)
        self._layout = State(initialValue: displaySettings.layout)
        self._showNumbers = State(initialValue: displaySettings.showNumbers)
        self._showEmails = State(initialValue: displaySettings.showEmails)
        self._showSessionMenuBarIcon = State(initialValue: displaySettings.showSessionMenuBarIcon)
        self._blinkSessionIconWhenIdle = State(initialValue: displaySettings.blinkSessionIconWhenIdle)
        self._beepWhenIdle = State(initialValue: displaySettings.beepWhenIdle)
        self._loadBalancerEnabled = State(initialValue: loadBalancerSettings.enabled)
        self._autoSwitch = State(initialValue: loadBalancerSettings.autoSwitchWhenWasted)
        self._preferEarlierReset = State(initialValue: loadBalancerSettings.preferEarlierReset)
        self._strategy = State(initialValue: loadBalancerSettings.strategy)
        self.onSetStatsSource = onSetStatsSource
        self.onSetWindows = onSetWindows
        self.onSetLabels = onSetLabels
        self.onSetLayout = onSetLayout
        self.onSetShowNumbers = onSetShowNumbers
        self.onSetShowEmails = onSetShowEmails
        self.onSetShowSessionMenuBarIcon = onSetShowSessionMenuBarIcon
        self.onSetBlinkSessionIconWhenIdle = onSetBlinkSessionIconWhenIdle
        self.onSetBeepWhenIdle = onSetBeepWhenIdle
        self.onSetLoadBalancerEnabled = onSetLoadBalancerEnabled
        self.onSetAutoSwitch = onSetAutoSwitch
        self.onSetPreferEarlierReset = onSetPreferEarlierReset
        self.onSetStrategy = onSetStrategy
    }

    var body: some View {
        Form {
            Section("Menu Bar") {
                Picker("Stats", selection: $source) {
                    ForEach(StatsSource.allCases, id: \.rawValue) { value in
                        Text(value.title).tag(value)
                    }
                }
                Picker("Windows", selection: $windows) {
                    ForEach(WindowSelection.allCases, id: \.rawValue) { value in
                        Text(value.title).tag(value)
                    }
                }
                Picker("Labels", selection: $labels) {
                    ForEach(LabelStyle.allCases, id: \.rawValue) { value in
                        Text(value.title).tag(value)
                    }
                }
                Picker("Layout", selection: $layout) {
                    ForEach(BarLayout.allCases, id: \.rawValue) { value in
                        Text(value.title).tag(value)
                    }
                }
                Toggle("Show numbers", isOn: $showNumbers)
                Toggle("Show emails", isOn: $showEmails)
                Toggle("Show session status in menu bar", isOn: $showSessionMenuBarIcon)
                Toggle("Blink when no active session", isOn: $blinkSessionIconWhenIdle)
                Toggle("Beep when no active session", isOn: $beepWhenIdle)
            }

            Section("Load Balancer") {
                Toggle("Enabled", isOn: $loadBalancerEnabled)

                Toggle(isOn: $autoSwitch) {
                    SettingsHelpLabel(
                        title: "Auto switch when wasted",
                        help: "When the active Codex account has no useful capacity left, CodexMaxx switches to the best available account during refresh.")
                }

                Toggle(isOn: $preferEarlierReset) {
                    SettingsHelpLabel(
                        title: "Prefer earlier weekly reset",
                        help: "When two accounts are similarly good, prefer the one whose weekly limit resets sooner.")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Strategy")
                        .font(.subheadline.weight(.medium))

                    VStack(spacing: 8) {
                        ForEach(LoadBalancerStrategy.allCases, id: \.rawValue) { value in
                            StrategyRadioRow(
                                strategy: value,
                                selected: strategy == value,
                                onSelect: { strategy = value })
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(minWidth: 480, minHeight: 660)
        .onChange(of: source) { _, value in onSetStatsSource(value) }
        .onChange(of: windows) { _, value in onSetWindows(value) }
        .onChange(of: labels) { _, value in onSetLabels(value) }
        .onChange(of: layout) { _, value in onSetLayout(value) }
        .onChange(of: showNumbers) { _, value in onSetShowNumbers(value) }
        .onChange(of: showEmails) { _, value in onSetShowEmails(value) }
        .onChange(of: showSessionMenuBarIcon) { _, value in onSetShowSessionMenuBarIcon(value) }
        .onChange(of: blinkSessionIconWhenIdle) { _, value in onSetBlinkSessionIconWhenIdle(value) }
        .onChange(of: beepWhenIdle) { _, value in onSetBeepWhenIdle(value) }
        .onChange(of: loadBalancerEnabled) { _, value in onSetLoadBalancerEnabled(value) }
        .onChange(of: autoSwitch) { _, value in onSetAutoSwitch(value) }
        .onChange(of: preferEarlierReset) { _, value in onSetPreferEarlierReset(value) }
        .onChange(of: strategy) { _, value in onSetStrategy(value) }
    }
}

struct SettingsHelpLabel: View {
    let title: String
    let help: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .help(help)
                .accessibilityLabel("\(title) info")
        }
        .help(help)
    }
}

struct StrategyRadioRow: View {
    let strategy: LoadBalancerStrategy
    let selected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(selected ? Color.accentColor : Color(nsColor: .secondaryLabelColor))
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(strategy.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(strategy.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .background(
                selected ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Color.accentColor.opacity(0.45) : Color.secondary.opacity(0.18), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
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
        Button(action: {
            if !actionsDisabled, !account.active {
                onSwitch(account.name)
            }
        }) {
            VStack(alignment: .leading, spacing: 5) {
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

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(isSwitching ? "switching" : account.statusText)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(isSwitching || wasted ? .secondary : .primary)
                        if let resetCredits = account.resetCredits {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 9, weight: .semibold))
                                Text(resetCredits.menuRowSummary)
                            }
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .help(resetCredits.helpText)
                        }
                    }
                }

                if let snapshot = account.snapshot {
                    UsageBars(snapshot: snapshot, dimmed: wasted, combined: false, settings: .popup, forceInline: true)
                    if let resets = UsageText.resetSummary(snapshot) {
                        Text(resets)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let pace = UsageText.weeklyPaceSummary(snapshot) {
                        Text(pace)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(account.error ?? "No usage")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .buttonStyle(.plain)
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

struct UsageHistorySample: Codable, Sendable {
    let accountName: String
    let timestamp: Date
    let usedPercent: Double

    enum CodingKeys: String, CodingKey {
        case accountName = "account_name"
        case timestamp
        case usedPercent = "used_percent"
    }
}

enum UsageHistoryStore {
    private static let retentionDays = 120

    static func load() -> [UsageHistorySample] {
        guard let data = try? Data(contentsOf: CodexProfileStore.usageHistoryURL) else { return [] }
        return (try? JSONDecoder().decode([UsageHistorySample].self, from: data)) ?? []
    }

    static func record(accounts: [CodexAccountUsage], now: Date = Date()) -> [UsageHistorySample] {
        var samples = self.load()
        for account in accounts {
            guard let usedPercent = account.snapshot?.secondary?.usedPercent else { continue }
            samples.append(UsageHistorySample(
                accountName: account.name,
                timestamp: now,
                usedPercent: max(0, min(100, usedPercent))))
        }

        let cutoff = Calendar.current.date(byAdding: .day, value: -retentionDays, to: now) ?? now
        samples = samples.filter { $0.timestamp >= cutoff }
        self.save(samples)
        return samples
    }

    private static func save(_ samples: [UsageHistorySample]) {
        do {
            try FileManager.default.createDirectory(
                at: CodexProfileStore.usageHistoryURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(samples)
            try data.write(to: CodexProfileStore.usageHistoryURL, options: .atomic)
        } catch {
            NSLog("CodexMaxx failed to save usage history: \(error.localizedDescription)")
        }
    }
}

@MainActor
final class UsageController: ObservableObject {
    @Published private(set) var accounts: [CodexAccountUsage] = []
    @Published private(set) var usageHistory: [UsageHistorySample] = UsageHistoryStore.load()
    @Published private(set) var activityDays: [UsageHistoryDay] = []
    @Published private(set) var sessionStatus = CodexSessionStatus(count: 0, sampledAt: Date())
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
            let loadedAccounts = await withTaskGroup(of: CodexAccountUsage.self) { group in
                for profile in profiles {
                    group.addTask {
                        await CodexUsageLoader.load(profile: profile)
                    }
                }
                var rows: [CodexAccountUsage] = []
                for await row in group {
                    rows.append(row)
                }
                return rows
            }
            let accounts = self.sortAccounts(loadedAccounts)
            self.accounts = accounts
            self.usageHistory = UsageHistoryStore.record(accounts: accounts)
            self.activityDays = CodexActivityStore.days(accounts: accounts)
            self.updatedAt = Date()
            self.lastError = nil
            if self.switchingAccountName == nil {
                self.statusMessage = nil
            }
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    func refreshSessionStatus() async {
        let status = await Task.detached {
            CodexSessionMonitor.load()
        }.value
        self.sessionStatus = status
    }

    func switchToAccount(named name: String) async {
        guard self.canStartAccountAction else { return }
        self.startSwitching(to: name)
        await self.finishSwitching(to: name)
    }

    func startSwitching(to name: String) {
        self.switchingAccountName = name
        self.isRefreshing = true
        self.lastError = nil
        self.statusMessage = "Switching to \(self.displayName(for: name))..."
        self.markActiveAccount(named: name)
    }

    func finishSwitching(to name: String) async {
        defer {
            self.switchingAccountName = nil
            self.isRefreshing = false
        }
        do {
            try CodexProfileStore.switchToProfile(named: name)
            await self.refresh()
            self.statusMessage = "Switched to \(self.displayName(for: name))"
        } catch {
            await self.refresh()
            self.lastError = error.localizedDescription
            self.statusMessage = nil
        }
    }

    func balanceNow(settings: LoadBalancerSettings) async {
        do {
            guard let selected = CodexLoadBalancer.selectAccount(from: self.accounts, settings: settings) else {
                throw NSError(domain: "CodexMaxx", code: 20, userInfo: [
                    NSLocalizedDescriptionKey: "No available Codex account to balance to",
                ])
            }
            guard selected.name != self.accounts.first(where: \.active)?.name else {
                self.lastError = nil
                return
            }
            try CodexProfileStore.switchToProfile(named: selected.name)
            await self.refresh()
        } catch {
            self.lastError = error.localizedDescription
        }
    }

    func autoBalanceIfNeeded(settings: LoadBalancerSettings) async {
        guard settings.enabled, settings.autoSwitchWhenWasted else { return }
        guard self.accounts.first(where: \.active)?.isLoadBalancerAvailable != true else { return }
        guard let selected = CodexLoadBalancer.selectAccount(from: self.accounts, settings: settings) else { return }
        guard selected.name != self.accounts.first(where: \.active)?.name else { return }
        do {
            try CodexProfileStore.switchToProfile(named: selected.name)
            await self.refresh()
        } catch {
            self.lastError = error.localizedDescription
        }
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

    func setError(_ message: String?) {
        self.lastError = message
    }

    private func markActiveAccount(named name: String) {
        self.accounts = self.sortAccounts(self.accounts.map { $0.withActive($0.name == name) })
    }

    private func displayName(for name: String) -> String {
        self.accounts.first(where: { $0.name == name })?.displayName ?? name
    }

    private func sortAccounts(_ accounts: [CodexAccountUsage]) -> [CodexAccountUsage] {
        accounts.sorted { lhs, rhs in
            if lhs.active != rhs.active { return lhs.active && !rhs.active }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

struct CodexProfile: Sendable {
    let name: String
    let label: String?
    let homeURL: URL
    let active: Bool
    let lastSelectedAt: Double?
}

struct CodexAccountUsage: Identifiable, Sendable {
    var id: String { self.name }
    let name: String
    let label: String?
    let active: Bool
    let lastSelectedAt: Double?
    let snapshot: UsageSnapshot?
    let resetCredits: CodexResetCreditsSnapshot?
    let resetCreditsError: String?
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

    var isLoadBalancerAvailable: Bool {
        guard self.snapshot != nil else { return false }
        return !self.isWasted
    }

    var statusText: String {
        guard let snapshot else { return "offline" }
        if self.isWasted {
            return UsageText.comeback(snapshot) ?? "wasted"
        }
        return UsageText.summary(snapshot)
    }

    func withActive(_ active: Bool) -> CodexAccountUsage {
        CodexAccountUsage(
            name: self.name,
            label: self.label,
            active: active,
            lastSelectedAt: self.lastSelectedAt,
            snapshot: self.snapshot,
            resetCredits: self.resetCredits,
            resetCreditsError: self.resetCreditsError,
            error: self.error)
    }
}

enum CodexLoadBalancer {
    private static let secondsPerDay = 86_400.0
    private static let unknownResetBucketDays = 10_000
    private static let secondaryCapacityCredits: [String: Double] = [
        "free": 1_134.0,
        "plus": 7_560.0,
        "business": 7_560.0,
        "team": 7_560.0,
        "edu": 7_560.0,
        "pro": 50_400.0,
        "enterprise": 50_400.0,
    ]
    private static let planAliases = [
        "education": "edu",
        "k12": "edu",
        "guest": "free",
        "go": "free",
        "free_workspace": "free",
        "quorum": "free",
        "unknown": "free",
    ]

    static func selectAccount(
        from accounts: [CodexAccountUsage],
        settings: LoadBalancerSettings,
        now: Date = Date())
        -> CodexAccountUsage?
    {
        var candidates = accounts.filter(\.isLoadBalancerAvailable)
        guard !candidates.isEmpty else { return nil }

        if settings.preferEarlierReset {
            let earliest = candidates.map { self.resetBucketDays($0, now: now) }.min() ?? self.unknownResetBucketDays
            candidates = candidates.filter { self.resetBucketDays($0, now: now) == earliest }
        }

        switch settings.strategy {
        case .capacityWeighted:
            return self.selectCapacityWeighted(candidates)
        case .roundRobin:
            return candidates.min(by: self.roundRobinComesBefore)
        case .usageWeighted:
            return candidates.min(by: self.usageComesBefore)
        }
    }

    private static func selectCapacityWeighted(_ accounts: [CodexAccountUsage]) -> CodexAccountUsage? {
        let weighted = accounts.map { account in
            (account, self.remainingSecondaryCredits(account))
        }
        let total = weighted.map(\.1).reduce(0, +)
        guard total > 0 else {
            return accounts.min(by: self.usageComesBefore)
        }

        var cursor = Double.random(in: 0..<total)
        for (account, weight) in weighted {
            cursor -= weight
            if cursor <= 0 {
                return account
            }
        }
        return accounts.last
    }

    private static func remainingSecondaryCredits(_ account: CodexAccountUsage) -> Double {
        let capacity = self.secondaryCapacityCredits(for: account)
        guard capacity > 0 else { return 0 }
        let used = account.snapshot?.secondary?.usedPercent
            ?? account.snapshot?.primary?.usedPercent
            ?? 0
        return max(0, capacity * (1 - min(100, used) / 100))
    }

    private static func secondaryCapacityCredits(for account: CodexAccountUsage) -> Double {
        let raw = account.snapshot?.identity?.loginMethod
        let normalized = self.normalizePlan(raw)
        let resolved = self.planAliases[normalized] ?? normalized
        return self.secondaryCapacityCredits[resolved] ?? self.secondaryCapacityCredits["free"]!
    }

    private static func normalizePlan(_ plan: String?) -> String {
        let normalized = (plan ?? "")
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        if normalized.contains("enterprise") { return "enterprise" }
        if normalized.contains("business") { return "business" }
        if normalized.contains("team") { return "team" }
        if normalized.contains("edu") || normalized.contains("education") { return "edu" }
        if normalized.contains("pro") { return "pro" }
        if normalized.contains("plus") { return "plus" }
        if normalized.contains("free") { return "free" }
        return normalized.isEmpty ? "free" : normalized
    }

    private static func resetBucketDays(_ account: CodexAccountUsage, now: Date) -> Int {
        guard let reset = account.snapshot?.secondary?.resetsAt else {
            return self.unknownResetBucketDays
        }
        return max(0, Int(reset.timeIntervalSince(now) / self.secondsPerDay))
    }

    private static func usageComesBefore(_ lhs: CodexAccountUsage, _ rhs: CodexAccountUsage) -> Bool {
        let lhsSecondary = lhs.snapshot?.secondary?.usedPercent ?? lhs.snapshot?.primary?.usedPercent ?? 0
        let rhsSecondary = rhs.snapshot?.secondary?.usedPercent ?? rhs.snapshot?.primary?.usedPercent ?? 0
        if lhsSecondary != rhsSecondary { return lhsSecondary < rhsSecondary }

        let lhsPrimary = lhs.snapshot?.primary?.usedPercent ?? 0
        let rhsPrimary = rhs.snapshot?.primary?.usedPercent ?? 0
        if lhsPrimary != rhsPrimary { return lhsPrimary < rhsPrimary }

        return self.roundRobinComesBefore(lhs, rhs)
    }

    private static func roundRobinComesBefore(_ lhs: CodexAccountUsage, _ rhs: CodexAccountUsage) -> Bool {
        let lhsSelected = lhs.lastSelectedAt ?? 0
        let rhsSelected = rhs.lastSelectedAt ?? 0
        if lhsSelected != rhsSelected { return lhsSelected < rhsSelected }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }
}

enum CodexProfileStore {
    private static var stableManagedRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codexmaxx")
    }
    private static var stableCodexProfilesRoot: URL {
        Self.stableManagedRoot.appendingPathComponent("profiles/codex")
    }
    private static var managedRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(Self.isDevVariant ? ".codexmaxx-dev" : ".codexmaxx")
    }
    private static var codexProfilesRoot: URL {
        Self.managedRoot.appendingPathComponent("profiles/codex")
    }
    static var usageHistoryURL: URL {
        Self.managedRoot.appendingPathComponent("usage-history.json")
    }
    static var activityHistoryURL: URL {
        Self.managedRoot.appendingPathComponent("activity-history.json")
    }
    private static let liveCodexHome = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".codex")
    private static var backupRoot: URL {
        Self.managedRoot.appendingPathComponent("backups")
    }
    private static let switchedFiles = [
        "auth.json",
        "config.toml",
        "models_cache.json",
        "installation_id",
        "version.json",
    ]

    private static var isDevVariant: Bool {
        let bundleId = Bundle.main.bundleIdentifier ?? ""
        let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        return bundleId.hasSuffix(".dev") || displayName == "CodexMaxx Dev"
    }

    static func loadProfiles() throws -> [CodexProfile] {
        let root = Self.codexProfilesRoot
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Self.seedDevProfilesFromStableIfNeeded()
        let config = (try? Self.loadConfig()) ?? CodexMaxxConfig.empty
        let active = Self.activeProfileName()
        let urls = Self.profileURLs(in: root)

        return urls.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            guard FileManager.default.fileExists(atPath: url.appendingPathComponent("auth.json").path) else { return nil }
            let name = url.lastPathComponent
            return CodexProfile(
                name: name,
                label: config.profiles[name]?.label,
                homeURL: url,
                active: name == active,
                lastSelectedAt: config.profiles[name]?.lastSelectedAt)
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
        try Self.recordActiveProfileName(name)
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
            label: label.isEmpty ? nil : label,
            lastSelectedAt: previous?.lastSelectedAt)
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
            label: nil,
            lastSelectedAt: nil)
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

    static func loadLoadBalancerSettings() -> LoadBalancerSettings {
        ((try? Self.loadConfig()) ?? CodexMaxxConfig.empty).loadBalancer
    }

    static func saveLoadBalancerSettings(_ settings: LoadBalancerSettings) throws {
        var config = (try? Self.loadConfig()) ?? CodexMaxxConfig.empty
        config.loadBalancer = settings
        try Self.saveConfig(config)
    }

    private static func seedDevProfilesFromStableIfNeeded() throws {
        guard Self.isDevVariant else { return }
        guard Self.profileURLs(in: Self.codexProfilesRoot).isEmpty else { return }

        let sourceProfiles = Self.profileURLs(in: Self.stableCodexProfilesRoot)
        guard !sourceProfiles.isEmpty else { return }

        try FileManager.default.createDirectory(at: Self.codexProfilesRoot, withIntermediateDirectories: true)
        for source in sourceProfiles {
            let destination = Self.codexProfilesRoot.appendingPathComponent(source.lastPathComponent)
            guard !FileManager.default.fileExists(atPath: destination.path) else { continue }
            try FileManager.default.copyItem(at: source, to: destination)
        }

        let stableConfigURL = Self.stableManagedRoot.appendingPathComponent("config.json")
        let stableConfig = (try? Self.loadConfig(from: stableConfigURL)) ?? .empty
        var config = (try? Self.loadConfig()) ?? .empty
        for (name, profile) in stableConfig.profiles where config.profiles[name] == nil {
            config.profiles[name] = profile
        }
        if config.active == nil {
            config.active = stableConfig.active
        }
        try Self.saveConfig(config)
    }

    private static func profileURLs(in root: URL) -> [URL] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles])
        else { return [] }

        return urls.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                && FileManager.default.fileExists(atPath: url.appendingPathComponent("auth.json").path)
        }
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
            return false
        }
        return lhsIdentity == rhsIdentity
    }

    private static func profileIdentity(at home: URL) -> String? {
        let url = home.appendingPathComponent("auth.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let tokens = json["tokens"] as? [String: Any] ?? json
        if let accountID = Self.nonEmptyString(tokens["account_id"]) ?? Self.nonEmptyString(tokens["accountId"]) {
            return "account:\(accountID)"
        }
        if let email = Self.email(fromIDToken: Self.nonEmptyString(tokens["id_token"]) ?? Self.nonEmptyString(tokens["idToken"])) {
            return "email:\(email.lowercased())"
        }
        return nil
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }

    private static func email(fromIDToken token: String?) -> String? {
        guard let token else { return nil }
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let profile = json["https://api.openai.com/profile"] as? [String: Any]
        return json["email"] as? String ?? profile?["email"] as? String
    }

    private static func activeProfileName() -> String? {
        let config = (try? Self.loadConfig()) ?? CodexMaxxConfig.empty
        return config.active
    }

    private static func recordActiveProfileName(_ name: String) throws {
        var config = (try? Self.loadConfig()) ?? CodexMaxxConfig.empty
        config.active = name
        var profile = config.profiles[name] ?? CodexMaxxProfile(
            addedAt: ISO8601DateFormatter().string(from: Date()),
            label: nil,
            lastSelectedAt: nil)
        profile.lastSelectedAt = Date().timeIntervalSince1970
        config.profiles[name] = profile
        try Self.saveConfig(config)
    }

    private static func loadConfig() throws -> CodexMaxxConfig {
        let url = Self.managedRoot.appendingPathComponent("config.json")
        return try Self.loadConfig(from: url)
    }

    private static func loadConfig(from url: URL) throws -> CodexMaxxConfig {
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
    var loadBalancer: LoadBalancerSettings

    static let empty = CodexMaxxConfig(version: 1, active: nil, profiles: [:], loadBalancer: .disabled)

    enum CodingKeys: String, CodingKey {
        case version
        case active
        case profiles
        case loadBalancer = "load_balancer"
    }

    init(
        version: Int,
        active: String?,
        profiles: [String: CodexMaxxProfile],
        loadBalancer: LoadBalancerSettings = .disabled)
    {
        self.version = version
        self.active = active
        self.profiles = profiles
        self.loadBalancer = loadBalancer
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        self.active = try container.decodeIfPresent(String.self, forKey: .active)
        self.profiles = try container.decodeIfPresent([String: CodexMaxxProfile].self, forKey: .profiles) ?? [:]
        self.loadBalancer = try container.decodeIfPresent(LoadBalancerSettings.self, forKey: .loadBalancer) ?? .disabled
    }
}

struct CodexMaxxProfile: Codable, Sendable {
    var addedAt: String?
    var label: String?
    var lastSelectedAt: Double? = nil

    enum CodingKeys: String, CodingKey {
        case addedAt = "added_at"
        case label
        case lastSelectedAt = "last_selected_at"
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
            let resetCredits: CodexResetCreditsSnapshot?
            let resetCreditsError: String?
            do {
                resetCredits = try await CodexResetCreditsFetcher.fetchResetCredits(
                    accessToken: credentials.accessToken,
                    accountId: credentials.accountId,
                    env: env)
                resetCreditsError = nil
            } catch {
                resetCredits = nil
                resetCreditsError = error.localizedDescription
            }
            return CodexAccountUsage(
                name: profile.name,
                label: profile.label,
                active: profile.active,
                lastSelectedAt: profile.lastSelectedAt,
                snapshot: snapshot,
                resetCredits: resetCredits,
                resetCreditsError: resetCreditsError,
                error: snapshot == nil ? "No rate limits returned" : nil)
        } catch {
            return CodexAccountUsage(
                name: profile.name,
                label: profile.label,
                active: profile.active,
                lastSelectedAt: profile.lastSelectedAt,
                snapshot: nil,
                resetCredits: nil,
                resetCreditsError: nil,
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

struct UsagePace: Sendable {
    enum Stage: Sendable {
        case onTrack
        case slightlyAhead
        case ahead
        case farAhead
        case slightlyBehind
        case behind
        case farBehind
    }

    let stage: Stage
    let deltaPercent: Double
    let etaSeconds: TimeInterval?
    let willLastToReset: Bool

    static func weekly(window: RateWindow, now: Date = Date(), defaultWindowMinutes: Int = 10_080) -> UsagePace? {
        guard let resetsAt = window.resetsAt else { return nil }
        let minutes = window.windowMinutes ?? defaultWindowMinutes
        guard minutes > 0 else { return nil }

        let duration = TimeInterval(minutes) * 60
        let timeUntilReset = resetsAt.timeIntervalSince(now)
        guard timeUntilReset > 0, timeUntilReset <= duration else { return nil }

        let elapsed = min(max(duration - timeUntilReset, 0), duration)
        let expected = min(max((elapsed / duration) * 100, 0), 100)
        let actual = min(max(window.usedPercent, 0), 100)
        if elapsed == 0, actual > 0 { return nil }

        let delta = actual - expected
        let stage = Self.stage(for: delta)
        var etaSeconds: TimeInterval?
        var willLastToReset = false

        if elapsed > 0, actual > 0 {
            let rate = actual / elapsed
            if rate > 0 {
                let remaining = max(0, 100 - actual)
                let eta = remaining / rate
                if eta >= timeUntilReset {
                    willLastToReset = true
                } else {
                    etaSeconds = eta
                }
            }
        } else if elapsed > 0, actual == 0 {
            willLastToReset = true
        }

        return UsagePace(
            stage: stage,
            deltaPercent: delta,
            etaSeconds: etaSeconds,
            willLastToReset: willLastToReset)
    }

    private static func stage(for delta: Double) -> Stage {
        let absoluteDelta = abs(delta)
        if absoluteDelta <= 2 { return .onTrack }
        if absoluteDelta <= 6 { return delta >= 0 ? .slightlyAhead : .slightlyBehind }
        if absoluteDelta <= 12 { return delta >= 0 ? .ahead : .behind }
        return delta >= 0 ? .farAhead : .farBehind
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

    static func fullDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
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

    static func menuBarSummary(_ snapshot: UsageSnapshot, resetCredits: CodexResetCreditsSnapshot?, settings: DisplaySettings) -> String {
        var parts: [String] = []
        if settings.windows != .week {
            parts.append("\(settings.label(for: .session).isEmpty ? "S" : settings.label(for: .session)) \(snapshot.primary.map(Self.capacity) ?? "?")")
        }
        if settings.windows != .session {
            parts.append("\(settings.label(for: .week).isEmpty ? "W" : settings.label(for: .week)) \(snapshot.secondary.map(Self.capacity) ?? "?")")
        }
        if let resetCredits {
            parts.append("R \(resetCredits.menuBarSummary)")
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

    static func resetSummary(_ snapshot: UsageSnapshot, now: Date = Date()) -> String? {
        var parts: [String] = []
        if let primary = snapshot.primary, let line = self.resetLine(for: primary, label: "S", now: now) {
            parts.append(line)
        }
        if let secondary = snapshot.secondary, let line = self.resetLine(for: secondary, label: "W", now: now) {
            parts.append(line)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func weeklyPaceSummary(_ snapshot: UsageSnapshot, now: Date = Date()) -> String? {
        guard let weekly = snapshot.secondary,
              let pace = UsagePace.weekly(window: weekly, now: now) else {
            return nil
        }
        if pace.stage == .onTrack {
            return "Pace: On pace"
        }

        let deltaValue = Int(abs(pace.deltaPercent).rounded())
        let left: String
        switch pace.stage {
        case .onTrack:
            left = "On pace"
        case .slightlyAhead, .ahead, .farAhead:
            left = "\(deltaValue)% in deficit"
        case .slightlyBehind, .behind, .farBehind:
            left = "\(deltaValue)% in reserve"
        }

        let right: String?
        if pace.willLastToReset {
            right = "Lasts until reset"
        } else if let etaSeconds = pace.etaSeconds {
            let eta = self.durationText(seconds: etaSeconds, now: now)
            right = eta == "now" ? "Runs out now" : "Runs out in \(eta)"
        } else {
            right = nil
        }

        if let right {
            return "Pace: \(left) · \(right)"
        }
        return "Pace: \(left)"
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

    static func resetCountdownDescription(from date: Date, now: Date = Date()) -> String {
        let seconds = max(0, date.timeIntervalSince(now))
        if seconds < 1 { return "now" }

        let totalMinutes = max(1, Int(ceil(seconds / 60)))
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes / 60) % 24
        let minutes = totalMinutes % 60

        if days > 0 {
            if hours > 0 { return "in \(days)d \(hours)h" }
            return "in \(days)d"
        }
        if hours > 0 {
            if minutes > 0 { return "in \(hours)h \(minutes)m" }
            return "in \(hours)h"
        }
        return "in \(totalMinutes)m"
    }

    static func compactCountdown(to date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 {
            return hours > 0 ? "\(days)d\(hours)h" : "\(days)d"
        }
        if hours > 0 {
            return minutes > 0 ? "\(hours)h\(minutes)m" : "\(hours)h"
        }
        return "\(max(1, minutes))m"
    }

    private static func resetLine(for window: RateWindow, label: String, now: Date) -> String? {
        if let reset = window.resetsAt {
            return "\(label) resets \(self.resetCountdownDescription(from: reset, now: now))"
        }
        guard let text = window.resetDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        if text.lowercased().hasPrefix("resets") {
            return "\(label) \(text)"
        }
        return "\(label) resets \(text)"
    }

    private static func durationText(seconds: TimeInterval, now: Date) -> String {
        let date = now.addingTimeInterval(seconds)
        let countdown = self.resetCountdownDescription(from: date, now: now)
        if countdown == "now" { return "now" }
        if countdown.hasPrefix("in ") { return String(countdown.dropFirst(3)) }
        return countdown
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

struct CodexResetCredit: Identifiable, Sendable {
    let id: String
    let status: String?
    let expiresAt: Date?

    var isAvailable: Bool {
        (self.status ?? "").lowercased() == "available"
    }
}

struct CodexResetCreditsSnapshot: Sendable {
    let availableCount: Int
    let credits: [CodexResetCredit]
    let updatedAt: Date

    var availableCredits: [CodexResetCredit] {
        self.credits.filter(\.isAvailable)
            .sorted {
                ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture)
            }
    }

    var nextExpiration: Date? {
        self.availableCredits.compactMap(\.expiresAt).first
    }

    var summaryDetail: String {
        guard let nextExpiration else {
            return self.availableCount == 0 ? "No available resets" : "Expiration unknown"
        }
        return "Next expires \(UsageText.resetCountdownDescription(from: nextExpiration))"
    }

    var menuBarSummary: String {
        guard let nextExpiration else { return "\(self.availableCount)" }
        return "\(self.availableCount) \(UsageText.compactCountdown(to: nextExpiration))"
    }

    var menuRowSummary: String {
        let label = self.availableCount == 1 ? "reset" : "resets"
        guard let nextExpiration else { return "\(self.availableCount) \(label)" }
        return "\(self.availableCount) \(label) · \(UsageText.compactCountdown(to: nextExpiration))"
    }

    var expirationLines: [String] {
        self.availableCredits.enumerated().map { index, credit in
            guard let expiresAt = credit.expiresAt else {
                return "Reset \(index + 1): expiration unknown"
            }
            return "Reset \(index + 1): \(UsageText.fullDateTime(expiresAt))"
        }
    }

    var helpText: String {
        let available = self.availableCredits
        guard !available.isEmpty else { return "No available Codex reset credits" }
        return available.enumerated().map { index, credit in
            guard let expiresAt = credit.expiresAt else {
                return "\(index + 1). expiration unknown"
            }
            return "\(index + 1). expires \(UsageText.fullDateTime(expiresAt)) (\(UsageText.resetCountdownDescription(from: expiresAt)))"
        }.joined(separator: "\n")
    }
}

struct CodexResetCreditsResponse: Decodable, Sendable {
    let availableCount: Int?
    let credits: [Credit]

    enum CodingKeys: String, CodingKey {
        case availableCount = "available_count"
        case credits
    }

    struct Credit: Decodable, Sendable {
        let id: String?
        let status: String?
        let expiresAt: Date?

        enum CodingKeys: String, CodingKey {
            case id
            case status
            case expiresAt = "expires_at"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try container.decodeIfPresent(String.self, forKey: .id)
            self.status = try container.decodeIfPresent(String.self, forKey: .status)
            self.expiresAt = Self.decodeDate(container, forKey: .expiresAt)
        }

        private static func decodeDate(_ container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Date? {
            if let value = try? container.decode(Double.self, forKey: key) {
                return Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1000 : value)
            }
            if let value = try? container.decode(Int.self, forKey: key) {
                let seconds = Double(value)
                return Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1000 : seconds)
            }
            guard let value = try? container.decode(String.self, forKey: key), !value.isEmpty else {
                return nil
            }
            if let seconds = Double(value) {
                return Date(timeIntervalSince1970: seconds > 10_000_000_000 ? seconds / 1000 : seconds)
            }
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) {
                return date
            }
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            return plain.date(from: value)
        }
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

    static func chatGPTBaseURL(env: [String: String]) -> String {
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

enum CodexResetCreditsFetcher {
    static func fetchResetCredits(accessToken: String, accountId: String?, env: [String: String]) async throws -> CodexResetCreditsSnapshot {
        let base = CodexOAuthUsageFetcher.chatGPTBaseURL(env: env)
        guard let url = URL(string: base + "/wham/rate-limit-reset-credits") else {
            throw NSError(domain: "CodexMaxx", code: 30, userInfo: [NSLocalizedDescriptionKey: "Invalid reset credits URL"])
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Codex Desktop", forHTTPHeaderField: "originator")
        request.setValue("CodexMaxx", forHTTPHeaderField: "User-Agent")
        if let accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-ID")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "CodexMaxx", code: 31, userInfo: [NSLocalizedDescriptionKey: "Invalid reset credits response"])
        }
        guard (200...299).contains(http.statusCode) else {
            throw NSError(domain: "CodexMaxx", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Reset credits API returned \(http.statusCode)"])
        }

        let decoded = try JSONDecoder().decode(CodexResetCreditsResponse.self, from: data)
        let credits = decoded.credits.enumerated().map { index, credit in
            CodexResetCredit(
                id: credit.id ?? "\(index)-\(credit.expiresAt?.timeIntervalSince1970 ?? 0)",
                status: credit.status,
                expiresAt: credit.expiresAt)
        }
        let availableCredits = credits.filter(\.isAvailable)
        return CodexResetCreditsSnapshot(
            availableCount: decoded.availableCount ?? availableCredits.count,
            credits: credits,
            updatedAt: Date())
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
