import SwiftUI

struct WeaponSimulatorLauncher: View {
    let weaponCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .trailing) {
                LinearGradient(
                    colors: [Color.apexRed.opacity(0.34), Color.white.opacity(0.055)],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                ApexSlashPattern()
                    .foregroundStyle(.white.opacity(0.045))
                    .frame(width: 150)
                    .accessibilityHidden(true)

                HStack(spacing: 14) {
                    Image(systemName: "waveform.path.ecg.rectangle.fill")
                        .font(.system(size: 21, weight: .bold))
                        .foregroundStyle(Color.apexRed)
                        .frame(width: 46, height: 46)
                        .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 13))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("COMBAT SIMULATOR")
                            .font(.caption.weight(.black))
                            .tracking(1.15)
                            .foregroundStyle(.white.opacity(0.56))

                        Text("Run a custom hit mix")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)

                        Text("HEAD · BODY · LEGS")
                            .font(.caption2.monospacedDigit().weight(.bold))
                            .tracking(0.35)
                            .foregroundStyle(.white.opacity(0.38))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "arrow.up.right")
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(.white.opacity(0.74))
                        .frame(width: 44, height: 44)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 4,
                    bottomLeadingRadius: 18,
                    bottomTrailingRadius: 4,
                    topTrailingRadius: 18,
                    style: .continuous
                )
            )
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.apexRed)
                    .frame(width: 3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(SimulatorPressStyle())
        .accessibilityLabel("Run combat simulator")
        .accessibilityHint("Choose armor and hit locations, then compare \(weaponCount) verified weapons or pick one")
    }
}

struct WeaponSimulatorView: View {
    private enum WeaponChoiceMode: String, CaseIterable, Identifiable {
        case best
        case selected

        var id: String { rawValue }

        var title: String {
            switch self {
            case .best: "Find Best"
            case .selected: "Pick Weapon"
            }
        }

        var symbol: String {
            switch self {
            case .best: "trophy.fill"
            case .selected: "scope"
            }
        }
    }

    struct Result: Identifiable {
        var id: String { weapon.id }

        let weapon: WeaponStat
        let averageDamage: Double
        let shots: Int
        let ttk: Double
        let mixedDPS: Double
        let fitsInMagazine: Bool
    }

    @Environment(\.dismiss) private var dismiss
    @State private var selectedHealth: WeaponTargetHealth
    @State private var choiceMode: WeaponChoiceMode = .best
    @State private var selectedWeaponID: String
    @State private var hitMix = WeaponHitMix.bodyOnly

    let weapons: [WeaponStat]

    init(
        weapons: [WeaponStat],
        initialHealth: WeaponTargetHealth,
        initialWeaponID: String?
    ) {
        self.weapons = weapons
        _selectedHealth = State(initialValue: initialHealth)
        _selectedWeaponID = State(initialValue: initialWeaponID ?? weapons.first?.id ?? "")
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--simulator-mixed-hits") {
            _hitMix = State(initialValue: WeaponHitMix(head: 2, body: 7, legs: 1))
        }
        if ProcessInfo.processInfo.arguments.contains("--simulator-picked-weapon") {
            _choiceMode = State(initialValue: .selected)
        }
#endif
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    simulatorHeader
                    defenseSection
                    weaponSection
                    hitMixSection
                    resultSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
        }
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(red: 0.025, green: 0.027, blue: 0.035))
        .sensoryFeedback(.selection, trigger: selectedHealth)
        .sensoryFeedback(.selection, trigger: choiceMode)
        .sensoryFeedback(.selection, trigger: hitMix)
    }

    private var simulatorHeader: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .center, spacing: 12) {
                Text("COMBAT SIMULATOR")
                    .font(.caption.weight(.black))
                    .tracking(1.6)
                    .foregroundStyle(Color.apexRed)

                Spacer(minLength: 4)

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.black))
                        .foregroundStyle(Color.apexRed)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close simulator")
            }

            Text("Build the gunfight")
                .font(.largeTitle.weight(.black))
                .foregroundStyle(.white)

            Text("Compare expected time to kill using your own landed-shot mix.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.52))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var defenseSection: some View {
        SimulatorSection(title: "DEFENSE", trailing: "100 HEALTH + SHIELD") {
            HStack(spacing: 8) {
                ForEach(WeaponTargetHealth.allCases) { target in
                    Button {
                        selectedHealth = target
                    } label: {
                        VStack(spacing: 2) {
                            Text(target.rawValue, format: .number)
                                .font(.subheadline.monospacedDigit().weight(.black))

                            Text(target.label)
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(selectedHealth == target ? .white : .white.opacity(0.52))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background {
                            if selectedHealth == target {
                                UnevenRoundedRectangle(
                                    topLeadingRadius: 4,
                                    bottomLeadingRadius: 13,
                                    bottomTrailingRadius: 4,
                                    topTrailingRadius: 13,
                                    style: .continuous
                                )
                                .fill(Color.apexRed)
                            } else {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.white.opacity(0.06))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .accessibilityLabel("\(target.label) armor, \(target.rawValue) total health")
                    .accessibilityAddTraits(selectedHealth == target ? .isSelected : [])
                }
            }
        }
    }

    private var weaponSection: some View {
        SimulatorSection(title: "WEAPON", trailing: "\(weapons.count) VERIFIED") {
            HStack(spacing: 8) {
                ForEach(WeaponChoiceMode.allCases) { mode in
                    Button {
                        choiceMode = mode
                    } label: {
                        Label(mode.title, systemImage: mode.symbol)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(choiceMode == mode ? .white : .white.opacity(0.52))
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(
                                choiceMode == mode
                                    ? Color.apexRed.opacity(0.82)
                                    : Color.white.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .accessibilityAddTraits(choiceMode == mode ? .isSelected : [])
                }
            }

            if choiceMode == .selected {
                Menu {
                    ForEach(weapons.sorted { $0.name < $1.name }) { weapon in
                        Button {
                            selectedWeaponID = weapon.id
                        } label: {
                            if selectedWeaponID == weapon.id {
                                Label(weapon.name, systemImage: "checkmark")
                            } else {
                                Text(weapon.name)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "scope")
                            .foregroundStyle(Color.apexRed)

                        Text(selectedWeapon?.name ?? "Choose a weapon")
                            .font(.body.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Spacer()

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.white.opacity(0.42))
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Selected weapon, \(selectedWeapon?.name ?? "none")")
            }
        }
    }

    private var hitMixSection: some View {
        SimulatorSection(title: "LANDED HIT MIX", trailing: mixSummary) {
            Text("Use relative hits. For example, 2 head / 7 body / 1 legs becomes a 20 / 70 / 10 mix.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.44))
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                HitMixRow(
                    title: "Head",
                    symbol: "brain.head.profile",
                    value: hitMix.head,
                    percentage: percentage(for: hitMix.head),
                    canDecrement: canDecrement(hitMix.head),
                    canIncrement: hitMix.head < 10,
                    decrement: { hitMix.head -= 1 },
                    increment: { hitMix.head += 1 }
                )

                Divider().overlay(.white.opacity(0.07))

                HitMixRow(
                    title: "Body",
                    symbol: "figure.arms.open",
                    value: hitMix.body,
                    percentage: percentage(for: hitMix.body),
                    canDecrement: canDecrement(hitMix.body),
                    canIncrement: hitMix.body < 10,
                    decrement: { hitMix.body -= 1 },
                    increment: { hitMix.body += 1 }
                )

                Divider().overlay(.white.opacity(0.07))

                HitMixRow(
                    title: "Legs",
                    symbol: "figure.walk",
                    value: hitMix.legs,
                    percentage: percentage(for: hitMix.legs),
                    canDecrement: canDecrement(hitMix.legs),
                    canIncrement: hitMix.legs < 10,
                    decrement: { hitMix.legs -= 1 },
                    increment: { hitMix.legs += 1 }
                )
            }
            .padding(.horizontal, 12)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))

            Text("Head damage is unhelmeted. Fortified, damage falloff, misses, and reload time are not modeled.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.34))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var resultSection: some View {
        if let result = visibleResults.first {
            SimulatorResultCard(
                result: result,
                targetHealth: selectedHealth.rawValue,
                choiceModeLabel: choiceMode == .best ? "BEST MATCH" : "SIMULATION"
            )

            if choiceMode == .best, visibleResults.count > 1 {
                VStack(alignment: .leading, spacing: 0) {
                    Text("NEXT FASTEST")
                        .font(.caption.weight(.black))
                        .tracking(1.25)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.bottom, 8)

                    ForEach(Array(visibleResults.dropFirst().prefix(2).enumerated()), id: \.element.id) { index, result in
                        HStack(spacing: 12) {
                            Text(index + 2, format: .number)
                                .font(.caption.monospacedDigit().weight(.black))
                                .foregroundStyle(Color.apexRed)
                                .frame(width: 22, alignment: .trailing)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.weapon.name)
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(.white)

                                Text("\(result.shots) EXPECTED SHOTS · \(result.averageDamage.compactStat) AVG DMG")
                                    .font(.caption2.monospacedDigit().weight(.medium))
                                    .foregroundStyle(.white.opacity(0.4))
                            }

                            Spacer()

                            Text("\(result.ttk, specifier: "%.2f")s")
                                .font(.headline.monospacedDigit().weight(.black))
                                .foregroundStyle(.white)
                        }
                        .padding(.vertical, 11)

                        if index == 0 {
                            Divider().overlay(.white.opacity(0.07))
                        }
                    }
                }
            }
        } else {
            ContentUnavailableView(
                "No comparable result",
                systemImage: "waveform.path.ecg",
                description: Text("Add at least one landed hit to the mix.")
            )
            .frame(minHeight: 240)
        }
    }

    private var selectedWeapon: WeaponStat? {
        weapons.first(where: { $0.id == selectedWeaponID }) ?? weapons.first
    }

    private var visibleResults: [Result] {
        let candidates: [WeaponStat]
        switch choiceMode {
        case .best:
            candidates = weapons
        case .selected:
            candidates = selectedWeapon.map { [$0] } ?? []
        }

        let results = candidates.compactMap(result(for:)).sorted { left, right in
            if abs(left.ttk - right.ttk) > 0.000_1 {
                return left.ttk < right.ttk
            }
            return left.mixedDPS > right.mixedDPS
        }

        guard choiceMode == .best else { return results }
        let singleMagazineResults = results.filter(\.fitsInMagazine)
        return singleMagazineResults.isEmpty ? results : singleMagazineResults
    }

    private func result(for weapon: WeaponStat) -> Result? {
        guard let averageDamage = weapon.expectedDamage(for: hitMix),
              let shots = weapon.expectedShots(
                toEliminate: selectedHealth.rawValue,
                mix: hitMix
              ),
              let ttk = weapon.expectedTTK(
                targetHealth: selectedHealth.rawValue,
                mix: hitMix
              ) else { return nil }

        return Result(
            weapon: weapon,
            averageDamage: averageDamage,
            shots: shots,
            ttk: ttk,
            mixedDPS: averageDamage * weapon.roundsPerMinute / 60,
            fitsInMagazine: weapon.expectedKillFitsInBaseMagazine(
                targetHealth: selectedHealth.rawValue,
                mix: hitMix
            )
        )
    }

    private var mixSummary: String {
        "\(percentage(for: hitMix.head)) / \(percentage(for: hitMix.body)) / \(percentage(for: hitMix.legs))"
    }

    private func percentage(for value: Int) -> Int {
        guard hitMix.total > 0 else { return 0 }
        return Int((Double(value) / Double(hitMix.total) * 100).rounded())
    }

    private func canDecrement(_ value: Int) -> Bool {
        value > 0 && hitMix.total > 1
    }
}

private struct SimulatorSection<Content: View>: View {
    let title: String
    let trailing: String
    @ViewBuilder let content: Content

    init(
        title: String,
        trailing: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.caption.weight(.black))
                    .tracking(1.25)
                    .foregroundStyle(.white.opacity(0.54))

                Spacer(minLength: 8)

                Text(trailing)
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .tracking(0.35)
                    .foregroundStyle(.white.opacity(0.32))
                    .multilineTextAlignment(.trailing)
            }

            content
        }
    }
}

private struct HitMixRow: View {
    let title: String
    let symbol: String
    let value: Int
    let percentage: Int
    let canDecrement: Bool
    let canIncrement: Bool
    let decrement: () -> Void
    let increment: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color.apexRed)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)

                Text("\(percentage)% OF LANDED HITS")
                    .font(.caption2.monospacedDigit().weight(.bold))
                    .foregroundStyle(.white.opacity(0.36))
            }

            Spacer(minLength: 4)

            Button(action: decrement) {
                Image(systemName: "minus")
                    .font(.caption.weight(.black))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(canDecrement ? .white.opacity(0.72) : .white.opacity(0.18))
            .disabled(!canDecrement)
            .accessibilityLabel("Decrease \(title.lowercased()) hits")

            Text(value, format: .number)
                .font(.headline.monospacedDigit().weight(.black))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: 32)
                .contentTransition(.numericText())
                .accessibilityLabel("\(value) relative \(title.lowercased()) hits")

            Button(action: increment) {
                Image(systemName: "plus")
                    .font(.caption.weight(.black))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(canIncrement ? .white : .white.opacity(0.18))
            .disabled(!canIncrement)
            .accessibilityLabel("Increase \(title.lowercased()) hits")
        }
        .frame(minHeight: 58)
    }
}

private struct SimulatorResultCard: View {
    let result: WeaponSimulatorView.Result
    let targetHealth: Int
    let choiceModeLabel: String

    var body: some View {
        ZStack(alignment: .trailing) {
            LinearGradient(
                colors: [Color.apexRed.opacity(0.5), Color.black.opacity(0.88)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            ApexSlashPattern()
                .foregroundStyle(.white.opacity(0.055))
                .frame(width: 190)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(choiceModeLabel)
                        .font(.caption2.weight(.black))
                        .tracking(1.25)
                        .foregroundStyle(.white.opacity(0.62))

                    Spacer()

                    Text("\(targetHealth) HP")
                        .font(.caption.monospacedDigit().weight(.black))
                        .foregroundStyle(.white.opacity(0.7))
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .lastTextBaseline, spacing: 14) {
                        weaponName
                        Spacer(minLength: 8)
                        ttk
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        weaponName
                        ttk
                    }
                }

                HStack(spacing: 0) {
                    SimulatorMetric(value: result.averageDamage.compactStat, label: "AVG DMG")
                    SimulatorMetric(value: result.shots.formatted(), label: "SHOTS")
                    SimulatorMetric(value: result.mixedDPS.compactStat, label: "MIX DPS")
                }

                HStack(spacing: 12) {
                    DamageZoneValue(label: "HEAD", value: result.weapon.headDamage)
                    DamageZoneValue(label: "BODY", value: result.weapon.bodyDamage)
                    DamageZoneValue(label: "LEGS", value: result.weapon.legDamage)
                }

                if !result.fitsInMagazine {
                    Label("Base magazine requires a reload", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.yellow.opacity(0.86))
                }
            }
            .padding(20)
        }
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 4,
                bottomLeadingRadius: 24,
                bottomTrailingRadius: 4,
                topTrailingRadius: 24,
                style: .continuous
            )
        )
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.apexRed)
                .frame(width: 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(choiceModeLabel), \(result.weapon.name), \(result.ttk.formatted(.number.precision(.fractionLength(2)))) second expected time to kill, \(result.shots) shots, \(result.averageDamage.compactStat) average damage"
        )
    }

    private var weaponName: some View {
        Text(result.weapon.name)
            .font(.system(.title, design: .rounded, weight: .black))
            .foregroundStyle(.white)
            .lineLimit(2)
            .minimumScaleFactor(0.78)
    }

    private var ttk: some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text(result.ttk, format: .number.precision(.fractionLength(2)))
                .font(.system(size: 44, weight: .black, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())

            Text("SEC")
                .font(.caption2.weight(.black))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.54))
        }
        .foregroundStyle(.white)
    }
}

private struct SimulatorMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.black))
                .foregroundStyle(.white)

            Text(label)
                .font(.caption2.weight(.bold))
                .tracking(0.65)
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DamageZoneValue: View {
    let label: String
    let value: Double

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.caption2.weight(.black))
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.4))

            Text(value.compactStat)
                .font(.caption.monospacedDigit().weight(.black))
                .foregroundStyle(.white.opacity(0.82))
        }
    }
}

private struct SimulatorPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
