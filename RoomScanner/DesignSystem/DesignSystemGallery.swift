#if DEBUG
import SwiftUI

struct DesignSystemGallery: View {
    @State private var dark = false
    @State private var largeText = false
    @State private var progress = 0.35
    init(dark:Bool = false,largeText:Bool = false) {
        _dark = State(initialValue:dark); _largeText = State(initialValue:largeText)
    }
    var body: some View {
        Form {
            Section("Appearance") {
                Toggle("Dark mode",isOn:$dark)
                Toggle("Accessibility text size",isOn:$largeText)
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
                DSStatCell(title:"Rooms",value:"6").dsCard()
                DSStatusBadge(title:"Device validation pending",symbol:"exclamationmark.circle",role:.warning)
                Text("Badge").dsBadge()
                Label("Floating controls",systemImage:"slider.horizontal.3").dsFloatingBar()
                DSInlineAudioRow(title:AppLanguage.text("Sample recording"),subtitle:AppLanguage.text("Sample data"),time:"0:12 / 0:38",playing:false,progress:$progress) {}
                DSEmptyState(title:"No photos yet",symbol:"photo",detail:"Photos appear here after capture.")
            }
        }
        .navigationTitle("Design system")
        .preferredColorScheme(dark ? .dark : .light)
        .dynamicTypeSize(largeText ? .accessibility2 : .large)
        .dsAppTheme()
    }
}
#Preview("Light") { NavigationStack { DesignSystemGallery() }.preferredColorScheme(.light) }
#Preview("Dark") { NavigationStack { DesignSystemGallery(dark:true) } }
#Preview("Accessibility XXL") { NavigationStack { DesignSystemGallery(largeText:true) } }
#endif
