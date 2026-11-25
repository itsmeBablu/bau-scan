import Foundation

/// CP1252 text with explicit UTF-16 DXF escapes for characters outside the codepage.
enum DXFTextEncoding {
    static func data(_ text: String) -> Data {
        var output = Data()
        for scalar in text.unicodeScalars {
            if let bytes = String(scalar).data(using:.windowsCP1252,allowLossyConversion:false) { output.append(bytes) }
            else {
                for unit in String(scalar).utf16 { output.append(contentsOf:String(format:"\\U+%04X",unit).utf8) }
            }
        }
        return output
    }
}
