//  UserAgreementSheetView.swift
//  Split Rewards
//
//  Updated Terms of Service (User-Only; Rewards Pool Model)
//

import SwiftUI

struct UserAgreementSheetView: View {
    var body: some View {
        TitleView(title: "Terms of Service")

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                sectionTitle("1. Acceptance of Terms")
                sectionText(
                    "By accessing or using Split (the \"Service\"), you agree to be bound by these Terms of Service (\"Terms\"). If you do not agree to these Terms, do not use the Service."
                )

                sectionTitle("2. About Split")
                sectionText(
                    "Split provides software that enables you to send and receive payments over the Bitcoin Lightning Network, message other users, and, when available, participate in Split’s bitcoin rewards program based on spending with participating merchants. Split is not a bank, payment processor, money transmitter, or custodian. Split does not hold, control, or have access to your bitcoin, private keys, or wallet funds."
                )

                sectionTitle("3. Non-Custodial Wallet and User Responsibility")
                sectionText(
                    "The Service is non-custodial. You are solely responsible for maintaining control of your wallet, safeguarding your private keys and recovery materials, and confirming payment details before authorizing any transaction. If you lose access to your wallet or keys, Split cannot recover your funds."
                )

                sectionTitle("4. How Lightning Payments Work")
                sectionText(
                    "Payments initiated through Split occur over the Bitcoin Lightning Network using wallet software and related services. Lightning payments are generally final and irreversible once completed. Split cannot reverse, refund, or cancel any payment."
                )

                sectionTitle("5. Messaging and User Content")
                sectionText(
                    "Split may allow you to send private messages, transmit attachments, upload photos, write captions, and otherwise submit content through the Service (\"User Content\"). You are solely responsible for your User Content and for your interactions with other users."
                )

                sectionText(
                    "You represent and warrant that you own or control the necessary rights to any User Content you submit and that your User Content does not violate applicable law, these Terms, or any third-party rights. By submitting User Content, you grant Split a limited, non-exclusive, worldwide, royalty-free license to host, store, transmit, reproduce, display, distribute, and remove that User Content solely as necessary to operate and provide the Service."
                )

                sectionText(
                    "Split may provide messaging and sharing features, but Split does not guarantee message delivery, receipt, response, authenticity of counterparties, or successful interaction between users. You are solely responsible for evaluating any person, message, payment request, attachment, or content you choose to engage with through the Service."
                )

                sectionTitle("6. Public Websites and Shared Links")
                sectionText(
                    "Some Split-operated web pages, download links, or externally shareable resources may be public by design. Use discretion when choosing what information to submit through any public-facing or shareable surface."
                )

                sectionText(
                    "Copies of public-facing content or shared materials may remain temporarily in caches, backups, logs, or previously shared links for a limited period. Split may remove or restrict content or access at any time to enforce these Terms, comply with law, or protect users and the Service."
                )

                sectionTitle("7. Bitcoin Rewards Program")
                sectionText(
                    "From time to time, Split may offer a rewards program that distributes bitcoin to eligible users. Rewards are not interest, yield, or a guaranteed benefit. Any rewards are a discretionary distribution by Split, subject to eligibility, availability, and program rules that may change at any time."
                )

                sectionText(
                    "Rewards are calculated using your spending with participating merchants during a given period (for example, a calendar month) relative to total participating-merchant spend by all users during that same period. If Split allocates a reward pool for that period, your share may be determined proportionally based on that relative spend. Split may apply minimum thresholds, exclusions, caps, anti-abuse adjustments, or other rules in its discretion."
                )

                sectionText(
                    "Split may delay, reduce, withhold, or decline to issue rewards for suspected fraud, abuse, attempted manipulation, prohibited activity, chargeback-style disputes (where applicable), sanctions concerns, or to comply with legal obligations. Split may pause or end the rewards program at any time, with or without notice."
                )

                sectionTitle("8. Participating Merchants and Spend Attribution")
                sectionText(
                    "Split identifies participating merchants using receiving public keys or other technical identifiers (for example, Lightning node or invoice-related keys) that Split maintains in its database. When you make a payment, Split may compare the payment’s receiving identifier to its participating-merchant list to attribute that spend for rewards purposes."
                )

                sectionText(
                    "Split does not control merchant pricing, goods, services, or fulfillment. Any dispute regarding a purchase must be resolved directly between you and the merchant. Split does not provide refunds or chargebacks and does not mediate disputes as a required service."
                )

                sectionTitle("9. Fees, Taxes, and Bitcoin Volatility")
                sectionText(
                    "You are responsible for any network fees, routing fees, miner fees, or other costs associated with Bitcoin and Lightning transactions. Bitcoin is volatile. The fiat value of any rewards (if issued) may change significantly before or after distribution."
                )

                sectionText(
                    "You are solely responsible for determining and satisfying any tax obligations related to your use of the Service, including receiving bitcoin rewards. Split does not provide tax advice."
                )

                sectionTitle("10. Prohibited and Illegal Use")
                sectionText(
                    "You may not use the Service for unlawful, fraudulent, abusive, harmful, or otherwise prohibited activity, including attempting to manipulate rewards, evade restrictions, impersonate others, spam users, interfere with the Service’s normal operation, or misuse messaging or sharing features."
                )

                sectionText(
                    "You may not upload, send, post, store, or share illegal or illicit photos, images, videos, captions, messages, or other content, including content involving exploitation, child sexual abuse material, trafficking, threats, harassment, hateful conduct, non-consensual sexual content, scams, malware, phishing, doxxing, or infringement of intellectual property or privacy rights."
                )

                sectionText(
                    "All applicable civil, criminal, regulatory, and intellectual property laws apply to your use of Split’s messaging and sharing features. You are solely responsible for the legality of your conduct and User Content. Split may report unlawful activity to law enforcement or other appropriate parties where permitted or required by law."
                )

                sectionTitle("11. Data Collection and Privacy Summary")
                sectionText(
                    "Split collects limited data necessary to operate the Service and the rewards program, which may include Lightning payment metadata such as amounts, timestamps, and whether a payment matches a participating merchant identifier. Split is not a blockchain analytics service and does not attempt to deanonymize users."
                )

                sectionText(
                    "Split does not require government-issued identity verification for basic use of the Service. Split does not intentionally track user-to-user payments for rewards purposes. For more details, please review Split’s Privacy Policy."
                )

                sectionTitle("12. Suspension, Moderation, and Termination")
                sectionText(
                    "Split may review, refuse, remove, restrict, or disable access to any User Content, messaging functionality, sharing functionality, or account access at any time if we believe it may violate these Terms, create risk for users or third parties, harm the Service, or expose Split to legal or regulatory risk."
                )

                sectionText(
                    "Split may suspend or terminate access to the Service at any time if you violate these Terms, engage in harmful conduct, attempt to abuse rewards, or if your use poses risk to Split, other users, or third parties. Split is not obligated to pre-screen all content or communications, and failure to act in a particular instance does not waive Split’s right to act later."
                )

                sectionTitle("13. Disclaimer of Warranties")
                sectionText(
                    "The Service is provided on an \"as is\" and \"as available\" basis without warranties of any kind, express or implied. Split does not guarantee uninterrupted access, successful routing, payment completion, or rewards availability."
                )

                sectionTitle("14. Limitation of Liability")
                sectionText(
                    "To the fullest extent permitted by law, Split is not liable for lost funds, lost private keys, failed or misrouted payments, service interruptions, rewards not issued or reduced, merchant disputes, wallet software failures, network outages, user-generated content, or disputes, harms, or damages arising from interactions between users."
                )

                sectionTitle("15. Changes to the Service or Terms")
                sectionText(
                    "Split may modify the Service, the rewards program, or these Terms at any time. Continued use of the Service after changes become effective constitutes acceptance of the updated Terms."
                )

                sectionTitle("16. Governing Law")
                sectionText(
                    "These Terms are governed by the laws of the District of Columbia, without regard to conflict of law principles."
                )

                sectionTitle("17. Contact Information")
                VStack(alignment: .leading, spacing: 6) {
                    Text("Split\nWashington, DC")
                    Link(
                        "support@example.com",
                        destination: URL(string: "mailto:support@example.com")!
                    )
                }
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.headline)
    }

    private func sectionText(_ text: String) -> some View {
        Text(text)
            .font(.body)
    }
}

#Preview {
    UserAgreementSheetView()
}





