import Foundation
import os.log

private let logger = Logger(subsystem: "com.opencodeproviders", category: "DeepSeekProvider")

/// Provider for DeepSeek API credit balance tracking
/// Uses pay-as-you-go billing model with prepaid credits
final class DeepSeekProvider: ProviderProtocol {
    let identifier: ProviderIdentifier = .deepSeek
    let type: ProviderType = .payAsYouGo

    // MARK: - API Response Structures

    /// Response structure for GET /user/balance endpoint
    private struct BalanceResponse: Codable {
        let isAvailable: Bool?
        let balanceInfos: [BalanceInfo]?

        enum CodingKeys: String, CodingKey {
            case isAvailable = "is_available"
            case balanceInfos = "balance_infos"
        }
    }

    private struct BalanceInfo: Codable {
        let currency: String?
        let totalBalance: String?
        let grantedBalance: String?
        let toppedUpBalance: String?

        enum CodingKeys: String, CodingKey {
            case currency
            case totalBalance = "total_balance"
            case grantedBalance = "granted_balance"
            case toppedUpBalance = "topped_up_balance"
        }
    }

    // MARK: - ProviderProtocol

    func fetch() async throws -> ProviderResult {
        guard let apiKey = TokenManager.shared.getDeepSeekAPIKey() else {
            logger.error("Failed to retrieve DeepSeek API key")
            throw ProviderError.authenticationFailed("DeepSeek API key not found")
        }

        let balanceResponse = try await fetchBalance(apiKey: apiKey)

        guard let balanceInfos = balanceResponse.balanceInfos, !balanceInfos.isEmpty else {
            logger.warning("No balance info returned from DeepSeek API")
            throw ProviderError.providerError("No balance information available")
        }

        // Use the first balance info entry (typically USD or primary currency)
        guard let primaryBalance = balanceInfos.first,
              let totalBalanceStr = primaryBalance.totalBalance,
              let totalBalance = Double(totalBalanceStr) else {
            throw ProviderError.decodingError("Could not parse total balance")
        }

        let grantedBalance = Double(primaryBalance.grantedBalance ?? "0") ?? 0.0
        let toppedUpBalance = Double(primaryBalance.toppedUpBalance ?? "0") ?? 0.0
        let currency = primaryBalance.currency ?? "USD"

        // For pay-as-you-go: utilization is not meaningful (no upper bound on top-ups)
        // We use cost = total_balance (remaining credit), utilization = 0
        logger.info("Successfully fetched DeepSeek balance: \(currency) \(String(format: "%.2f", totalBalance)) (granted: \(String(format: "%.2f", grantedBalance)), topped-up: \(String(format: "%.2f", toppedUpBalance)))")

        let details = DetailedUsage(
            totalCredits: totalBalance,
            remainingCredits: totalBalance,
            monthlyCost: totalBalance,
            creditsRemaining: totalBalance,
            creditsTotal: totalBalance + grantedBalance + toppedUpBalance,
            authSource: "~/.local/share/opencode/auth.json"
        )

        return ProviderResult(
            usage: .payAsYouGo(utilization: 0.0, cost: totalBalance, resetsAt: nil),
            details: details
        )
    }

    // MARK: - Private API Methods

    /// Fetches credit balance from DeepSeek API
    /// - Parameter apiKey: DeepSeek API key
    /// - Returns: BalanceResponse containing balance information
    private func fetchBalance(apiKey: String) async throws -> BalanceResponse {
        let endpoint = "https://api.deepseek.com/user/balance"

        guard let url = URL(string: endpoint) else {
            logger.error("Invalid balance endpoint URL")
            throw ProviderError.networkError("Invalid endpoint URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("Invalid response type from balance API")
            throw ProviderError.networkError("Invalid response type")
        }

        guard httpResponse.statusCode == 200 else {
            logger.error("Balance API request failed with status code: \(httpResponse.statusCode)")
            throw ProviderError.networkError("HTTP \(httpResponse.statusCode)")
        }

        do {
            let balanceResponse = try JSONDecoder().decode(BalanceResponse.self, from: data)
            return balanceResponse
        } catch {
            logger.error("Failed to decode balance response: \(error.localizedDescription)")
            throw ProviderError.decodingError(error.localizedDescription)
        }
    }
}
