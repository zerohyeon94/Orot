//
//  TodaySkyWidget.swift
//  OrotWidgets
//
//  세션이 없을 때 스탠바이·홈 화면에 두는 "오늘의 밤하늘" 위젯.
//  오늘의 별 개수, 실제 달 위상, 지금 채우는 수(宿)를 보여 줍니다.
//  스탠바이 야간 모드는 화면을 빨간 단색으로 바꾸므로 색이 아니라 밝기와 형태로 구분합니다.
//

import SwiftUI
import WidgetKit

struct TodaySkyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SkySnapshot.widgetKind, provider: TodaySkyProvider()) { entry in
            TodaySkyView(entry: entry)
                .containerBackground(OrotColor.skyNight, for: .widget)
        }
        .configurationDisplayName("오늘의 밤하늘")
        .description("오늘 띄운 별, 오늘의 달, 채우고 있는 별자리를 보여 줘요.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Timeline
struct TodaySkyEntry: TimelineEntry {
    let date: Date
    /// 앱을 아직 한 번도 열지 않았으면 nil
    let snapshot: SkySnapshot?
}

struct TodaySkyProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodaySkyEntry {
        TodaySkyEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodaySkyEntry) -> Void) {
        let saved = SkySnapshot.load()
        completion(TodaySkyEntry(date: Date(), snapshot: saved?.on(Date()) ?? (context.isPreview ? .sample : nil)))
    }

    /// 자정에 오늘 기록과 달 위상이 바뀌므로 지금과 다음 자정 두 장면을 둡니다.
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodaySkyEntry>) -> Void) {
        let now = Date()
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        let saved = SkySnapshot.load()
        let entries = [now, midnight].map { TodaySkyEntry(date: $0, snapshot: saved?.on($0)) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

private extension SkySnapshot {
    static let sample = SkySnapshot(
        day: Date(), todayStars: 2, todayPureMinutes: 75, completedMansions: 1,
        mansionLabel: "항(亢)", mansionFilled: 2, mansionStarCount: 4,
        mansionPoints: [CGPoint(x: -20, y: 6), CGPoint(x: -6, y: -4), CGPoint(x: 8, y: 2), CGPoint(x: 21, y: -6)],
        mansionMagnitudes: [2, 1]
    )
}

// MARK: - View
private struct TodaySkyView: View {
    let entry: TodaySkyEntry

    var body: some View {
        let moon = MoonPhase(date: entry.date)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text(moon.name)
                    .font(OrotFont.regular(12))
                    .foregroundStyle(OrotColor.textSecondary)
                Spacer(minLength: 4)
                MoonPhaseIcon(phase: moon, size: 22)
            }

            if let snapshot = entry.snapshot {
                MansionGlyph(snapshot: snapshot)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 6)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(snapshot.todayStars)")
                        .font(OrotFont.extraLight(40))
                        .foregroundStyle(OrotColor.textPrimary)
                        .widgetAccentable()
                    Text("오늘의 별")
                        .font(OrotFont.regular(12))
                        .foregroundStyle(OrotColor.textSecondary)
                }
                Text(caption(snapshot))
                    .font(OrotFont.regular(11))
                    .foregroundStyle(OrotColor.textCaption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Spacer()
                Text("오롯을 열어\n첫 별을 띄워 보세요")
                    .font(OrotFont.light(15))
                    .foregroundStyle(OrotColor.textSecondary)
            }
        }
    }

    private func caption(_ s: SkySnapshot) -> String {
        guard let label = s.mansionLabel else { return "스물여덟 수를 모두 채웠어요" }
        return "\(label) · \(s.mansionFilled) / \(s.mansionStarCount)"
    }
}

/// 지금 채우는 수의 모양. 채운 별은 밝게, 빈 자리는 점선 고리로 그립니다.
private struct MansionGlyph: View {
    let snapshot: SkySnapshot

    var body: some View {
        GeometryReader { geo in
            let points = fitted(in: geo.size)
            ZStack {
                Path { path in
                    for (i, p) in points.enumerated() {
                        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                }
                .stroke(OrotColor.constellationLine, style: StrokeStyle(lineWidth: 1, dash: [2, 3]))

                ForEach(points.indices, id: \.self) { i in
                    star(i).position(points[i])
                }
            }
        }
    }

    @ViewBuilder
    private func star(_ i: Int) -> some View {
        if i < snapshot.mansionFilled {
            let magnitude = i < snapshot.mansionMagnitudes.count ? snapshot.mansionMagnitudes[i] : 3
            let d = OrotStar.diameter[max(0, min(4, magnitude - 1))] + 1.5
            Circle()
                .fill(OrotColor.star(magnitude: magnitude))
                .frame(width: d, height: d)
                .shadow(color: OrotColor.star(magnitude: magnitude).opacity(0.6), radius: OrotStar.glow[max(0, min(4, magnitude - 1))] / 2)
                .widgetAccentable()
        } else {
            Circle()
                .strokeBorder(OrotColor.starSlotEmpty, style: StrokeStyle(lineWidth: 1, dash: [1.5, 1.5]))
                .frame(width: 8, height: 8)
        }
    }

    /// 별자리 좌표를 칸 크기에 맞춰 가운데에 놓습니다.
    private func fitted(in size: CGSize) -> [CGPoint] {
        let raw = snapshot.mansionPoints
        guard let minX = raw.map(\.x).min(), let maxX = raw.map(\.x).max(),
              let minY = raw.map(\.y).min(), let maxY = raw.map(\.y).max() else { return [] }
        let inset: CGFloat = 8
        let w = max(maxX - minX, 1), h = max(maxY - minY, 1)
        let scale = min((size.width - inset * 2) / w, (size.height - inset * 2) / h, 3.2)
        let ox = (size.width - w * scale) / 2, oy = (size.height - h * scale) / 2
        return raw.map { CGPoint(x: ox + ($0.x - minX) * scale, y: oy + ($0.y - minY) * scale) }
    }
}
