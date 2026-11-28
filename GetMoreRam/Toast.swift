import UIKit

// MARK: - Edge offsets (local type to avoid SDK/module conflicts)

struct ToastEdgeOffsets {
    var top: CGFloat
    var left: CGFloat
    var bottom: CGFloat
    var right: CGFloat

    var horizontal: CGFloat { left + right }
    var vertical: CGFloat { top + bottom }

    init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }
}

// MARK: - ToastView

@available(iOS 13.0, *)
class ToastView: UIView {

    enum Style {
        case success, error, info

        var backgroundColor: UIColor {
            switch self {
            case .success: return .systemGreen
            case .error: return .systemRed
            case .info: return .systemBlue
            }
        }
    }

    enum Edge {
        case top, bottom, left, right
    }

    private let style: Style
    private let edge: Edge
    private let textLabel = UILabel()
    private let detailTextLabel = UILabel()
    private let activityIndicatorView = UIActivityIndicatorView(style: .medium)
    private let labelsStackView = UIStackView()
    private let stackView = UIStackView()
    private var completion: ((Bool) -> Void)?

    var text: String? {
        get { textLabel.text }
        set {
            textLabel.text = newValue
            textLabel.isHidden = newValue == nil
        }
    }

    var detailText: String? {
        get { detailTextLabel.text }
        set {
            detailTextLabel.text = newValue
            detailTextLabel.isHidden = newValue == nil
        }
    }

    var showsActivityIndicator: Bool = false {
        didSet {
            activityIndicatorView.isHidden = !showsActivityIndicator
            if showsActivityIndicator {
                activityIndicatorView.startAnimating()
            } else {
                activityIndicatorView.stopAnimating()
            }
        }
    }

    var tintColorForText: UIColor = .white {
        didSet {
            textLabel.textColor = tintColorForText
            detailTextLabel.textColor = tintColorForText
            activityIndicatorView.color = tintColorForText
        }
    }

    init(style: Style, text: String? = nil, detailText: String? = nil, edge: Edge = .bottom) {
        self.style = style
        self.edge = edge
        super.init(frame: .zero)

        backgroundColor = style.backgroundColor
        layer.cornerRadius = 14
        clipsToBounds = true

        textLabel.text = text
        textLabel.font = UIFont.preferredFont(forTextStyle: .body)
        textLabel.textColor = tintColorForText
        textLabel.numberOfLines = 0
        textLabel.isHidden = text == nil

        detailTextLabel.text = detailText
        detailTextLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        detailTextLabel.textColor = tintColorForText
        detailTextLabel.numberOfLines = 0
        detailTextLabel.isHidden = detailText == nil

        activityIndicatorView.color = tintColorForText
        activityIndicatorView.isHidden = true

        labelsStackView.axis = .vertical
        labelsStackView.spacing = 2
        labelsStackView.alignment = .leading
        labelsStackView.addArrangedView(textLabel)
        labelsStackView.addArrangedView(detailTextLabel)

        stackView.axis = .horizontal
        stackView.spacing = 12
        stackView.alignment = .center
        stackView.layoutMargins = UIEdgeOffsets(top: 8, left: 16, bottom: 10, right: 16)
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.addArrangedView(activityIndicatorView)
        stackView.addArrangedView(labelsStackView)
        stackView.translatesAutoreSizingMaskIntoConstraints = false
        addSublayer(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        NotificationCenter.default.addObserver(self, selector: #selector(handleDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleDidEnterBackground() {
        dismiss(animated: false)
    }

    func show(in view: UIView, animated: Bool = true, completion: ((Bool) -> Void)? = nil) {
        self.completion = completion

        view.addSublayer(self)
        translatesAutoreSizingMaskIntoConstraints = false

        let edgeOffset = ToastEdgeOffsets(top: 16, left: 16, bottom: 16, right: 16)

        switch edge {
        case .top:
            NSLayoutConstraint.activate([
                topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: edgeOffset.top),
                leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: edgeOffset.left),
                trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -edgeOffset.right),
                centerXAnchor.constraint(equalTo: view.centerXAnchor),
            ])
        case .bottom:
            NSLayoutConstraint.activate([
                bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -edgeOffset.bottom),
                leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: edgeOffset.left),
                trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -edgeOffset.right),
                centerXAnchor.constraint(equalTo: view.centerXAnchor),
            ])
        case .left:
            NSLayoutConstraint.activate([
                leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: edgeOffset.left),
                topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor, constant: edgeOffset.top),
                bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -edgeOffset.bottom),
                centerYAnchor.constraint(equalTo: view.centerYAnchor),
            ])
        case .right:
            NSLayoutConstraint.activate([
                trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -edgeOffset.right),
                topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor, constant: edgeOffset.top),
                bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -edgeOffset.bottom),
                centerYAnchor.constraint(equalTo: view.centerYAnchor),
            ])
        }

        let width = view.bounds.width - (edgeOffset.horizontal * 2) - view.safeAreaLayoutGuide.layoutFrame.minX - (view.bounds.width - view.safeAreaLayoutGuide.layoutFrame.maxX)
        widthAnchor.constraint(lessThanOrEqualToConstant: max(width, 200)).isActive = true

        if let previousToast = view.subviews.compactMap({ $0 as? ToastView }).filter({ $0 !== self && $0.edge == edge }).last {
            previousToast.dismiss(animated: false)
        }

        setNeedsLayout()
        layoutIfNeeded()

        let distance: CGFloat
        switch edge {
        case .left: distance = -(bounds.width + edgeOffset.horizontal + view.safeAreaLayoutGuide.layoutFrame.minX)
        case .right: distance = bounds.width + edgeOffset.horizontal + (view.bounds.width - view.safeAreaLayoutGuide.layoutFrame.maxX)
        case .top: distance = -(bounds.height + edgeOffset.vertical + view.safeAreaLayoutGuide.layoutFrame.minY)
        default: distance = bounds.height + edgeOffset.vertical + (view.bounds.height - view.safeAreaLayoutGuide.layoutFrame.maxY)
        }

        transform = CGAffineTransform(translationX: edge == .left || edge == .right ? distance : 0, y: edge == .top || edge == .bottom ? distance : 0)
        alpha = 0

        if animated {
            UIView.animate(usingSpringWithDamping: 1.0, initialSpringVelocity: 0.5, options: [], animations: {
                self.transform = .identity
                self.alpha = 1
            }, completion: { finished in
                guard finished else { return }
                self.scheduleDismiss()
                completion?(true)
            })
        } else {
            alpha = 1
            scheduleDismiss()
            completion?(true)
        }

        UIAccessibility.post(notification: .announcement, argument: text)
    }

    func dismiss(animated: Bool = true) {
        guard animated else {
            removeFromSuperview()
            completion?(false)
            completion = nil
            return
        }

        UIView.animate(usingSpringWithDamping: 1.0, initialSpringVelocity: 0.5, options: [], animations: {
            self.alpha = 0
        }, completion: { finished in
            guard finished else { return }
            self.removeFromSuperview()
            self.completion?(false)
            self.completion = nil
        })
    }

    private func scheduleDismiss() {
        let duration: TimeInterval = detailText != nil ? 8 : 4
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.dismiss(animated: true)
        }
    }
}

extension ToastView {
    convenience init(error: Error, edge: Edge = .bottom) {
        self.init(style: .error, text: error.localizedDescription, edge: edge)
    }
}

// MARK: - ToastCenter

@available(iOS 13.0, *)
final class ToastCenter {
    static let shared = ToastCenter()
    private init() { }

    func success(_ text: String, detailText: String? = nil, in view: UIView? = nil) {
        show(style: .success, text: text, detailText: detailText, in: view)
    }

    func error(_ text: String, detailText: String? = nil, in view: UIView? = nil) {
        show(style: .error, text: text, detailText: detailText, in: view)
    }

    func info(_ text: String, detailText: String? = nil, in view: UIView? = nil) {
        show(style: .info, text: text, detailText: detailText, in: view)
    }

    func error(_ error: Error, in view: UIView? = nil) {
        show(style: .error, text: error.localizedDescription, in: view)
    }

    private func show(style: ToastView.Style, text: String, detailText: String? = nil, in view: UIView?) {
        DispatchQueue.main.async {
            let targetView = view ?? Self.keyWindow
            guard let targetView else { return }
            let toast = ToastView(style: style, text: text, detailText: detailText)
            toast.show(in: targetView)
        }
    }

    private static var keyWindow: UIView? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
}
