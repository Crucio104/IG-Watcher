# 📱 Instagram Watcher per iPhone (iOS / SwiftUI)

App nativa in Swift / SwiftUI progettata per monitorare, analizzare e confrontare i tuoi follower e seguiti di Instagram, con **priorità assoluta alla protezione del tuo account da ban, blocchi temporanei e shadowban**.

---

## ✨ Funzionalità Principali

1. **3 Categorie di Confronto Immediate**:
   - 🔴 **Non ti seguono**: Profili che segui, ma che non ricambiano il tuo follow.
   - 🟢 **I tuoi Fan**: Profili che ti seguono, ma che tu non segui.
   - 🔵 **Follower Reciproci**: Profili con cui vi seguite a vicenda.
2. **📉 Tracciamento Follower Persi con Notifiche**:
   - Confronta automaticamente ogni nuova scansione con lo storico salvato.
   - Registra chi ha smesso di seguirti con **data e ora esatta**.
   - Invia una notifica locale iOS (`UNUserNotificationCenter`) appena viene rilevato un defollow.
3. **🛡️ Follow / Unfollow Sicuro (Zero Rischio Ban)**:
   - Integrazione con **Deep Link nativo** (`instagram://user?username=...`).
   - Toccando il pulsante nella lista, si apre istantaneamente il profilo nell'app ufficiale Instagram per compiere l'azione con 1 tap, autenticata direttamente da Meta.
   - Questo azzera totalmente il rischio di "Azione bloccata" causato dalle chiamate bot emulate.
4. **🧠 Algoritmo Anti-Ban Umano (`AntiBanRateLimiter`)**:
   - Ritardi casuali e non costanti (Jitter tra 2.8s e 5.2s) tra ogni singola pagina.
   - Pause di raffreddamento prolungate (8s - 14s) ogni 4 pagine.
   - User-Agent mobile autentico estratto dal browser WebKit di sistema.
   - Gestione automatica del backoff protettivo in caso di codice HTTP 429.

---

## ⚠️ Nota Tecnica Trasparente: "Chi visita il mio profilo?"

Nel tuo messaggio chiedevi se fosse possibile sapere chi visita il tuo profilo:
- **La risposta tecnica ufficiale è NO: è impossibile.**
- **Perché?** I server di Meta / Instagram non registrano né rendono accessibili i log dei singoli visitatori a nessuna API (né pubblica, né privata) per stringenti ragioni di privacy e architettura distribuita.
- **Tutte le app sull'App Store che promettono "Scopri chi ti spia" sono truffe (scam/phishing)**: mostrano profili generati casualmente o amici con cui hai interagito di recente, con il solo scopo di far pagare abbonamenti o rubare le credenziali.
- Gli unici dati che Instagram fornisce (e solo per account Professional/Creator) sono dati **aggregati anonimi** (es. *"42 visite al profilo questa settimana"*), mai l'elenco degli username.

---

## 📂 Struttura del Progetto

```
Instagram watcher/
├── Info.plist                                 # Configurazione query schemes (instagram://) e permessi
├── README.md                                  # Questa documentazione
└── Sources/
    ├── App/
    │   └── InstagramWatcherApp.swift          # Entry point SwiftUI e gestione notifiche
    ├── Models/
    │   ├── InstagramUser.swift                # Modello utente e record follower persi
    │   └── ComparisonResult.swift             # Categorie e snapshot storico
    ├── Services/
    │   ├── InstagramSessionManager.swift      # Gestione sicura cookie WKWebView
    │   ├── InstagramAPIService.swift          # Fetch protetto liste follower/following
    │   ├── FollowerTrackerService.swift       # Algoritmo di confronto e tracking defollow
    │   ├── DeepLinkService.swift              # Apertura profilo 1-tap nell'app Instagram
    │   └── NotificationService.swift          # Notifiche push locali iOS
    ├── Utilities/
    │   └── AntiBanRateLimiter.swift           # Ritardi casuali e protezione anti-bot
    └── Views/
        ├── Dashboard/
        │   ├── DashboardView.swift            # Schermata principale e KPI
        │   └── Components/
        │       └── StatCardView.swift         # Card interattive per categoria
        ├── Login/
        │   └── InstagramLoginWebView.swift    # Login sicuro nel browser WebKit
        ├── Users/
        │   ├── UserListView.swift             # Vista elenco filtrabile con ricerca
        │   └── Components/
        │       └── UserRowView.swift          # Riga utente con avatar e pulsante rapido
        ├── LostFollowers/
        │   └── LostFollowersHistoryView.swift # Storico cronologico follower persi
        └── Settings/
            └── SettingsView.swift             # Impostazioni, notifiche e trasparenza
```

---

## 🚀 Come installare ed eseguire l'app su iPhone tramite Xcode

Non serve pagare l'account Apple Developer da 99$/anno: puoi installarla gratis usando il tuo normale Apple ID!

1. **Apri Xcode sul tuo Mac**.
2. Fai clic su **File > New > Project...**
3. Seleziona **iOS > App** e clicca su **Next**.
4. Imposta:
   - **Product Name**: `InstagramWatcher`
   - **Interface**: `SwiftUI`
   - **Language**: `Swift`
5. Trascina la cartella `Sources` e il file `Info.plist` nel nuovo progetto in Xcode.
6. Collega il tuo iPhone al Mac con il cavetto USB.
7. Nelle impostazioni del target in Xcode (**Signing & Capabilities**):
   - Seleziona il tuo **Team** (il tuo Apple ID personale).
   - Inserisci un Bundle Identifier univoco (es. `com.tuonome.instagramwatcher`).
8. Seleziona il tuo iPhone come dispositivo di destinazione in alto e premi il tasto **Play (Run)**.
9. Sull'iPhone: se al primo avvio compare *"Sviluppatore non attendibile"*, vai su:
   - **Impostazioni > Generali > Gestione VPN e dispositivo** > fai tap sul tuo Apple ID e premi **Autorizza**.
