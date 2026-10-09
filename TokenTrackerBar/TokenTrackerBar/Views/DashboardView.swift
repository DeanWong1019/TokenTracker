    import SwiftUI

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var serverManager: ServerManager
    var limitsSettings: LimitsSettingsStore = .shared
    @ObservedObject private var localization = LocalizationObserver.shared

    var body: some View {
        VStack(spacing: 0) {
            // Clawd companion replaces the old header + Today card
            ClawdCompanionView(viewModel: viewModel)

            switch serverManager.status {
            case .idle, .starting:
                ServerStartingView()
            case .running:
                if viewModel.isSyncing && viewModel.summary == nil {
                    syncingView
                } else if viewModel.isLoading && viewModel.summary == nil {
                    loadingView
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(spacing: 16) {
                            SummaryCardsView(
                                todayTokens: viewModel.todayTokens,
                                todayCost: viewModel.todayCost,
                                last7dTokens: viewModel.last7dTokens,
                                last7dActiveDays: viewModel.last7dActiveDays,
                                last30dTokens: viewModel.last30dTokens,
                                last30dAvgPerDay: viewModel.last30dAvgPerDay,
                                totalTokens: viewModel.totalTokens,
                                totalCost: viewModel.totalCost
                            )
                            UsageLimitsView(
                                limits: viewModel.usageLimits,
                                subscriptions: viewModel.subscriptions,
                                settings: limitsSettings
                            )
                            ActivityHeatmapView(
                                heatmap: viewModel.heatmap,
                                showsTransientLocalData: viewModel.activityShowsTransientLocalData
                            )
                            UsageTrendChartWrapper(
                                daily: viewModel.daily,
                                monthly: viewModel.monthly,
                                hourly: viewModel.hourly,
                                period: $viewModel.period,
                                onPeriodChange: { viewModel.switchPeriod($0) }
                            )
                            TopModelsView(models: viewModel.topModels)
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        .padding(.bottom, 12)
                    }
                }
            case .failed(let message):
                ServerOfflineView(message: message) {
                    await serverManager.retry()
                    if serverManager.isServerRunning {
                        // A Dashboard window that gave up while the server was
                        // down keeps its stale overlay unless it is told to
                        // reload too. No-op when no window is open.
                        DashboardWindowController.shared.reload()
                        await viewModel.loadAll()
                    }
                }
            }

            Divider()
            FooterView()
        }
        .modifier(PopoverSurfaceBackground())
        .id(localization.revision)
    }

    private var syncingView: some View {
        VStack(spacing: 10) {
            Spacer()
            ProgressView()
                .controlSize(.regular)
            Text(Strings.syncingUsageData)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(Strings.syncingFirstLaunchHint)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var loadingView: some View {
        VStack(spacing: 10) {
            Spacer()
            ProgressView()
                .controlSize(.regular)
            Text(Strings.loadingData)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

/// Popover backdrop. On macOS 26+ the content stays transparent so the system
/// `NSPopover` chrome's automatic Liquid Glass shows through (the popover hosts the
/// content over `NSGlassEffectView` — see `StatusBarController.setupPopover`). Older
/// systems keep the classic `.regularMaterial`.
private struct PopoverSurfaceBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
        } else {
            content.background(.regularMaterial)
        }
    }
}

#Preview("Full Menu Bar Popover") {
    DashboardPopoverPreview()
}

#Preview("Full Menu Bar Popover · 简体中文") {
    DashboardPopoverPreview(localeOverride: NativeLocalization.chineseLocale)
}

@MainActor
private struct DashboardPopoverPreview: View {
    @StateObject private var viewModel: DashboardViewModel = {
        let viewModel = DashboardViewModel()
        viewModel.heatmap = previewHeatmap()
        viewModel.daily = previewDailyUsage()
        viewModel.monthly = previewMonthlyUsage()
        viewModel.hourly = previewHourlyUsage()
        return viewModel
    }()
    @StateObject private var serverManager: ServerManager = {
        let manager = ServerManager()
        manager.status = .running
        return manager
    }()
    @StateObject private var limitsSettings = LimitsSettingsStore(
        userDefaults: UserDefaults(suiteName: "TokenTrackerBar.CanvasPreview")!
    )

    init(localeOverride: String? = nil) {
        #if DEBUG
        NativeLocalization.previewLocaleOverride = localeOverride
        #endif
    }

    var body: some View {
        DashboardView(
            viewModel: viewModel,
            serverManager: serverManager,
            limitsSettings: limitsSettings
        )
            .frame(width: 480, height: 720)
    }

    private static func previewHeatmap() -> HeatmapResponse {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 1

        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let thisWeekStart = calendar.date(byAdding: .day, value: 1 - weekday, to: today) ?? today
        let firstWeekStart = calendar.date(byAdding: .weekOfYear, value: -51, to: thisWeekStart) ?? thisWeekStart
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        var activeDays = 0
        let weeks: [[HeatmapCell?]] = (0..<52).map { weekIndex in
            (0..<7).map { dayIndex in
                guard let date = calendar.date(
                    byAdding: .day,
                    value: weekIndex * 7 + dayIndex,
                    to: firstWeekStart
                ), date <= today else { return nil }

                let pattern = (weekIndex * 7 + dayIndex * 3) % 11
                let level = pattern < 6 ? (pattern % 4) + 1 : 0
                if level > 0 { activeDays += 1 }
                let tokens = level * (18_000 + ((weekIndex * 1_337 + dayIndex * 821) % 42_000))
                return HeatmapCell(
                    day: formatter.string(from: date),
                    totalTokens: tokens,
                    billableTotalTokens: tokens,
                    level: level
                )
            }
        }

        return HeatmapResponse(
            from: formatter.string(from: firstWeekStart),
            to: formatter.string(from: today),
            activeDays: activeDays,
            streakDays: 3,
            weeks: weeks
        )
    }

    private static func previewDailyUsage() -> [DailyEntry] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let formatter = previewDateFormatter("yyyy-MM-dd")
        let today = calendar.startOfDay(for: Date())

        return (0..<180).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset - 179, to: today) else {
                return nil
            }
            let weekday = calendar.component(.weekday, from: date)
            let weekendFactor = weekday == 1 || weekday == 7 ? 0.55 : 1.0
            let baseline = 38_000 + ((offset * 7_319) % 210_000)
            let tokens = Int(Double(baseline) * weekendFactor)
            return DailyEntry(
                day: formatter.string(from: date),
                totalTokens: tokens,
                billableTotalTokens: tokens,
                inputTokens: tokens / 3,
                outputTokens: tokens / 2,
                cachedInputTokens: tokens / 6,
                conversationCount: 2 + (offset % 9)
            )
        }
    }

    private static func previewMonthlyUsage() -> [MonthlyEntry] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = Date()
        let formatter = previewDateFormatter("yyyy-MM")

        return (0..<24).compactMap { offset in
            guard let date = calendar.date(byAdding: .month, value: offset - 23, to: now) else {
                return nil
            }
            let tokens = 1_200_000 + ((offset * 827_341) % 5_600_000)
            return MonthlyEntry(
                month: formatter.string(from: date),
                totalTokens: tokens,
                billableTotalTokens: tokens,
                inputTokens: tokens / 3,
                outputTokens: tokens / 2,
                cachedInputTokens: tokens / 6,
                conversationCount: 45 + offset * 7
            )
        }
    }

    private static func previewHourlyUsage() -> [HourlyEntry] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let formatter = previewDateFormatter("yyyy-MM-dd'T'HH:mm:ss")
        let now = Date()
        let currentHour = calendar.component(.hour, from: now)
        let today = calendar.startOfDay(for: now)

        return (0...currentHour).compactMap { hour in
            guard let date = calendar.date(byAdding: .hour, value: hour, to: today) else { return nil }
            let tokens = 9_000 + ((hour * 13_711 + 17_003) % 96_000)
            return HourlyEntry(
                hour: formatter.string(from: date),
                totalTokens: tokens,
                billableTotalTokens: tokens,
                inputTokens: tokens / 3,
                outputTokens: tokens / 2,
                cachedInputTokens: tokens / 6,
                conversationCount: 1 + (hour % 4)
            )
        }
    }

    private static func previewDateFormatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter
    }
}
