import AppIntents
import WidgetKit

enum RotationModeChoice: String, AppEnum {
    case ranked
    case pubs

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Mode"
    static var caseDisplayRepresentations: [RotationModeChoice: DisplayRepresentation] = [
        .ranked: DisplayRepresentation(title: "Ranked", image: .init(systemName: "shield.lefthalf.filled")),
        .pubs: DisplayRepresentation(title: "Pubs", image: .init(systemName: "person.3.fill"))
    ]

    var modeID: String {
        switch self {
        case .ranked: "ranked"
        case .pubs: "battle_royale"
        }
    }
}

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Apex Map Rotation" }
    static var description: IntentDescription { "Choose the rotation shown in compact widgets." }

    @Parameter(title: "Mode", default: .ranked)
    var mode: RotationModeChoice
}
