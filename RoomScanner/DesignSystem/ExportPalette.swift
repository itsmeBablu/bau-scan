import CoreGraphics

/// Fixed legacy drawing colors, intentionally independent of UI appearance.
enum ExportPalette {
    static let primary = CGColor(red:250/255,green:204/255,blue:21/255,alpha:1)
    static let secondary = CGColor(red:254/255,green:240/255,blue:138/255,alpha:1)
    static let softBackground = CGColor(red:254/255,green:243/255,blue:199/255,alpha:1)
    static let ink = CGColor(red:17/255,green:17/255,blue:16/255,alpha:1)
    static let warmInk = CGColor(red:39/255,green:32/255,blue:0/255,alpha:1)
}
