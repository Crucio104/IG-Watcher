import SwiftUI

/// Vista dello storico dei nuovi follower acquisiti con stile smeraldo, timeline e ricerca
public struct GainedFollowersHistoryView: View {
    @ObservedObject var locManager = LocalizationManager.shared
    public let records: [GainedFollowerRecord]
    @State private var searchText = ""
    @State private var shareURL: URL? = nil

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    public var filteredRecords: [GainedFollowerRecord] {
        if searchText.isEmpty {
            return records
        } else {
            return records.filter {
                $0.user.username.localizedCaseInsensitiveContains(searchText) ||
                $0.user.fullName.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    public var body: some View {
        List {
            Section {
                ForEach(filteredRecords) { record in
                    HStack(spacing: 14) {
                        // Avatar con ring verde smeraldo
                        ZStack {
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [Color(red: 0.15, green: 0.85, blue: 0.55), Color(red: 0.05, green: 0.65, blue: 0.85)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 2
                                )
                                .frame(width: 48, height: 48)

                            AsyncImage(url: record.user.profilePicURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 42, height: 42)
                                        .clipShape(Circle())
                                case .empty:
                                    Circle()
                                        .fill(Color(UIColor.tertiarySystemFill))
                                        .frame(width: 42, height: 42)
                                        .overlay(ProgressView().scaleEffect(0.6))
                                case .failure:
                                    Circle()
                                        .fill(Color(UIColor.tertiarySystemFill))
                                        .frame(width: 42, height: 42)
                                        .overlay(
                                            Image(systemName: "person.fill")
                                                .foregroundColor(.secondary)
                                        )
                                @unknown default:
                                    Circle()
                                        .fill(Color(UIColor.tertiarySystemFill))
                                        .frame(width: 42, height: 42)
                                }
                            }
                        }

                        // Dati Utente & Data di inizio follow
                        VStack(alignment: .leading, spacing: 4) {
                            Text("@\(record.user.username)")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)

                            HStack(spacing: 5) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(red: 0.10, green: 0.78, blue: 0.48))
                                Text("\(loc("gained.detected_on")) \(dateFormatter.string(from: record.detectedAt))")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        // Pulsante d'azione UNIFORMATO
                        Button {
                            DeepLinkService.shared.openProfile(username: record.user.username)
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 11, weight: .bold))
                                Text(loc("action.view_profile"))
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .frame(minWidth: 84, minHeight: 32)
                            .padding(.horizontal, 10)
                            .background(
                                Capsule()
                                    .fill(Color(red: 0.10, green: 0.78, blue: 0.48).opacity(0.12))
                            )
                            .foregroundColor(Color(red: 0.08, green: 0.68, blue: 0.40))
                            .overlay(
                                Capsule()
                                    .stroke(Color(red: 0.10, green: 0.78, blue: 0.48).opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                HStack {
                    Text("\(filteredRecords.count) \(loc("gained.header_count"))")
                        .font(.footnote)
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "person.badge.plus")
                        .foregroundColor(Color(red: 0.10, green: 0.78, blue: 0.48))
                }
            } footer: {
                Text(loc("gained.footer_desc"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
        }
        .listStyle(InsetGroupedListStyle())
        .searchable(text: $searchText, prompt: loc("gained.search_prompt"))
        .navigationTitle(loc("category.gained"))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !records.isEmpty {
                    Button {
                        if let url = CSVExportService.exportGainedFollowersToCSV(records: records) {
                            shareURL = url
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                    }
                }
            }
        }
        .sheet(item: Binding(
            get: { shareURL.map { ShareItem(url: $0) } },
            set: { shareURL = $0?.url }
        )) { item in
            ShareSheet(activityItems: [item.url])
        }
        .overlay {
            if filteredRecords.isEmpty {
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.10, green: 0.78, blue: 0.48).opacity(0.12))
                            .frame(width: 80, height: 80)
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 36))
                            .foregroundColor(Color(red: 0.10, green: 0.78, blue: 0.48))
                    }

                    Text(searchText.isEmpty ? loc("gained.empty_title") : "\(loc("list.empty_search"))")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(searchText.isEmpty ? loc("gained.empty_desc") : "\"\(searchText)\"")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                }
            }
        }
    }
}
