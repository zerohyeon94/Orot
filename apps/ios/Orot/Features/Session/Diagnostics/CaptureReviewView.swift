//
//  CaptureReviewView.swift
//  Orot
//
//  세션 중 1분마다 찍은 사진을 한 장씩 보며 집중 / 졸음 / 딴짓을 고릅니다.
//  DATA_COLLECTION 플래그가 있을 때만 포함됩니다.
//

#if DATA_COLLECTION
import SwiftUI

// MARK: - Review Screen
struct CaptureReviewView: View {
    @ObservedObject var collector: TrainingDataCollector
    @Environment(\.dismiss) private var dismiss

    @State private var total = 0
    @State private var confirmsDiscard = false

    private var current: TrainingDataCollector.Capture? { collector.pending.first }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            VStack(spacing: 0) {
                header
                if let capture = current {
                    let layout = landscape ? AnyLayout(HStackLayout(spacing: 28)) : AnyLayout(VStackLayout(spacing: 20))
                    layout {
                        CapturePhoto(capture: capture)
                        CaptureLabelButtons(index: total - collector.pending.count + 1, total: total, date: capture.date) { label in
                            withAnimation(OrotMotion.tap) { collector.review(capture, as: label) }
                        }
                        .frame(maxWidth: landscape ? 300 : .infinity)
                    }
                    .padding(.top, 16)
                } else {
                    doneMessage
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(OrotColor.skyDeepNight.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear { total = collector.pending.count }
        .confirmationDialog("남은 사진을 모두 지울까요?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("\(collector.pending.count)장 지우기", role: .destructive) { collector.discardPending() }
        } message: {
            Text("고르지 않은 사진은 학습에 쓰이지 않고 기기에서 삭제돼요.")
        }
    }

    private var header: some View {
        HStack {
            Text("사진 고르기")
                .font(OrotFont.title)
                .foregroundStyle(OrotColor.textPrimary)
            Spacer()
            if !collector.pending.isEmpty {
                Button("모두 지우기") { confirmsDiscard = true }
                    .buttonStyle(OrotTextButtonStyle())
                    .padding(.trailing, 12)
            }
            Button("닫기") { dismiss() }
                .buttonStyle(OrotTextButtonStyle())
        }
    }

    private var doneMessage: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("모두 골랐어요")
                .font(OrotFont.light(22))
                .foregroundStyle(OrotColor.textPrimary)
            Text("고른 사진은 AI 분석 화면에서 zip으로 내보낼 수 있어요")
                .font(OrotFont.caption)
                .foregroundStyle(OrotColor.textCaption)
            Spacer()
            Button("닫기") { dismiss() }
                .buttonStyle(OrotPrimaryButtonStyle())
        }
    }
}

// MARK: - Photo
private struct CapturePhoto: View {
    let capture: TrainingDataCollector.Capture

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            image(capture.fullURL)
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: OrotRadius.md))
            // 모델이 실제로 보는 얼굴 크롭
            image(capture.faceURL)
                .scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: OrotRadius.sm))
                .overlay(RoundedRectangle(cornerRadius: OrotRadius.sm).strokeBorder(OrotColor.hairline))
                .padding(10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func image(_ url: URL) -> Image {
        if let ui = UIImage(contentsOfFile: url.path) { return Image(uiImage: ui).resizable() }
        return Image(systemName: "photo").resizable()
    }
}

// MARK: - Label Buttons
private struct CaptureLabelButtons: View {
    let index: Int
    let total: Int
    let date: Date
    let onSelect: (TrainingDataCollector.ReviewLabel?) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("\(date.formatted(date: .omitted, time: .shortened)) · \(index) / \(total)")
                .font(OrotFont.caption)
                .tracking(0.5)
                .monospacedDigit()
                .foregroundStyle(OrotColor.textSecondary)
            Text("이때 어떤 상태였나요?")
                .font(OrotFont.regular(15))
                .foregroundStyle(OrotColor.textPrimary)
            HStack(spacing: 8) {
                ForEach(TrainingDataCollector.ReviewLabel.allCases) { label in
                    Button(label.title) { onSelect(label) }
                        .buttonStyle(OrotSecondaryButtonStyle(height: 52))
                }
            }
            Button("모르겠어요 · 건너뛰기") { onSelect(nil) }
                .buttonStyle(OrotTextButtonStyle())
        }
    }
}

// MARK: - Entry Button (세션 완료 화면 · AI 분석 화면)
struct CaptureReviewButton: View {
    @ObservedObject var collector: TrainingDataCollector
    @State private var showsReview = false

    var body: some View {
        // 마지막 장을 고르면 버튼이 사라지므로, 화면은 항상 있는 VStack에 붙입니다.
        VStack {
            if !collector.pending.isEmpty {
                Button("학습용 사진 \(collector.pending.count)장 고르기") { showsReview = true }
                    .buttonStyle(OrotTextButtonStyle())
            }
        }
        .fullScreenCover(isPresented: $showsReview) {
            CaptureReviewView(collector: collector)
        }
    }
}
#endif
