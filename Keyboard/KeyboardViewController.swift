import UIKit

/// OfflineVoice keyboard. iOS forbids keyboards from using the microphone, so
/// this keyboard never records: tapping the mic launches the container app,
/// which records & transcribes on-device and writes the text to the App Group.
/// When the user returns to the host app, this keyboard inserts that text.
///
/// Deliberately minimal — one mic button plus the essentials. The whole pitch is
/// "dead simple + never loses what you said".
final class KeyboardViewController: UIInputViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Returning from the container app: drop in whatever was transcribed.
        insertPendingIfAny()
    }

    // MARK: - Round-trip insertion

    private func insertPendingIfAny() {
        guard let text = SharedStore.takePending() else { return }
        textDocumentProxy.insertText(text)
    }

    // MARK: - Actions

    @objc private func tapMic() {
        statusLabel.text = "正在打开 OfflineVoice 录音…"
        openContainerApp("offlinevoice://dictate")
    }

    @objc private func tapBackspace() {
        textDocumentProxy.deleteBackward()
    }

    @objc private func tapNextKeyboard() {
        advanceToNextInputMode()
    }

    /// Open the container app from inside a keyboard extension. `extensionContext.open`
    /// is unreliable for keyboards, so walk the responder chain to UIApplication's
    /// `openURL:` — the established way keyboards launch their container app.
    private func openContainerApp(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        let selector = sel_registerName("openURL:")
        var responder: UIResponder? = self
        while let current = responder {
            if current !== self, current.responds(to: selector) {
                _ = current.perform(selector, with: url)
                return
            }
            responder = current.next
        }
        extensionContext?.open(url, completionHandler: nil)
    }

    // MARK: - UI

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.text = "点麦克风说话 · 全程本地"
        label.font = .systemFont(ofSize: 13)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()

    private func buildUI() {
        view.backgroundColor = UIColor(white: 0.12, alpha: 1.0)

        let mic = makeButton(systemName: "mic.fill", action: #selector(tapMic))
        mic.backgroundColor = view.tintColor ?? .systemBlue
        mic.tintColor = .white
        mic.layer.cornerRadius = 32

        let backspace = makeButton(systemName: "delete.left", action: #selector(tapBackspace))
        let globe = makeButton(systemName: "globe", action: #selector(tapNextKeyboard))

        let row = UIStackView(arrangedSubviews: [globe, mic, backspace])
        row.axis = .horizontal
        row.alignment = .center
        row.distribution = .equalCentering
        row.translatesAutoresizingMaskIntoConstraints = false

        let stack = UIStackView(arrangedSubviews: [statusLabel, row])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: 220),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            mic.widthAnchor.constraint(equalToConstant: 64),
            mic.heightAnchor.constraint(equalToConstant: 64),
        ])
    }

    private func makeButton(systemName: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        button.setImage(UIImage(systemName: systemName, withConfiguration: config), for: .normal)
        button.tintColor = .label
        button.addTarget(self, action: action, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }
}
