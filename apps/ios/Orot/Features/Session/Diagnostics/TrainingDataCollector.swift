//
//  TrainingDataCollector.swift
//  Orot
//
//  DEBUG 전용 학습 데이터 수집 — CoreML 모델이 실제로 받는 얼굴 크롭을
//  Documents/Collected/<수집 대상>/<라벨>/ 에 JPEG로 저장합니다.
//  폴더 구조는 research/ml 학습 스크립트의 --data_dir 형식과 같습니다.
//

#if DEBUG
import SwiftUI
import CoreImage
import Vision
import AudioToolbox
import UniformTypeIdentifiers

// MARK: - Collector
@MainActor
final class TrainingDataCollector: ObservableObject {
    /// 폴더 이름은 학습 class_map과 같아야 합니다 (Open → awake, Closed/yawn → drowsy).
    enum Label: String, CaseIterable, Identifiable {
        case open = "Open", closed = "Closed", yawn = "yawn"
        var id: String { rawValue }
        var title: String {
            switch self {
            case .open: return "눈 뜸 (모니터·책 보기 포함)"
            case .closed: return "눈 감음"
            case .yawn: return "하품"
            }
        }
    }

    nonisolated static let root = URL.documentsDirectory.appending(path: "Collected")

    @Published var person = "me"
    @Published private(set) var recording: Label?
    @Published private(set) var counts: [Label: Int] = [:]

    private let context = CIContext()

    private var personDir: URL {
        let name = person.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "/", with: "_")
        return Self.root.appending(path: name.isEmpty ? "me" : name)
    }

    func start(_ label: Label) { recording = label }
    func stop() { recording = nil }

    /// 감지 서비스가 얼굴을 찾은 프레임마다 호출합니다. 기록 중이 아니면 아무것도 하지 않습니다.
    func save(pixelBuffer: CVPixelBuffer, faceRect: CGRect) {
        guard let label = recording else { return }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        // 모델 입력과 같은 영역 (regionOfInterest = faceRect)
        let rect = VNImageRectForNormalizedRect(faceRect, Int(image.extent.width), Int(image.extent.height))
        guard let data = context.jpegRepresentation(
            of: image.cropped(to: rect),
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        ) else { return }

        let dir = personDir.appending(path: label.rawValue)
        let url = dir.appending(path: "\(Int(Date().timeIntervalSince1970 * 1000)).jpg")
        counts[label, default: 0] += 1
        Task.detached(priority: .utility) {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try data.write(to: url)
            } catch {
                print("❌ 수집 이미지 저장 실패: \(error)")
            }
        }
    }

    func refreshCounts() {
        for label in Label.allCases {
            let files = try? FileManager.default.contentsOfDirectory(atPath: personDir.appending(path: label.rawValue).path)
            counts[label] = files?.count ?? 0
        }
    }
}

// MARK: - Export (Collected 폴더 전체를 zip으로)
struct CollectedDataExport: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .zip) { _ in
            var zipURL: URL?
            var coordinatorError: NSError?
            var copyError: Error?
            // .forUploading 읽기는 폴더를 임시 zip으로 만들어 줍니다 (블록 안에서만 유효)
            NSFileCoordinator().coordinate(readingItemAt: TrainingDataCollector.root, options: .forUploading, error: &coordinatorError) { tempURL in
                let dest = FileManager.default.temporaryDirectory.appending(path: "Collected.zip")
                do {
                    try? FileManager.default.removeItem(at: dest)
                    try FileManager.default.copyItem(at: tempURL, to: dest)
                    zipURL = dest
                } catch {
                    copyError = error
                }
            }
            guard let zipURL else { throw coordinatorError ?? copyError ?? CocoaError(.fileReadUnknown) }
            return SentTransferredFile(zipURL)
        }
    }
}

// MARK: - Panel (AI 분석 화면 하단)
struct DataCollectionPanel: View {
    @ObservedObject var collector: TrainingDataCollector
    let cameraService: CameraService

    @State private var status = "라벨을 누르면 3초 뒤 5초 동안 기록합니다"
    @State private var isBusy = false

    private let countdown = 3
    private let duration = 5
    private let captureInterval: CFAbsoluteTime = 0.2

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("학습 데이터 수집")
                .font(.headline)
                .foregroundColor(.white)

            TextField("수집 대상 (사람별로 다르게)", text: $collector.person)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .disabled(isBusy)
                .onSubmit { collector.refreshCounts() }

            ForEach(TrainingDataCollector.Label.allCases) { label in
                Button {
                    Task { await record(label) }
                } label: {
                    HStack {
                        Text(label.title)
                        Spacer()
                        Text("\(collector.counts[label] ?? 0)장")
                            .monospacedDigit()
                    }
                    .padding(12)
                    .background(collector.recording == label ? Color.red.opacity(0.6) : Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .foregroundColor(.white)
                .disabled(isBusy)
            }

            Text(status)
                .font(.caption)
                .foregroundColor(.gray)

            ShareLink(item: CollectedDataExport(), preview: SharePreview("Collected.zip")) {
                Label("수집 데이터 내보내기 (zip)", systemImage: "square.and.arrow.up")
            }
            .disabled(isBusy)
        }
        .padding()
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear { collector.refreshCounts() }
    }

    private func record(_ label: TrainingDataCollector.Label) async {
        isBusy = true
        for remaining in stride(from: countdown, to: 0, by: -1) {
            status = "\(remaining)초 뒤 '\(label.title)' 기록 시작"
            try? await Task.sleep(for: .seconds(1))
        }

        let previousInterval = cameraService.frameInterval
        cameraService.frameInterval = captureInterval
        AudioServicesPlaySystemSound(1113)  // 시작음 — 눈을 감고 있어도 알 수 있게
        collector.start(label)
        status = "🔴 '\(label.title)' 기록 중 (\(duration)초)"
        try? await Task.sleep(for: .seconds(duration))

        collector.stop()
        cameraService.frameInterval = previousInterval
        AudioServicesPlaySystemSound(1114)  // 종료음
        status = "✅ '\(label.title)' 기록 완료"
        isBusy = false
    }
}
#endif
