import SwiftUI

/// Vista dello storico dei follower persi con timeline visiva, localizzazione e data di rilevamento
public struct LostFollowersHistoryView: View {
    @ObservedObject var locManager = LocalizationManager.shared
    public let records: [LostFollowerRecord]
    @State private var searchText = ""
    @State private var shareURL: URL? = nil

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    public var filteredRecords: [LostFollowerRecord] {
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
                        // Avatar con ring d'allerta
                        ZStack {
                            Circle()
                                .stroke(Theme.lostGradient, lineWidth: 2)
                                .frame(width: 48, height: 48)

                            AsyncImage(url: record.user.profilePicURL) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 42, height: 42)
                                        .clipShape(Circle())
                                default:
                                    Circle()
                                        .fill(Color(UIColor.tertiarySystemFill))
                                        .frame(width: 42, height: 42)
                                        .overlay(
                                            Image(systemName: "person.fill")
                                                .foregroundColor(.secondary)
                                        )
                                }
                            }
                        }

                        // Dati Utente & Data
                        VStack(alignment: .leading, spacing: 4) {
                            Text("@\(record.user.username)")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.primary)

                            HStack(spacing: 5) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(red: 0.95, green: 0.45, blue: 0.12))
                                Text("\(loc("lost.detected_on")) \(dateFormatter.string(from: record.detectedAt))")
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
                                    .fill(Color(red: 0.95, green: 0.45, blue: 0.12).opacity(0.12))
                            )
                            .foregroundColor(Color(red: 0.95, green: 0.45, blue: 0.12))
                            .overlay(
                                Capsule()
                                    .stroke(Color(red: 0.95, green: 0.45, blue: 0.12).opacity(0.28), lineWidth: 1)
                            )
                        }
                        .buttonStyle(BorderlessButtonStyle())
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                HStack {
                    Text("\(filteredRecords.count) \(loc("lost.header_count"))")
                        .font(.footnote)
                        .fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "bell.badge.fill")
                        .font(.caption2)
                        .foregroundColor(Color(red: 0.95, green: 0.45, blue: 0.12))
                }
            } footer: {
                Text(loc("lost.footer_desc"))
            }
        }
        .listStyle(InsetGroupedListStyle())
        .searchable(text: $searchText, prompt: loc("lost.search_prompt"))
        .navigationTitle(loc("lost.title"))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !records.isEmpty {
                    Button {
                        if let url = CSVExportService.exportLostFollowersToCSV(records: records) {
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
                            .fill(Color.green.opacity(0.12))
                            .frame(width: 80, height: 80)
                        Image(systemName: "heart.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.green)
                    }

                    Text(loc("lost.empty_title"))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)

                    Text(loc("lost.empty_desc"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                }
            }
        }
    }
}
