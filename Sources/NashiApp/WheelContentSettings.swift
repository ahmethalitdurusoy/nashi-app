import SwiftUI
import NashiCore

/// Per-wheel lists of slices the user chose to hide. Stored as plain string
/// arrays so they survive updates; an empty wheel never appears — when every
/// slice for a file is hidden, the full list is shown instead.
enum WheelContentPreferences {
    static func key(for mode:WheelMode)->String { switch mode { case .convert:return "wheelHiddenFormats";case .tools:return "wheelHiddenTools";case .actions:return "wheelHiddenActions" } }
    static func hidden(_ mode:WheelMode,defaults:UserDefaults = .standard)->Set<String> { Set(defaults.stringArray(forKey:key(for:mode)) ?? []) }
    static func setHidden(_ ids:Set<String>,for mode:WheelMode,defaults:UserDefaults = .standard) {
        if ids.isEmpty { defaults.removeObject(forKey:key(for:mode)) } else { defaults.set(ids.sorted(),forKey:key(for:mode)) }
    }
    static func visible<T>(_ items:[T],mode:WheelMode,id:(T)->String,defaults:UserDefaults = .standard)->[T] {
        let hidden=hidden(mode,defaults:defaults)
        let kept=items.filter{!hidden.contains(id($0))}
        return kept.isEmpty ? items:kept
    }
    static var allFormats:[String] { Array(Set(FeatureCatalog.conversionMatrix.values.joined())).sorted() }
    static var allTools:[ToolKind] {
        let used=Set(FeatureCatalog.singleTools.values.joined()).union(FeatureCatalog.multipleTools.values.joined())
        return ToolKind.allCases.filter{used.contains($0)}
    }
    static func formatTitle(_ format:String)->String { format == "gz" ? "GZIP":format.uppercased() }
}

struct WheelContentSettingsView:View {
    private struct Choice:Identifiable { let id:String;let title:String;let symbol:String?;let localized:Bool }
    private struct ChoiceGroup:Identifiable { let id:String;let title:String;let choices:[Choice] }
    @State private var mode=WheelMode.convert
    @State private var hidden:Set<String>=WheelContentPreferences.hidden(.convert)
    private var groups:[ChoiceGroup] {
        switch mode {
        case .convert:
            let formats=WheelContentPreferences.allFormats
            func targets(_ source:String)->Set<String> { Set(FeatureCatalog.conversionMatrix[source] ?? []).union([source]) }
            let image=targets("jpg"),audio=targets("mp3"),video=targets("mp4").union(targets("mov"))
            func choices(_ list:[String])->[Choice] { list.map{Choice(id:$0,title:WheelContentPreferences.formatTitle($0),symbol:nil,localized:false)} }
            let images=formats.filter{image.contains($0)},sounds=formats.filter{!image.contains($0)&&audio.contains($0)},movies=formats.filter{!image.contains($0) && !audio.contains($0)&&video.contains($0)}
            let other=formats.filter{!image.contains($0) && !audio.contains($0) && !video.contains($0)}
            return [ChoiceGroup(id:"images",title:"Images",choices:choices(images)),ChoiceGroup(id:"audio",title:"Audio",choices:choices(sounds)),ChoiceGroup(id:"video",title:"Video",choices:choices(movies)),ChoiceGroup(id:"other",title:"Documents and other",choices:choices(other))].filter{!$0.choices.isEmpty}
        case .tools:
            return [ChoiceGroup(id:"tools",title:"File tools wheel",choices:WheelContentPreferences.allTools.map{Choice(id:$0.rawValue,title:FeatureCatalog.toolNames[$0] ?? $0.title,symbol:FeatureCatalog.toolSymbols[$0],localized:true)})]
        case .actions:
            return [ChoiceGroup(id:"actions",title:"File actions wheel",choices:FileAction.allCases.map{Choice(id:$0.rawValue,title:$0.title,symbol:$0.symbol,localized:true)})]
        }
    }
    var body:some View {
        let all=groups.flatMap(\.choices)
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                VStack(alignment:.leading,spacing:6) {
                    Text("Wheel contents").font(.system(size:24,weight:.bold,design:.rounded))
                    Text("Choose what each wheel shows. Unchecked items are hidden; if nothing is left for a file, the wheel shows everything.").font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                }
                Picker("",selection:$mode) {
                    LText("Conversion wheel").tag(WheelMode.convert)
                    LText("File tools wheel").tag(WheelMode.tools)
                    LText("File actions wheel").tag(WheelMode.actions)
                }.pickerStyle(.segmented).labelsHidden()
                HStack {
                    Text("Shown: \(all.filter{!hidden.contains($0.id)}.count) / \(all.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    Spacer()
                    Button("Show all") { update([]) }.disabled(hidden.isEmpty)
                }
                ForEach(groups) { group in
                    GroupBox {
                        LazyVGrid(columns:[GridItem(.adaptive(minimum:mode == .convert ? 92:190),spacing:8,alignment:.leading)],alignment:.leading,spacing:8) {
                            ForEach(group.choices) { choice in
                                Toggle(isOn:Binding(get:{!hidden.contains(choice.id)},set:{shown in update(shown ? hidden.subtracting([choice.id]):hidden.union([choice.id]))})) {
                                    HStack(spacing:6) {
                                        if let symbol=choice.symbol { Image(systemName:symbol).frame(width:16).foregroundStyle(NashiPalette.forest) }
                                        if choice.localized { LText(choice.title).lineLimit(1) } else { Text(verbatim:choice.title).lineLimit(1) }
                                    }.font(.system(size:12,weight:.medium))
                                }.toggleStyle(.checkbox)
                            }
                        }.frame(maxWidth:.infinity,alignment:.leading)
                    } label:{ LText(group.title).font(.headline) }
                }
            }.padding(28)
        }
        .onChange(of:mode) { hidden=WheelContentPreferences.hidden($0) }
    }
    private func update(_ ids:Set<String>) {
        hidden=ids;WheelContentPreferences.setHidden(ids,for:mode)
    }
}
