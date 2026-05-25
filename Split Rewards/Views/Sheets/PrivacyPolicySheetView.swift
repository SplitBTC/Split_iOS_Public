//
//  PrivacyPolicySheetView.swift
//  Split Rewards
//
//  Privacy Policy (Updated for Rewards Pool + Merchant Pubkey Matching)
//

import SwiftUI

struct PrivacyPolicySheetView: View {
    var body: some View {
        TitleView(title: "Privacy Policy")

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                Text("Last Updated: March 24th, 2026")
                    .font(.headline)

                Text("This Privacy Policy explains how Split (\"Split,\" \"we,\" \"our,\" or \"us\") collects, uses, and protects information when you use the Split platform, including our mobile applications and related services (collectively, the \"Service\"). By using the Service, you agree to the collection and use of information as described in this Privacy Policy.")

                Text("1. Overview")
                    .font(.headline)
                Text("Split is designed to be privacy-preserving by default. We provide non-custodial software that enables payments over the Bitcoin Lightning Network, private messaging between users, and, when available, participation in Split’s bitcoin rewards program. We do not custody user funds.")

                Text("2. Information We Collect")
                    .font(.headline)

                Text("2.1 Information We Do Not Collect")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 8) {
                    Text("• Names")
                    Text("• Email addresses (unless you voluntarily contact us)")
                    Text("• Phone numbers")
                    Text("• Physical addresses")
                    Text("• Bank account information")
                    Text("• Government-issued identification")
                    Text("• Private keys or wallet seed phrases")
                }

                Text("2.2 Wallet, Lightning Address, and Profile Information")
                    .font(.headline)
                Text("To operate the Service, Split may process wallet-related and account-related identifiers such as your Lightning address, wallet public key, messaging public key, messaging identity signature data, and profile photo URL if you upload a profile photo. We do not control or manage your private keys and cannot access user funds.")

                Text("2.3 Transaction and Rewards Data")
                    .font(.headline)
                Text("To operate the Service and calculate rewards, Split may collect limited metadata associated with payments you initiate through the app, including:")
                VStack(alignment: .leading, spacing: 8) {
                    Text("• Payment amount")
                    Text("• Timestamp")
                    Text("• Whether the receiving identifier matches a participating merchant identifier stored by Split (e.g., a merchant public key)")
                    Text("• Limited internal identifiers needed to attribute spend and calculate rewards (e.g., month/period keys and totals)")
                    Text("• Rewards payout records (e.g., payout amount, timestamp, and status) when rewards are issued")
                }
                Text("We do not collect names or contact details for typical use. We do not collect your private keys or seed phrase. We do not need itemized purchase details to run Split. We do not intentionally use invoice descriptions/memos for rewards attribution.")

                Text("2.4 Messaging, Attachment, and Notification Data")
                    .font(.headline)
                Text("If you use Split’s messaging features, Split may process limited information necessary to route and deliver private messages while they are pending, including sender and recipient identifiers, Lightning addresses, messaging public keys, message type, timestamps, delivery state, and messaging device tokens used for push delivery. If you send private messaging attachments, Split may also process limited attachment metadata such as file size, content type, and related delivery status.")
                Text("Split’s private messaging system is designed so that private message content and private messaging attachment content are end-to-end encrypted between participating users. Our servers are intended to receive and temporarily store encrypted message envelopes and encrypted private attachment blobs rather than plaintext private content. Split may still process the metadata described above to route, deliver, and secure the messaging service.")

                Text("2.5 Device, Website, and Usage Information")
                    .font(.headline)
                Text("We may collect limited technical information necessary to operate and secure the Service, such as app version, basic device information, IP-derived region (approximate), and error logs/crash diagnostics. Our public website may also use analytics tags, cookies, or similar technologies to understand traffic and improve the Service. This information is used for reliability, debugging, security, and product improvement.")

                Text("3. How We Use Information")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 8) {
                    Text("• Operate and maintain the Service")
                    Text("• Route and deliver private messages and private messaging attachments")
                    Text("• Identify participating merchants using technical identifiers (e.g., merchant public keys)")
                    Text("• Calculate rewards eligibility and proportional rewards amounts")
                    Text("• Issue rewards payouts and maintain payout records")
                    Text("• Monitor for abuse, fraud, or misuse (including attempted manipulation of rewards)")
                    Text("• Operate push delivery and messaging reliability features")
                    Text("• Improve performance and reliability")
                    Text("• Comply with legal obligations")
                }
                Text("Split does not sell personal data.")

                Text("4. Private Messaging and Encryption")
                    .font(.headline)
                Text("Split’s private messaging features are designed to use end-to-end encryption for message content and private messaging attachments between participating users. In the current mobile app, messaging private keys and a separate local messaging-storage key are kept in device secure storage, and decrypted local message history and cached private messaging attachments are re-encrypted at rest on device.")
                Text("Private messages are temporarily queued on Split’s servers only as needed for delivery. In the current service, private message records awaiting recipient acknowledgement are generally retained for up to 14 days if the recipient is offline. After a message is received, Split deletes the message relay record. Private messaging attachment blobs are stored separately as encrypted blobs and are deleted after confirmed recipient receipt or expiration, subject to limited operational delays.")

                Text("5. Rewards Program and Merchant Attribution")
                    .font(.headline)
                Text("When available, Split may distribute bitcoin rewards to eligible users based on spending with participating merchants during a given period (for example, a calendar month). Split attributes eligible spend by comparing the receiving identifier of a payment (such as a merchant public key) against Split’s database of participating merchant identifiers.")
                Text("Rewards are discretionary and may be funded by Split and/or sponsors. Rewards are not guaranteed, may change over time, and may be paused or discontinued. Split does not require item-level purchase information to calculate rewards, and we do not control merchants’ goods, services, pricing, or fulfillment.")

                Text("6. Analytics and Advertising")
                    .font(.headline)
                Text("Split may use limited usage and transaction metadata for internal analytics, product improvement, and fraud prevention. Split may also use website analytics tools or similar technologies to understand website traffic and usage patterns. We do not use your transaction metadata for third-party targeted advertising. If our data practices change in the future, we will update this Privacy Policy and provide notice as required by law.")

                Text("7. Data Sharing")
                    .font(.headline)
                Text("We do not sell or rent user data. We may share limited information in the following circumstances:")
                VStack(alignment: .leading, spacing: 8) {
                    Text("• With service providers who assist in operating the Service (e.g., infrastructure, storage, analytics, and notification providers), subject to contractual confidentiality and security obligations")
                    Text("• When required by law, legal process, or a valid government request")
                    Text("• To investigate or prevent illegal activity, fraud, security threats, or abuse of the Service")
                }
                Text("If Split works with sponsors to fund rewards, Split may share high-level, aggregated program reporting (for example, total eligible spend or total rewards distributed) that is not intended to identify individual users.")

                Text("8. Data Security")
                    .font(.headline)
                Text("We implement reasonable technical and organizational measures to protect the limited data we collect and process. However, no system is completely secure. You acknowledge that use of the Service is at your own risk. Split cannot recover lost wallet keys or reverse Lightning payments, and we cannot guarantee that security measures will never be bypassed.")

                Text("9. Data Retention")
                    .font(.headline)
                Text("We retain information only for as long as necessary to operate the Service, calculate and administer rewards, comply with legal obligations, and enforce our Terms of Service. We periodically review and delete data that is no longer required.")
                Text("Different data types may have different retention periods. For example, private messages awaiting delivery are generally retained only temporarily, and successfully received private message relay records are deleted after recipient acknowledgement. Some operational records may be retained longer where necessary for security, fraud prevention, legal compliance, or rewards administration.")

                Text("10. Your Choices")
                    .font(.headline)
                Text("You may stop using the Service at any time. You may choose whether to upload a profile photo or use private messaging.")
                Text("Because Split does not collect traditional personal identity information for typical use, there may be limited ability to access, modify, or delete all data associated with your use of the Service, especially where retention is necessary for security, fraud prevention, legal compliance, or rewards administration.")

                Text("11. Children’s Privacy")
                    .font(.headline)
                Text("Split does not knowingly collect personal information from children. If you believe a child has provided personal information to Split, please contact us so we can take appropriate action.")

                Text("12. Changes to This Policy")
                    .font(.headline)
                Text("We may update this Privacy Policy from time to time. Changes will be effective when posted. Continued use of the Service after changes constitutes acceptance of the revised policy.")

                Text("13. Contact Us")
                    .font(.headline)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Split\nWashington, DC")
                    Link("support@example.com", destination: URL(string: "mailto:support@example.com")!)
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    PrivacyPolicySheetView()
}
