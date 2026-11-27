//
//  Toast.swift
//  GetMoreRam
//
//  SideStore-inspired toast notifications (ToastView parity for SwiftUI).
//  Short duration for simple messages, longer when detail text is present.
//

import SwiftUI

enum ToastDuration {
    /// SideStore `shortToastViewDuration`
    static let short: TimeInterval = 4.0
    /// SideStore `longToastViewDuration`
    static let long: TimeInterval = 8.0
}

enum ToastStyle {
    case success
    case error
    case info

    var iconName: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .success: return .green
        case .error: return .red
        case .info: return .blue
        }
    }
}

/// Shared toast state — inject via environment or observe from root.
@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()

    @Published var isPresented = false
    @Published var title = ""
    @Published var detail: String?
    @Published var style: ToastStyle = .info

    private var hideTask: Task<Void, Never>?

    func show(title: String, detail: String? = nil, style: ToastStyle = .info) {
        hideTask?.cancel()
        self.title = title
        self.detail = detail
        self.style = style
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isPresented = true
        }
        let duration = detail == nil ? ToastDuration.short : ToastDuration.long
        hideTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.isPresented = false
                }
            }
        }
    }

    func success(_ title: String, detail: String? = nil) {
        show(title: title, detail: detail, style: .success)
    }

    func error(_ title: String, detail: String? = nil) {
        show(title: title, detail: detail, style: .error)
    }

    func info(_ title: String, detail: String? = nil) {
        show(title: title, detail: detail, style: .info)
    }

    func dismiss() {
        hideTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            isPresented = false
        }
    }
}

struct ToastBannerView: View {
    @ObservedObject var center: ToastCenter

    var body: some View {
        if center.isPresented {
            VStack {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: center.style.iconName)
                        .foregroundColor(center.style.iconColor)
                        .font(.system(size: 20))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(center.title)
                            .font(.system(.body, design: .default))
                            .foregroundColor(.primary)
                            .lineLimit(2)

                        if let detail = center.detail, !detail.isEmpty {
                            Text(detail)
                                .font(.footnote)
                                .foregroundColor(.secondary)
                                .lineLimit(4)
                        }
                    }

                    Spacer(minLength: 0)

                    Button {
                        center.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                .padding(.horizontal, 12)
                .padding(.top, 8)

                Spacer()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(999)
            .allowsHitTesting(true)
        }
    }
}

/// Overlay modifier — attach once at the root so any screen can post toasts.
struct ToastOverlayModifier: ViewModifier {
    @ObservedObject var center: ToastCenter

    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content
            ToastBannerView(center: center)
        }
    }
}

extension View {
    func toastOverlay(_ center: ToastCenter = .shared) -> some View {
        modifier(ToastOverlayModifier(center: center))
    }
}
