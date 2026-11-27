#if os(macOS)
import SwiftUI

/// The surrounding List owns selection, focus, contextual menus and package dragging.
struct DSMacLibraryRow: View {
    let title: String
    let detail: Text
    let symbol: String
    var thumbnail: CGImage? = nil

    var body: some View {
        HStack(spacing: DS.Spacing.m) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
                    .fill(DS.ColorToken.card.color)
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1)
                        .resizable().scaledToFit().padding(DS.Spacing.xs)
                } else {
                    Image(systemName: symbol)
                        .font(DS.Typography.title3)
                        .foregroundStyle(DS.ColorToken.accent.color)
                }
            }
            .frame(width: DS.Size.macLibraryThumbnail, height: DS.Size.macLibraryThumbnail)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text(title).font(DS.Typography.body.weight(.semibold)).lineLimit(2)
                detail.font(DS.Typography.caption).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, DS.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .help(Text(verbatim: title))
    }
}

struct DSMacMeasurementRow: View {
    let title: Text
    let value: String
    var confidence: Confidence? = nil

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.m) {
                title.fixedSize()
                Spacer(minLength: DS.Spacing.s)
                reading.fixedSize()
            }
            VStack(alignment: .leading, spacing: DS.Spacing.xs) { title; reading }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, DS.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private var reading: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.xs) {
            Text(verbatim: value).font(DS.Typography.body.weight(.medium)).monospacedDigit()
            if let confidence, confidence != .high {
                Image(systemName: confidence == .medium ? "questionmark.circle" : "exclamationmark.circle")
                    .foregroundStyle(confidence == .medium ? DS.ColorToken.warning.color : DS.ColorToken.error.color)
                    .accessibilityLabel(Text(confidence == .medium ? "confidence.medium" : "confidence.low"))
            }
        }
    }
}
#endif
