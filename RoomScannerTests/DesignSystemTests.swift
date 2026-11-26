import XCTest
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif
@testable import RoomScanner

final class DesignSystemTests: XCTestCase {
    @MainActor private func rgb(_ token:DS.ColorToken,dark:Bool,high:Bool) throws -> [Double] {
        #if os(iOS)
        let color = try XCTUnwrap(UIColor(named:token.rawValue,in:.main,compatibleWith:nil),token.rawValue)
        let traits = UITraitCollection(traitsFrom:[.init(userInterfaceStyle:dark ? .dark : .light),.init(accessibilityContrast:high ? .high : .normal)])
        var r:CGFloat = 0,g:CGFloat = 0,b:CGFloat = 0,a:CGFloat = 0
        XCTAssertTrue(color.resolvedColor(with:traits).getRed(&r,green:&g,blue:&b,alpha:&a))
        XCTAssertEqual(a,1,accuracy:0.001)
        return [Double(r),Double(g),Double(b)]
        #else
        let name:NSAppearance.Name = dark ? (high ? .accessibilityHighContrastDarkAqua : .darkAqua) : (high ? .accessibilityHighContrastAqua : .aqua)
        let appearance = try XCTUnwrap(NSAppearance(named:name))
        let named = try XCTUnwrap(NSColor(named:NSColor.Name(token.rawValue),bundle:.main),token.rawValue)
        var resolved:NSColor?
        appearance.performAsCurrentDrawingAppearance { resolved = named.usingColorSpace(.sRGB) }
        let color = try XCTUnwrap(resolved)
        XCTAssertEqual(color.alphaComponent,1,accuracy:0.001)
        return [Double(color.redComponent),Double(color.greenComponent),Double(color.blueComponent)]
        #endif
    }
    private func luminance(_ rgb:[Double]) -> Double {
        zip(rgb,[0.2126,0.7152,0.0722]).reduce(0) { total,pair in
            let linear = pair.0 <= 0.04045 ? pair.0/12.92 : pow((pair.0+0.055)/1.055,2.4)
            return total+linear*pair.1
        }
    }
    @MainActor func testEveryTokenResolvesInAllAppearances() throws {
        for dark in [false,true] { for high in [false,true] {
            for token in DS.ColorToken.allCases { XCTAssertEqual(try rgb(token,dark:dark,high:high).count,3) }
        } }
    }
    @MainActor func testResolvedTextAndControlContrastPairs() throws {
        for dark in [false,true] { for high in [false,true] {
            var pairs:[(DS.ColorToken,DS.ColorToken,Double)] = [(.onBrand,.brand,4.5),(.onAccent,.accent,4.5),(.onRecording,.recording,4.5),(.textPrimary,.selection,4.5)]
            for background in [DS.ColorToken.surface,.surfaceGrouped,.card] {
                for foreground in [DS.ColorToken.accent,.textPrimary,.textSecondary,.success,.warning,.error,.info,.recording] { pairs.append((foreground,background,4.5)) }
                pairs.append((.separator,background,3))
            }
            for (foreground,background,minimum) in pairs {
                let a = luminance(try rgb(foreground,dark:dark,high:high)),b = luminance(try rgb(background,dark:dark,high:high))
                XCTAssertGreaterThanOrEqual((max(a,b)+0.05)/(min(a,b)+0.05),minimum,"\(foreground)/\(background), dark=\(dark), high=\(high)")
            }
        } }
    }
    func testTokensKeepAccessibleSizeGridAndReducedMotionPolicy() {
        XCTAssertGreaterThanOrEqual(DS.Size.minimumTouchTarget,44)
        for spacing in [DS.Spacing.xs,DS.Spacing.s,DS.Spacing.m,DS.Spacing.l,DS.Spacing.xl] {
            XCTAssertEqual(spacing.truncatingRemainder(dividingBy:4),0)
        }
        XCTAssertNil(DS.Motion.animation(reduceMotion:true))
        XCTAssertNotNil(DS.Motion.animation(reduceMotion:false))
    }
}
