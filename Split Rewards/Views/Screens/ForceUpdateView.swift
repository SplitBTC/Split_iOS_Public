//
//  ForceUpdateView.swift
//  Split Rewards
//
//  Created by TeeVee on 6/29/25.
//
import SwiftUI

struct ForcedUpdateView: View {
    var body: some View {
        VStack(spacing: 24) {
            Text("Update Required")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Please update to the latest version of Split for continued usage. If you are having any issues please do not hesitate to reach out to support@example.com")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding()

            Button(action: {
                if let url = URL(string: "https://apps.apple.com/us/app/split-rewards/id6740720801") {
                    UIApplication.shared.open(url)
                }
            }) {
                Text("Update Now")
                    .bold()
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .padding(.horizontal)
        }
        .padding()
    }
}


