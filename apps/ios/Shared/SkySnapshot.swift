//
//  SkySnapshot.swift
//  Orot
//
//  앱이 위젯에 넘기는 오늘의 밤하늘 요약. App Group 저장소로 주고받습니다.
//

import CoreGraphics
import Foundation

struct SkySnapshot: Codable, Equatable {
    /// 기록한 날의 시작 시각
    var day: Date
    var todayStars: Int
    var todayPureMinutes: Int
    var completedMansions: Int
    /// 지금 채우는 수 ("항(亢)"). 28수를 모두 채웠으면 nil
    var mansionLabel: String?
    var mansionFilled: Int
    var mansionStarCount: Int
    var mansionPoints: [CGPoint]
    var mansionMagnitudes: [Int]

    static let appGroup = "group.com.focussense.app"
    static let widgetKind = "TodaySkyWidget"
    private static let key = "sky.snapshot"

    static func load() -> SkySnapshot? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(SkySnapshot.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.appGroup)?.set(data, forKey: Self.key)
    }

    /// 날짜가 바뀌었으면 오늘 기록은 0부터 다시 셉니다.
    func on(_ date: Date) -> SkySnapshot {
        guard !Calendar.current.isDate(day, inSameDayAs: date) else { return self }
        var next = self
        next.day = Calendar.current.startOfDay(for: date)
        next.todayStars = 0
        next.todayPureMinutes = 0
        return next
    }
}
