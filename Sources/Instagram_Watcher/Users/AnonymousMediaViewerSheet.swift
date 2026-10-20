import SwiftUI
import AVKit
import Photos

/// Visualizzatore e Downloader di Profili Instagram in stile nativo Instagram, 100% anonimo.
/// Replica fedelmente l'interfaccia di un profilo Instagram ufficiale:
/// - Header profilo (Avatar con anello Storie IG, Statistiche Post/Follower/Seguiti, Nome e Bio)
/// - Schede native IG: Griglia Post 3x3 e Storie Attive
/// - Story player interattivo con barre di progresso segmentate e navigazione a tocco (sinistra/destra)
/// - Modalità Dettaglio Post in stile feed con supporto a caroselli multi-foto/video
/// - Salvataggio istantaneo nel Rullino Foto iOS (PHPhotoLibrary) con feedback aptico e toast di conferma
/// - Conforme al 100% alla lingua selezionata nelle impostazioni.
public struct AnonymousMediaViewerSheet: View {
    public let user: InstagramUser
    @ObservedObject var locManager = LocalizationManager.shared
    @ObservedObject var sessionManager = InstagramSessionManager.shared
    @Environment(\.dismiss) var dismiss

    // Dati Profilo e Media
    @State private var profile: ResolvedUserProfile? = nil
    @State private var stories: [InstagramStoryItem] = []
    @State private var posts: [InstagramPostItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String? = nil

    // Tab selezionata (0: Griglia Post, 1: Storie)
    @State private var selectedTab: Int = 0
    @State private var showingStoryPlayer: Bool = false
    @State private var activeStoryIndex: Int = 0
    @State private var selectedPostDetail: InstagramPostItem? = nil

    // Download & Feedback
    @State private var isDownloading = false
    @State private var downloadToast: String? = nil
    @State private var profileURLToShare: URL? = nil

    // Paginazione Post
    @State private var isLoadingMorePosts: Bool = false
    @State private var canLoadMorePosts: Bool = true

    public init(user: InstagramUser) {
        self.user = user
    }

    public var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemBackground)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Barra Anonimato Stealth
                    stealthNoticeBanner

                    ScrollView(showsIndicators: true) {
                        VStack(spacing: 14) {
                            // Header Profilo in stile Instagram
                            instagramProfileHeader

                            // Selettore Tab in stile Instagram (Griglia Post / Storie)
                            instagramTabBar

                            // Contenuto principale
                            if isLoading {
                                loadingPlaceholder
                            } else if isPrivateAndNotFollowed {
                                privateAccountView
                            } else {
                                if selectedTab == 0 {
                                    postsGridView
                                } else {
                                    storiesInlineView
                                }
                            }
                        }
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 15, weight: .bold))
                            Text(loc("viewer.title"))
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(.primary)
                    }
                }

                ToolbarItem(placement: .principal) {
                    HStack(spacing: 4) {
                        Text("@\(profile?.username ?? user.username)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.primary)

                        if profile?.isVerified == true || user.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                        }

                        if profile?.isPrivate == true || user.isPrivate {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 6) {
                        Text(loc("viewer.anonymous_badge"))
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color(red: 0.12, green: 0.85, blue: 0.75))
                            .clipShape(Capsule())
                    }
                }
            }
            .fullScreenCover(isPresented: $showingStoryPlayer) {
                if !stories.isEmpty {
                    InstagramStoryPlayerView(
                        stories: stories,
                        initialIndex: activeStoryIndex,
                        username: profile?.username ?? user.username,
                        profilePicURL: profile?.profilePicURL ?? user.profilePicURL,
                        onDownload: { url, isVideo in
                            Task { await downloadMedia(url: url, isVideo: isVideo) }
                        }
                    )
                }
            }
            .sheet(item: $selectedPostDetail) { post in
                InstagramPostDetailSheet(
                    post: post,
                    username: profile?.username ?? user.username,
                    userAvatar: profile?.profilePicURL ?? user.profilePicURL,
                    session: sessionManager.currentSession,
                    onDownload: { url, isVideo in
                        Task { await downloadMedia(url: url, isVideo: isVideo) }
                    }
                )
            }
            .sheet(item: Binding(
                get: { profileURLToShare.map { ShareItem(url: $0) } },
                set: { profileURLToShare = $0?.url }
            )) { item in
                ShareSheet(activityItems: [item.url])
            }
            .overlay(alignment: .bottom) {
                if let toast = downloadToast {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.green)
                        Text(toast)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(Capsule())
                    .shadow(color: Color.black.opacity(0.12), radius: 12, y: 6)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .task {
            await loadProfileData()
        }
    }

    // MARK: - Banner Notifica Anonimato Stealth

    private var stealthNoticeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.slash.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Color(red: 0.12, green: 0.85, blue: 0.75))

            Text(loc("viewer.no_seen_notice"))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color(UIColor.secondarySystemGroupedBackground))
    }

    // MARK: - Header Profilo in Stile Instagram Ufficiale

    private var instagramProfileHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Riga Foto Profilo + Statistiche
            HStack(spacing: 20) {
                // Foto Profilo (con anello storie se ci sono storie attive)
                Button {
                    if !stories.isEmpty {
                        self.activeStoryIndex = 0
                        self.showingStoryPlayer = true
                    }
                } label: {
                    ZStack {
                        if !stories.isEmpty {
                            Circle()
                                .stroke(Theme.instagramGradient, lineWidth: 2.8)
                                .frame(width: 86, height: 86)
                        } else {
                            Circle()
                                .stroke(Color(UIColor.separator), lineWidth: 1)
                                .frame(width: 82, height: 82)
                        }

                        AsyncImage(url: profile?.profilePicURL ?? user.profilePicURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 76, height: 76)
                                    .clipShape(Circle())
                            default:
                                Circle()
                                    .fill(Color(UIColor.secondarySystemBackground))
                                    .frame(width: 76, height: 76)
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 32))
                                            .foregroundColor(.secondary)
                                    )
                            }
                        }

                        if !stories.isEmpty {
                            VStack {
                                Spacer()
                                HStack {
                                    Spacer()
                                    Circle()
                                        .fill(Color(red: 0.88, green: 0.17, blue: 0.44))
                                        .frame(width: 18, height: 18)
                                        .overlay(
                                            Image(systemName: "play.fill")
                                                .font(.system(size: 9, weight: .black))
                                                .foregroundColor(.white)
                                        )
                                }
                            }
                            .frame(width: 82, height: 82)
                        }
                    }
                }
                .buttonStyle(PlainButtonStyle())

                // Statistiche (Post, Follower, Seguiti)
                HStack(spacing: 0) {
                    statColumn(
                        count: posts.count > 0 ? "\(posts.count)" : (profile?.postsCount != nil && profile!.postsCount > 0 ? "\(profile!.postsCount)" : "0"),
                        label: loc("viewer.posts")
                    )

                    Spacer()

                    statColumn(
                        count: formatStatCount(profile?.followersCount ?? 0),
                        label: loc("viewer.followers")
                    )

                    Spacer()

                    statColumn(
                        count: formatStatCount(profile?.followingCount ?? 0),
                        label: loc("viewer.following")
                    )
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // Nome e Dettagli Bio
            VStack(alignment: .leading, spacing: 3) {
                if let name = profile?.fullName, !name.isEmpty {
                    Text(name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)
                } else if !user.fullName.isEmpty {
                    Text(user.fullName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)
                }

                if let bio = profile?.biography, !bio.isEmpty {
                    Text(bio)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                        .lineLimit(4)
                }

                if !stories.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                            .foregroundColor(Color(red: 0.88, green: 0.17, blue: 0.44))
                        Text(loc("viewer.tap_story_hint"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(red: 0.88, green: 0.17, blue: 0.44))
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.horizontal, 16)

            // Pulsanti Azione in Stile Instagram
            HStack(spacing: 10) {
                if !stories.isEmpty {
                    Button {
                        self.activeStoryIndex = 0
                        self.showingStoryPlayer = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.circle.fill")
                            Text("\(loc("viewer.watch_stories")) (\(stories.count))")
                        }
                        .font(.system(size: 13, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Theme.instagramGradient)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                        Text(loc("viewer.no_active_stories"))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color(UIColor.secondarySystemBackground))
                    .foregroundColor(.secondary)
                    .cornerRadius(8)
                }

                Button {
                    if let u = URL(string: "https://www.instagram.com/\(profile?.username ?? user.username)/") {
                        self.profileURLToShare = u
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(UIColor.secondarySystemBackground))
                        .foregroundColor(.primary)
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func statColumn(count: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(count)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
            Text(label)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Barra Tab in Stile Instagram

    private var instagramTabBar: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 0) {
                // Tab Post
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedTab = 0
                    }
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "square.grid.3x3.fill")
                            .font(.system(size: 18))
                            .foregroundColor(selectedTab == 0 ? .primary : .secondary.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 10)

                        Rectangle()
                            .fill(selectedTab == 0 ? Color.primary : Color.clear)
                            .frame(height: 1.5)
                    }
                }

                // Tab Storie
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedTab = 1
                    }
                } label: {
                    VStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Image(systemName: "circle.circle.fill")
                                .font(.system(size: 18))
                            if !stories.isEmpty {
                                Text("\(stories.count)")
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color(red: 0.88, green: 0.17, blue: 0.44))
                                    .foregroundColor(.white)
                                    .clipShape(Capsule())
                            }
                        }
                        .foregroundColor(selectedTab == 1 ? .primary : .secondary.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10)

                        Rectangle()
                            .fill(selectedTab == 1 ? Color.primary : Color.clear)
                            .frame(height: 1.5)
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Griglia Post in Stile Instagram (3 Colonne)

    private var postsGridView: some View {
        Group {
            if posts.isEmpty {
                VStack(spacing: 12) {
                    Spacer().frame(height: 40)
                    Image(systemName: "camera")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(.secondary.opacity(0.6))

                    Text(loc("viewer.no_posts"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)

                    Text(loc("viewer.no_posts_sub"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)

                    Button {
                        Task {
                            await loadProfileData()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .bold))
                            Text(loc("status.update_now"))
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.12))
                        .foregroundColor(.blue)
                        .clipShape(Capsule())
                    }
                    .padding(.top, 8)
                }
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 2),
                        GridItem(.flexible(), spacing: 2),
                        GridItem(.flexible(), spacing: 2)
                    ],
                    spacing: 2
                ) {
                    ForEach(posts) { post in
                        Button {
                            self.selectedPostDetail = post
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                AsyncImage(url: post.imageURL) { phase in
                                    switch phase {
                                    case .success(let img):
                                        img
                                            .resizable()
                                            .scaledToFill()
                                            .frame(minWidth: 0, maxWidth: .infinity)
                                            .aspectRatio(1, contentMode: .fit)
                                            .clipped()
                                    default:
                                        Rectangle()
                                            .fill(Color(UIColor.secondarySystemBackground))
                                            .aspectRatio(1, contentMode: .fit)
                                    }
                                }

                                if post.isCarousel {
                                    Image(systemName: "square.fill.on.square.fill")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white)
                                        .shadow(color: .black.opacity(0.6), radius: 2)
                                        .padding(6)
                                } else if post.isVideo {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(.white)
                                        .shadow(color: .black.opacity(0.6), radius: 2)
                                        .padding(6)
                                }
                            }
                        }
                        .onAppear {
                            if post.id == posts.last?.id && canLoadMorePosts && !isLoadingMorePosts {
                                Task { await loadMorePosts() }
                            }
                        }
                    }
                }

                // Sezione caricamento e pulsante per visualizzare post più vecchi
                if isLoadingMorePosts {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.9)
                        Text(loc("viewer.loading_older_posts"))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                } else if canLoadMorePosts && !posts.isEmpty {
                    Button {
                        Task { await loadMorePosts() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 12, weight: .bold))
                            Text(loc("viewer.load_more_posts"))
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color(UIColor.secondarySystemBackground))
                        .clipShape(Capsule())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
            }
        }
    }

    // MARK: - Storie Inline

    private var storiesInlineView: some View {
        Group {
            if stories.isEmpty {
                VStack(spacing: 12) {
                    Spacer().frame(height: 40)
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(.secondary.opacity(0.6))

                    Text(loc("viewer.no_active_stories"))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary)

                    Text(loc("viewer.no_stories_sub"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                }
            } else {
                LazyVStack(spacing: 16) {
                    ForEach(Array(stories.enumerated()), id: \.element.id) { index, story in
                        VStack(spacing: 10) {
                            HStack {
                                Text("\(loc("viewer.story_count")) \(index + 1) \(loc("viewer.of")) \(stories.count)")
                                    .font(.system(size: 12, weight: .bold))
                                Spacer()
                                Text(timeRemaining(expiresAt: story.expiresAt))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }

                            // Anteprima Media
                            AsyncImage(url: story.imageURL) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable().scaledToFit().cornerRadius(12)
                                default:
                                    Rectangle().fill(Color(UIColor.secondarySystemBackground)).frame(height: 380).cornerRadius(12)
                                }
                            }

                            // Bottone Salva nel Rullino
                            Button {
                                Task {
                                    await downloadMedia(
                                        url: story.isVideo ? (story.videoURL ?? story.imageURL) : story.imageURL,
                                        isVideo: story.isVideo
                                    )
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.down.circle.fill")
                                    Text(loc("viewer.save_roll"))
                                }
                                .font(.system(size: 13, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color(UIColor.secondarySystemBackground))
                                .foregroundColor(.primary)
                                .cornerRadius(10)
                            }
                        }
                        .padding(12)
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(16)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Vista Account Privato (Non Seguito)

    private var isPrivateAndNotFollowed: Bool {
        guard let p = profile else { return false }
        return p.isPrivate && !p.followedByViewer && posts.isEmpty && stories.isEmpty
    }

    private var privateAccountView: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 40)

            Circle()
                .stroke(Color.primary.opacity(0.2), lineWidth: 2)
                .frame(width: 80, height: 80)
                .overlay(
                    Image(systemName: "lock.fill")
                        .font(.system(size: 34))
                        .foregroundColor(.primary)
                )

            Text(loc("viewer.private_account"))
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.primary)

            Text(loc("viewer.private_notice"))
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
                .lineSpacing(3)
        }
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 12) {
            Spacer().frame(height: 50)
            ProgressView()
                .scaleEffect(1.2)
            Text(loc("viewer.connecting"))
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Caricamento Dati & Download

    private func loadProfileData() async {
        guard let session = sessionManager.currentSession else { return }
        
        // Pulisce immediatamente i dati precedenti per evitare flash o residui dell'account scelto prima
        self.profile = nil
        self.posts = []
        self.stories = []
        self.selectedPostDetail = nil
        self.isLoading = true

        // 1. Risolvi il profilo
        let resolved = await AnonymousMediaService.shared.resolveProfile(user: user, session: session)
        self.profile = resolved

        // Mostra subito i post iniziali se già presenti
        if !resolved.initialPosts.isEmpty {
            self.posts = resolved.initialPosts
            self.isLoading = false
        }

        // 2. Carica storie e ulteriori post in parallelo su tutti gli endpoint
        async let fetchedStories = AnonymousMediaService.shared.fetchUserStories(userID: resolved.id, session: session)
        async let fetchedPosts = AnonymousMediaService.shared.fetchUserPosts(userID: resolved.id, username: resolved.username, session: session)

        let (loadedStories, loadedPosts) = await (fetchedStories, fetchedPosts)
        self.stories = loadedStories
        if !loadedPosts.isEmpty {
            var combined = self.posts
            for p in loadedPosts {
                if !combined.contains(where: { $0.id == p.id }) {
                    combined.append(p)
                }
            }
            self.posts = combined.isEmpty ? loadedPosts : combined
        }

        self.isLoading = false
    }

    private func downloadMedia(url: URL?, isVideo: Bool) async {
        guard let mediaURL = url else { return }
        isDownloading = true
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.prepare()

        do {
            _ = try await AnonymousMediaService.shared.downloadMedia(from: mediaURL, isVideo: isVideo)
            impact.impactOccurred()

            withAnimation(.spring()) {
                downloadToast = isVideo ? loc("viewer.saved_video_toast") : loc("viewer.saved_toast")
            }

            try? await Task.sleep(nanoseconds: 2_600_000_000)
            withAnimation(.easeOut) {
                downloadToast = nil
            }
        } catch {
            print("Download media error: \(error)")
            withAnimation {
                downloadToast = loc("viewer.error_save")
            }
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            withAnimation(.easeOut) {
                downloadToast = nil
            }
        }
        isDownloading = false
    }

    private func loadMorePosts() async {
        guard !isLoadingMorePosts && canLoadMorePosts else { return }
        guard let session = sessionManager.currentSession else { return }
        isLoadingMorePosts = true

        let currentIDs = posts.map { $0.id }
        let newItems = await AnonymousMediaService.shared.fetchMoreUserPosts(
            userID: profile?.id ?? user.id,
            username: profile?.username ?? user.username,
            existingShortcodes: currentIDs,
            session: session
        )

        let totalExpected = profile?.postsCount ?? user.mediaCount ?? 0
        if newItems.isEmpty {
            if totalExpected > 0 && posts.count >= totalExpected {
                canLoadMorePosts = false
            } else if totalExpected == 0 && !posts.isEmpty {
                canLoadMorePosts = false
            }
        } else {
            var existingSet = Set(self.posts.map { $0.id })
            var toAdd: [InstagramPostItem] = []
            for item in newItems {
                if !existingSet.contains(item.id) {
                    existingSet.insert(item.id)
                    toAdd.append(item)
                }
            }
            if toAdd.isEmpty {
                if totalExpected > 0 && posts.count >= totalExpected {
                    canLoadMorePosts = false
                }
            } else {
                withAnimation {
                    self.posts.append(contentsOf: toAdd)
                }
                if totalExpected > 0 && self.posts.count >= totalExpected {
                    canLoadMorePosts = false
                }
            }
        }

        isLoadingMorePosts = false
    }

    private func formatStatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        }
        return "\(count)"
    }

    private func timeRemaining(expiresAt: Date) -> String {
        let diff = expiresAt.timeIntervalSince(Date())
        if diff <= 0 { return loc("viewer.expired") }
        let hours = Int(diff / 3600)
        let mins = Int((diff.truncatingRemainder(dividingBy: 3600)) / 60)
        if hours > 0 {
            return "\(loc("viewer.expires_in")) \(hours)h"
        } else {
            return "\(loc("viewer.expires_in")) \(mins)m"
        }
    }
}

// MARK: - Controller Video Player Personalizzato in Stile Instagram (Loop, Audio & Controlli)

struct PlayerViewControllerRepresentable: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false // Evita che AVPlayerViewController blocchi gli swipe orizzontali del carosello
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player != player {
            uiViewController.player = player
        }
    }
}

public struct IncognitoVideoPlayerView: View {
    public let url: URL
    @Binding public var isMuted: Bool
    public var autoPlay: Bool = true
    public var showSoundToggle: Bool = true
    public var onFinishedPlaying: (@MainActor @Sendable () -> Void)? = nil

    @State private var player: AVPlayer? = nil
    @State private var isPlaying: Bool = true
    @State private var showPlayPauseIcon: Bool = false
    @State private var loopObserver: NSObjectProtocol? = nil

    public init(
        url: URL,
        isMuted: Binding<Bool>,
        autoPlay: Bool = true,
        showSoundToggle: Bool = true,
        onFinishedPlaying: (@MainActor @Sendable () -> Void)? = nil
    ) {
        self.url = url
        self._isMuted = isMuted
        self.autoPlay = autoPlay
        self.showSoundToggle = showSoundToggle
        self.onFinishedPlaying = onFinishedPlaying
    }

    public var body: some View {
        ZStack {
            Color.black

            if let p = player {
                PlayerViewControllerRepresentable(player: p)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        togglePlayPause()
                    }
            } else {
                ProgressView()
                    .tint(.white)
            }

            // Icona animata Play / Pausa al tocco
            if showPlayPauseIcon {
                Image(systemName: isPlaying ? "play.fill" : "pause.fill")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(18)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
                    .transition(.scale.combined(with: .opacity))
            }

            // Tasto Mute / Unmute in stile Instagram
            if showSoundToggle {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button {
                            withAnimation(.spring(response: 0.25)) {
                                isMuted.toggle()
                            }
                        } label: {
                            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.black.opacity(0.65))
                                .clipShape(Circle())
                        }
                        .padding(12)
                    }
                }
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onChange(of: isMuted) {
            player?.isMuted = isMuted
        }
        .onChange(of: url) {
            cleanup()
            setupPlayer()
        }
        .onDisappear {
            cleanup()
        }
    }

    private func setupPlayer() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        let p = AVPlayer(url: url)
        p.isMuted = isMuted
        self.player = p

        if autoPlay {
            p.play()
            self.isPlaying = true
        } else {
            self.isPlaying = false
        }

        let finishedHandler = onFinishedPlaying
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: p.currentItem,
            queue: .main
        ) { [weak p] _ in
            Task { @MainActor in
                if let onFinished = finishedHandler {
                    onFinished()
                } else {
                    p?.seek(to: .zero)
                    p?.play()
                }
            }
        }
    }

    private func togglePlayPause() {
        guard let p = player else { return }
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.prepare()
        impact.impactOccurred()

        if isPlaying {
            p.pause()
            isPlaying = false
        } else {
            p.play()
            isPlaying = true
        }

        withAnimation(.easeIn(duration: 0.12)) {
            showPlayPauseIcon = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 650_000_000)
            withAnimation(.easeOut(duration: 0.2)) {
                showPlayPauseIcon = false
            }
        }
    }

    private func cleanup() {
        if let obs = loopObserver {
            NotificationCenter.default.removeObserver(obs)
            loopObserver = nil
        }
        player?.pause()
        player = nil
    }
}

// MARK: - Story Player a Schermo Intero in Stile Instagram Ufficiale con Riproduzione Video Reale

public struct InstagramStoryPlayerView: View {
    public let stories: [InstagramStoryItem]
    public let initialIndex: Int
    public let username: String
    public let profilePicURL: URL?
    public let onDownload: (URL?, Bool) -> Void

    @Environment(\.dismiss) var dismiss
    @State private var currentIndex: Int = 0
    @State private var isMuted: Bool = false
    @State private var downloadToast: String? = nil

    public init(
        stories: [InstagramStoryItem],
        initialIndex: Int,
        username: String,
        profilePicURL: URL?,
        onDownload: @escaping (URL?, Bool) -> Void
    ) {
        self.stories = stories
        self.initialIndex = initialIndex
        self.username = username
        self.profilePicURL = profilePicURL
        self.onDownload = onDownload
    }

    public var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            if currentIndex < stories.count {
                let currentStory = stories[currentIndex]

                // Visualizzazione Media: Video Player Reale o Foto
                GeometryReader { geo in
                    ZStack {
                        if currentStory.isVideo, let vidURL = currentStory.videoURL {
                            IncognitoVideoPlayerView(
                                url: vidURL,
                                isMuted: $isMuted,
                                autoPlay: true,
                                showSoundToggle: false,
                                onFinishedPlaying: {
                                    if currentIndex < stories.count - 1 {
                                        currentIndex += 1
                                    } else {
                                        dismiss()
                                    }
                                }
                            )
                            .frame(width: geo.size.width, height: geo.size.height)
                        } else if let imgURL = currentStory.imageURL {
                            AsyncImage(url: imgURL) { phase in
                                switch phase {
                                case .success(let img):
                                    img
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: geo.size.width, height: geo.size.height)
                                default:
                                    ProgressView().tint(.white)
                                }
                            }
                        }

                        // Aree di tocco per navigazione: sinistra (precedente), destra (successiva)
                        HStack(spacing: 0) {
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if currentIndex > 0 {
                                        currentIndex -= 1
                                    }
                                }

                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if currentIndex < stories.count - 1 {
                                        currentIndex += 1
                                    } else {
                                        dismiss()
                                    }
                                }
                        }
                    }
                }

                // Overlay Superiore: Barre di Progresso Segmentate + Info Autore + Tasti
                VStack {
                    // Barre di progresso segmentate in stile Instagram
                    HStack(spacing: 4) {
                        ForEach(0..<stories.count, id: \.self) { idx in
                            GeometryReader { segGeo in
                                Rectangle()
                                    .fill(idx <= currentIndex ? Color.white : Color.white.opacity(0.35))
                                    .cornerRadius(2)
                            }
                            .frame(height: 2.5)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    // Autore + Controllo Audio + Tasto Chiudi
                    HStack(spacing: 10) {
                        AsyncImage(url: profilePicURL) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().scaledToFill().frame(width: 34, height: 34).clipShape(Circle())
                            default:
                                Circle().fill(Color.white.opacity(0.2)).frame(width: 34, height: 34)
                            }
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text("@\(username)")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                            Text(currentStory.isVideo ? "Video" : "Foto")
                                .font(.system(size: 10))
                                .foregroundColor(.white.opacity(0.7))
                        }

                        Spacer()

                        if currentStory.isVideo {
                            Button {
                                isMuted.toggle()
                            } label: {
                                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(8)
                            }
                        }

                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .padding(8)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)

                    Spacer()

                    // Barra Inferiore: Salva direttamente nel Rullino Foto
                    HStack {
                        Spacer()

                        Button {
                            let isVid = currentStory.isVideo
                            let targetURL = isVid ? (currentStory.videoURL ?? currentStory.imageURL) : currentStory.imageURL
                            onDownload(targetURL, isVid)

                            let impact = UIImpactFeedbackGenerator(style: .medium)
                            impact.prepare()
                            impact.impactOccurred()

                            withAnimation(.spring()) {
                                downloadToast = isVid ? loc("viewer.saved_video_toast") : loc("viewer.saved_toast")
                            }
                            Task {
                                try? await Task.sleep(nanoseconds: 2_500_000_000)
                                withAnimation(.easeOut) {
                                    downloadToast = nil
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.down.to.line.compact")
                                    .font(.system(size: 15, weight: .bold))
                                Text(currentStory.isVideo ? loc("viewer.save_roll") + " (Video)" : loc("viewer.save_roll"))
                                    .font(.system(size: 13, weight: .bold))
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(.ultraThinMaterial)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                        }

                        Spacer()
                    }
                    .padding(.bottom, 30)
                }

                // Toast di notifica salvataggio all'interno dello story player
                if let toast = downloadToast {
                    VStack {
                        Spacer()
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.green)
                            Text(toast)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.85))
                        .clipShape(Capsule())
                        .padding(.bottom, 90)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
        }
        .onAppear {
            self.currentIndex = initialIndex
        }
    }
}

// MARK: - Scheda Dettaglio Post in Stile Instagram Feed (Video Player Reale + Caroselli Gestiti Perfettamente)

public struct InstagramPostDetailSheet: View {
    public let post: InstagramPostItem
    public let username: String
    public let userAvatar: URL?
    public let session: InstagramSession?
    public let onDownload: (URL?, Bool) -> Void
    @Environment(\.dismiss) var dismiss

    @State private var currentPost: InstagramPostItem
    @State private var carouselIndex: Int = 0
    @State private var isMuted: Bool = false
    @State private var downloadToast: String? = nil
    @State private var isDownloading: Bool = false
    @State private var isFetchingDetails: Bool = false

    public init(
        post: InstagramPostItem,
        username: String,
        userAvatar: URL?,
        session: InstagramSession? = nil,
        onDownload: @escaping (URL?, Bool) -> Void
    ) {
        self.post = post
        self._currentPost = State(initialValue: post)
        self.username = username
        self.userAvatar = userAvatar
        self.session = session
        self.onDownload = onDownload
    }

    public var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Header Autore
                        HStack(spacing: 10) {
                            AsyncImage(url: userAvatar) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable().scaledToFill().frame(width: 36, height: 36).clipShape(Circle())
                                default:
                                    Circle().fill(Color(UIColor.secondarySystemBackground)).frame(width: 36, height: 36)
                                }
                            }

                            Text("@\(username)")
                                .font(.system(size: 14, weight: .bold))

                            Spacer()

                            if isFetchingDetails {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 8)

                        // MEDIA: Carosello Multi-Foto/Video, Video Singolo con Player o Foto Singola
                        if currentPost.isCarousel && !currentPost.carouselItems.isEmpty {
                            VStack(spacing: 8) {
                                ZStack(alignment: .center) {
                                    TabView(selection: $carouselIndex) {
                                        ForEach(0..<currentPost.carouselItems.count, id: \.self) { idx in
                                            let item = currentPost.carouselItems[idx]
                                            ZStack {
                                                Color.black

                                                if item.isVideo, let vURL = item.videoURL {
                                                    IncognitoVideoPlayerView(
                                                        url: vURL,
                                                        isMuted: $isMuted,
                                                        autoPlay: idx == carouselIndex
                                                    )
                                                } else if let imgURL = item.imageURL {
                                                    AsyncImage(url: imgURL) { phase in
                                                        switch phase {
                                                        case .success(let img):
                                                            img
                                                                .resizable()
                                                                .scaledToFit()
                                                        default:
                                                            ProgressView().tint(.white)
                                                        }
                                                    }
                                                }
                                            }
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 390)
                                            .tag(idx)
                                        }
                                    }
                                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                                    .frame(height: 390)

                                    // Frecce di scorrimento laterali per facilitare lo swipe su tutti i dispositivi
                                    HStack {
                                        if carouselIndex > 0 {
                                            Button {
                                                withAnimation(.easeInOut(duration: 0.22)) {
                                                    carouselIndex -= 1
                                                }
                                            } label: {
                                                Image(systemName: "chevron.left.circle.fill")
                                                    .font(.system(size: 32))
                                                    .foregroundColor(.white.opacity(0.85))
                                                    .shadow(color: .black.opacity(0.6), radius: 4)
                                                    .padding(10)
                                            }
                                        }

                                        Spacer()

                                        if carouselIndex < currentPost.carouselItems.count - 1 {
                                            Button {
                                                withAnimation(.easeInOut(duration: 0.22)) {
                                                    carouselIndex += 1
                                                }
                                            } label: {
                                                Image(systemName: "chevron.right.circle.fill")
                                                    .font(.system(size: 32))
                                                    .foregroundColor(.white.opacity(0.85))
                                                    .shadow(color: .black.opacity(0.6), radius: 4)
                                                    .padding(10)
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 4)

                                    // Badge contatore carosello in stile Instagram (es. 1/5) in alto a destra
                                    VStack {
                                        HStack {
                                            Spacer()
                                            Text("\(carouselIndex + 1)/\(currentPost.carouselItems.count)")
                                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 9)
                                                .padding(.vertical, 4)
                                                .background(Color.black.opacity(0.65))
                                                .clipShape(Capsule())
                                                .padding(10)
                                        }
                                        Spacer()
                                    }
                                }

                                // Indicatore a pallini interattivi del carosello
                                HStack(spacing: 6) {
                                    ForEach(0..<currentPost.carouselItems.count, id: \.self) { idx in
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.22)) {
                                                carouselIndex = idx
                                            }
                                        } label: {
                                            Circle()
                                                .fill(idx == carouselIndex ? Color.blue : Color.secondary.opacity(0.35))
                                                .frame(width: idx == carouselIndex ? 7.5 : 5, height: idx == carouselIndex ? 7.5 : 5)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .padding(.top, 2)
                            }
                        } else if currentPost.isVideo {
                            // Video Singolo con Player Reale
                            ZStack {
                                Color.black

                                if let vidURL = currentPost.videoURL {
                                    IncognitoVideoPlayerView(
                                        url: vidURL,
                                        isMuted: $isMuted,
                                        autoPlay: true
                                    )
                                } else {
                                    // Thumbnail provvisorio mentre fetchPostDetails carica il video HD
                                    AsyncImage(url: currentPost.imageURL) { phase in
                                        switch phase {
                                        case .success(let img):
                                            img.resizable().scaledToFit()
                                        default:
                                            ProgressView().tint(.white)
                                        }
                                    }
                                    if isFetchingDetails {
                                        VStack(spacing: 8) {
                                            ProgressView().tint(.white)
                                            Text(loc("viewer.loading_media"))
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundColor(.white)
                                        }
                                        .padding(12)
                                        .background(Color.black.opacity(0.6))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 390)
                        } else {
                            // Foto Singola
                            AsyncImage(url: currentPost.imageURL) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable().scaledToFit()
                                default:
                                    Rectangle().fill(Color(UIColor.secondarySystemBackground)).frame(height: 380)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 390)
                        }

                        // Barra Azioni: Mi piace + Salvataggio DIRETTO nelle Foto (Nessun popup o menu di scelta)
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Image(systemName: "heart.fill")
                                    .foregroundColor(Color(red: 1.0, green: 0.22, blue: 0.38))
                                Text("\(currentPost.likeCount)")
                                    .font(.system(size: 14, weight: .bold))
                            }

                            Spacer()

                            if currentPost.isCarousel && !currentPost.carouselItems.isEmpty {
                                // Tasto Salva elemento attivo del Carosello
                                let currentItem = currentPost.carouselItems[carouselIndex]
                                Button {
                                    saveMediaItemDirectly(item: currentItem)
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: currentItem.isVideo ? "video.fill" : "arrow.down.circle.fill")
                                        Text("\(loc("viewer.save_roll")) (\(carouselIndex + 1)/\(currentPost.carouselItems.count))")
                                    }
                                    .font(.system(size: 12, weight: .bold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .clipShape(Capsule())
                                }

                                // Tasto Salva Tutti gli elementi del Carosello (se più di 1)
                                if currentPost.carouselItems.count > 1 {
                                    Button {
                                        saveAllCarouselItemsDirectly(items: currentPost.carouselItems)
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "square.and.arrow.down.on.square.fill")
                                            Text(loc("viewer.save_all"))
                                        }
                                        .font(.system(size: 12, weight: .bold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .background(Color(UIColor.secondarySystemBackground))
                                        .foregroundColor(.primary)
                                        .clipShape(Capsule())
                                    }
                                }
                            } else {
                                // Tasto Salva Singolo Post (Foto o Video) direttamente nelle Foto
                                Button {
                                    saveSinglePostDirectly()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: currentPost.isVideo ? "video.fill" : "arrow.down.circle.fill")
                                        Text(currentPost.isVideo ? loc("viewer.save_roll") + " (Video)" : loc("viewer.save_roll"))
                                    }
                                    .font(.system(size: 13, weight: .bold))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 7)
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 4)

                        // Didascalia
                        if !currentPost.caption.isEmpty {
                            HStack(alignment: .top, spacing: 6) {
                                Text("@\(username)")
                                    .font(.system(size: 13, weight: .bold))
                                Text(currentPost.caption)
                                    .font(.system(size: 13))
                            }
                            .padding(.horizontal, 14)
                        }
                    }
                    .padding(.bottom, 40)
                }

                // Toast di notifica salvataggio diretto nel rullino
                if let toast = downloadToast {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.green)
                        Text(toast)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Color(UIColor.secondarySystemGroupedBackground))
                    .clipShape(Capsule())
                    .shadow(color: Color.black.opacity(0.16), radius: 14, y: 6)
                    .padding(.bottom, 20)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("@\(username)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(loc("nav.close")) {
                        dismiss()
                    }
                }
            }
        }
        .task {
            // Risolvi automaticamente i dettagli completi del post (video_url HD o tutti gli slide del carosello)
            if (currentPost.isCarousel && currentPost.carouselItems.isEmpty) ||
               (currentPost.isVideo && currentPost.videoURL == nil) {
                if let sess = session ?? InstagramSessionManager.shared.currentSession {
                    isFetchingDetails = true
                    if let detailed = await AnonymousMediaService.shared.fetchPostDetails(shortcode: currentPost.id, session: sess) {
                        withAnimation(.easeInOut) {
                            if currentPost.isCarousel && detailed.carouselItems.isEmpty {
                                // Preserva la struttura carosello se il dettaglio ha restituito solo la prima miniatura
                            } else {
                                self.currentPost = detailed
                            }
                        }
                    }
                    isFetchingDetails = false
                }
            }
        }
    }

    // MARK: - Salvataggio Diretto nelle Foto (Nessun Popup)

    private func saveMediaItemDirectly(item: InstagramMediaSubItem) {
        guard !isDownloading else { return }
        let isVid = item.isVideo
        guard let url = isVid ? (item.videoURL ?? item.imageURL) : item.imageURL else { return }

        isDownloading = true
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.prepare()

        Task {
            do {
                _ = try await AnonymousMediaService.shared.downloadMedia(from: url, isVideo: isVid)
                impact.impactOccurred()
                withAnimation(.spring()) {
                    downloadToast = isVid ? loc("viewer.saved_video_toast") : loc("viewer.saved_toast")
                }
                try? await Task.sleep(nanoseconds: 2_600_000_000)
                withAnimation(.easeOut) {
                    downloadToast = nil
                }
            } catch {
                withAnimation {
                    downloadToast = loc("viewer.error_save")
                }
                try? await Task.sleep(nanoseconds: 2_600_000_000)
                withAnimation(.easeOut) {
                    downloadToast = nil
                }
            }
            isDownloading = false
        }
    }

    private func saveAllCarouselItemsDirectly(items: [InstagramMediaSubItem]) {
        guard !isDownloading else { return }
        isDownloading = true
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.prepare()

        Task {
            do {
                _ = try await AnonymousMediaService.shared.downloadAllMedia(items: items)
                impact.impactOccurred()
                withAnimation(.spring()) {
                    downloadToast = loc("viewer.saved_all_toast")
                }
                try? await Task.sleep(nanoseconds: 2_600_000_000)
                withAnimation(.easeOut) {
                    downloadToast = nil
                }
            } catch {
                withAnimation {
                    downloadToast = loc("viewer.error_save")
                }
                try? await Task.sleep(nanoseconds: 2_600_000_000)
                withAnimation(.easeOut) {
                    downloadToast = nil
                }
            }
            isDownloading = false
        }
    }

    private func saveSinglePostDirectly() {
        guard !isDownloading else { return }
        let isVid = currentPost.isVideo
        guard let url = isVid ? (currentPost.videoURL ?? currentPost.imageURL) : currentPost.imageURL else { return }

        isDownloading = true
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.prepare()

        Task {
            do {
                _ = try await AnonymousMediaService.shared.downloadMedia(from: url, isVideo: isVid)
                impact.impactOccurred()
                withAnimation(.spring()) {
                    downloadToast = isVid ? loc("viewer.saved_video_toast") : loc("viewer.saved_toast")
                }
                try? await Task.sleep(nanoseconds: 2_600_000_000)
                withAnimation(.easeOut) {
                    downloadToast = nil
                }
            } catch {
                withAnimation {
                    downloadToast = loc("viewer.error_save")
                }
                try? await Task.sleep(nanoseconds: 2_600_000_000)
                withAnimation(.easeOut) {
                    downloadToast = nil
                }
            }
            isDownloading = false
        }
    }
}

