import SwiftUI
import Charts

/// The stats window: two streak cards above a line graph plotting accuracy and words-per-
/// minute per session over time — the core trade-off. Built with Apple's native Swift
/// Charts so it reads as a first-class macOS chart — dashed vertical gridlines, a trailing
/// y axis, a legend distinguishing the two lines.
struct StatsView: View {
    let db: Database

    /// Loaded once when the window appears. Empty until then (and stays empty if there's
    /// no session history yet, which the view shows as a placeholder).
    @State private var points: [Database.SessionStat] = []
    /// Consecutive-days streak, loaded alongside the points.
    @State private var dayStreak = 0
    /// Longest single typing streak ever (characters + the day it happened); nil if none.
    @State private var bestStreak: (count: Int, date: Date)?
    /// The session currently under the cursor on the chart (nil when not hovering), used to
    /// draw the marker rule and tooltip.
    @State private var hoveredID: Int64?

    private var hoveredPoint: Database.SessionStat? {
        hoveredID.flatMap { id in points.first { $0.id == id } }
    }

    /// One spacing unit. Every gap, pad, and margin on the page is a multiple of this so
    /// the layout sits on a single grid — outer gutter, gap between cards, and the padding
    /// inside each card are all the same `grid`, and intra-card text uses `grid / 2`.
    private let grid: CGFloat = 16
    /// Shared corner radius for every card on the page, so the boxes read as a set.
    private let cornerRadius: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: grid) {
            HStack(alignment: .top, spacing: grid) {
                streakBox
                bestStreakBox
                requestBox
            }

            accuracyCard
        }
        .padding(grid)
        .frame(width: 640, height: 460)
        .onAppear(perform: load)
    }

    /// The chart in a bordered card with its label, matching the streak box.
    private var accuracyCard: some View {
        VStack(alignment: .leading, spacing: grid / 2) {
            Text("accuracy vs words per minute")
            if points.isEmpty {
                // No completed sessions with keystrokes yet — nothing to plot.
                Spacer()
                HStack {
                    Spacer()
                    Text("No sessions recorded yet.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                Spacer()
            } else {
                accuracyChart
            }
        }
        .padding(grid)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1)
        )
    }

    /// Fixed height for the top-row stat cards so they line up regardless of content.
    private let statCardHeight: CGFloat = 150

    /// Card: "practice streak" / big count / "days" pinned to the bottom, per the mockup.
    private var streakBox: some View {
        statCard {
            Text("practice streak")
            Text("\(dayStreak)")
                .font(.system(size: 56, weight: .bold))
            Spacer()
            Text(dayStreak == 1 ? "day" : "days")
        }
    }

    /// Card: "best typing streak" / longest character count / the date it happened.
    private var bestStreakBox: some View {
        statCard {
            Text("best typing streak")
            Text(bestStreak.map { "\($0.count.formatted())" } ?? "—")
                .font(.system(size: 40, weight: .bold))
            Text("characters")
            Spacer()
            Text(bestStreak.map { Self.dateLabel($0.date) } ?? " ")
        }
    }

    /// Fills the spare space in the top row: a prompt linking to the feature-request board.
    /// Inverted (dark fill, white type) so it reads as the call-to-action among the cards.
    private var requestBox: some View {
        Link(destination: URL(string: "https://typesati.canny.io/feature-requests")!) {
            VStack(alignment: .leading, spacing: grid / 2) {
                Text("feature missing?")
                Text("request it")
                    .font(.system(size: 28, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(grid)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color(red: 0x3e / 255, green: 0x3e / 255, blue: 0x3e / 255)) // #3e3e3e
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(accuracyColor, lineWidth: 2) // #4747BA
            )
        }
        .buttonStyle(.plain)
        // Suppress the system keyboard focus ring (it picks up the accent colour — pink here).
        .focusable(false)
        .frame(maxWidth: .infinity, minHeight: statCardHeight, maxHeight: statCardHeight)
    }

    /// Shared stat-card chrome: leading-aligned content, fixed height, bordered card.
    private func statCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: grid / 2) {
            content()
        }
        .padding(grid)
        .frame(width: 200, height: statCardHeight, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1)
        )
    }

    /// Formats a date as e.g. "13th June 2026" — ordinal day, full month, year.
    private static func dateLabel(_ date: Date) -> String {
        let day = Calendar.current.component(.day, from: date)
        let ordinal = NumberFormatter.localizedString(from: NSNumber(value: day), number: .ordinal)
        let monthYear = date.formatted(.dateTime.month(.wide).year())
        return "\(ordinal) \(monthYear)"
    }

    /// Top of the y scale: always cover accuracy's full 0–100% and any WPM that runs higher,
    /// so neither line is clipped. The two share one axis — the legend tells them apart.
    private var yMax: Double {
        let maxWPM = points.compactMap(\.wpm).max() ?? 0
        return max(100, (maxWPM / 20).rounded(.up) * 20)
    }

    private let accuracyColor = Color(red: 0x47 / 255, green: 0x47 / 255, blue: 0xBA / 255) // #4747BA
    private let wpmColor = Color(red: 0x10 / 255, green: 0x10 / 255, blue: 0x13 / 255)      // #101013

    /// A fill that fades from the series color (near the line) down to clear (at the floor),
    /// like the reference traffic graph.
    private func areaFill(_ color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.35), color.opacity(0.02)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var accuracyChart: some View {
        Chart(points) { point in
            // Areas first so the lines stroke cleanly on top. Both use explicit yStart/yEnd
            // ranges so Swift Charts plots them absolutely instead of stacking them.
            AreaMark(
                x: .value("Session", point.date),
                yStart: .value("min", 0),
                yEnd: .value("Accuracy", point.accuracy),
                series: .value("Band", "accuracy")
            )
            .interpolationMethod(.linear)
            .foregroundStyle(areaFill(accuracyColor))

            // Solid white below the WPM line, masking the accuracy gradient down there so
            // the bottom band reads as a clean white separation. Its own `series` keeps the
            // fill a single continuous shape; yStart/yEnd keeps it from stacking on accuracy.
            if let wpm = point.wpm {
                AreaMark(
                    x: .value("Session", point.date),
                    yStart: .value("min", 0),
                    yEnd: .value("WPM", wpm),
                    series: .value("Band", "wpm")
                )
                .interpolationMethod(.linear)
                .foregroundStyle(.white)
            }

            LineMark(
                x: .value("Session", point.date),
                y: .value("Value", point.accuracy),
                series: .value("Metric", "accuracy")
            )
            .interpolationMethod(.linear)
            .foregroundStyle(by: .value("Metric", "accuracy"))

            PointMark(
                x: .value("Session", point.date),
                y: .value("Value", point.accuracy)
            )
            .symbolSize(point.id == hoveredID ? 90 : 28)
            .foregroundStyle(accuracyColor)

            if let wpm = point.wpm {
                LineMark(
                    x: .value("Session", point.date),
                    y: .value("Value", wpm),
                    series: .value("Metric", "wpm")
                )
                .interpolationMethod(.linear)
                .foregroundStyle(by: .value("Metric", "wpm"))

                PointMark(
                    x: .value("Session", point.date),
                    y: .value("Value", wpm)
                )
                .symbolSize(point.id == hoveredID ? 90 : 28)
                .foregroundStyle(wpmColor)
            }

            // Vertical marker under the cursor while hovering.
            if let hp = hoveredPoint {
                RuleMark(x: .value("Session", hp.date))
                    .foregroundStyle(Color.secondary.opacity(0.4))
            }
        }
        // Accuracy (%) and WPM share one axis. Pin the floor at 0 and the ceiling above
        // both so heights stay comparable across visits instead of auto-fitting.
        .chartYScale(domain: 0...yMax)
        .chartForegroundStyleScale([
            "accuracy": accuracyColor,
            "wpm": wpmColor,
        ])
        .chartYAxis {
            // Trailing y axis with solid gridlines, like the reference.
            AxisMarks(position: .trailing) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel()
            }
        }
        .chartXAxis {
            // Dashed vertical gridlines at each labelled date, matching macOS chart styling.
            AxisMarks { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                AxisTick()
                // Day + abbreviated month (e.g. "5 Jun") — unambiguous, no MM/DD guessing.
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                // Transparent layer that tracks the cursor and resolves it to the nearest
                // session, plus the floating tooltip pinned above that session's marker.
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            hoveredID = nearestPoint(to: location, proxy: proxy, geo: geo)?.id
                        case .ended:
                            hoveredID = nil
                        }
                    }

                if let hp = hoveredPoint,
                   let x = proxy.position(forX: hp.date) {
                    tooltip(hp)
                        .frame(width: 160)
                        .position(
                            x: min(max(x, 80), geo.size.width - 80),
                            y: 28
                        )
                }
            }
        }
    }

    /// The session whose date is closest to the cursor's x position, or nil if off-chart.
    private func nearestPoint(
        to location: CGPoint, proxy: ChartProxy, geo: GeometryProxy
    ) -> Database.SessionStat? {
        let plotX = location.x - geo[proxy.plotAreaFrame].origin.x
        guard let date: Date = proxy.value(atX: plotX) else { return nil }
        return points.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }

    /// Floating label showing the hovered session's date, accuracy, and WPM.
    private func tooltip(_ p: Database.SessionStat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(p.date.formatted(.dateTime.day().month(.abbreviated).hour().minute()))
                .font(.caption.weight(.semibold))
            swatchRow(accuracyColor, "\(Int(p.accuracy.rounded()))%")
            swatchRow(wpmColor, p.wpm.map { "\(Int($0.rounded())) wpm" } ?? "—")
        }
        .font(.caption)
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.2))
        )
        .shadow(radius: 2, y: 1)
    }

    /// A colored dot + value line, matching the chart series colors.
    private func swatchRow(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
        }
    }

    private func load() {
        points = (try? db.sessionStats()) ?? []
        dayStreak = (try? db.currentDayStreak()) ?? 0
        bestStreak = (try? db.bestTypingStreak()) ?? nil
    }
}
