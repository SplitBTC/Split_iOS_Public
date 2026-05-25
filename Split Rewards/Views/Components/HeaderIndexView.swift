//
//  HeaderIndexView.swift
//  Split
//
//  Created by TeeVee on 1/6/25.
//
import SwiftUI

struct HeaderIndexView: View {

    var body: some View {
        NavigationStack {  // Ensure this is wrapped in a NavigationStack for navigation functionality
            VStack {
                HStack {
                    // Image on the left
                    Image("SplitLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100) // Adjust size as needed
                        .padding(.leading, 3) // Padding to prevent image from being too close to the left edge

                    Spacer()
                }
            }
        }
    }
}


















