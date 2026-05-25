//
//  PaymentLockedSheetView.swift
//  Split Rewards
//
//  Created by TeeVee on 10/17/25.
//
import SwiftUI
import SafariServices

// Identifiable wrapper for URL
private struct SafariItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct PaymentLockedSheetView: View {
    let invoiceUrl: String?

    @Environment(\.dismiss) private var dismiss
    @State private var safariItem: SafariItem? = nil   // <- sheet(item:) binding

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 50))
                .foregroundStyle(.red)
                .padding(.top, 28)

            Text("Account Locked")
                .font(.title2).bold()

            Text("Your account is locked due to an unpaid failed payment. To unlock your account, pay the outstanding invoice.")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            if let urlString = invoiceUrl, let url = URL(string: urlString) {
                Button {
                    print("🟦 View & Pay tapped with URL:", url.absoluteString)
                    safariItem = SafariItem(url: url)     // <- set item to present
                } label: {
                    Text("View & Pay Invoice")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            } else {
                Text("Check your email for the invoice.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button("Close") { dismiss() }
                .padding(.top, 8)
        }
        .padding()
        .presentationDetents([.medium, .large])
        .onAppear {
            print("🔍 PaymentLockedSheetView appeared with invoiceUrl:", invoiceUrl ?? "nil")
        }
        // Present Safari when safariItem is set
        .sheet(item: $safariItem) { item in
            SafariView(url: item.url)
                .ignoresSafeArea()
        }
    }
}

// Helper Safari View
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        print("🧭 SFSafariViewController make with URL:", url.absoluteString)
        return SFSafariViewController(url: url)
    }
    func updateUIViewController(_ vc: SFSafariViewController, context: Context) {}
}



