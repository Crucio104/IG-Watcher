import Foundation

/// Sistema Anti-Ban avanzato per proteggere l'account Instagram da rilevamenti bot e shadowban.
/// Simula il comportamento umano di navigazione con delay variabili randomizzati e pause strategiche.
public actor AntiBanRateLimiter {
    public static let shared = AntiBanRateLimiter()

    private var requestCount: Int = 0
    private let baseDelayRange: ClosedRange<Double> = 2.0...4.5      // Secondi di attesa normale tra pagine consecutive
    private let cooldownBatchSize: Int = 5                            // Ogni quante pagine fare una pausa di raffreddamento
    private let cooldownDelayRange: ClosedRange<Double> = 7.0...12.0   // Secondi di pausa raffreddamento

    private init() {}

    /// Esegue una pausa asincrona simulando tempi di navigazione umani
    /// - Parameter pageIndex: Indice di pagina corrente (la pagina 1 parte subito senza attesa)
    public func waitHumanDelay(pageIndex: Int = 2, onStatusUpdate: (@Sendable (String) -> Void)? = nil) async throws {
        // La pagina 1 viene caricata immediatamente per una risposta istantanea all'utente
        guard pageIndex > 1 else { return }

        requestCount += 1
        let isCooldown = (requestCount % cooldownBatchSize == 0)
        let delaySeconds = isCooldown ? Double.random(in: cooldownDelayRange) : Double.random(in: baseDelayRange)

        let msg = isCooldown
            ? String(format: "🛡️ Anti-ban cooldown: %.1fs...", delaySeconds)
            : String(format: "⏱️ Human pacing delay: %.1fs...", delaySeconds)
        onStatusUpdate?(msg)

        let nanoSeconds = UInt64(delaySeconds * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoSeconds)
    }

    /// Reset del contatore sessione
    public func reset() {
        requestCount = 0
    }

    /// Backoff esponenziale di protezione in caso di avviso HTTP 429 da Instagram
    public func handleRateLimitWarning(retryCount: Int, onStatusUpdate: (@Sendable (String) -> Void)? = nil) async throws {
        let backoff = min(60.0 * Double(retryCount), 180.0)
        let msg = String(format: "⚠️ Instagram rate limit warning. Cooling down for %.0fs...", backoff)
        onStatusUpdate?(msg)
        try await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
    }
}
