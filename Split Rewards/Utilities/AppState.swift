//
//  AppState.swift
//  Split Rewards
//
//  Created by TeeVee on 1/21/25.
//

import Foundation

/// Reserved for future server-session state.
/// Not used for routing or wallet lifecycle.
@MainActor
final class AppState: ObservableObject {

    /// Backend userId (derived from wallet pubkey after auth).
    @Published var userId: String?

    /// Wallet pubkey used for auth.
    @Published var pubkey: String?

    /// Whether we currently believe the server session cookie is valid.
    /// This is *not* used to gate UI.
    @Published var hasValidSession: Bool = false

    init() {}
}


