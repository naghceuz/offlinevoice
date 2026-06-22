import SwiftUI

/// Full-screen recorder shown when the keyboard launches the app via
/// `offlinevoice://dictate`. The user taps to record, the app transcribes
/// on-device and writes the text to the App Group, then prompts them to return
/// to the host app where the keyboard inserts it.
struct RoundTripView: View {
    @StateObject private var model = DictationViewModel(roundTrip: true)
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.05, blue: 0.12), Color(red: 0.10, green: 0.06, blue: 0.20)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                if let result = model.roundTripResult {
                    done(result)
                } else {
                    recording
                }
            }
            .padding(28)
        }
        .onAppear { model.startRecording() }
    }

    private var recording: some View {
        VStack(spacing: 28) {
            Text(model.isRecording ? "录音中…说完点一下停止" : "准备…")
                .font(.headline)
                .foregroundStyle(.white)

            if model.phase == .transcribing {
                ProgressView().tint(.white)
                Text("识别中…").foregroundStyle(.secondary)
            } else {
                Button {
                    model.toggleRoundTripRecording()
                } label: {
                    Circle()
                        .fill(model.isRecording ? Color.red : Color.accentColor)
                        .frame(width: 96, height: 96)
                        .overlay(Image(systemName: model.isRecording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 36)).foregroundStyle(.white))
                }
            }

            if let notice = model.notice {
                Text(notice).font(.footnote).foregroundStyle(.orange)
                Button("重试") { model.clear(); model.startRecording() }
                    .foregroundStyle(.white)
            }
        }
    }

    private func done(_ text: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44)).foregroundStyle(.green)
            Text(text)
                .font(.body).foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
            Text("点左上角 ‹ 返回刚才的 App，文字会自动插入输入框。")
                .font(.footnote).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("再说一段") { model.clear(); model.roundTripResult = nil; model.startRecording() }
                .foregroundStyle(.white)
        }
    }
}
