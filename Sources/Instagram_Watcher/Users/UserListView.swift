import SwiftUI

/// Vista di dettaglio per sfogliare una specifica categoria di utenti con filtri rapidi, ricerca e pulsanti uniformati
public struct UserListView: View {
    @ObservedObject var locManager = LocalizationManager.shared
    public let category: FollowerCategory
    public let users: [InstagramUser]

    public enum SortOrder: String, CaseIterable, Identifiable {
        case initial = "Default"
        case az = "A → Z"
        case za = "Z → A"
        public var id: String { rawValue }
    }

    @ObservedObject var whitelist = WhitelistService.shared
    @ObservedObject var safetyTracker = DailySafetyTracker.shared
    @State private var searchText = ""
    @State private var selectedFilterIndex = 0
    @State private var sortOrder: SortOrder = .initial
    @State private var shareURL: URL? = nil
    @State private var showCopiedAlert = false

    @ObservedObject var trackerService = FollowerTrackerService.shared

    private func storyCountFor(user: InstagramUser) -> Int {
        let map = trackerService.activeStoriesMap
        if let count = map[user.id], count > 0 {
            return count
        }
        if let count = map[user.username.lowercased()], count > 0 {
            return count
        }
        return 0
    }

    public var filteredUsers: [InstagramUser] {
        var result = users.filter { user in
            // Filtro testo
            let matchesSearch = searchText.isEmpty ||
                user.username.localizedCaseInsensitiveContains(searchText) ||
                user.fullName.localizedCaseInsensitiveContains(searchText)

            // Filtro pill
            let matchesPill: Bool
            switch selectedFilterIndex {
            case 1: matchesPill = user.isVerified
            case 2: matchesPill = user.isPrivate
            case 3: matchesPill = whitelist.isProtected(userID: user.id)
            default: matchesPill = true
            }

            return matchesSearch && matchesPill
        }

        switch sortOrder {
        case .az:
            result.sort { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }
        case .za:
            result.sort { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedDescending }
        case .initial:
            // Priorità all'apertura: chi ha storie attive sta SOPRA, poi chi ha post, poi alfabetico
            result.sort { a, b in
                let aStories = storyCountFor(user: a)
                let bStories = storyCountFor(user: b)
                if aStories != bStories {
                    return aStories > bStories
                }
                let aPosts = a.mediaCount ?? 0
                let bPosts = b.mediaCount ?? 0
                if aPosts != bPosts {
                    return aPosts > bPosts
                }
                return a.username.localizedCaseInsensitiveCompare(b.username) == .orderedAscending
            }
        }

        return result
    }

    public var body: some View {
        List {
            // Quota di Sicurezza Giornaliera Anti-Ban (visibile in Non Ricambiano)
            if category == .notFollowingBack {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "shield.checkered")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(safetyTracker.statusColor)
                            Text(loc("safety.quota_title"))
                                .font(.system(size: 13, weight: .bold))
                            Spacer()
                            Text("\(safetyTracker.actionsToday) / \(safetyTracker.recommendedDailyLimit)")
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundColor(safetyTracker.statusColor)
                        }

                        ProgressView(value: safetyTracker.safetyProgress)
                            .tint(safetyTracker.statusColor)

                        Text(loc("safety.quota_desc"))
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            // Sezione Filtro Rapido
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterButton(title: loc("list.filter_all"), index: 0)
                        filterButton(title: loc("list.filter_verified"), index: 1)
                        filterButton(title: loc("list.filter_private"), index: 2)
                        filterButton(title: "★ \(loc("list.filter_protected"))", index: 3)
                    }
                    .padding(.vertical, 4)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))

            // Sezione Lista Utenti
            Section {
                ForEach(filteredUsers) { user in
                    UserRowView(
                        user: user,
                        actionTitle: actionTitleForCategory(category),
                        actionIcon: actionIconForCategory(category),
                        actionColor: actionColorForCategory(category)
                    )
                }
            } header: {
                HStack {
                    Text("\(filteredUsers.count) \(loc("list.profiles_count"))")
                        .font(.footnote)
                        .fontWeight(.semibold)
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                        Text(loc("list.anti_ban_tag"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .listStyle(InsetGroupedListStyle())
        .searchable(text: $searchText, prompt: loc("list.search_prompt"))
        .refreshable {
            await trackerService.refreshActiveStories()
        }
        .task {
            if trackerService.activeStoriesMap.isEmpty {
                await trackerService.refreshActiveStories()
            }
        }
        .navigationTitle(localizedCategoryTitle(category))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    // Menu Ordinamento & Strumenti
                    Menu {
                        Section("Sort") {
                            Button { sortOrder = .initial } label: {
                                Label("Default", systemImage: sortOrder == .initial ? "checkmark" : "")
                            }
                            Button { sortOrder = .az } label: {
                                Label("A → Z", systemImage: sortOrder == .az ? "checkmark" : "")
                            }
                            Button { sortOrder = .za } label: {
                                Label("Z → A", systemImage: sortOrder == .za ? "checkmark" : "")
                            }
                        }

                        Section("Tools") {
                            Button {
                                copyAllUsernames()
                            } label: {
                                Label("Copy Usernames", systemImage: "doc.on.doc")
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 14, weight: .semibold))
                    }

                    if !users.isEmpty {
                        Button {
                            if let url = CSVExportService.exportUsersToCSV(users: filteredUsers, categoryName: category.rawValue) {
                                shareURL = url
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14, weight: .semibold))
                        }
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
        .alert(isPresented: $showCopiedAlert) {
            Alert(
                title: Text(loc("safety.copied_title")),
                message: Text("\(filteredUsers.count) \(loc("safety.copied_desc"))"),
                dismissButton: .default(Text(loc("nav.done")))
            )
        }
        .overlay {
            if filteredUsers.isEmpty {
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(actionColorForCategory(category).opacity(0.12))
                            .frame(width: 76, height: 76)
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 32))
                            .foregroundColor(actionColorForCategory(category))
                    }

                    Text(searchText.isEmpty ? loc("list.empty_title") : "\(loc("list.empty_search"))")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(searchText.isEmpty ? loc("list.empty_desc") : "\"\(searchText)\"")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
        }
    }

    private func filterButton(title: String, index: Int) -> some View {
        Button {
            selectedFilterIndex = index
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(selectedFilterIndex == index ? actionColorForCategory(category) : Color(UIColor.tertiarySystemFill))
                )
                .foregroundColor(selectedFilterIndex == index ? .white : .primary)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func localizedCategoryTitle(_ cat: FollowerCategory) -> String {
        switch cat {
        case .notFollowingBack: return loc("category.not_following_back")
        case .fans: return loc("category.fans")
        case .mutuals: return loc("category.mutuals")
        case .lost: return loc("category.lost")
        case .ghosts: return loc("category.ghosts")
        }
    }

    private func actionTitleForCategory(_ cat: FollowerCategory) -> String {
        switch cat {
        case .notFollowingBack: return loc("action.unfollow")
        case .fans: return loc("action.follow")
        case .mutuals: return loc("action.view_profile")
        case .lost: return loc("action.view_profile")
        case .ghosts: return loc("action.view_profile")
        }
    }

    private func actionIconForCategory(_ cat: FollowerCategory) -> String {
        switch cat {
        case .notFollowingBack: return "person.badge.minus"
        case .fans: return "person.badge.plus"
        case .mutuals: return "arrow.up.right"
        case .lost: return "arrow.up.right"
        case .ghosts: return "eye.slash"
        }
    }

    private func actionColorForCategory(_ cat: FollowerCategory) -> Color {
        switch cat {
        case .notFollowingBack: return Color(red: 1.0, green: 0.22, blue: 0.38)
        case .fans: return Color(red: 0.05, green: 0.75, blue: 0.55)
        case .mutuals: return Color(red: 0.38, green: 0.28, blue: 0.95)
        case .lost: return Color(red: 0.95, green: 0.45, blue: 0.12)
        case .ghosts: return Color(red: 0.55, green: 0.55, blue: 0.65)
        }
    }

    private func copyAllUsernames() {
        let text = filteredUsers.map { "@\($0.username)" }.joined(separator: "\n")
        UIPasteboard.general.string = text
        showCopiedAlert = true
    }
}
