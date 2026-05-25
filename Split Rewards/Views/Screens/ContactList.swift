//
//  ContactList.swift
//  Split Rewards
//
//  Created by TeeVee on 3/22/26.
//

import SwiftUI

struct ContactList: View {
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject private var walletManager: WalletManager

    private let background = Color.black
    private let rowSurface = Color.splitInputSurface

    @State private var contacts: [WalletManager.WalletContact] = []
    @State private var profilePicUrlsByIdentifier: [String: String] = [:]
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showCreateContact = false

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            Group {
                if isLoading {
                    loadingState
                } else if let errorMessage {
                    errorState(message: errorMessage)
                } else if contacts.isEmpty {
                    emptyState
                } else {
                    contactList
                }
            }
        }
        .navigationTitle("Contacts")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink(destination: BlockedUsersView()) {
                    Image(systemName: "nosign")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)

                Button {
                    showCreateContact = true
                } label: {
                    Image(systemName: "plus")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .task {
            await loadContacts()
        }
        .task(id: contacts.map(\.id).joined(separator: "|")) {
            await refreshProfilePics()
        }
        .sheet(isPresented: $showCreateContact, onDismiss: {
            Task {
                await loadContacts(forceReload: true)
            }
        }) {
            NavigationStack {
                CreateContactView(
                    paymentIdentifier: "",
                    isPaymentIdentifierEditable: true
                )
                .environmentObject(walletManager)
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            Spacer()

            ProgressView()
                .tint(.white)
                .scaleEffect(1.1)

            Text("Loading Contacts")
                .font(.headline.weight(.semibold))
                .foregroundColor(.white)

            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 88, height: 88)

                Image(systemName: "person.text.rectangle.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
            }

            Text("No Contacts Yet")
                .font(.title3.weight(.semibold))
                .foregroundColor(.white)

            Text("Saved Breez contacts will appear here in alphabetical order.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.splitBrandPink)

            Text("Unable to Load Contacts")
                .font(.title3.weight(.semibold))
                .foregroundColor(.white)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Button("Try Again") {
                Task { await loadContacts(forceReload: true) }
            }
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(Color.splitBrandPink)
            )
            .buttonStyle(.plain)

            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private var contactList: some View {
        List {
            ForEach(contacts) { contact in
                NavigationLink(destination: ContactDetailView(contact: contact)) {
                    HStack(spacing: 12) {
                        avatarView(for: contact)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(contact.name)
                                .font(.headline.weight(.semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)

                            Text(contact.paymentIdentifier)
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.58))
                                .lineLimit(1)
                        }

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(rowSurface)
                    )
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .environment(\.colorScheme, .dark)
    }

    private func avatarView(for contact: WalletManager.WalletContact) -> some View {
        let normalized = contact.paymentIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return ZStack {
            Circle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 50, height: 50)

            if let rawUrl = profilePicUrlsByIdentifier[normalized],
               let url = URL(string: rawUrl),
               !rawUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    default:
                        Image(systemName: "person.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
            }
        }
    }

    @MainActor
    private func loadContacts(forceReload: Bool = false) async {
        if isLoading && !forceReload { return }

        isLoading = true
        errorMessage = nil

        do {
            let loaded = try await walletManager.listContacts()
            contacts = loaded.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    @MainActor
    private func refreshProfilePics() async {
        guard !contacts.isEmpty else {
            profilePicUrlsByIdentifier = [:]
            return
        }

        var updated = profilePicUrlsByIdentifier

        for contact in contacts {
            let address = contact.paymentIdentifier
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            guard !address.isEmpty, updated[address] == nil else { continue }

            do {
                let recipient = try await ResolveMessageRecipientAPI.resolveRecipient(
                    lightningAddress: address,
                    authManager: authManager,
                    walletManager: walletManager
                )
                updated[address] = recipient.profilePicUrl
            } catch {
                updated[address] = ""
            }
        }

        profilePicUrlsByIdentifier = updated
    }
}

#Preview {
    NavigationStack {
        ContactList()
    }
    .environmentObject(WalletManager())
    .environmentObject(AuthManager())
}
