import SwiftUI

// MARK: - Anti-Stalker Tracker Detection View
//
// Shows detected Bluetooth trackers that may be following the user.
// Displays threat scores, sighting history, and allows whitelisting.

struct TrackerDetectionView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @ObservedObject private var lang = LanguageManager.shared
    @ObservedObject private var detectionService = TrackerDetectionService.shared
    @Environment(\.dismiss) private var dismiss

    private let ink = Color(red: 18/255, green: 32/255, blue: 58/255)
    private let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private let alert = Color(red: 196/255, green: 69/255, blue: 60/255)
    private let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)

    @State private var showIgnoreConfirm = false
    @State private var trackerToIgnore: DetectedTracker?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Scan status bar
                HStack(spacing: 8) {
                    if detectionService.isScanning {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text(lang.localized("tracker.scanning"))
                            .font(.scaled(size: 13))
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .font(.scaled(size: 14))
                            .foregroundStyle(.secondary)
                        Text(lang.localized("tracker.notScanning"))
                            .font(.scaled(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        if detectionService.isScanning {
                            detectionService.stop()
                        } else {
                            detectionService.start()
                        }
                    } label: {
                        Text(detectionService.isScanning
                             ? lang.localized("tracker.stop")
                             : lang.localized("tracker.start"))
                            .font(.scaled(size: 13, weight: .medium))
                            .foregroundStyle(safe)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground))

                if detectionService.detectedTrackers.isEmpty {
                    emptyState
                } else {
                    trackerList
                }
            }
            .background(Color(.systemBackground))
            .navigationTitle(lang.localized("tracker.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(lang.localized("duress.close")) { dismiss() }
                }
            }
            .alert(lang.localized("tracker.ignore.title"), isPresented: $showIgnoreConfirm) {
                Button(lang.localized("tracker.ignore.confirm")) {
                    if let tracker = trackerToIgnore {
                        detectionService.ignoreTracker(peripheralId: tracker.peripheralId)
                    }
                }
                Button(lang.localized("settings.action.cancel"), role: .cancel) {}
            } message: {
                Text(lang.localized("tracker.ignore.message"))
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "shield.checkered")
                .font(.system(size: 48))
                .foregroundStyle(safe.opacity(0.5))
            Text(lang.localized("tracker.empty.title"))
                .font(.scaled(size: 18, weight: .semibold))
                .foregroundStyle(ink)
            Text(lang.localized("tracker.empty.body"))
                .font(.scaled(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: - Tracker List

    private var trackerList: some View {
        ScrollView {
            VStack(spacing: 8) {
                let critical = detectionService.detectedTrackers.filter { $0.threatScore >= 70 }
                let warnings = detectionService.detectedTrackers.filter { $0.threatScore >= 40 && $0.threatScore < 70 }
                let low = detectionService.detectedTrackers.filter { $0.threatScore < 40 }

                if !critical.isEmpty {
                    sectionHeader(lang.localized("tracker.section.critical"), color: alert)
                    ForEach(critical) { tracker in
                        trackerCard(tracker, borderColor: alert)
                    }
                }

                if !warnings.isEmpty {
                    sectionHeader(lang.localized("tracker.section.warning"), color: lamp)
                    ForEach(warnings) { tracker in
                        trackerCard(tracker, borderColor: lamp)
                    }
                }

                if !low.isEmpty {
                    sectionHeader(lang.localized("tracker.section.nearby"), color: .secondary)
                    ForEach(low) { tracker in
                        trackerCard(tracker, borderColor: Color(.separator))
                    }
                }
            }
            .padding(16)
        }
    }

    private func sectionHeader(_ title: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.scaled(size: 12, weight: .semibold))
                .foregroundStyle(color)
            Spacer()
        }
        .padding(.top, 8)
    }

    private func trackerCard(_ tracker: DetectedTracker, borderColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: iconForType(tracker.type))
                    .font(.scaled(size: 18))
                    .foregroundStyle(borderColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tracker.name ?? tracker.type.rawValue)
                        .font(.scaled(size: 14, weight: .medium))
                        .foregroundStyle(ink)
                    Text(tracker.type.rawValue)
                        .font(.scaled(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                threatBadge(score: tracker.threatScore)
            }

            // Details
            HStack(spacing: 16) {
                detailItem(icon: "clock.fill",
                          text: String(format: lang.localized("tracker.sightings"), tracker.sightings.count))
            }

            // Time range
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.scaled(size: 10))
                    .foregroundStyle(.secondary)
                Text("\(relativeTime(tracker.firstSeen)) - \(relativeTime(tracker.lastSeen))")
                    .font(.scaled(size: 11))
                    .foregroundStyle(.secondary)
            }

            // Actions
            HStack(spacing: 10) {
                Button {
                    trackerToIgnore = tracker
                    showIgnoreConfirm = true
                } label: {
                    Text(lang.localized("tracker.action.ignore"))
                        .font(.scaled(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(.separator).opacity(0.4), lineWidth: 1)
                        )
                }

                if tracker.threatScore >= 40 {
                    Button {
                        coordinator.triggerSOS(method: .longPress)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sos")
                                .font(.scaled(size: 10))
                            Text(lang.localized("tracker.action.sos"))
                                .font(.scaled(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(alert)
                        )
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(borderColor.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(borderColor.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func detailItem(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.scaled(size: 10))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.scaled(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func threatBadge(score: Int) -> some View {
        Text("\(score)")
            .font(.scaled(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(
                Circle().fill(score >= 70 ? alert : score >= 40 ? lamp : Color(.systemGray4))
            )
    }

    private func iconForType(_ type: TrackerType) -> String {
        switch type {
        case .airTag:   return "airtag"
        case .smartTag: return "sensor.tag.radiowaves.forward"
        case .tile:     return "square.fill"
        case .beacon:   return "wave.3.right.circle"
        case .unknown:  return "questionmark.circle"
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
