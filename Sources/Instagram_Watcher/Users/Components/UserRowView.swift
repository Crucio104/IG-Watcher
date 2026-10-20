import SwiftUI

/// Riga profilo utente con avatar racchiuso da ring in stile Instagram Stories,
/// badge verificato e pulsante azione rapida sicura (Deep Link) uniformato
public struct UserRowView: View {
    public let user: InstagramUser
    public let customActionTitle: String?
    public let actionIcon: String
    public let actionColor: Color
    @State private var showingMediaViewer = false

    public init(
        user: InstagramUser,
        actionTitle: String? = nil,
        actionIcon: String = "arrow.up.right",
        actionColor: Color = .blue
    ) {
        self.user = user
        self.customActionTitle = actionTitle
        self.actionIcon = actionIcon
        self.actionColor = actionColor
    }

    public var body: some View {
        let actionTitle = customActionTitle ?? loc("action.view_profile")
        HStack(spacing: 12) {
            // Immagine profilo con ring colorato in stile Story
            ZStack {
                Circle()
                    .stroke(
                        Theme.instagramGradient,
                        lineWidth: 2
                    )
                    .frame(width: 48, height: 48)

                AsyncImage(url: user.profilePicURL) { phase in
                    switch phase {
                    case .empty:
                        Circle()
                            .fill(Color(UIColor.tertiarySystemFill))
                            .frame(width: 42, height: 42)
                            .overlay(ProgressView().scaleEffect(0.6))
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 42, height: 42)
                            .clipShape(Circle())
                    case .failure:
                        Circle()
                            .fill(Color(UIColor.tertiarySystemFill))
                            .frame(width: 42, height: 42)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(.secondary)
                            )
                    @unknown default:
                        EmptyView()
                    }
                }
            }

            // Dati anagrafici utente
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(user.username)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if user.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.blue)
                            .font(.system(size: 12))
                    }

                    if user.isPrivate {
                        Image(systemName: "lock.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 11))
                    }
                }

                if !user.fullName.isEmpty {
                    Text(user.fullName)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            // Pulsante Protezione VIP / Whitelist
            Button {
                WhitelistService.shared.toggleProtection(user: user)
            } label: {
                Image(systemName: WhitelistService.shared.isProtected(userID: user.id) ? "star.fill" : "star")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(WhitelistService.shared.isProtected(userID: user.id) ? Color(red: 1.0, green: 0.75, blue: 0.0) : Color.secondary.opacity(0.4))
                    .padding(6)
                    .background(
                        Circle()
                            .fill(WhitelistService.shared.isProtected(userID: user.id) ? Color(red: 1.0, green: 0.75, blue: 0.0).opacity(0.12) : Color.clear)
                    )
            }
            .buttonStyle(BorderlessButtonStyle())

            // Pulsante Visualizzatore Storie / Post Anonimo
            Button {
                showingMediaViewer = true
            } label: {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 15))
                    .foregroundColor(Color(red: 0.51, green: 0.15, blue: 0.79))
                    .padding(5)
                    .background(Color(red: 0.51, green: 0.15, blue: 0.79).opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(BorderlessButtonStyle())

            // Pulsante d'azione ONE-TAP UNIFORMATO
            Button {
                DailySafetyTracker.shared.recordAction()
                DeepLinkService.shared.openProfile(username: user.username)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: actionIcon)
                        .font(.system(size: 11, weight: .bold))
                    Text(actionTitle)
                        .font(.system(size: 12, weight: .bold))
                }
                .frame(minWidth: 84, minHeight: 32)
                .padding(.horizontal, 10)
                .background(
                    Capsule()
                        .fill(actionColor.opacity(0.12))
                )
                .foregroundColor(actionColor)
                .overlay(
                    Capsule()
                        .stroke(actionColor.opacity(0.28), lineWidth: 1)
                )
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showingMediaViewer) {
            AnonymousMediaViewerSheet(user: user)
                .id(user.id)
        }
    }
}
