import SwiftUI

struct LegendsScreen: View {
    @State private var model = LegendPickRatesViewModel()

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    ScreenHeader(eyebrow: "CURRENT META", title: "Legend Picks")

                    rankPicker

                    if model.isLoading, model.snapshot == nil {
                        LoadingPickRatesView()
                    } else if let snapshot = model.snapshot {
                        leaderboard(snapshot)
                    } else {
                        PickRatesFailureView(message: model.errorMessage) {
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
        }
        .task {
            if model.snapshot == nil {
                await model.load()
            }
        }
    }

    private var rankPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(LegendRank.allCases) { rank in
                    Button {
                        Task { await model.select(rank) }
                    } label: {
                        Text(rank.title)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(model.selectedRank == rank ? .white : .white.opacity(0.62))
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(
                                model.selectedRank == rank
                                    ? Color.apexRed
                                    : Color.white.opacity(0.07),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isLoading)
                    .accessibilityAddTraits(model.selectedRank == rank ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 1, for: .scrollContent)
    }

    @ViewBuilder
    private func leaderboard(_ snapshot: LegendPickRateSnapshot) -> some View {
        if let message = model.errorMessage {
            ErrorBanner(message: message) {
                Task { await model.load(force: true) }
            }
        }

        if let leader = snapshot.legends.first {
            MetaLeaderCard(legend: leader, rank: model.selectedRank)
        }

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text("PICK RATE LEADERBOARD")
                    .font(.caption.weight(.black))
                    .tracking(1.25)
                    .foregroundStyle(.white.opacity(0.52))

                Spacer()

                if let sample = snapshot.sampleDescription {
                    Text("\(sample) players")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.42))
                }
            }
            .padding(.bottom, 8)

            ForEach(Array(snapshot.legends.enumerated()), id: \.element.id) { index, legend in
                LegendPickRateRow(
                    position: index + 1,
                    legend: legend,
                    maximumRate: snapshot.legends.first?.pickRate ?? 1
                )

                if index != snapshot.legends.indices.last {
                    Divider()
                        .overlay(.white.opacity(0.07))
                }
            }
        }

        VStack(spacing: 8) {
            Text("Updated \(snapshot.fetchedAt, style: .relative)")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.48))

            Link(
                "Data provided by Apex Legends Status",
                destination: URL(string: "https://apexlegendsstatus.com")!
            )
            .font(.caption.weight(.medium))
            .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

private struct MetaLeaderCard: View {
    let legend: LegendPickRate
    let rank: LegendRank

    var body: some View {
        ZStack(alignment: .trailing) {
            LinearGradient(
                colors: [Color(hex: legend.colorHex).opacity(0.48), .black.opacity(0.78)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            ApexSlashPattern()
                .foregroundStyle(.white.opacity(0.06))
                .frame(width: 180)
                .accessibilityHidden(true)

            HStack(alignment: .center, spacing: 18) {
                Text("01")
                    .font(.system(size: 54, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.16))

                VStack(alignment: .leading, spacing: 3) {
                    Text("MOST PICKED · \(rank.title.uppercased())")
                        .font(.caption2.weight(.black))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.62))

                    Text(legend.name)
                        .font(.system(.title, design: .rounded, weight: .black))
                        .foregroundStyle(.white)
                }

                Spacer()

                Text(legend.pickRate, format: .number.precision(.fractionLength(1)))
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .overlay(alignment: .topTrailing) {
                        Text("%")
                            .font(.caption.weight(.black))
                            .offset(x: 10, y: 2)
                    }
                    .padding(.trailing, 10)
            }
            .padding(20)
        }
        .frame(minHeight: 124)
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(legend.name), most picked at \(legend.pickRate, specifier: "%.1f") percent")
    }
}

private struct LegendPickRateRow: View {
    let position: Int
    let legend: LegendPickRate
    let maximumRate: Double

    var body: some View {
        HStack(spacing: 12) {
            Text(position, format: .number)
                .font(.caption.monospacedDigit().weight(.bold))
                .foregroundStyle(position <= 3 ? Color.apexRed : .white.opacity(0.36))
                .frame(width: 24, alignment: .trailing)

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(legend.name)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)

                    Spacer()

                    Text("\(legend.pickRate, specifier: "%.1f")%")
                        .font(.subheadline.monospacedDigit().weight(.black))
                        .foregroundStyle(.white)
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.07))

                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: legend.colorHex), Color.apexRed],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(
                                width: proxy.size.width
                                    * max(0.025, legend.pickRate / max(maximumRate, 0.1))
                            )
                    }
                }
                .frame(height: 5)
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Rank \(position), \(legend.name), \(legend.pickRate, specifier: "%.1f") percent pick rate"
        )
    }
}

private struct LoadingPickRatesView: View {
    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
            Text("Reading the current meta…")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.62))
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }
}

private struct PickRatesFailureView: View {
    let message: String?
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Couldn’t load pick rates", systemImage: "chart.bar.xaxis")
        } description: {
            Text(message ?? "The current meta is temporarily unavailable.")
        } actions: {
            Button("Try again", action: retry)
                .buttonStyle(.borderedProminent)
                .tint(.apexRed)
        }
        .frame(minHeight: 420)
    }
}

extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let value = UInt64(clean, radix: 16) ?? 0xD61F23
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
