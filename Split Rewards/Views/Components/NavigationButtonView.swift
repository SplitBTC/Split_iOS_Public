//
//  NavigationButtonView.swift
//  Split-iOS
//
//  Created by TeeVee on 1/9/25.
//
import SwiftUI

struct NavigationButtonView<Destination: View>: View {
    let title: String
    let destination: Destination

    var body: some View {
        NavigationLink(destination: destination) {
            Text(title)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.splitBrandBlue)
                .cornerRadius(12)
                .foregroundColor(.white)
        }
    }
}
