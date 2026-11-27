import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Shared tokens. AppTheme remains the compatibility entry point, not a second palette.
public enum DS {
    /// User-selected native SF Symbols shared by navigation, canvas and quantities.
    public enum Symbol {
        public static let project = "building.2", house = "house", technical = "wrench.and.screwdriver"
        public static let studio = "cube", settings = "gearshape", floorPlan = "square.split.2x2", ar = "viewfinder"
        public static let voiceNote = "waveform", photo = "camera", pin = "mappin"
        public static let measure = "ruler", recenter = "scope", options = "ellipsis"
        public static let restoreScan = "clock.arrow.circlepath"
        public static let floorArea = "square.dashed", wallArea = "rectangle", ceilingArea = "arrow.up.to.line"
        public static let perimeter = "square.dashed", minimumHeight = "arrow.down.to.line", maximumHeight = "arrow.up.to.line"
        public static let volume = "cube", door = "door.left.hand.closed", window = "window.vertical.closed"
        public static let otherOpening = "square.dashed", unhostedOpening = "questionmark.circle"
        public static let wasteAllowance = "arrow.3.trianglepath", flooring = "square.grid.3x3", paintArea = "paintbrush.pointed"
    }
    public enum ColorToken: String, CaseIterable {
        case accent = "AccentColor"
        case brand = "Brand"
        case onBrand = "OnBrand"
        case onAccent = "OnAccent"
        case surface = "Surface"
        case surfaceGrouped = "SurfaceGrouped"
        case card = "Card"
        case separator = "Separator"
        case textPrimary = "TextPrimary"
        case textSecondary = "TextSecondary"
        case success = "StatusSuccess"
        case warning = "StatusWarning"
        case error = "StatusError"
        case info = "StatusInfo"
        case recording = "Recording"
        case onRecording = "OnRecording"
        case selection = "Selection"
        case brandSubtle = "BrandSubtle"
        case brandSurface = "BrandSurface"
        case brandInk = "BrandInk"
        case mediaSurface = "MediaSurface"
        public var color: Color { Color(rawValue,bundle:.main) }
        public var platformColor: AppPlatformColor {
            #if canImport(UIKit)
            UIColor(named:rawValue,in:.main,compatibleWith:nil) ?? .label
            #else
            NSColor(named:NSColor.Name(rawValue),bundle:.main) ?? .labelColor
            #endif
        }
    }
    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 12
        public static let l: CGFloat = 16
        public static let xl: CGFloat = 24
    }
    public enum Radius {
        public static let compact: CGFloat = 6
        public static let small: CGFloat = 8
        public static let thumbnail: CGFloat = 10
        public static let panel: CGFloat = 12
        public static let card: CGFloat = 14
        public static let floating: CGFloat = 16
        public static let inspector: CGFloat = 18
        public static let toolbar: CGFloat = 20
        public static let project: CGFloat = 22
        public static let large: CGFloat = 24
    }
    public enum IconSize: CGFloat { case small = 18,libraryAction = 24,medium = 32,capture = 38,large = 48,hero = 64 }
    static func materialPreviewColor(_ point:TechnicalPoint3) -> Color { Color(red:point.x,green:point.y,blue:point.z) }
    public enum Stroke {
        public static let separator: CGFloat = 0.5
        public static let emphasis: CGFloat = 1
    }
    public enum Shadow {
        public static let opacity = 0.06
        public static let radius: CGFloat = 4
        public static let y: CGFloat = 2
    }
    public enum Motion {
        public static let feedback = 0.12
        public static let transition = 0.2
        public static func animation(reduceMotion: Bool) -> Animation? {
            reduceMotion ? nil : .easeInOut(duration:transition)
        }
    }
    public enum Size {
        #if os(macOS)
        public static let macLibraryThumbnail: CGFloat = 40
        public static let macSidebarMinimum: CGFloat = 220
        public static let macSidebarIdeal: CGFloat = 280
        #endif
        public static let minimumTouchTarget: CGFloat = 44
        public static let libraryAction: CGFloat = 48
        public static let libraryCardMinimumWidth: CGFloat = 180
        public static let projectCardMinimumWidth: CGFloat = 200
        public static let statMinimumWidth: CGFloat = 130
        public static let thumbnail: CGFloat = 140
        public static let logo: CGFloat = 40
    }
    public struct ScaledSizes: DynamicProperty {
        @ScaledMetric(relativeTo:.body) public var thumbnail: CGFloat = Size.thumbnail
        public init() {}
    }
    public enum Typography {
        public static let largeTitle = Font.largeTitle
        public static let title = Font.title
        public static let title2 = Font.title2
        public static let title3 = Font.title3
        public static let headline = Font.headline
        public static let body = Font.body
        public static let callout = Font.callout
        public static let subheadline = Font.subheadline
        public static let footnote = Font.footnote
        public static let caption = Font.caption
        public static let caption2 = Font.caption2
        #if os(iOS)
        public static let measurement = Font.title3.weight(.semibold).monospacedDigit()
        #else
        public static let measurement = Font.headline.monospacedDigit()
        #endif
    }

    #if os(iOS)
    static func libraryColumns(compact: Bool, textSize: DynamicTypeSize,
                               minimumWidth: CGFloat = Size.libraryCardMinimumWidth) -> [GridItem] {
        if textSize.isAccessibilitySize || (compact && textSize >= .xxLarge) { return [GridItem(.flexible())] }
        if compact { return [GridItem(.flexible()), GridItem(.flexible())] }
        return [GridItem(.adaptive(minimum: minimumWidth))]
    }
    #endif
}

public extension View {
    func dsIcon(_ size:DS.IconSize,weight:Font.Weight = .regular) -> some View { font(.system(size:size.rawValue,weight:weight)) }
    func dsAppTheme() -> some View { modifier(DSAppAppearance()) }
    func dsRecordingTint() -> some View { tint(DS.ColorToken.recording.color) }
    func dsCameraIndicatorTint() -> some View { tint(DS.ColorToken.onBrand.color) }
    /// Preserve native prominent-button layout while keeping labels readable
    /// against the appearance-dependent accent/recording fill.
    func dsProminentControl(recording: Bool = false) -> some View {
        buttonStyle(.borderedProminent)
            .tint(recording ? DS.ColorToken.recording.color : DS.ColorToken.accent.color)
            .foregroundStyle(recording ? DS.ColorToken.onRecording.color : DS.ColorToken.onAccent.color)
    }
}

private struct DSAppAppearance:ViewModifier {
    @AppStorage("ui.appearance") private var appearance = "system"
    @Environment(\.colorScheme) private var inheritedScheme
    private var scheme:ColorScheme? {
        switch appearance { case "light": .light; case "dark": .dark; default: nil }
    }
    func body(content:Content) -> some View {
        content.tint(DS.ColorToken.accent.color)
            .preferredColorScheme(scheme)
            .environment(\.colorScheme,scheme ?? inheritedScheme)
    }
}
