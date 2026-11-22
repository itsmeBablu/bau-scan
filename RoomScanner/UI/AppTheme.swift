import SwiftUI
#if canImport(UIKit)
import UIKit
public typealias AppPlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
public typealias AppPlatformColor = NSColor
#endif

/// Charte graphique et styles dWalkScan
/// - Primary Yellow: #facc15 (main color)
/// - Secondary Yellow: #fef08a (soft background tint: #fef3c7)
/// - Dark Charcoal: #111110 (deep warm charcoal: #272000) for text
public enum AppTheme {
    // MARK: - Palette SwiftUI Colors

    /// Primary Yellow: #facc15 (main color)
    public static let primaryYellow = Color(red: 250/255, green: 204/255, blue: 21/255)

    /// Secondary Yellow: #fef08a
    public static let secondaryYellow = Color(red: 254/255, green: 240/255, blue: 138/255)

    /// Soft background tint: #fef3c7
    public static let softBackgroundTint = Color(red: 254/255, green: 243/255, blue: 199/255)

    /// Dark Charcoal: #111110 (text & dark chrome)
    public static let darkCharcoal = Color(red: 17/255, green: 17/255, blue: 16/255)

    /// Deep warm charcoal: #272000 (text & rich contrast)
    public static let deepWarmCharcoal = Color(red: 39/255, green: 32/255, blue: 0/255)

    // MARK: - CoreGraphics Colors

    public static let primaryCGColor = CGColor(red: 250/255, green: 204/255, blue: 21/255, alpha: 1)
    public static let secondaryCGColor = CGColor(red: 254/255, green: 240/255, blue: 138/255, alpha: 1)
    public static let softBackgroundTintCGColor = CGColor(red: 254/255, green: 243/255, blue: 199/255, alpha: 1)
    public static let darkCharcoalCGColor = CGColor(red: 17/255, green: 17/255, blue: 16/255, alpha: 1)
    public static let deepWarmCharcoalCGColor = CGColor(red: 39/255, green: 32/255, blue: 0/255, alpha: 1)

    // MARK: - Platform Colors (RealityKit / SceneBuilder)

    public static var primaryPlatformColor: AppPlatformColor {
        #if canImport(UIKit)
        UIColor(red: 250/255, green: 204/255, blue: 21/255, alpha: 1)
        #else
        NSColor(red: 250/255, green: 204/255, blue: 21/255, alpha: 1)
        #endif
    }

    public static var secondaryPlatformColor: AppPlatformColor {
        #if canImport(UIKit)
        UIColor(red: 254/255, green: 240/255, blue: 138/255, alpha: 1)
        #else
        NSColor(red: 254/255, green: 240/255, blue: 138/255, alpha: 1)
        #endif
    }
}

// MARK: - Liquid Glass Modifiers

public struct LiquidGlassModifier: ViewModifier {
    public var cornerRadius: CGFloat = 16
    public var tint: Color? = nil
    public var hasBorder: Bool = true
    public var shadowRadius: CGFloat = 10

    public func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: cornerRadius,style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    if hasBorder {
                        RoundedRectangle(cornerRadius: cornerRadius,style: .continuous)
                            .stroke(.primary.opacity(0.08),lineWidth: 0.5)
                    }
                }
                .shadow(color: .black.opacity(0.06),radius: min(shadowRadius,4),x: 0,y: 2)
        }
    }

}

public struct LiquidGlassCardModifier: ViewModifier {
    public var cornerRadius: CGFloat = 14

    public func body(content: Content) -> some View {
        content.padding().background {
            RoundedRectangle(cornerRadius: cornerRadius,style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius,style: .continuous)
                        .stroke(.primary.opacity(0.08),lineWidth: 0.5)
                }
        }
    }

}

public extension View {
    /// Adaptive system material with a quiet separator and restrained shadow.
    func liquidGlass(cornerRadius: CGFloat = 16, tint: Color? = nil, hasBorder: Bool = true, shadowRadius: CGFloat = 10) -> some View {
        modifier(LiquidGlassModifier(cornerRadius: cornerRadius, tint: tint, hasBorder: hasBorder, shadowRadius: shadowRadius))
    }

    /// Liquid Glass style card with soft border and subtle specular reflection.
    func liquidGlassCard(cornerRadius: CGFloat = 14) -> some View {
        modifier(LiquidGlassCardModifier(cornerRadius: cornerRadius))
    }
}

/// IBV / dWalkScan brand logo with vector support and fallback.
public struct BrandLogoView: View {
    public var size: CGFloat = 40

    public init(size: CGFloat = 40) {
        self.size = size
    }

    public var body: some View {
        Image("AppLogo")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }
}
