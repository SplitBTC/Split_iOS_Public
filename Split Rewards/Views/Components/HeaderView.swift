//  HeaderView.swift
//  Split-iOS
//
//  Created by TeeVee on 1/8/25.
//
import SwiftUI

struct HeaderView: View {
    // Brand color (matching rest of app)
    private let pink = Color.splitBrandPink

    var body: some View {
        HStack {
            // Left: Token logo in a circle
            Image("token_logo")
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(pink.opacity(0.9), lineWidth: 1.5)
                )
                .padding(.leading, 16)

            Spacer()

            HStack(spacing: 5) {
                NavigationLink(destination: ContactList()) {
                    Image(systemName: "person.text.rectangle")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.9))
                        )
                }

                NavigationLink(destination: BTCMerchantMapView()) {
                    Image(systemName: "storefront.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(10)
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.9))
                        )
                }

                // Right: Profile icon → ProfileView
                NavigationLink(destination: ProfileView()) {
                    Image(systemName: "line.3.horizontal")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(Color.white)
                        .padding(10)
                        .background(
                            Circle()
                                .fill(Color.black.opacity(0.9))
                        )
                }
            }
            .padding(.trailing, 16)
        }
        .padding(.top, 28) // Space from status bar
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.black.opacity(0.95)
                .ignoresSafeArea(edges: .top)
        )
    }
}

struct HeaderView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HeaderView()
                Spacer()
                    .background(Color.black.opacity(0.95))
            }
        }
    }
}
