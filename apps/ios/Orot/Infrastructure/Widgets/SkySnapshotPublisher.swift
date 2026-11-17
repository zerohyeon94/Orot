//
//  SkySnapshotPublisher.swift
//  Orot
//
//  세션 기록이 바뀌면 오늘의 밤하늘 요약을 위젯(스탠바이)에 넘깁니다.
//

import Foundation
import WidgetKit

extension StudySessionStore {
    func publishSkySnapshot() {
        let today = sessions(for: Date())
        let mansion = sky.currentMansion
        let snapshot = SkySnapshot(
            day: Calendar.current.startOfDay(for: Date()),
            todayStars: today.count,
            todayPureMinutes: Int(today.reduce(0) { $0 + $1.netFocusTime } / 60),
            completedMansions: sky.completedCount,
            mansionLabel: mansion?.label,
            mansionFilled: mansion.map(sky.filledCount) ?? 0,
            mansionStarCount: mansion?.starCount ?? 0,
            mansionPoints: mansion?.points ?? [],
            mansionMagnitudes: mansion.map(sky.magnitudes) ?? []
        )
        guard snapshot != SkySnapshot.load() else { return }
        snapshot.save()
        WidgetCenter.shared.reloadTimelines(ofKind: SkySnapshot.widgetKind)
    }
}
