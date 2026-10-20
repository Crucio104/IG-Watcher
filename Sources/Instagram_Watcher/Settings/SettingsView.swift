import SwiftUI

/// Vista impostazioni, lingua globale, backup database, sicurezza anti-ban e gestione sessione
public struct SettingsView: View {
    @ObservedObject var locManager = LocalizationManager.shared
    @ObservedObject var sessionManager = InstagramSessionManager.shared
    @ObservedObject var trackerService = FollowerTrackerService.shared

    @State private var notificationsEnabled = false
    @State private var showingLogoutAlert = false
    @State private var showingDataClearedAlert = false
    @State private var backupShareURL: URL? = nil
    @State private var showingShareSheet = false

    public var body: some View {
        Form {
            // Sezione Selezione Lingua Globale
            Section {
                Picker(selection: $locManager.currentLanguage) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName)
                            .tag(lang)
                    }
                } label: {
                    HStack(spacing: 12) {
                        settingsBadge(icon: "globe", color: .blue)
                        Text(loc("settings.language"))
                    }
                }
            } header: {
                Text(loc("settings.language_section"))
            }

            // Sezione Notifiche Push
            Section {
                HStack(spacing: 12) {
                    settingsBadge(icon: "bell.badge.fill", color: .red)
                    Toggle(loc("settings.notify_lost"), isOn: $notificationsEnabled)
                        .onChange(of: notificationsEnabled) { oldValue, newValue in
                            if newValue && !oldValue {
                                Task {
                                    let granted = await NotificationService.shared.requestAuthorization()
                                    if !granted {
                                        await MainActor.run {
                                            notificationsEnabled = false
                                        }
                                    }
                                }
                            }
                        }
                }
            } header: {
                Text(loc("settings.notifications_section"))
            } footer: {
                Text(loc("settings.notify_lost_desc"))
            }

            // Sezione Backup & Salvataggio Dati Permanente
            Section {
                Button {
                    if let fileURL = trackerService.exportBackupFile() {
                        self.backupShareURL = fileURL
                        self.showingShareSheet = true
                    }
                } label: {
                    HStack(spacing: 12) {
                        settingsBadge(icon: "arrow.down.doc.fill", color: .indigo)
                        Text(loc("settings.export_backup"))
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                    }
                }

                Button(role: .destructive) {
                    showingDataClearedAlert = true
                } label: {
                    HStack(spacing: 12) {
                        settingsBadge(icon: "trash.fill", color: .red)
                        Text(loc("settings.clear_data"))
                            .foregroundColor(.red)
                    }
                }
            } header: {
                Text(loc("settings.backup_section"))
            } footer: {
                Text(loc("settings.backup_footer"))
            }

            // Sezione Protezione Anti-Ban Certificata
            Section {
                HStack(spacing: 12) {
                    settingsBadge(icon: "shield.checkered", color: .green)
                    Text(loc("settings.protection_status"))
                    Spacer()
                    Text(loc("settings.status_active"))
                        .foregroundColor(.green)
                        .fontWeight(.semibold)
                }

                HStack(spacing: 12) {
                    settingsBadge(icon: "timer", color: .orange)
                    Text(loc("settings.delay_label"))
                    Spacer()
                    Text(loc("settings.delay_value"))
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 12) {
                    settingsBadge(icon: "pause.circle.fill", color: .purple)
                    Text(loc("settings.cooldown_label"))
                    Spacer()
                    Text(loc("settings.cooldown_value"))
                        .foregroundColor(.secondary)
                }

                HStack(spacing: 12) {
                    settingsBadge(icon: "hand.tap.fill", color: .teal)
                    Text(loc("settings.actions_label"))
                    Spacer()
                    Text(loc("settings.actions_value"))
                        .foregroundColor(.blue)
                }
            } header: {
                Text(loc("settings.antiban_section"))
            } footer: {
                Text(loc("settings.antiban_footer"))
            }

            // Sezione Sessione Instagram & Disconnessione
            Section {
                if let session = sessionManager.currentSession {
                    HStack(spacing: 12) {
                        settingsBadge(icon: "person.crop.circle.fill", color: .gray)
                        Text(loc("settings.user_id"))
                        Spacer()
                        Text(session.userID)
                            .foregroundColor(.secondary)
                            .font(.system(.body, design: .monospaced))
                    }
                }

                Button(role: .destructive) {
                    showingLogoutAlert = true
                } label: {
                    HStack {
                        Spacer()
                        Text(loc("settings.logout"))
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
            } header: {
                Text(loc("settings.session_section"))
            }
        }
        .navigationTitle(loc("settings.title"))
        .task {
            notificationsEnabled = await NotificationService.shared.isAuthorized()
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = backupShareURL {
                ShareSheet(items: [url])
            }
        }
        .alert(loc("settings.logout"), isPresented: $showingLogoutAlert) {
            Button(loc("settings.cancel"), role: .cancel) {}
            Button(loc("settings.logout_confirm"), role: .destructive) {
                sessionManager.logout()
            }
        } message: {
            Text(loc("settings.logout_message"))
        }
        .alert(loc("settings.clear_confirm"), isPresented: $showingDataClearedAlert) {
            Button(loc("settings.cancel"), role: .cancel) {}
            Button(loc("settings.clear_confirm"), role: .destructive) {
                trackerService.clearAllData()
            }
        } message: {
            Text(loc("settings.clear_message"))
        }
    }

    private func settingsBadge(icon: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(color)
                .frame(width: 28, height: 28)
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
        }
    }
}
