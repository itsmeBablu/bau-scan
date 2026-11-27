#if DEBUG
import SwiftUI

struct DesignSystemGallery: View {
    @State private var dark = false
    @State private var largeText = false
    @State private var progress = 0.35
    @State private var language = AppLanguage.system
    @Environment(\.locale) private var inheritedLocale
    private var sampleLocale: Locale { language == .system ? inheritedLocale : language.locale }
    init(dark:Bool = false,largeText:Bool = false) {
        _dark = State(initialValue:dark); _largeText = State(initialValue:largeText)
    }
    var body: some View {
        Form {
            Section("Appearance") {
                Toggle("Dark mode",isOn:$dark)
                Toggle("Accessibility text size",isOn:$largeText)
                Picker("Language", selection: $language) {
                    Text("System").tag(AppLanguage.system)
                    Text("English").tag(AppLanguage.english)
                    Text("Deutsch").tag(AppLanguage.german)
                }
            }
            Section("Semantic colors") {
                ForEach(DS.ColorToken.allCases,id:\.rawValue) { token in
                    HStack { RoundedRectangle(cornerRadius:DS.Radius.small).fill(token.color).frame(width:DS.Size.minimumTouchTarget,height:DS.Size.minimumTouchTarget); Text(token.rawValue) }
                }
            }
            Section("System typography") {
                Text("Large title").font(DS.Typography.largeTitle)
                Text("Title").font(DS.Typography.title)
                Text("Heading").font(DS.Typography.headline)
                Text("Body text").font(DS.Typography.body)
                Text("Caption").font(DS.Typography.caption)
            }
            Section("Buttons") {
                ForEach(DSButtonStyle.Kind.allCases,id:\.rawValue) { kind in
                    Button(kind.rawValue) {}.buttonStyle(DSButtonStyle(kind:kind))
                }
                Button("Disabled action") {}.buttonStyle(DSButtonStyle()).disabled(true)
            }
            Section("Components") {
                DSSectionHeader(title:"Measurements") {}
                #if os(iOS)
                DSStatGrid {
                    DSStatCell(title: "Scanned area (sum)", value: MeasurementFormat.squareMeters(86.4, locale: sampleLocale))
                    DSStatCell(title: "Rooms", value: "6")
                }.dsCard()
                Button {} label: {
                    DSThumbnailCard(title: AppLanguage.text("Floor plans", locale: sampleLocale)) {
                        Image(systemName: "square.split.bottomrightquarter").accessibilityHidden(true)
                    }.dsLibraryCard()
                }.dsLibraryButton()
                #else
                DSStatCell(title:"Rooms",value:"6").dsCard()
                DSMacLibraryRow(title: AppLanguage.text("House", locale: sampleLocale),
                                detail: Text(verbatim: MeasurementFormat.squareMeters(86.4, locale: sampleLocale)),
                                symbol: "house")
                DSMacMeasurementRow(title: Text("measures.perimeter"),
                                    value: MeasurementFormat.length(32.8, unit: .both, locale: sampleLocale),
                                    confidence: .medium)
                #endif
                DSStatusBadge(title:"Device validation pending",symbol:"exclamationmark.circle",role:.warning)
                Text("Badge").dsBadge()
                Label("Floating controls",systemImage:"slider.horizontal.3").dsFloatingBar()
                DSInlineAudioRow(title:AppLanguage.text("Sample recording",locale:sampleLocale),subtitle:AppLanguage.text("Sample data",locale:sampleLocale),time:"0:12 / 0:38",playing:false,progress:$progress) {}
                DSEmptyState(title:"No photos yet",symbol:"photo",detail:"Photos appear here after capture.")
            }
        }
        .navigationTitle("Design system")
        .preferredColorScheme(dark ? .dark : .light)
        .dynamicTypeSize(largeText ? .accessibility2 : .large)
        .dsAppTheme()
        .environment(\.locale, sampleLocale)
    }
}
#Preview("Light") { NavigationStack { DesignSystemGallery() }.preferredColorScheme(.light) }
#Preview("Dark") { NavigationStack { DesignSystemGallery(dark:true) } }
#Preview("Accessibility XXL") { NavigationStack { DesignSystemGallery(largeText:true) } }
#endif
