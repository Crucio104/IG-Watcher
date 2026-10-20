import SwiftUI

/// Vista per filtrare Seguiti, Follower o Tutti (qualsiasi profilo su Instagram)
/// e aprirne il profilo in stile Instagram 100% anonimo.
/// Mostra per primi gli account che hanno storie o post attivi al momento,
/// con conteggio visibile e anello gradiente Instagram sulle storie attive.
public struct AnonymousSearchSheet: View {
    @ObservedObject var locManager = LocalizationManager.shared
    @ObservedObject var trackerService = FollowerTrackerService.shared
    @ObservedObject var sessionManager = InstagramSessionManager.shared
    @Environment(\.dismiss) var dismiss

    // Filtri Categorie richieste: 0: Seguiti, 1: Follower, 2: Tutti
    @State private var selectedFilterCategory = 0
    @State private var searchInput = ""
    @State private var selectedUserForViewer: InstagramUser? = nil

    // Mappa storie attive recuperate dal reels tray in background
    @State private var activeStoriesMap: [String: Int] = [:]
    @State private var isFetchingTray = false

    public var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemBackground)
                    .ignoresSafeArea()

                VStack(spacing: 12) {
                    // Campo di ricerca in alto
                    searchBarSection

                    // Barra Filtri Categorie: Seguiti | Follower | Tutti
                    categoryFilterBar

                    // Lista Profili Ordinata (Storie attive per primi)
                    userListView
                }
            }
            .navigationTitle(loc("viewer.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc("nav.close")) {
                        dismiss()
                    }
                }
            }
            .sheet(item: $selectedUserForViewer) { user in
                AnonymousMediaViewerSheet(user: user)
                    .id(user.id)
            }
            .task {
                await loadReelsTray()
            }
        }
    }

    // MARK: - Barra di Ricerca

    private var searchBarSection: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)

                TextField(loc("viewer.search_hint"), text: $searchInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)

                if !searchInput.isEmpty {
                    Button {
                        searchInput = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(12)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)

            // Se l'utente digita un username non in cache o cerca globalmente
            let clean = searchInput.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "")
            if !clean.isEmpty {
                Button {
                    openSearchedUsername(clean)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "eye.slash.fill")
                        Text("\(loc("viewer.search_button")): @\(clean)")
                    }
                    .font(.system(size: 13, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Theme.instagramGradient)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    // MARK: - Barra Filtri: Seguiti, Follower, Tutti

    private var categoryFilterBar: some View {
        Picker("", selection: $selectedFilterCategory) {
            Text(loc("viewer.filter_following")).tag(0)
            Text(loc("viewer.filter_followers")).tag(1)
            Text(loc("viewer.filter_all")).tag(2)
        }
        .pickerStyle(SegmentedPickerStyle())
        .padding(.horizontal, 16)
    }

    // MARK: - Lista Profili con Priorità Storie Attive

    private var userListView: some View {
        let users = sortedFilteredUsers()

        return Group {
            if users.isEmpty && searchInput.isEmpty {
                VStack(spacing: 12) {
                    Spacer().frame(height: 50)
                    Image(systemName: "person.2.slash")
                        .font(.system(size: 38))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text(loc("list.empty_title"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(users) { user in
                        Button {
                            self.selectedUserForViewer = user
                        } label: {
                            userRowView(for: user)
                        }
                    }
                }
                .listStyle(PlainListStyle())
                .refreshable {
                    await loadReelsTray()
                }
            }
        }
    }

    private func userRowView(for user: InstagramUser) -> some View {
        let storyCount = storyCountFor(user: user)
        let hasStories = storyCount > 0

        return HStack(spacing: 12) {
            // Avatar con anello gradiente se ha storie attive
            ZStack {
                if hasStories {
                    Circle()
                        .stroke(Theme.instagramGradient, lineWidth: 2.2)
                        .frame(width: 50, height: 50)
                }

                AsyncImage(url: user.profilePicURL) { phase in
                    switch phase {
                    case .success(let img):
                        img
                            .resizable()
                            .scaledToFill()
                            .frame(width: hasStories ? 43 : 46, height: hasStories ? 43 : 46)
                            .clipShape(Circle())
                    default:
                        Circle()
                            .fill(Color(UIColor.secondarySystemBackground))
                            .frame(width: hasStories ? 43 : 46, height: hasStories ? 43 : 46)
                            .overlay(Image(systemName: "person.fill").foregroundColor(.secondary))
                    }
                }
            }

            // Info Utente & Conteggi Storie / Post
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text("@\(user.username)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)

                    if user.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.blue)
                    }

                    if user.isPrivate {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }

                // Sottotitolo con conteggio storie attive e post
                HStack(spacing: 6) {
                    if hasStories {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color(red: 0.88, green: 0.17, blue: 0.44))
                                .frame(width: 6, height: 6)

                            Text("\(storyCount) \(loc("viewer.active_stories_suffix"))")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Color(red: 0.88, green: 0.17, blue: 0.44))
                        }
                    }

                    if let posts = user.mediaCount, posts > 0 {
                        if hasStories {
                            Text("•")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        Text("\(posts) \(loc("viewer.posts_tab"))")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    } else if !hasStories {
                        if !user.fullName.isEmpty {
                            Text(user.fullName)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        } else {
                            Text(loc("viewer.no_active_stories"))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.secondary.opacity(0.5))
        }
        .padding(.vertical, 3)
    }

    // MARK: - Filtri e Ordinamento

    private func sortedFilteredUsers() -> [InstagramUser] {
        var baseList: [InstagramUser] = []

        switch selectedFilterCategory {
        case 0:
            // Seguiti (Following): NotFollowingBack + Mutuals
            baseList = trackerService.latestResult.notFollowingBack + trackerService.latestResult.mutuals
        case 1:
            // Follower: Fans + Mutuals
            baseList = trackerService.latestResult.fans + trackerService.latestResult.mutuals
        default:
            // Tutti: tutti i contatti unici in cache
            let all = trackerService.latestResult.notFollowingBack + trackerService.latestResult.fans + trackerService.latestResult.mutuals
            var seen = Set<String>()
            for u in all {
                if !seen.contains(u.id) {
                    seen.insert(u.id)
                    baseList.append(u)
                }
            }
        }

        // Filtra per testo ricerca se inserito
        let cleanQuery = searchInput.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "@", with: "").lowercased()
        if !cleanQuery.isEmpty {
            baseList = baseList.filter {
                $0.username.lowercased().contains(cleanQuery) || $0.fullName.lowercased().contains(cleanQuery)
            }
        }

        // Ordina: Chi ha storie attive viene PRIMA, poi chi ha post, poi alfabetico
        return baseList.sorted { a, b in
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

            return a.username.lowercased() < b.username.lowercased()
        }
    }

    private func storyCountFor(user: InstagramUser) -> Int {
        let sharedMap = trackerService.activeStoriesMap
        if let count = activeStoriesMap[user.id] ?? sharedMap[user.id], count > 0 {
            return count
        }
        if let count = activeStoriesMap[user.username.lowercased()] ?? sharedMap[user.username.lowercased()], count > 0 {
            return count
        }
        return 0
    }

    // MARK: - Caricamento Reels Tray

    private func loadReelsTray() async {
        guard let session = sessionManager.currentSession, !isFetchingTray else { return }
        isFetchingTray = true
        await trackerService.refreshActiveStories(session: session)
        self.activeStoriesMap = trackerService.activeStoriesMap
        self.isFetchingTray = false
    }

    private func openSearchedUsername(_ clean: String) {
        let all = trackerService.latestResult.notFollowingBack + trackerService.latestResult.fans + trackerService.latestResult.mutuals
        if let found = all.first(where: { $0.username.lowercased() == clean.lowercased() }) {
            self.selectedUserForViewer = found
            return
        }

        self.selectedUserForViewer = InstagramUser(
            id: clean,
            username: clean,
            fullName: clean
        )
    }
}
