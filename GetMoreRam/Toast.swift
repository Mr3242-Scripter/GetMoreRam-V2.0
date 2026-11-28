//
//  ToastView.swift
//  GetMoreRam
//
//  Created by Riley Testut on 7/19/19.
//  Based on AltStore/SideStore ToastView by Riley Testut.
//

@preconcurrency import UIKit

// MARK: - SideStore ToastView API compatibility (public UIKit mapping)
extension UISpringTimingParameters {
    convenience init(stiffness: CGFloat, dampingRatio: CGFloat) {
        let mass: CGFloat = 1.0
        let damping = 2.0 * dampingRatio * sqrt(stiffness * mass)
        self.init(mass: mass, stiffness: stiffness, damping: damping, initialVelocity: .zero)
    }
}

extension UIViewPropertyAnimator {
    convenience init(springTimingParameters: UITimingCurveProvider, animations: (() -> Void)?) {
        self.init(duration: 0.5, timingParameters: springTimingParameters)
        if let animations {
            addAnimations(animations)
        }
    }
}

extension TimeInterval
{
    static let shortToastViewDuration = 4.0
    static let longToastViewDuration = 8.0
}

extension ToastView
{
    static let openErrorLogNotification = Notification.Name("ALTOpenErrorLogNotification")
    static let willShowNotification = Notification.Name("ToastViewWillShowNotification")
    static let didShowNotification = Notification.Name("ToastViewDidShowNotification")
    static let willDismissNotification = Notification.Name("ToastViewWillDismissNotification")
    static let didDismissNotification = Notification.Name("ToastViewDidDismissNotification")
    static let userInfoKeyPropertyAnimator = "ToastViewUserInfoKeyPropertyAnimator"

    public enum PresentationEdge: Int {
        case none
        case top
        case bottom
        case left
        case right
    }
}

class ToastView: UIControl
{
    public let textLabel = UILabel()
    public let detailTextLabel = UILabel()
    public let activityIndicatorView = UIActivityIndicatorView(style: .medium)

    var presentationEdge: PresentationEdge = .bottom {
        didSet {
            if presentationEdge == .none {
                presentationEdge = .bottom
            }
        }
    }

    var alignmentEdge: PresentationEdge = .none
    var edgeOffset = UIOffset(horizontal: 15, vertical: 15)

    private(set) var isShown = false
    var preferredDuration: TimeInterval
    var opensErrorLog: Bool = false

    private let dimmingView = UIView()
    private let stackView = UIStackView()
    private let labelsStackView = UIStackView()
    private var dismissTimer: Timer?

    private var axisConstraint: NSLayoutConstraint?
    private var hiddenAxisConstraint: NSLayoutConstraint?
    private var alignmentConstraint: NSLayoutConstraint?
    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?

    convenience init(text: String, detailText: String?, opensLog: Bool = false) {
        self.init(text: text, detailText: detailText)
        self.opensErrorLog = opensLog
    }

    init(text: String, detailText detailedText: String?)
    {
        if detailedText == nil {
            self.preferredDuration = .shortToastViewDuration
        } else {
            self.preferredDuration = .longToastViewDuration
        }

        super.init(frame: .zero)
        self.initialize()

        self.textLabel.text = text
        self.detailTextLabel.text = detailedText

        // SideStore uses .altPrimary; approximate brand blue
        self.backgroundColor = UIColor(red: 0.20, green: 0.45, blue: 0.95, alpha: 1.0)
        self.textLabel.textColor = .white
        self.detailTextLabel.textColor = .white

        self.isAccessibilityElement = true
        self.layoutMargins = UIEdgeInsets(top: 8, left: 16, bottom: 10, right: 16)
        self.setNeedsLayout()

        self.labelsStackView.spacing = (detailedText != nil) ? 4.0 : 0.0
        self.labelsStackView.alignment = .leading
        self.addTarget(self, action: #selector(ToastView.showErrorLog), for: .touchUpInside)
    }

    public override init(frame: CGRect) {
        self.preferredDuration = .shortToastViewDuration
        super.init(frame: frame)
        self.initialize()
    }

    convenience init(error: Error, opensLog: Bool = false) {
        self.init(error: error)
        self.opensErrorLog = opensLog
    }

    convenience init(error: Error) {
        let nsError = error as NSError
        let text = (nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String)
            ?? NSLocalizedString("Operation Failed", comment: "")
        let detail: String?
        if let localized = error as? LocalizedError, let desc = localized.errorDescription, !desc.isEmpty {
            detail = desc
        } else {
            detail = nsError.localizedDescription
        }
        self.init(text: text, detailText: detail)
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func initialize() {
        edgeOffset = UIOffset(horizontal: 15, vertical: 15)

        dimmingView.backgroundColor = .black
        dimmingView.alpha = 0.1
        dimmingView.isHidden = true
        dimmingView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(dimmingView)
        NSLayoutConstraint.activate([
            dimmingView.topAnchor.constraint(equalTo: self.topAnchor),
            dimmingView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            dimmingView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            dimmingView.trailingAnchor.constraint(equalTo: self.trailingAnchor)
        ])

        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = 10
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(stackView)

        activityIndicatorView.color = .white
        activityIndicatorView.hidesWhenStopped = true
        activityIndicatorView.stopAnimating()

        textLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        textLabel.numberOfLines = 0

        detailTextLabel.font = UIFont.systemFont(ofSize: 15)
        detailTextLabel.numberOfLines = 0

        labelsStackView.axis = .vertical
        labelsStackView.alignment = .fill
        labelsStackView.addArrangedSubview(textLabel)
        labelsStackView.addArrangedSubview(detailTextLabel)

        stackView.addArrangedSubview(activityIndicatorView)
        stackView.addArrangedSubview(labelsStackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: self.layoutMarginsGuide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: self.layoutMarginsGuide.bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: self.layoutMarginsGuide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: self.layoutMarginsGuide.trailingAnchor)
        ])

        self.layer.cornerRadius = 16
        self.clipsToBounds = true

        NotificationCenter.default.addObserver(self, selector: #selector(ToastView.toastViewWillShow(_:)), name: ToastView.willShowNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func layoutSubviews()
    {
        super.layoutSubviews()

        if self.superview != nil, axisConstraint == nil {
            self.translatesAutoresizingMaskIntoConstraints = false

            let width = self.superview!.bounds.width - (edgeOffset.horizontal * 2) - self.superview!.safeAreaInsets.left - self.superview!.safeAreaInsets.right
            widthConstraint = self.widthAnchor.constraint(lessThanOrEqualToConstant: min(width, 400))
            heightConstraint = self.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)

            switch presentationEdge {
            case .bottom:
                axisConstraint = self.bottomAnchor.constraint(equalTo: self.superview!.safeAreaLayoutGuide.bottomAnchor, constant: -edgeOffset.vertical)
                hiddenAxisConstraint = self.topAnchor.constraint(equalTo: self.superview!.bottomAnchor)
            case .top:
                axisConstraint = self.topAnchor.constraint(equalTo: self.superview!.safeAreaLayoutGuide.topAnchor, constant: edgeOffset.vertical)
                hiddenAxisConstraint = self.bottomAnchor.constraint(equalTo: self.superview!.topAnchor)
            case .left:
                axisConstraint = self.leadingAnchor.constraint(equalTo: self.superview!.safeAreaLayoutGuide.leadingAnchor, constant: edgeOffset.horizontal)
                hiddenAxisConstraint = self.trailingAnchor.constraint(equalTo: self.superview!.leadingAnchor)
            case .right:
                axisConstraint = self.trailingAnchor.constraint(equalTo: self.superview!.safeAreaLayoutGuide.trailingAnchor, constant: -edgeOffset.horizontal)
                hiddenAxisConstraint = self.leadingAnchor.constraint(equalTo: self.superview!.trailingAnchor)
            case .none:
                break
            }

            switch alignmentEdge {
            case .left:
                alignmentConstraint = self.leadingAnchor.constraint(equalTo: self.superview!.safeAreaLayoutGuide.leadingAnchor, constant: edgeOffset.horizontal)
            case .right:
                alignmentConstraint = self.trailingAnchor.constraint(equalTo: self.superview!.safeAreaLayoutGuide.trailingAnchor, constant: -edgeOffset.horizontal)
            case .top, .bottom, .none:
                alignmentConstraint = self.centerXAnchor.constraint(equalTo: self.superview!.centerXAnchor)
            }

            NSLayoutConstraint.activate([
                widthConstraint!,
                heightConstraint!,
                alignmentConstraint!,
                hiddenAxisConstraint!
            ].compactMap { $0 })
        }
    }

    func show(in viewController: UIViewController) {
        self.show(in: viewController.view)
    }

    func show(in view: UIView) {
        self.show(in: view, duration: self.preferredDuration)
    }

    func show(in view: UIView, duration: TimeInterval)
    {
        dismissTimer?.invalidate()

        if duration > 0 {
            dismissTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
                self?.dismiss()
            }
        } else {
            dismissTimer = nil
        }

        if isShown { return }

        isShown = true

        textLabel.preferredMaxLayoutWidth = view.bounds.width
        detailTextLabel.preferredMaxLayoutWidth = view.bounds.width

        view.addSubview(self)
        view.layoutIfNeeded()

        hiddenAxisConstraint?.isActive = false
        axisConstraint?.isActive = true

        let timingParameters = UISpringTimingParameters(stiffness: 750.0, dampingRatio: 1.0)
        let animator = UIViewPropertyAnimator(springTimingParameters: timingParameters, animations: {
            view.layoutIfNeeded()
        })
        animator.addCompletion { [weak self] (position: UIViewAnimatingPosition) in
            guard let self = self else { return }
            if position == .end {
                NotificationCenter.default.post(name: ToastView.didShowNotification, object: self)
            }
        }
        animator.startAnimation()

        NotificationCenter.default.post(name: ToastView.willShowNotification, object: self, userInfo: [ToastView.userInfoKeyPropertyAnimator: animator])

        let announcement = (self.textLabel.text ?? "") + ". " + (self.detailTextLabel.text ?? "")
        self.accessibilityLabel = announcement
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
            UIAccessibility.post(notification: .announcement, argument: announcement)
        }
    }

    @objc func dismiss() {
        if !isShown { return }

        isShown = false
        dismissTimer?.invalidate()

        if self.superview != nil {
            axisConstraint?.isActive = false
            hiddenAxisConstraint?.isActive = true
        }

        let timingParameters = UISpringTimingParameters(stiffness: 750.0, dampingRatio: 1.0)
        let animator = UIViewPropertyAnimator(springTimingParameters: timingParameters, animations: {
            self.superview?.layoutIfNeeded()
        })
        animator.addCompletion { [weak self] (position: UIViewAnimatingPosition) in
            guard let self = self else { return }
            if position != .end { return }

            self.removeFromSuperview()

            self.axisConstraint = nil
            self.hiddenAxisConstraint = nil
            self.alignmentConstraint = nil

            NotificationCenter.default.post(name: ToastView.didDismissNotification, object: self)
        }
        animator.startAnimation()

        NotificationCenter.default.post(name: ToastView.willDismissNotification, object: self, userInfo: [ToastView.userInfoKeyPropertyAnimator: animator])
    }

    @objc private func toastViewWillShow(_ notification: Notification) {
        guard let toastView = notification.object as? ToastView, toastView != self else { return }
        if toastView.presentationEdge == self.presentationEdge {
            dismiss()
        }
    }

    override var isHighlighted: Bool {
        get { return super.isHighlighted }
        set {
            super.isHighlighted = newValue
            dimmingView.isHidden = !newValue
        }
    }

    override var layoutMargins: UIEdgeInsets {
        get { return super.layoutMargins }
        set {
            super.layoutMargins = newValue
            stackView.layoutMargins = newValue
        }
    }
}

private extension ToastView {
    @objc func showErrorLog() {
        guard self.opensErrorLog else { return }
        NotificationCenter.default.post(name: ToastView.openErrorLogNotification, object: self)
    }
}

extension ToastView {
    @MainActor
    static func present(text: String, detailText: String? = nil, duration: TimeInterval? = nil) {
        let toast = ToastView(text: text, detailText: detailText)
        if let duration {
            toast.preferredDuration = duration
        }
        toast.presentationEdge = .bottom
        guard let window = keyWindow() else { return }
        toast.show(in: window)
    }

    @MainActor
    static func presentError(_ error: Error) {
        let toast = ToastView(error: error)
        toast.presentationEdge = .bottom
        guard let window = keyWindow() else { return }
        toast.show(in: window)
    }

    @MainActor
    private static func keyWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        for scene in scenes where scene.activationState == .foregroundActive {
            if let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first {
                return window
            }
        }
        return scenes.flatMap { $0.windows }.first
    }
}

@MainActor
enum ToastCenter {
    static let shared = ToastCenterProxy()
}

@MainActor
final class ToastCenterProxy {
    func success(_ title: String, detail: String? = nil) {
        ToastView.present(text: title, detailText: detail)
    }

    func error(_ title: String, detail: String? = nil) {
        ToastView.present(text: title, detailText: detail)
    }

    func info(_ title: String, detail: String? = nil) {
        ToastView.present(text: title, detailText: detail)
    }

    func error(_ error: Error) {
        ToastView.presentError(error)
    }
}
