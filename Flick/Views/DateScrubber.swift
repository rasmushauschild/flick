import SwiftUI

struct DateScrubber: View {
    @Binding var selectedDate: Date
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Text(selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .opacity(isHovering ? 0 : 1)

            NumberStrip(selectedDate: $selectedDate)
                .opacity(isHovering ? 1 : 0)
        }
        .frame(height: 38)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

private struct NumberStrip: View {
    @Binding var selectedDate: Date
    @Environment(Store.self) private var store

    @State private var position = ScrollPosition()
    @State private var currentOffsetX: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0
    @State private var animationTask: Task<Void, Never>?

    private let today = Calendar.current.startOfDay(for: Date())
    private let itemWidth: CGFloat = 20
    private let spacing: CGFloat = 18
    private let horizontalPadding: CGFloat = 16
    private let animationDuration: Double = 0.5

    private let dates: [Date] = {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return (-730...730).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
    }()

    private func offsetX(for date: Date) -> CGFloat {
        guard let index = dates.firstIndex(where: { Calendar.current.isDate($0, inSameDayAs: date) }) else { return 0 }
        let cellStride = itemWidth + spacing
        let centerOfItem = horizontalPadding + CGFloat(index) * cellStride + itemWidth / 2
        return centerOfItem - viewportWidth / 2
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: spacing) {
                    ForEach(dates, id: \.self) { date in
                        dateCell(for: date)
                    }
                }
                .padding(.horizontal, horizontalPadding)
            }
            .scrollPosition($position)
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.x
            } action: { _, newValue in
                currentOffsetX = newValue
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.12),
                        .init(color: .black, location: 0.88),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .onAppear {
                viewportWidth = geo.size.width
                position.scrollTo(x: offsetX(for: selectedDate))
            }
            .onChange(of: geo.size.width) { _, new in
                viewportWidth = new
            }
            .onChange(of: selectedDate) { _, newDate in
                animateScroll(to: offsetX(for: newDate))
            }
        }
        .frame(height: 38)
    }

    @ViewBuilder
    private func dateCell(for date: Date) -> some View {
        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
        let isToday = Calendar.current.isDate(date, inSameDayAs: today)
        let hasContent = store.hasContent(for: date)
        VStack(spacing: 3) {
            Text(date.formatted(.dateTime.day()))
                .font(.system(size: isSelected ? 14 : 12,
                              weight: isToday ? .bold : .regular))
                .foregroundStyle(isSelected ? Color.primary : Color(white: 0.72))
                .frame(width: itemWidth)

            Circle()
                .frame(width: 3, height: 3)
                .foregroundStyle(Color.primary.opacity(hasContent ? 0.4 : 0))
        }
        .contentShape(Rectangle())
        .onTapGesture { selectedDate = date }
    }

    private func animateScroll(to target: CGFloat) {
        animationTask?.cancel()
        let from = currentOffsetX
        let duration = animationDuration
        let startTime = Date()

        animationTask = Task { @MainActor in
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(startTime)
                let t = min(1.0, elapsed / duration)
                let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
                let current = from + (target - from) * CGFloat(eased)
                position.scrollTo(x: current)
                if t >= 1.0 { break }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
    }
}
