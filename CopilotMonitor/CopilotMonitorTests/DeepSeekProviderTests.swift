import XCTest
@testable import OpenCode_Bar

final class DeepSeekProviderTests: XCTestCase {
    private final class MockURLProtocol: URLProtocol {
        static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

        override static func canInit(with request: URLRequest) -> Bool {
            true
        }

        override static func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }

        override func startLoading() {
            guard let handler = MockURLProtocol.requestHandler else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }

            do {
                let (response, data) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testProviderIdentifier() {
        let provider = DeepSeekProvider()
        XCTAssertEqual(provider.identifier, .deepSeek)
    }

    func testProviderType() {
        let provider = DeepSeekProvider()
        XCTAssertEqual(provider.type, .payAsYouGo)
    }

    func testFetchSuccess() async throws {
        guard TokenManager.shared.getDeepSeekAPIKey() != nil else {
            throw XCTSkip("DeepSeek API key not available; skipping fetch test.")
        }

        let session = makeSession()
        let provider = DeepSeekProvider(tokenManager: .shared, session: session)

        let balanceJSON = """
        {
          "is_available": true,
          "balance_infos": [
            {
              "currency": "CNY",
              "total_balance": "0.00",
              "granted_balance": "0.00",
              "topped_up_balance": "0.00"
            }
          ]
        }
        """

        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            if url.path == "/user/balance" {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(balanceJSON.utf8))
            }

            let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let result = try await provider.fetch()

        switch result.usage {
        case .payAsYouGo(let remaining, let total):
            XCTAssertEqual(remaining, 0.0, accuracy: 0.001)
            XCTAssertEqual(total, 0.0, accuracy: 0.001)
        default:
            XCTFail("Expected pay-as-you-go usage")
        }

        XCTAssertEqual(result.details?.totalCredits ?? -1, 0.0, accuracy: 0.001)
        XCTAssertEqual(result.details?.remainingCredits ?? -1, 0.0, accuracy: 0.001)
    }

    func testFetchReturnsAuthenticationErrorOn401() async throws {
        guard TokenManager.shared.getDeepSeekAPIKey() != nil else {
            throw XCTSkip("DeepSeek API key not available; skipping fetch test.")
        }

        let session = makeSession()
        let provider = DeepSeekProvider(tokenManager: .shared, session: session)

        MockURLProtocol.requestHandler = { request in
            let url = request.url ?? URL(string: "https://api.deepseek.com")!
            let response = HTTPURLResponse(url: url, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }

        do {
            _ = try await provider.fetch()
            XCTFail("Expected authentication failure")
        } catch let error as ProviderError {
            switch error {
            case .authenticationFailed:
                break
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFetchReturnsErrorOnUnavailable() async throws {
        guard TokenManager.shared.getDeepSeekAPIKey() != nil else {
            throw XCTSkip("DeepSeek API key not available; skipping fetch test.")
        }

        let session = makeSession()
        let provider = DeepSeekProvider(tokenManager: .shared, session: session)

        let balanceJSON = """
        {
          "is_available": false,
          "balance_infos": []
        }
        """

        MockURLProtocol.requestHandler = { request in
            guard let url = request.url else {
                throw URLError(.badURL)
            }

            if url.path == "/user/balance" {
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(balanceJSON.utf8))
            }

            let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        do {
            _ = try await provider.fetch()
            XCTFail("Expected error for unavailable balance")
        } catch let error as ProviderError {
            switch error {
            case .decodingError:
                break
            default:
                XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testParseBalanceWithMultipleCurrencies() throws {
        let balanceJSON = """
        {
          "is_available": true,
          "balance_infos": [
            {
              "currency": "CNY",
              "total_balance": "100.50",
              "granted_balance": "50.00",
              "topped_up_balance": "50.50"
            },
            {
              "currency": "USD",
              "total_balance": "10.25",
              "granted_balance": "5.00",
              "topped_up_balance": "5.25"
            }
          ]
        }
        """

        let data = Data(balanceJSON.utf8)
        let decoded = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: data)

        XCTAssertTrue(decoded.isAvailable)
        XCTAssertEqual(decoded.balanceInfos.count, 2)
        XCTAssertEqual(decoded.balanceInfos[0].currency, "CNY")
        XCTAssertEqual(decoded.balanceInfos[0].totalBalance, "100.50")
        XCTAssertEqual(decoded.balanceInfos[0].grantedBalance, "50.00")
        XCTAssertEqual(decoded.balanceInfos[0].toppedUpBalance, "50.50")
        XCTAssertEqual(decoded.balanceInfos[1].currency, "USD")
    }

    func testParseBalanceWithEmptyInfos() throws {
        let balanceJSON = """
        {
          "is_available": true,
          "balance_infos": []
        }
        """

        let data = Data(balanceJSON.utf8)
        let decoded = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: data)

        XCTAssertTrue(decoded.isAvailable)
        XCTAssertTrue(decoded.balanceInfos.isEmpty)
    }

    func testParseBalanceUnavailable() throws {
        let balanceJSON = """
        {
          "is_available": false,
          "balance_infos": []
        }
        """

        let data = Data(balanceJSON.utf8)
        let decoded = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: data)

        XCTAssertFalse(decoded.isAvailable)
        XCTAssertTrue(decoded.balanceInfos.isEmpty)
    }
}
