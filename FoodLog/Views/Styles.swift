import SwiftUI

// MARK: - Shared UI Styles

struct CardSurface: ViewModifier {
    let cornerRadius: CGFloat
    let background: Color
    let strokeOpacity: Double
    let shadowOpacity: Double

    init(
        cornerRadius: CGFloat = 14,
        background: Color = Color(.secondarySystemGroupedBackground),
        strokeOpacity: Double = 0.08,
        shadowOpacity: Double = 0.04
    ) {
        self.cornerRadius = cornerRadius
        self.background = background
        self.strokeOpacity = strokeOpacity
        self.shadowOpacity = shadowOpacity
    }

    func body(content: Content) -> some View {
        content
            .background(background, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.primary.opacity(strokeOpacity), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(shadowOpacity), radius: 6, x: 0, y: 3)
    }
}

extension View {
    func cardSurface(
        cornerRadius: CGFloat = 14,
        background: Color = Color(.secondarySystemGroupedBackground),
        strokeOpacity: Double = 0.08,
        shadowOpacity: Double = 0.04
    ) -> some View {
        modifier(
            CardSurface(
                cornerRadius: cornerRadius,
                background: background,
                strokeOpacity: strokeOpacity,
                shadowOpacity: shadowOpacity
            )
        )
    }
}

struct SectionHeaderTextStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.headline)
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    func sectionHeaderStyle() -> some View {
        modifier(SectionHeaderTextStyle())
    }
}

struct PillSurface: ViewModifier {
    let background: Color
    let strokeOpacity: Double

    init(background: Color, strokeOpacity: Double = 0.25) {
        self.background = background
        self.strokeOpacity = strokeOpacity
    }

    func body(content: Content) -> some View {
        content
            .background(background, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(background.opacity(strokeOpacity), lineWidth: 0.5)
            )
    }
}

extension View {
    func pillSurface(background: Color) -> some View {
        modifier(PillSurface(background: background))
    }
}

// MARK: - Liquid Glass Styles

private struct LiquidGlassInputStyle: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color?

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
    }
}

private struct LiquidGlassButtonStyle: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else {
            if prominent {
                content.buttonStyle(.borderedProminent)
            } else {
                content.buttonStyle(.bordered)
            }
        }
    }
}

extension View {
    func liquidGlassInputStyle(cornerRadius: CGFloat = 16, tint: Color? = nil) -> some View {
        modifier(LiquidGlassInputStyle(cornerRadius: cornerRadius, tint: tint))
    }

    func liquidGlassButtonStyle(prominent: Bool = false) -> some View {
        modifier(LiquidGlassButtonStyle(prominent: prominent))
    }

    @ViewBuilder
    func glassNavigationBar() -> some View {
        if #available(iOS 26.0, *) {
            self.toolbarBackgroundVisibility(.hidden, for: .navigationBar)
        } else {
            self
        }
    }
}

// MARK: - Glass Circle Button

struct GlassCircleButton: View {
    let icon: String
    let iconColor: Color
    let size: CGFloat
    var tint: Color? = nil
    var showShadow: Bool = false
    let action: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            let glass = tint.map { Glass.regular.tint($0) } ?? .regular
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: size, height: size)
            }
            .glassEffect(glass.interactive(), in: .circle)
            .shadow(color: showShadow ? Color.black.opacity(0.18) : .clear, radius: 12, x: 0, y: 6)
        } else {
            Button(action: action) {
                ZStack {
                    Circle()
                        .fill(.clear)
                        .frame(width: size, height: size)
                        .background(.thinMaterial, in: Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                        )
                        .shadow(color: showShadow ? Color.black.opacity(0.18) : .clear, radius: 12, x: 0, y: 6)
                    Image(systemName: icon)
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(iconColor)
                }
            }
            .buttonStyle(BounceButtonStyle())
        }
    }
}

// MARK: - Bounce Button Style

struct BounceButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
