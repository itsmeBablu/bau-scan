import XCTest
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif
@testable import RoomScanner

final class DesignSystemTests: XCTestCase {
    #if os(macOS)
    @MainActor func testMacMeasurementReflowsInNarrowDetail() throws {
        let locale = Locale(identifier: "de_DE")
        let range = [2.54, 3.10].map { MeasurementFormat.length($0, unit: .both, locale: locale) }
            .joined(separator: " – ")
        let row = DSMacMeasurementRow(title: Text(verbatim: "Lichte Raumhöhe"),
                                      value: range, confidence: .medium)
        func snapshot(width: CGFloat) throws -> CGImage {
            let renderer = ImageRenderer(content: row.frame(width: width).padding().background(DS.ColorToken.surface.color))
            return try XCTUnwrap(renderer.cgImage)
        }
        let wide = try snapshot(width: 520)
        let narrow = try snapshot(width: 180)
        XCTAssertGreaterThan(narrow.height, wide.height)
        for (name, image) in [("wide", wide), ("narrow", narrow)] {
            let size = NSSize(width: CGFloat(image.width), height: CGFloat(image.height))
            let attachment = XCTAttachment(image: NSImage(cgImage: image, size: size))
            attachment.name = "Mac measurement - " + name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
    #endif
    #if os(iOS)
    func testLibraryCardsGiveAccessibilityTextAFullRow() {
        XCTAssertEqual(DS.libraryColumns(compact: true, textSize: .large).count, 2)
        XCTAssertEqual(DS.libraryColumns(compact: true, textSize: .xxLarge).count, 1)
        for compact in [true, false] {
            let columns = DS.libraryColumns(compact: compact, textSize: .accessibility2)
            XCTAssertEqual(columns.count, 1)
            guard case .flexible = columns.first?.size else { return XCTFail("Expected a full-width card") }
        }
    }
    #endif
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

    @MainActor func testFlowLayoutWrapsPastelBadgesOntoNextLineWhenNarrow() throws {
        let badges = DSFlowLayout(spacing: DS.Spacing.s, lineSpacing: DS.Spacing.s) {
            DSMetricBadge(title: "Layouts", value: "5", tone: .sky)
            DSMetricBadge(title: "Floors", value: "3", tone: .lavender)
            DSMetricBadge(title: "Total area", value: "250.0 m²", tone: .butter)
            DSMetricBadge(title: "Approved", value: "4", tone: .mint)
            DSMetricBadge(title: "Accepted", value: "6", tone: .peach)
        }
        func renderedHeight(width: CGFloat) throws -> Int {
            let renderer = ImageRenderer(content: badges.frame(width: width).padding(DS.Spacing.s).background(DS.ColorToken.card.color))
            return try XCTUnwrap(renderer.cgImage).height
        }
        let wide = try renderedHeight(width: 640)
        let narrow = try renderedHeight(width: 220)
        XCTAssertGreaterThan(narrow, wide)
    }
}
