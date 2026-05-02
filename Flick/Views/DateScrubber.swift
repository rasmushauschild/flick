import AppKit
import QuartzCore
import SwiftUI

struct DateScrubber: View {
    @Binding var selectedDate: Date
    /// Driven from `RootView` so the strip reveals when hovering anywhere in the header,
    /// not just over the scrubber's own bounds.
    var isActive: Bool

    var body: some View {
        ZStack {
            Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.78))
                .opacity(isActive ? 0 : 1)
                // Invisible when the strip is active but still in the ZStack; must not intercept clicks.
                .allowsHitTesting(!isActive)

            NumberStrip(selectedDate: $selectedDate)
                .opacity(isActive ? 1 : 0)
                .allowsHitTesting(isActive)
        }
        .frame(height: 38)
    }
}

private struct NumberStrip: View {
    @Binding var selectedDate: Date

    /// Bound to `scrollPosition(id:anchor: .center)` — the day currently aligned with the viewport center.
    /// `selectedDate` mirrors this with paired `onChange` handlers (each guarded against equal writes to avoid loops).
    @State private var centeredDate: Date?
    /// While a programmatic select is animating, ignore `centeredDate` echoes so an in-flight neighbor doesn't overwrite the tapped day.
    @State private var suppressCenteredEcho = false
    /// When true, `centeredDate` updates use a slow smooth animation; when false, disablesAnimations keeps scrubbing/snapping responsive.
    @State private var programmaticScrollActive = false

    private let today = Calendar.current.startOfDay(for: Date())
    private let cellWidth: CGFloat = 28
    private let spacing: CGFloat = 18
    private let unselectedFontSize: CGFloat = 15
    private let selectedFontSize: CGFloat = 20
    /// Programmatic scroll-to-day. Long `Transaction` + `programmaticScrollActive` so AppKit honors a slow glide; finger
    /// scrubbing uses `disablesAnimations` so snaps stay responsive.
    private let dateSnapAnimationDuration: Double = 2.0

    private let dates: [Date] = {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (-730...730).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
    }()

    var body: some View {
        GeometryReader { geo in
            let centerInset = max(0, (geo.size.width - cellWidth) / 2)
            /// Pull the edge fade ~20pt in from each bezel (normalized; capped so stops stay ordered on tiny widths).
            let edgeInsetNorm = min(20.0 / max(geo.size.width, 1), 0.35)
            let leftOpaqueStart = edgeInsetNorm + 0.22 * (1 - 2 * edgeInsetNorm)
            let rightOpaqueEnd = 1 - edgeInsetNorm - 0.22 * (1 - 2 * edgeInsetNorm)
            ZStack {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: spacing) {
                        ForEach(dates, id: \.self) { date in
                            dateCell(for: date)
                        }
                    }
                    .scrollTargetLayout()
                    // Let taps fall through to the ScrollView — per-cell Buttons do not receive clicks reliably on macOS
                    // inside NSScrollView; a single viewport-centered mapping selects the correct day.
                    .allowsHitTesting(false)
                }
                .contentMargins(.horizontal, centerInset, for: .scrollContent)
                .scrollTargetBehavior(.viewAligned(limitBehavior: .never))
                .scrollPosition(id: $centeredDate, anchor: .center)
                .transaction { tx in
                    if !programmaticScrollActive {
                        tx.disablesAnimations = true
                    }
                }
                // Viewport-sized alpha fade: dates blend into whatever is behind the strip (glass), not a painted overlay.
                // Tap handling stays on the outer `ZStack` so faded edge pixels don’t drop clicks.
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: edgeInsetNorm),
                            .init(color: .black, location: leftOpaqueStart),
                            .init(color: .black, location: rightOpaqueEnd),
                            .init(color: .clear, location: 1 - edgeInsetNorm)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                handleStripTap(at: location.x, viewportWidth: geo.size.width)
            }
            .onAppear {
                if centeredDate == nil {
                    centeredDate = selectedDate
                }
            }
            .onChange(of: centeredDate) { _, newDate in
                guard let newDate, !suppressCenteredEcho else { return }
                if newDate != selectedDate {
                    selectedDate = newDate
                    NSHapticFeedbackManager.defaultPerformer.perform(
                        .alignment,
                        performanceTime: .default
                    )
                }
            }
            .onChange(of: selectedDate) { _, newDate in
                // Avoid a second `centeredDate` animation fighting `selectDateProgrammatically`'s transaction.
                guard !suppressCenteredEcho else { return }
                if centeredDate != newDate {
                    animateProgrammaticScroll {
                        let tx = Transaction(animation: .smooth(duration: dateSnapAnimationDuration))
                        withTransaction(tx) {
                            centeredDate = newDate
                        }
                    }
                }
            }
        }
        .frame(height: 38)
    }

    private func animateProgrammaticScroll(_ updates: @escaping () -> Void) {
        programmaticScrollActive = true
        // Defer so the next layout pass sees `programmaticScrollActive` before the scroll transaction runs;
        // otherwise `.transaction { disablesAnimations }` can still suppress the programmatic animation.
        DispatchQueue.main.async {
            CATransaction.begin()
            CATransaction.setAnimationDuration(dateSnapAnimationDuration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
            updates()
            CATransaction.commit()
            DispatchQueue.main.asyncAfter(deadline: .now() + dateSnapAnimationDuration + 0.2) {
                programmaticScrollActive = false
            }
        }
    }

    /// Maps a tap in the scroll view's local (visible) space to a day using distance from viewport center — no fragile
    /// content-coordinate / scroll-offset math.
    private func handleStripTap(at x: CGFloat, viewportWidth: CGFloat) {
        let anchor = centeredDate ?? selectedDate
        guard let centerIdx = dates.firstIndex(where: { Calendar.current.isDate($0, inSameDayAs: anchor) }) else {
            return
        }
        let cellStride = cellWidth + spacing
        let delta = x - viewportWidth * 0.5
        let indexOffset = Int(round(delta / cellStride))
        let newIdx = max(0, min(dates.count - 1, centerIdx + indexOffset))
        selectDateProgrammatically(dates[newIdx])
    }

    /// Scroll + selection must update `scrollPosition` and `selectedDate` together; otherwise the strip may ignore a
    /// lone `selectedDate` write on macOS. The echo guard prevents the snap animation from re-emitting a neighbor day.
    private func selectDateProgrammatically(_ date: Date) {
        let changed = !Calendar.current.isDate(date, inSameDayAs: selectedDate)
        suppressCenteredEcho = true
        animateProgrammaticScroll {
            let tx = Transaction(animation: .smooth(duration: dateSnapAnimationDuration))
            withTransaction(tx) {
                centeredDate = date
                selectedDate = date
            }
        }
        // Match deferred `animateProgrammaticScroll` start + full smooth duration.
        DispatchQueue.main.asyncAfter(deadline: .now() + dateSnapAnimationDuration + 0.4) {
            suppressCenteredEcho = false
        }
        if changed {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }
    }

    @ViewBuilder
    private func dateCell(for date: Date) -> some View {
        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
        let isToday = Calendar.current.isDate(date, inSameDayAs: today)
        let selectionSpring = Animation.spring(response: 0.36, dampingFraction: 0.78)

        ZStack {
            Color.clear
            VStack(spacing: 3) {
                Text(date.formatted(.dateTime.day()))
                    .font(.system(size: unselectedFontSize, weight: isToday ? .bold : .regular))
                    .foregroundStyle(
                        isSelected
                            ? Color.primary
                            : Color.primary.opacity(isToday ? 0.52 : 0.38)
                    )
                    .scaleEffect(isSelected ? selectedFontSize / unselectedFontSize : 1, anchor: .center)
                    .animation(selectionSpring, value: isSelected)
                    .contentTransition(.numericText())

                Circle()
                    .frame(width: 3, height: 3)
                    .foregroundStyle(
                        Color.primary.opacity(isToday && isSelected ? 0.55 : (isToday ? 0.35 : 0))
                    )
                    .animation(selectionSpring, value: isSelected)
            }
        }
        .frame(width: cellWidth, height: 38)
        .contentShape(Rectangle())
    }
}
