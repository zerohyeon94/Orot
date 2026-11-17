//
//  TrainingDataCollector.swift
//  Orot
//
//  출시 전 테스트용 학습 데이터 수집 — CoreML 모델이 실제로 받는 얼굴 크롭을
//  Documents/Collected/<수집 대상>/<라벨>/ 에 JPEG로 저장합니다.
//  폴더 구조는 research/ml 학습 스크립트의 --data_dir 형식과 같습니다.
//
//  ⚠️ 앱 타깃의 SWIFT_ACTIVE_COMPILATION_CONDITIONS에 DATA_COLLECTION이 있을 때만 포함됩니다.
//     App Store 출시 전에 Debug/Release 설정에서 DATA_COLLECTION을 반드시 빼야 합니다.
//

#if DATA_COLLECTION
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

    /// 세션이 끝난 뒤 사람이 고르는 라벨. 얼굴 크롭은 학습 class_map 폴더로 갑니다.
    /// 딴짓(distracted)은 지금 모델이 쓰지 않는 폴더라 학습에서 빠지고, 나중을 위해 모아만 둡니다.
    enum ReviewLabel: CaseIterable, Identifiable {
        case focus, drowsy, distracted
        var id: Self { self }
        var folder: String {
            switch self {
            case .focus: return Label.open.rawValue
            case .drowsy: return Label.closed.rawValue
            case .distracted: return "distracted"
            }
        }
        var title: String {
            switch self {
            case .focus: return "집중"
            case .drowsy: return "졸음"
            case .distracted: return "딴짓"
            }
        }
    }

    /// 세션 중 1분마다 찍은, 아직 라벨을 고르지 않은 사진
    struct Capture: Identifiable, Hashable {
        let id: String
        let date: Date
        var faceURL: URL { TrainingDataCollector.pendingRoot.appending(path: "\(id)_face.jpg") }
        var fullURL: URL { TrainingDataCollector.pendingRoot.appending(path: "\(id)_full.jpg") }
    }

    nonisolated static let root = URL.documentsDirectory.appending(path: "Collected")
    /// 내보내기(zip)에 섞이지 않도록 Collected 밖에 둡니다.
    nonisolated static let pendingRoot = URL.documentsDirectory.appending(path: "CollectedPending")
    static let timedCaptureKey = "dataCollection.timedCapture"
    static let captureInterval: TimeInterval = 60

    @Published var person = "me"
    @Published private(set) var recording: Label?
    @Published private(set) var counts: [Label: Int] = [:]
    @Published private(set) var pending: [Capture] = []

    private let context = CIContext()
    private var isTimedCapturing = false
    private var lastCaptureAt: Date?

    init() {
        loadPending()
    }

    private var personDir: URL {
        let name = person.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "/", with: "_")
        return Self.root.appending(path: name.isEmpty ? "me" : name)
    }

    func start(_ label: Label) { recording = label }
    func stop() { recording = nil }

    /// 감지 서비스가 얼굴을 찾은 프레임마다 호출합니다. 기록 중도, 1분 캡처 차례도 아니면 아무것도 하지 않습니다.
    /// 얼굴이 없는 프레임(자리 비움)은 호출되지 않으므로 1분 캡처에서도 자동으로 빠집니다.
    func save(pixelBuffer: CVPixelBuffer, faceRect: CGRect) {
        let now = Date()
        let captureDue = isTimedCapturing && now.timeIntervalSince(lastCaptureAt ?? .distantPast) >= Self.captureInterval
        guard recording != nil || captureDue else { return }

        let image = CIImage(cvPixelBuffer: pixelBuffer)
        // 모델 입력과 같은 영역 (regionOfInterest = faceRect)
        let rect = VNImageRectForNormalizedRect(faceRect, Int(image.extent.width), Int(image.extent.height))
        guard let face = jpeg(image.cropped(to: rect)) else { return }
        let stamp = "\(Int(now.timeIntervalSince1970 * 1000))"

        if let label = recording {
            counts[label, default: 0] += 1
            write([(face, personDir.appending(path: label.rawValue).appending(path: "\(stamp).jpg"))])
        }

        if captureDue, let full = jpeg(image) {
            lastCaptureAt = now
            let capture = Capture(id: stamp, date: now)
            pending.append(capture)
            write([(face, capture.faceURL), (full, capture.fullURL)])
            print("✅ 학습용 사진 캡처 (\(pending.count)장 대기)")
        }
    }

    private func jpeg(_ image: CIImage) -> Data? {
        context.jpegRepresentation(of: image, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    }

    private func write(_ files: [(Data, URL)]) {
        Task.detached(priority: .utility) {
            do {
                for (data, url) in files {
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: url)
                }
            } catch {
                print("❌ 수집 이미지 저장 실패: \(error)")
            }
        }
    }

    // MARK: - Timed Capture (세션 중 1분마다 1장, 소리 없음)

    /// 영상 프레임을 저장하는 방식이라 셔터 소리가 나지 않습니다. 첫 장은 시작 1분 뒤에 찍습니다.
    func beginTimedCapture() {
        isTimedCapturing = true
        lastCaptureAt = Date()
        print("✅ 학습용 1분 캡처 시작")
    }

    func endTimedCapture() {
        guard isTimedCapturing else { return }
        isTimedCapturing = false
        print("✅ 학습용 1분 캡처 종료 (\(pending.count)장 대기)")
    }

    /// 고른 라벨 폴더로 옮깁니다. label이 nil이면(건너뛰기) 지웁니다.
    /// 얼굴 크롭은 <사람>/<라벨>/, 전체 화면은 나중 모델을 위해 <사람>/_full/<라벨>/에 둡니다.
    func review(_ capture: Capture, as label: ReviewLabel?) {
        pending.removeAll { $0.id == capture.id }
        let faceDest = label.map { personDir.appending(path: $0.folder).appending(path: "\(capture.id).jpg") }
        let fullDest = label.map { personDir.appending(path: "_full").appending(path: $0.folder).appending(path: "\(capture.id).jpg") }
        Task.detached(priority: .utility) {
            let fm = FileManager.default
            guard let faceDest, let fullDest else {
                try? fm.removeItem(at: capture.faceURL)
                try? fm.removeItem(at: capture.fullURL)
                return
            }
            do {
                for (src, dest) in [(capture.faceURL, faceDest), (capture.fullURL, fullDest)] {
                    try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try fm.moveItem(at: src, to: dest)
                }
            } catch {
                print("❌ 학습용 사진 분류 실패: \(error)")
            }
        }
        if label == .focus { counts[.open, default: 0] += 1 }
        if label == .drowsy { counts[.closed, default: 0] += 1 }
    }

    /// 아직 고르지 않은 사진을 모두 지웁니다.
    func discardPending() {
        pending = []
        try? FileManager.default.removeItem(at: Self.pendingRoot)
        print("🔄 대기 중인 학습용 사진 삭제")
    }

    private func loadPending() {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: Self.pendingRoot.path)) ?? []
        pending = files
            .filter { $0.hasSuffix("_face.jpg") }
            .map { String($0.dropLast("_face.jpg".count)) }
            .sorted()
            .map { Capture(id: $0, date: Date(timeIntervalSince1970: (Double($0) ?? 0) / 1000)) }
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

            Text("기록하는 동안 얼굴 사진이 이 기기에 저장되고, 내보낸 사진은 집중 감지 모델 학습에 쓰입니다. 찍히는 사람의 동의를 받아 주세요.")
                .font(.caption)
                .foregroundColor(.orange)

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

            CaptureReviewButton(collector: collector)

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
