import SwiftUI

/// Dashboard principale dell'applicazione ridisegnata con estetica di lusso,
/// luce ambientale sfumata, schede interattive, pull-to-refresh e supporto multilingua.
public struct DashboardView: View {
    @ObservedObject var locManager = LocalizationManager.shared
    @ObservedObject var sessionManager = InstagramSessionManager.shared
    @ObservedObject var trackerService = FollowerTrackerService.shared

    @State private var showingLoginSheet = false
    @State private var showingSettings = false
    @State private var showingAnonymousSearch = false
    @State private var pulseAnimation = false

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    public var body: some View {
        NavigationView {
            ZStack {
                // Sfondo con luce ambientale sfumata in alto
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()

                // Bagliore di luce ambientale in stile Instagram
                VStack {
                    RadialGradient(
                        colors: [
                            Color(red: 0.51, green: 0.15, blue: 0.79).opacity(0.14),
                            Color(red: 0.88, green: 0.17, blue: 0.44).opacity(0.06),
                            Color.clear
                        ],
                        center: .top,
                        startRadius: 0,
                        endRadius: 320
                    )
                    .frame(height: 320)
                    .ignoresSafeArea()

                    Spacer()
                }

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        if !sessionManager.isLoggedIn {
                            welcomeHeroCard
                        } else {
                            // Header profilo & stato protezione live
                            profileStatusHeader

                            // Monitor sincronizzazione dinamico: attivo SOLO durante il caricamento o errore
                            if trackerService.isAnalyzing || trackerService.lastErrorMessage != nil {
                                syncStatusBar
                            }

                            // Bento 1: Audit Salute & Tasso Reciprocità con anello dinamico
                            accountHealthBentoCard

                            // Bento 2: Variazioni Follower (Nuovi Follower vs Follower Persi)
                            followerDynamicsSection

                            // Bento 3: Relazioni Account (Non ricambiano full-width + Fan & Reciproci)
                            accountRelationshipsSection
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 28)
                }
                .refreshable {
                    if sessionManager.isLoggedIn && !trackerService.isAnalyzing {
                        startSync()
                    }
                }
            }
            .task {
                if sessionManager.isLoggedIn {
                    InstagramWebBridge.shared.prepare()
                    loadProfileIfNeeded()
                    await trackerService.refreshActiveStories()
                }
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    pulseAnimation = true
                }
                if sessionManager.isLoggedIn {
                    InstagramWebBridge.shared.prepare()
                    if sessionManager.currentUserProfile == nil || sessionManager.currentUserProfile?.profilePicURL == nil {
                        loadProfileIfNeeded()
                    }
                    Task {
                        await trackerService.refreshActiveStories()
                    }
                }
            }
            .onChange(of: sessionManager.isLoggedIn) { _, loggedIn in
                if loggedIn {
                    InstagramWebBridge.shared.prepare()
                    loadProfileIfNeeded()
                    Task {
                        await trackerService.refreshActiveStories()
                    }
                }
            }
            .navigationTitle(loc("app.title"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        if sessionManager.isLoggedIn {
                            Button {
                                startSync()
                            } label: {
                                if trackerService.isAnalyzing {
                                    ProgressView()
                                        .tint(.primary)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.primary)
                                        .padding(8)
                                        .background(Color(UIColor.secondarySystemGroupedBackground))
                                        .clipShape(Circle())
                                        .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
                                }
                            }
                            .disabled(trackerService.isAnalyzing)
                        }

                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.primary)
                                .padding(8)
                                .background(Color(UIColor.secondarySystemGroupedBackground))
                                .clipShape(Circle())
                                .shadow(color: Color.black.opacity(0.04), radius: 4, y: 2)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingLoginSheet) {
                NavigationView {
                    InstagramLoginWebView(onLoginSuccess: { _ in
                        self.startSync()
                    })
                    .navigationTitle(loc("nav.official_login"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(loc("nav.close")) {
                                showingLoginSheet = false
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                NavigationView {
                    SettingsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(loc("nav.done")) {
                                    showingSettings = false
                                }
                                .fontWeight(.bold)
                            }
                        }
                }
            }
            .sheet(isPresented: $showingAnonymousSearch) {
                AnonymousSearchSheet()
            }
        }
    }

    // MARK: - Componenti Grafici Dashboard

    /// Header profilo con avatar reale, username linkato e indicatore di sicurezza
    private var profileStatusHeader: some View {
        HStack(spacing: 12) {
            // Immagine profilo con ring Instagram gradient
            Button {
                if let username = sessionManager.currentUserProfile?.username {
                    DeepLinkService.shared.openProfile(username: username)
                }
            } label: {
                ZStack {
                    Circle()
                        .stroke(Theme.instagramGradient, lineWidth: 2.2)
                        .frame(width: 44, height: 44)

                    if let picURL = sessionManager.currentUserProfile?.profilePicURL {
                        AsyncImage(url: picURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 38, height: 38)
                                    .clipShape(Circle())
                            case .empty:
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .frame(width: 38, height: 38)
                            default:
                                fallbackAvatar
                            }
                        }
                        .id(picURL)
                    } else {
                        fallbackAvatar
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())

            // Username e nome completo
            VStack(alignment: .leading, spacing: 3) {
                if let profile = sessionManager.currentUserProfile {
                    HStack(spacing: 4) {
                        Text("@\(profile.username)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.primary)

                        if profile.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.blue)
                        }
                    }

                    Text(profile.fullName.isEmpty ? loc("app.title") : profile.fullName)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else {
                    Button {
                        loadProfileIfNeeded()
                    } label: {
                        HStack(spacing: 6) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text(loc("status.loading_profile"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())

                    Text(loc("app.title"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                        .scaleEffect(pulseAnimation ? 1.25 : 0.9)

                    Text(loc("status.shield_active"))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.green)
                }
            }

            Spacer()

            if !trackerService.isAnalyzing {
                Button {
                    startSync()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                        Text(loc("status.update_now"))
                            .font(.system(size: 12, weight: .bold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.blue.opacity(0.12))
                    .foregroundColor(.blue)
                    .clipShape(Capsule())
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 18)
    }

    private var fallbackAvatar: some View {
        Circle()
            .fill(Color(UIColor.tertiarySystemFill))
            .frame(width: 38, height: 38)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
            )
    }

    private func loadProfileIfNeeded() {
        guard let session = sessionManager.currentSession else { return }
        let knownUsername = sessionManager.currentUserProfile?.username ?? UserDefaults.standard.string(forKey: "com.instagramwatcher.cached_username")
        Task {
            // Tentativo 1: WebKit autenticato con credenziali live (estrae username e avatar con Regex/DOM e Feed)
            if let jsonString = await InstagramWebBridge.shared.fetchCurrentUserProfile(userID: session.userID, username: knownUsername),
               let data = jsonString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let uname = (json["username"] as? String) ?? (knownUsername ?? "")
                let fullName = (json["full_name"] as? String) ?? (json["first_name"] as? String) ?? ""
                let isVerified = (json["is_verified"] as? Bool) ?? false
                let rawPic = (json["profile_pic_url_hd"] as? String) ??
                             (json["profile_pic_url"] as? String) ??
                             ((json["hd_profile_pic_url_info"] as? [String: Any])?["url"] as? String) ??
                             (((json["hd_profile_pic_versions"] as? [[String: Any]])?.first)?["url"] as? String)
                let picURL = rawPic.flatMap { URL(string: $0.replacingOccurrences(of: "&amp;", with: "&")) }
                if !uname.isEmpty {
                    let user = InstagramUser(
                        id: session.userID,
                        username: uname,
                        fullName: fullName,
                        profilePicURL: picURL ?? sessionManager.currentUserProfile?.profilePicURL,
                        isVerified: isVerified
                    )
                    await MainActor.run {
                        sessionManager.updateUserProfile(user)
                    }
                    if picURL != nil {
                        return
                    }
                }
            }

            // Tentativo 2: Risolvi direttamente tramite la pagina profilo utente con AnonymousMediaService
            if let uname = (sessionManager.currentUserProfile?.username ?? knownUsername), !uname.isEmpty {
                let candidate = InstagramUser(id: session.userID, username: uname)
                let resolved = await AnonymousMediaService.shared.resolveProfile(user: candidate, session: session)
                if let pic = resolved.profilePicURL {
                    let updatedUser = InstagramUser(
                        id: resolved.id.isEmpty ? session.userID : resolved.id,
                        username: resolved.username.isEmpty ? uname : resolved.username,
                        fullName: resolved.fullName.isEmpty ? (sessionManager.currentUserProfile?.fullName ?? "") : resolved.fullName,
                        profilePicURL: pic,
                        isVerified: resolved.isVerified,
                        isPrivate: resolved.isPrivate,
                        mediaCount: resolved.postsCount
                    )
                    await MainActor.run {
                        sessionManager.updateUserProfile(updatedUser)
                    }
                    return
                }
            }

            // Tentativo 3: API Ufficiale (web_profile_info o accounts/current_user)
            if let profile = try? await InstagramAPIService.shared.fetchCurrentUserProfile(session: session, username: knownUsername) {
                if profile.profilePicURL != nil {
                    await MainActor.run {
                        sessionManager.updateUserProfile(profile)
                    }
                    return
                }
            }
        }
    }

    /// Card di benvenuto per utenti non ancora autenticati
    private var welcomeHeroCard: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(Theme.instagramGradient)
                    .frame(width: 86, height: 86)
                    .shadow(color: Color(red: 0.88, green: 0.17, blue: 0.44).opacity(0.4), radius: 20, x: 0, y: 8)

                Image(systemName: "eye.trianglebadge.exclamationmark")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.top, 6)

            VStack(spacing: 8) {
                Text(loc("welcome.title"))
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(.primary)

                Text(loc("welcome.subtitle"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 10)
            }

            VStack(alignment: .leading, spacing: 12) {
                benefitRow(icon: "shield.lefthalf.filled", color: .green, title: loc("welcome.benefit1.title"), desc: loc("welcome.benefit1.desc"))
                benefitRow(icon: "person.2.fill", color: .blue, title: loc("welcome.benefit2.title"), desc: loc("welcome.benefit2.desc"))
                benefitRow(icon: "bell.badge.fill", color: .orange, title: loc("welcome.benefit3.title"), desc: loc("welcome.benefit3.desc"))
            }
            .padding(16)
            .background(Color(UIColor.tertiarySystemGroupedBackground))
            .cornerRadius(16)

            Button {
                showingLoginSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 16, weight: .bold))
                    Text(loc("welcome.connect_button"))
                        .font(.system(size: 16, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.instagramGradient)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Color(red: 0.88, green: 0.17, blue: 0.44).opacity(0.4), radius: 14, x: 0, y: 7)
            }
            .padding(.top, 4)
        }
        .padding(22)
        .glassCard(cornerRadius: 24)
    }

    private func benefitRow(icon: String, color: Color, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
                Text(desc)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }

    /// Barra di avanzamento sincronizzazione in tempo reale
    private var syncStatusBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 8) {
                    Circle()
                        .fill(trackerService.isAnalyzing ? Color.green : (trackerService.lastErrorMessage != nil ? Color.red : Color.blue))
                        .frame(width: 9, height: 9)
                        .scaleEffect(trackerService.isAnalyzing && pulseAnimation ? 1.3 : 1.0)

                    Text(trackerService.isAnalyzing ? loc("status.syncing") : (trackerService.lastErrorMessage != nil ? loc("status.attention") : loc("status.shield_active")))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(trackerService.isAnalyzing ? .green : (trackerService.lastErrorMessage != nil ? .red : .blue))
                }

                Spacer()

                if trackerService.lastErrorMessage != nil && !trackerService.isAnalyzing {
                    Button(loc("status.retry")) {
                        startSync()
                    }
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.red)
                    .clipShape(Capsule())
                }
            }

            if let errorMsg = trackerService.lastErrorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.footnote)
                    Text(errorMsg)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(Color.red.opacity(0.08))
                .cornerRadius(10)
            } else {
                Text(trackerService.statusMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }

            if trackerService.isAnalyzing {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView()
                        .progressViewStyle(LinearProgressViewStyle(tint: .blue))

                    if trackerService.progressCount > 0 {
                        HStack {
                            Text("\(trackerService.progressCount) \(loc("status.processed_count"))")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                }
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 18)
    }

    /// Scheda Audit & Tasso di reciprocità con anello dinamico
    private var accountHealthBentoCard: some View {
        HStack(spacing: 16) {
            // Anello circolare di reciprocità
            ZStack {
                Circle()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 8)
                    .frame(width: 80, height: 80)

                Circle()
                    .trim(from: 0, to: CGFloat(max(trackerService.latestResult.reciprocityRate / 100.0, 0.03)))
                    .stroke(
                        Theme.instagramGradient,
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 80, height: 80)
                    .animation(.spring(response: 0.8, dampingFraction: 0.7), value: trackerService.latestResult.reciprocityRate)

                VStack(spacing: 1) {
                    Text("\(Int(round(trackerService.latestResult.reciprocityRate)))%")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundColor(.primary)
                    Text(loc("totals.reciprocity"))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                }
            }

            // Colonna destra: badge salute e totali rapidi
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(auditStatusColor)
                            .frame(width: 7, height: 7)
                        Text(auditStatusText)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(auditStatusColor)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(auditStatusColor.opacity(0.12))
                    .clipShape(Capsule())

                    Spacer()

                    Text(loc("totals.audit"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("totals.followers"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("\(trackerService.latestResult.totalFollowersCount)")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundColor(.primary)
                    }

                    Divider()
                        .frame(height: 22)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("totals.following"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text("\(trackerService.latestResult.totalFollowingCount)")
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundColor(.primary)
                    }

                    Divider()
                        .frame(height: 22)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("totals.ratio"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(String(format: "%.2f", trackerService.latestResult.ratio))
                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                            .foregroundColor(Color(red: 0.99, green: 0.47, blue: 0.22))
                    }
                }
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 20)
    }

    private var auditStatusText: String {
        let rate = trackerService.latestResult.reciprocityRate
        if rate >= 70 {
            return loc("totals.audit_optimal")
        } else if rate >= 40 {
            return loc("totals.audit_balanced")
        } else {
            return loc("totals.audit_attention")
        }
    }

    private var auditStatusColor: Color {
        let rate = trackerService.latestResult.reciprocityRate
        if rate >= 70 {
            return Color.green
        } else if rate >= 40 {
            return Color.blue
        } else {
            return Color.orange
        }
    }

    /// Sezione variazioni follower tra scan: Nuovi Follower (+) e Follower Persi (-)
    private var followerDynamicsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(red: 0.88, green: 0.17, blue: 0.44))
                Text(loc("dashboard.dynamics"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 4)

            HStack(spacing: 12) {
                // Nuovi follower acquisiti
                NavigationLink {
                    GainedFollowersHistoryView(
                        records: trackerService.latestResult.gainedFollowers
                    )
                } label: {
                    variationCard(
                        title: loc("category.gained"),
                        count: trackerService.latestResult.gainedFollowers.count,
                        prefix: "+",
                        subtitle: loc("category.gained_sub"),
                        icon: "person.badge.plus",
                        accentColor: Color(red: 0.10, green: 0.78, blue: 0.48),
                        gradient: LinearGradient(
                            colors: [Color(red: 0.10, green: 0.78, blue: 0.48), Color(red: 0.05, green: 0.58, blue: 0.78)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
                .buttonStyle(PlainButtonStyle())

                // Follower persi
                NavigationLink {
                    LostFollowersHistoryView(
                        records: trackerService.latestResult.lostFollowers
                    )
                } label: {
                    variationCard(
                        title: loc("category.lost"),
                        count: trackerService.latestResult.lostFollowers.count,
                        prefix: "-",
                        subtitle: loc("category.lost_sub"),
                        icon: "clock.arrow.circlepath",
                        accentColor: Color(red: 0.95, green: 0.45, blue: 0.12),
                        gradient: Theme.lostGradient
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    private func variationCard(title: String, count: Int, prefix: String, subtitle: String, icon: String, accentColor: Color, gradient: LinearGradient) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(gradient)
                        .frame(width: 36, height: 36)
                        .shadow(color: accentColor.opacity(0.3), radius: 6, y: 3)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                Spacer()
                Text("\(prefix)\(count)")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                    .foregroundColor(accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 18)
    }

    /// Sezione relazioni: Non ricambiano (Full-width hero) + Fan e Reciproci
    private var accountRelationshipsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "person.2.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(red: 0.51, green: 0.15, blue: 0.79))
                Text(loc("dashboard.relationships"))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 4)

            // 1. Non ti seguono (Hero Card full width)
            NavigationLink {
                UserListView(
                    category: .notFollowingBack,
                    users: trackerService.latestResult.notFollowingBack
                )
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(Theme.notFollowingGradient)
                            .frame(width: 48, height: 48)
                            .shadow(color: Color(red: 1.0, green: 0.22, blue: 0.38).opacity(0.35), radius: 8, y: 4)
                        Image(systemName: "person.badge.minus")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(loc("category.not_following_back"))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.primary)
                        Text(loc("category.not_following_back_sub"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(trackerService.latestResult.notFollowingBack.count)")
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundColor(Color(red: 1.0, green: 0.22, blue: 0.38))

                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(14)
                .glassCard(cornerRadius: 18)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color(red: 1.0, green: 0.22, blue: 0.38).opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())

            // 2. Griglia Fan e Reciproci
            LazyVGrid(columns: columns, spacing: 12) {
                // Fan
                NavigationLink {
                    UserListView(
                        category: .fans,
                        users: trackerService.latestResult.fans
                    )
                } label: {
                    StatCardView(
                        title: loc("category.fans"),
                        count: trackerService.latestResult.fans.count,
                        subtitle: loc("category.fans_sub"),
                        systemIcon: "star.fill",
                        gradient: Theme.fansGradient,
                        accentColor: Color(red: 0.05, green: 0.75, blue: 0.55)
                    )
                }
                .buttonStyle(PlainButtonStyle())

                // Reciproci
                NavigationLink {
                    UserListView(
                        category: .mutuals,
                        users: trackerService.latestResult.mutuals
                    )
                } label: {
                    StatCardView(
                        title: loc("category.mutuals"),
                        count: trackerService.latestResult.mutuals.count,
                        subtitle: loc("category.mutuals_sub"),
                        systemIcon: "arrow.2.squarepath",
                        gradient: Theme.mutualsGradient,
                        accentColor: Color(red: 0.38, green: 0.28, blue: 0.95)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }

            // 3. Follower Fantasma (Inattivi / Senza foto)
            NavigationLink {
                UserListView(
                    category: .ghosts,
                    users: trackerService.latestResult.ghostFollowers
                )
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(Theme.ghostsGradient)
                            .frame(width: 48, height: 48)
                            .shadow(color: Color(red: 0.58, green: 0.35, blue: 0.92).opacity(0.35), radius: 8, y: 4)
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(loc("category.ghosts"))
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.primary)
                        Text(loc("category.ghosts_sub"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(trackerService.latestResult.ghostFollowers.count)")
                            .font(.system(size: 26, weight: .heavy, design: .rounded))
                            .foregroundColor(Color(red: 0.58, green: 0.35, blue: 0.92))

                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(14)
                .glassCard(cornerRadius: 18)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color(red: 0.58, green: 0.35, blue: 0.92).opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())

            // 4. Storie & Post in Incognito / Downloader anonimo
            Button {
                showingAnonymousSearch = true
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(Theme.anonymousGradient)
                            .frame(width: 48, height: 48)
                            .shadow(color: Color(red: 0.12, green: 0.53, blue: 0.90).opacity(0.35), radius: 8, y: 4)
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(loc("dashboard.anonymous_viewer"))
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.primary)

                            Text("100% GHOST")
                                .font(.system(size: 8, weight: .black, design: .rounded))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(red: 0.12, green: 0.53, blue: 0.90))
                                .clipShape(Capsule())
                        }

                        Text(loc("dashboard.anonymous_viewer_sub"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "magnifyingglass.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Color(red: 0.12, green: 0.53, blue: 0.90))
                }
                .padding(14)
                .glassCard(cornerRadius: 18)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color(red: 0.12, green: 0.53, blue: 0.90).opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    private func startSync() {
        guard let session = sessionManager.currentSession else {
            showingLoginSheet = true
            return
        }
        Task {
            await trackerService.runAnalysis(session: session)
        }
    }
}
