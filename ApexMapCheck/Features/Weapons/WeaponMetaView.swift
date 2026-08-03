import SwiftUI

struct WeaponMetaScreen: View {
    @State private var model = WeaponMetaViewModel()
    @State private var isSimulatorPresented = false

    init() {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--show-weapon-simulator") {
            _isSimulatorPresented = State(initialValue: true)
        }
#endif
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ScreenHeader(eyebrow: "WEAPON META", title: "TTK Lab")

                    if let snapshot = model.snapshot {
                        WeaponSimulatorLauncher(weaponCount: snapshot.weapons.count) {
                            isSimulatorPresented = true
                        }
                    }

                    targetPicker

                    if model.isLoading, model.snapshot == nil {
                        LoadingWeaponMetaView()
                    } else if let snapshot = model.snapshot {
                        weaponContent(snapshot)
                    } else {
                        WeaponMetaFailureView(message: model.errorMessage) {
                            Task { await model.load(force: true) }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
            .refreshable {
                await model.load(force: true)
            }
            .scrollIndicators(.hidden)
            .apexNavigationScrollClearance()

            WeaponMetaScrollEdgeScrim()
        }
        .task {
            if model.snapshot == nil {
                await model.load()
            }
        }
        .sheet(isPresented: $isSimulatorPresented) {
            if let snapshot = model.snapshot {
                WeaponSimulatorView(
                    weapons: snapshot.weapons,
                    initialHealth: model.selectedHealth,
                    initialWeaponID: model.rankedWeapons.first?.id
                )
            }
        }
    }

    private var targetPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("TARGET HEALTH")
                    .font(.caption.weight(.black))
                    .tracking(1.25)
                    .foregroundStyle(.white.opacity(0.52))

                Spacer()

                Text("BODY SHOTS")
                    .font(.caption2.weight(.bold))
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.34))
            }

            HStack(spacing: 8) {
                ForEach(WeaponTargetHealth.allCases) { target in
                    Button {
                        withAnimation(.easeOut(duration: 0.18)) {
                            model.selectedHealth = target
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Text(target.rawValue, format: .number)
                                .font(.subheadline.monospacedDigit().weight(.black))

                            Text(target.label)
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(
                            model.selectedHealth == target ? .white : .white.opacity(0.54)
                        )
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .background {
                            if model.selectedHealth == target {
                                UnevenRoundedRectangle(
                                    topLeadingRadius: 4,
                                    bottomLeadingRadius: 14,
                                    bottomTrailingRadius: 4,
                                    topTrailingRadius: 14,
                                    style: .continuous
                                )
                                .fill(Color.apexRed)
                            } else {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(.white.opacity(0.065))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .accessibilityLabel("\(target.label) armor, \(target.rawValue) total health")
                    .accessibilityAddTraits(model.selectedHealth == target ? .isSelected : [])
                }
            }
        }
    }

    @ViewBuilder
    private func weaponContent(_ snapshot: WeaponMetaSnapshot) -> some View {
        if let warning = model.refreshWarning {
            ErrorBanner(message: warning) {
                Task { await model.load(force: true) }
            }
        }

        classPicker

        if let leader = model.rankedWeapons.first {
            WeaponLeaderCard(
                weapon: leader,
                targetHealth: model.selectedHealth.rawValue
            )

            WeaponLeaderboard(
                weapons: model.rankedWeapons,
                targetHealth: model.selectedHealth.rawValue
            )
        } else {
            ContentUnavailableView(
                "No weapons found",
                systemImage: "scope",
                description: Text("Try another weapon class.")
            )
            .frame(minHeight: 320)
        }

        WeaponMetaSourceView(snapshot: snapshot)
    }

    private var classPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                WeaponClassButton(
                    title: "All",
                    isSelected: model.selectedClass == nil,
                    action: {
                        withAnimation(.easeOut(duration: 0.18)) {
                            model.selectedClass = nil
                        }
                    }
                )

                ForEach(WeaponClass.allCases) { weaponClass in
                    WeaponClassButton(
                        title: weaponClass.title,
                        isSelected: model.selectedClass == weaponClass,
                        action: {
                            withAnimation(.easeOut(duration: 0.18)) {
                                model.selectedClass = weaponClass
                            }
                        }
                    )
                }
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 1, for: .scrollContent)
    }
}

private struct WeaponMetaScrollEdgeScrim: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                stops: [
                    .init(
                        color: Color(red: 0.055, green: 0.024, blue: 0.03),
                        location: 0
                    ),
                    .init(
                        color: Color(red: 0.04, green: 0.025, blue: 0.032).opacity(0.88),
                        location: 0.55
                    ),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 38)
            .ignoresSafeArea(edges: .top)

            Spacer(minLength: 0)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct WeaponClassButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(isSelected ? .white : .white.opacity(0.58))
                .padding(.horizontal, 15)
                .frame(minHeight: 44)
                .background(
                    isSelected ? Color.apexRed : Color.white.opacity(0.065),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct WeaponLeaderCard: View {
    let weapon: WeaponStat
    let targetHealth: Int

    private var ttk: Double {
        weapon.idealBodyTTK(targetHealth: targetHealth)
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            LinearGradient(
                colors: [Color.apexRed.opacity(0.48), Color.black.opacity(0.86)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            ApexSlashPattern()
                .foregroundStyle(.white.opacity(0.055))
                .frame(width: 190)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("FASTEST · \(weapon.weaponClass.title.uppercased())")
                        .font(.caption2.weight(.black))
                        .tracking(1.25)
                        .foregroundStyle(.white.opacity(0.62))

                    Spacer()

                    Text("\(targetHealth) HP")
                        .font(.caption.monospacedDigit().weight(.black))
                        .foregroundStyle(.white.opacity(0.72))
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .lastTextBaseline, spacing: 16) {
                        weaponName
                        Spacer(minLength: 12)
                        ttkValue
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        weaponName
                        ttkValue
                    }
                }

                HStack(spacing: 0) {
                    WeaponMetric(
                        value: weapon.bodyShots(toEliminate: targetHealth).formatted(),
                        label: "BODY SHOTS"
                    )
                    WeaponMetric(
                        value: weapon.bodyDamage.compactStat,
                        label: "DAMAGE"
                    )
                    WeaponMetric(
                        value: weapon.roundsPerMinute.compactStat,
                        label: weapon.usesPeakValues ? "PEAK RPM" : "RPM"
                    )
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
            "Fastest ideal body time to kill: \(weapon.name), \(ttk.formatted(.number.precision(.fractionLength(2)))) seconds against \(targetHealth) health, \(weapon.bodyShots(toEliminate: targetHealth)) body shots"
        )
    }

    private var weaponName: some View {
        Text(weapon.name)
            .font(.system(.title, design: .rounded, weight: .black))
            .foregroundStyle(.white)
            .lineLimit(2)
            .minimumScaleFactor(0.78)
    }

    private var ttkValue: some View {
        HStack(alignment: .lastTextBaseline, spacing: 4) {
            Text(ttk, format: .number.precision(.fractionLength(2)))
                .font(.system(size: 46, weight: .black, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())

            Text("SEC")
                .font(.caption2.weight(.black))
                .tracking(1)
                .foregroundStyle(.white.opacity(0.56))
        }
        .foregroundStyle(.white)
    }
}

private struct WeaponMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.black))
                .foregroundStyle(.white)

            Text(label)
                .font(.caption2.weight(.bold))
                .tracking(0.75)
                .foregroundStyle(.white.opacity(0.42))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WeaponLeaderboard: View {
    let weapons: [WeaponStat]
    let targetHealth: Int

    private var fastestTTK: Double {
        weapons.first?.idealBodyTTK(targetHealth: targetHealth) ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("IDEAL BODY TTK")
                    .font(.caption.weight(.black))
                    .tracking(1.25)
                    .foregroundStyle(.white.opacity(0.52))

                Spacer()

                Text("LOWER IS FASTER")
                    .font(.caption2.weight(.bold))
                    .tracking(0.7)
                    .foregroundStyle(.white.opacity(0.34))
            }
            .padding(.bottom, 8)

            ForEach(Array(weapons.enumerated()), id: \.element.id) { index, weapon in
                WeaponMetaRow(
                    position: index + 1,
                    weapon: weapon,
                    targetHealth: targetHealth,
                    fastestTTK: fastestTTK
                )

                if index != weapons.indices.last {
                    Divider()
                        .overlay(.white.opacity(0.07))
                }
            }
        }
    }
}

private struct WeaponMetaRow: View {
    let position: Int
    let weapon: WeaponStat
    let targetHealth: Int
    let fastestTTK: Double

    private var ttk: Double {
        weapon.idealBodyTTK(targetHealth: targetHealth)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(position, format: .number)
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(position <= 3 ? Color.apexRed : .white.opacity(0.34))
                .frame(width: 25, alignment: .trailing)

            VStack(alignment: .leading, spacing: 7) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        identity
                        Spacer(minLength: 8)
                        ttkLabel
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        identity
                        ttkLabel
                    }
                }

                GeometryReader { proxy in
                    Capsule()
                        .fill(.white.opacity(0.07))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.apexRed, Color.apexRed.opacity(0.5)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(
                                    width: proxy.size.width
                                        * max(0.08, min(1, fastestTTK / max(ttk, 0.01)))
                                )
                        }
                }
                .frame(height: 4)
            }
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(weapon.name)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(2)

            Text(detailText)
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(
                    weapon.fitsInBaseMagazine(targetHealth: targetHealth)
                        ? .white.opacity(0.42)
                        : Color.yellow.opacity(0.82)
                )
        }
    }

    private var ttkLabel: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("\(ttk, specifier: "%.2f")s")
                .font(.headline.monospacedDigit().weight(.black))
                .foregroundStyle(.white)
                .contentTransition(.numericText())

            Text("\(weapon.damagePerSecond.compactStat) DPS")
                .font(.caption2.monospacedDigit().weight(.bold))
                .foregroundStyle(.white.opacity(0.38))
        }
    }

    private var detailText: String {
        let shots = weapon.bodyShots(toEliminate: targetHealth)
        let base = "\(weapon.weaponClass.title.uppercased()) · \(shots) SHOTS · \(weapon.bodyDamage.compactStat) DMG"
        return weapon.fitsInBaseMagazine(targetHealth: targetHealth)
            ? base
            : "\(base) · RELOAD"
    }

    private var accessibilityDescription: String {
        let reload = weapon.fitsInBaseMagazine(targetHealth: targetHealth)
            ? ""
            : ", requires a reload with the base magazine"
        return "Rank \(position), \(weapon.name), \(ttk.formatted(.number.precision(.fractionLength(2)))) second ideal body time to kill, \(weapon.bodyShots(toEliminate: targetHealth)) shots, \(weapon.damagePerSecond.compactStat) damage per second\(reload)"
    }
}

private struct WeaponMetaSourceView: View {
    let snapshot: WeaponMetaSnapshot

    var body: some View {
        VStack(spacing: 9) {
            Text("Updated \(snapshot.fetchedAt, style: .relative)")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.48))

            Text("Read from each weapon’s current wiki page. Weapons without directly comparable body damage and fire-rate values are omitted. Real TTK still varies with charge-up, acceleration, burst behavior, armor perks, accuracy, and latency.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.42))
                .frame(maxWidth: 430)

            Link(
                "Weapon pages on the Apex Legends Wiki",
                destination: URL(string: "https://apexlegends.wiki.gg/wiki/Weapon")!
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

private struct LoadingWeaponMetaView: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(.white)

            Text("Reading the current weapon pages…")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }
}

private struct WeaponMetaFailureView: View {
    let message: String?
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Couldn’t load weapon stats", systemImage: "scope")
        } description: {
            Text(message ?? "Weapon stats are temporarily unavailable.")
        } actions: {
            Button("Try again", action: retry)
                .buttonStyle(.borderedProminent)
                .tint(.apexRed)
        }
        .frame(minHeight: 420)
    }
}

extension Double {
    var compactStat: String {
        formatted(.number.precision(.fractionLength(0...1)))
    }
}
