//
//  Split_RewardsTests.swift
//  Split RewardsTests
//
//  Created by TeeVee on 1/11/25.
//

import Foundation
import Network
import Testing
@testable import Split_Rewards

struct Split_RewardsTests {

    @Test func paymentUsdSnapshotDecodesExistingStoredSnapshotsAsNonReportable() throws {
        let json = """
        {
          "walletPubkey": "wallet-pubkey",
          "paymentId": "payment-id",
          "paymentType": "sent",
          "usdValueAtTransaction": 81.23,
          "btcUsdRateAtTransaction": 90234.12
        }
        """

        let snapshot = try JSONDecoder().decode(
            PaymentUsdSnapshot.self,
            from: Data(json.utf8)
        )

        #expect(snapshot.walletPubkey == "wallet-pubkey")
        #expect(snapshot.paymentId == "payment-id")
        #expect(snapshot.paymentType == .sent)
        #expect(snapshot.isReportable == false)
        #expect(snapshot.hasUsdSnapshot == true)
    }

    @Test func messagingDirectoryCheckpointScopesByBackendOrigin() throws {
        MessageDirectoryCheckpointStore.clear()
        defer { MessageDirectoryCheckpointStore.clear() }

        try MessageDirectoryCheckpointStore.storeIfNewer(
            MessagingDirectoryCheckpoint(
                rootHash: "prod-root",
                treeSize: 7,
                issuedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            scope: "https://prod.split.example"
        )

        try MessageDirectoryCheckpointStore.storeIfNewer(
            MessagingDirectoryCheckpoint(
                rootHash: "dev-root",
                treeSize: 7,
                issuedAt: Date(timeIntervalSince1970: 1_700_000_100)
            ),
            scope: "https://dev.split.example"
        )
    }

    @Test func messagingDirectoryCheckpointStillRejectsSameOriginConflicts() throws {
        MessageDirectoryCheckpointStore.clear()
        defer { MessageDirectoryCheckpointStore.clear() }

        try MessageDirectoryCheckpointStore.storeIfNewer(
            MessagingDirectoryCheckpoint(
                rootHash: "root-a",
                treeSize: 7,
                issuedAt: Date(timeIntervalSince1970: 1_700_000_000)
            ),
            scope: "https://prod.split.example"
        )

        do {
            try MessageDirectoryCheckpointStore.storeIfNewer(
                MessagingDirectoryCheckpoint(
                    rootHash: "root-b",
                    treeSize: 7,
                    issuedAt: Date(timeIntervalSince1970: 1_700_000_100)
                ),
                scope: "https://prod.split.example"
            )
            Issue.record("Expected a same-origin checkpoint conflict.")
        } catch let error as MessageDirectoryCheckpointStore.CheckpointError {
            switch error {
            case .conflictingCheckpoint:
                break
            case .staleCheckpoint:
                Issue.record("Expected a conflicting checkpoint, got stale.")
            }
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
    }

    @Test func lndConnectParserAcceptsPrivateIPAddressHosts() throws {
        let credentials = try LNDConnectParser.parse(
            lndConnectURL(host: "192.168.1.25")
        )

        #expect(credentials.host == "192.168.1.25")
        #expect(credentials.port == 8080)
    }

    @Test func lndConnectParserAcceptsTailscaleHosts() throws {
        let credentials = try LNDConnectParser.parse(
            lndConnectURL(host: "umbrel.tailnet.ts.net", port: 10009)
        )

        #expect(credentials.host == "umbrel.tailnet.ts.net")
        #expect(Set(credentials.restConnectionCandidates.map(\.host)) == Set(["umbrel.tailnet.ts.net"]))
        #expect(credentials.restConnectionCandidates.map(\.port) == [10009, 8080, 8081])
    }

    @Test func lndConnectParserAcceptsTailscaleIPv4Addresses() throws {
        let credentials = try LNDConnectParser.parse(
            lndConnectURL(host: "100.96.32.14", port: 10009)
        )

        #expect(credentials.host == "100.96.32.14")
        #expect(Set(credentials.restConnectionCandidates.map(\.host)) == Set(["100.96.32.14"]))
        #expect(credentials.restConnectionCandidates.map(\.port) == [10009, 8080, 8081])
    }

    @Test func lndConnectParserAllowsHostnamesThatWillBeCheckedAfterResolution() throws {
        let credentials = try LNDConnectParser.parse(
            lndConnectURL(host: "umbrel.example.com")
        )

        #expect(credentials.host == "umbrel.example.com")
    }

    @Test func lndConnectParserAllowsIPAddressLiteralsThatWillBeCheckedAfterResolution() throws {
        let credentials = try LNDConnectParser.parse(
            lndConnectURL(host: "8.8.8.8")
        )

        #expect(credentials.host == "8.8.8.8")
    }

    @Test func lndConnectParserAcceptsLocalHostnamesWithFallbackExpansion() throws {
        let credentials = try LNDConnectParser.parse(
            lndConnectURL(host: "umbrel.local", port: 10009)
        )

        #expect(credentials.host == "umbrel.local")
        #expect(credentials.restConnectionCandidates.map(\.host) == ["umbrel.local", "umbrel", "umbrel.local", "umbrel", "umbrel.local", "umbrel"])
        #expect(credentials.restConnectionCandidates.map(\.port) == [10009, 10009, 8080, 8080, 8081, 8081])
    }

    @Test func lndHostPolicyAcceptsSingleLabelLocalHostnames() throws {
        #expect(LNDHostAccessPolicy.validationError(for: "umbrel") == nil)
    }

    @Test func lndResolvedAddressPolicyAcceptsPrivateAndLocalAddresses() throws {
        let addresses: [LNDResolvedAddress] = [
            .ipv4(try #require(IPv4Address("192.168.1.25"))),
            .ipv4(try #require(IPv4Address("100.96.32.14"))),
            .ipv6(try #require(IPv6Address("fd7a:115c:a1e0::1"))),
            .ipv6(try #require(IPv6Address("fe80::1")))
        ]

        #expect(LNDHostAccessPolicy.resolvedAddressValidationError(for: addresses) == nil)
    }

    @Test func lndResolvedAddressPolicyRejectsPublicAddresses() throws {
        let publicIPv4Addresses: [LNDResolvedAddress] = [
            .ipv4(try #require(IPv4Address("8.8.8.8")))
        ]

        #expect(
            LNDHostAccessPolicy.resolvedAddressValidationError(for: publicIPv4Addresses)
            == .publicInternetHostNotAllowed
        )
    }

    @Test func lndResolvedAddressPolicyRejectsMixedPrivateAndPublicResults() throws {
        let mixedAddresses: [LNDResolvedAddress] = [
            .ipv4(try #require(IPv4Address("192.168.1.25"))),
            .ipv4(try #require(IPv4Address("8.8.8.8")))
        ]

        #expect(
            LNDHostAccessPolicy.resolvedAddressValidationError(for: mixedAddresses)
            == .publicInternetHostNotAllowed
        )
    }

    @Test func lndConnectParserStillRejectsTorHosts() throws {
        do {
            _ = try LNDConnectParser.parse(
                lndConnectURL(host: "umbrelhiddenservice.onion")
            )
            Issue.record("Expected a Tor host to be rejected.")
        } catch let error as LNDWalletError {
            #expect(error == .torOnionNotSupported)
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
    }

    @Test func coreLightningConnectParserAcceptsClnRestURL() throws {
        let credentials = try CoreLightningConnectParser.parse(
            "clnrest+https://umbrel.local:3010?rune=test-rune&name=Umbrel%20CLN"
        )

        #expect(credentials.scheme == "https")
        #expect(credentials.host == "umbrel.local")
        #expect(credentials.port == 3010)
        #expect(credentials.rune == "test-rune")
        #expect(credentials.label == "Umbrel CLN")
    }

    @Test func coreLightningConnectParserAcceptsJSONConnectionPayload() throws {
        let credentials = try CoreLightningConnectParser.parse(
            #"{"url":"https://192.168.1.25:3010","rune":"test-rune","label":"Core Lightning"}"#
        )

        #expect(credentials.scheme == "https")
        #expect(credentials.host == "192.168.1.25")
        #expect(credentials.port == 3010)
        #expect(credentials.rune == "test-rune")
        #expect(credentials.label == "Core Lightning")
    }

    @Test func coreLightningConnectParserAcceptsWrappedRestURL() throws {
        let credentials = try CoreLightningConnectParser.parse(
            "clnrest://https://umbrel.local:3010?rune=test-rune"
        )

        #expect(credentials.scheme == "https")
        #expect(credentials.host == "umbrel.local")
        #expect(credentials.port == 3010)
        #expect(credentials.rune == "test-rune")
    }

    @Test func coreLightningRestCandidatesIncludeLocalHostnameFallback() throws {
        let credentials = try CoreLightningConnectParser.parse(
            "clnrest+https://umbrel.local:2107?rune=test-rune"
        )

        #expect(credentials.restConnectionCandidates.map(\.host) == ["umbrel.local", "umbrel"])
        #expect(credentials.restConnectionCandidates.map(\.port) == [2107, 2107])
    }

    @Test func coreLightningConnectParserRejectsUnsupportedHosts() throws {
        do {
            _ = try CoreLightningConnectParser.parse(
                "clnrest+https://umbrelhiddenservice.onion:3010?rune=test-rune"
            )
            Issue.record("Expected an unsupported host to be rejected.")
        } catch let error as CoreLightningWalletError {
            #expect(error == .publicInternetHostNotAllowed)
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
    }

    @Test func eclairConnectParserAcceptsEclairHTTPURL() throws {
        let credentials = try EclairConnectParser.parse(
            connectionString: "eclair+http://umbrel.local:8080?password=api%2Bpass&name=Umbrel%20Eclair"
        )

        #expect(credentials.scheme == "http")
        #expect(credentials.host == "umbrel.local")
        #expect(credentials.port == 8080)
        #expect(credentials.apiPassword == "api+pass")
        #expect(credentials.label == "Umbrel Eclair")
    }

    @Test func eclairConnectParserAcceptsJSONURLPayload() throws {
        let credentials = try EclairConnectParser.parse(
            connectionString: #"{"url":"https://100.96.32.14:8443","apiPassword":"api+pass","label":"Eclair Node"}"#
        )

        #expect(credentials.scheme == "https")
        #expect(credentials.host == "100.96.32.14")
        #expect(credentials.port == 8443)
        #expect(credentials.apiPassword == "api+pass")
        #expect(credentials.label == "Eclair Node")
    }

    @Test func eclairConnectParserAcceptsQueryHostPayload() throws {
        let credentials = try EclairConnectParser.parse(
            connectionString: "eclair://connect?scheme=https&host=eclairhiddenservice.onion&port=9735&api_password=secret"
        )

        #expect(credentials.scheme == "https")
        #expect(credentials.host == "eclairhiddenservice.onion")
        #expect(credentials.port == 9735)
        #expect(credentials.apiPassword == "secret")
    }

    @Test func eclairConnectParserKeepsLiteralPlusInPassword() throws {
        let credentials = try EclairConnectParser.parse(
            connectionString: "eclair+http://umbrel.local:8080?password=api+pass"
        )

        #expect(credentials.apiPassword == "api+pass")
    }

    @Test func coreLightningAmountParserHandlesMsatSatAndBtcStrings() throws {
        #expect(CoreLightningMilliSatoshi.parse("2500msat") == 2_500)
        #expect(CoreLightningMilliSatoshi.parse("12sat") == 12_000)
        #expect(CoreLightningMilliSatoshi.parse("0.00000001btc") == 1_000)
    }

    @Test func nwcConnectParserAcceptsSecureRelays() throws {
        let credentials = try NWCConnectParser.parse(
            nwcConnectionURL(relay: "wss://relay.example.com")
        )

        #expect(credentials.walletPubkey == testNWCWalletPubkey)
        #expect(credentials.relayURLs == ["wss://relay.example.com"])
        #expect(credentials.secret == testNWCSecret)
    }

    @Test func nwcConnectParserRejectsInsecureNonLocalRelays() throws {
        do {
            _ = try NWCConnectParser.parse(
                nwcConnectionURL(relay: "ws://relay.example.com")
            )
            Issue.record("Expected an insecure non-local relay to be rejected.")
        } catch let error as NWCWalletError {
            #expect(error == .invalidRelay)
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
    }

    @Test func nwcConnectParserAcceptsLocalWebSocketRelaysInDebugBuilds() throws {
        #if DEBUG
        let credentials = try NWCConnectParser.parse(
            nwcConnectionURL(relay: "ws://localhost:7777")
        )

        #expect(credentials.relayURLs == ["ws://localhost:7777"])
        #endif
    }

    @Test func nwcBolt11DecoderExtractsPaymentHashAndRecoversDestinationPubkey() throws {
        let metadata = try #require(NWCBolt11MetadataDecoder.decode(bolt11DonationInvoice))

        #expect(metadata.amountSats == nil)
        #expect(metadata.paymentHash == "0001020304050607080900010203040506070809000102030405060708090102")
        #expect(metadata.destinationPubkey == "03e7156ae33b0a208d0744199163177e909e80176e55d97a2f221ede0f934dd9ad")
        #expect(metadata.description == "Please consider supporting this project")
    }

    @Test func nwcBolt11DecoderExtractsFixedAmountInvoices() throws {
        let metadata = try #require(NWCBolt11MetadataDecoder.decode(bolt11CoffeeInvoice))

        #expect(metadata.amountSats == 250_000)
        #expect(metadata.paymentHash == "0001020304050607080900010203040506070809000102030405060708090102")
        #expect(metadata.destinationPubkey == "03e7156ae33b0a208d0744199163177e909e80176e55d97a2f221ede0f934dd9ad")
        #expect(metadata.description == "1 cup coffee")
    }

    @Test func merchantPubkeyHashUsesBackendCompatibleNormalizationAndPrefix() throws {
        let expectedHash = "2b3878883bc0b1757f1d979dfad4f9ea727aaac7a193f533579a9f16ac27efcd"

        #expect(" 03E7156AE33B0A208D0744199163177E909E80176E55D97A2F221EDE0F934DD9AD ".splitRewardsMerchantPubkeyHashForTesting == expectedHash)
        #expect("   ".splitRewardsMerchantPubkeyHashForTesting == nil)
    }

    @Test func nwcBolt11DecoderRejectsInvalidChecksums() {
        let invalidChecksum = String(bolt11DonationInvoice.dropLast()) + "x"

        #expect(NWCBolt11MetadataDecoder.decode(invalidChecksum) == nil)
    }

    @Test func nwcBolt11DecoderRejectsNonCanonicalExplicitPayeeSignatures() {
        #expect(NWCBolt11MetadataDecoder.decode(bolt11InvalidHighSWithExplicitPayeeInvoice) == nil)
    }

    @Test func nwcNostrEventSignaturesVerifyAndRejectTampering() throws {
        let event = try NWCNostrCryptography.signEvent(
            privateKeyHex: testNWCSecret,
            createdAt: 1_700_000_000,
            kind: 23194,
            tags: [["p", testNWCWalletPubkey]],
            content: "hello"
        )

        let verified = try NWCNostrCryptography.verifyEvent(event)
        #expect(verified == true)

        let tampered = NWCNostrEvent(
            id: event.id,
            pubkey: event.pubkey,
            createdAt: event.createdAt,
            kind: event.kind,
            tags: event.tags,
            content: "goodbye",
            sig: event.sig
        )

        let tamperedVerified = try NWCNostrCryptography.verifyEvent(tampered)
        #expect(tamperedVerified == false)
    }

    @Test func nwcNIP44EncryptDecryptRoundTripAndRejectsTampering() throws {
        let senderSecret = testNWCSecret
        let recipientSecret = "0202020202020202020202020202020202020202020202020202020202020202"
        let recipientPubkey = try NWCNostrCryptography.publicKeyHex(privateKeyHex: recipientSecret)
        let senderPubkey = try NWCNostrCryptography.publicKeyHex(privateKeyHex: senderSecret)

        let encrypted = try NWCNostrCryptography.nip44Encrypt(
            plaintext: #"{"method":"get_balance","params":{}}"#,
            senderPrivateKeyHex: senderSecret,
            recipientPublicKeyHex: recipientPubkey
        )

        let decrypted = try NWCNostrCryptography.nip44Decrypt(
            payload: encrypted,
            recipientPrivateKeyHex: recipientSecret,
            senderPublicKeyHex: senderPubkey
        )

        #expect(decrypted == #"{"method":"get_balance","params":{}}"#)

        let tampered = String(encrypted.dropLast()) + (encrypted.last == "A" ? "B" : "A")
        do {
            _ = try NWCNostrCryptography.nip44Decrypt(
                payload: tampered,
                recipientPrivateKeyHex: recipientSecret,
                senderPublicKeyHex: senderPubkey
            )
            Issue.record("Expected tampered NIP-44 payload to fail.")
        } catch {
            // Expected: MAC or payload validation should fail.
        }
    }

    @Test func nwcNIP04EncryptDecryptRoundTrip() throws {
        let senderSecret = testNWCSecret
        let recipientSecret = "0303030303030303030303030303030303030303030303030303030303030303"
        let recipientPubkey = try NWCNostrCryptography.publicKeyHex(privateKeyHex: recipientSecret)
        let senderPubkey = try NWCNostrCryptography.publicKeyHex(privateKeyHex: senderSecret)

        let encrypted = try NWCNostrCryptography.nip04Encrypt(
            plaintext: #"{"method":"get_balance","params":{}}"#,
            senderPrivateKeyHex: senderSecret,
            recipientPublicKeyHex: recipientPubkey
        )

        let decrypted = try NWCNostrCryptography.nip04Decrypt(
            payload: encrypted,
            recipientPrivateKeyHex: recipientSecret,
            senderPublicKeyHex: senderPubkey
        )

        #expect(decrypted == #"{"method":"get_balance","params":{}}"#)
    }

    private func lndConnectURL(host: String, port: Int? = nil) -> String {
        let hostComponent = host.contains(":") ? "[\(host)]" : host
        let portComponent = port.map { ":\($0)" } ?? ""
        return "lndconnect://\(hostComponent)\(portComponent)?macaroon=00aa11bb"
    }

    private func nwcConnectionURL(relay: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":/?#[]@!$&'()*+,;=")
        let encodedRelay = relay.addingPercentEncoding(withAllowedCharacters: allowed) ?? relay
        return "nostr+walletconnect://\(testNWCWalletPubkey)?relay=\(encodedRelay)&secret=\(testNWCSecret)"
    }

    private var testNWCSecret: String {
        "0101010101010101010101010101010101010101010101010101010101010101"
    }

    private var testNWCWalletPubkey: String {
        "1111111111111111111111111111111111111111111111111111111111111111"
    }

    private var bolt11DonationInvoice: String {
        "lnbc1pvjluezsp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygspp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqdpl2pkx2ctnv5sxxmmwwd5kgetjypeh2ursdae8g6twvus8g6rfwvs8qun0dfjkxaq9qrsgq357wnc5r2ueh7ck6q93dj32dlqnls087fxdwk8qakdyafkq3yap9us6v52vjjsrvywa6rt52cm9r9zqt8r2t7mlcwspyetp5h2tztugp9lfyql"
    }

    private var bolt11CoffeeInvoice: String {
        "lnbc2500u1pvjluezsp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygspp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqdq5xysxxatsyp3k7enxv4jsxqzpu9qrsgquk0rl77nj30yxdy8j9vdx85fkpmdla2087ne0xh8nhedh8w27kyke0lp53ut353s06fv3qfegext0eh0ymjpf39tuven09sam30g4vgpfna3rh"
    }

    private var bolt11InvalidHighSWithExplicitPayeeInvoice: String {
        "lnbc25m1p70xwfzpp5qqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqqqsyqcyq5rqwzqfqypqdpl2pkx2ctnv5sxxmmwwd5kgetjypeh2ursdae8g6twvus8g6rfwvs8qun0dfjkxaqnp4q0n326hr8v9zprg8gsvezcch06gfaqqhde2aj730yg0durunfhv66sp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygs9qrsgqsp5zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zyg3zygsp5cfzp9ugllvk03rltd6hvndxj26ux6gcxc5azyxk060rj9tzghct5zvjlps76gx8wpq5yuu79688k8gnm2c0al6v608s96l0xzrrlqqwnzxmu"
    }

}
