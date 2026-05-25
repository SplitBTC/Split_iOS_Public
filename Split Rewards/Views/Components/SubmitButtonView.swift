//
//  SubmitButtonView.swift
//  Split
//
//  Created by TeeVee on 1/6/25.
//
import SwiftUI

struct SubmitButtonView: View {
    var title: String
    var action: () -> Void
    var isDisabled: Bool

    var body: some View {
        Button(action: action) {
            Text(title)
                .fontWeight(.bold)
                .frame(width: 300)
                .padding()
                .background(Color.splitBrandBlue)
                .foregroundColor(.white)
                .cornerRadius(8)
        }
        .padding(.top, 20)
        .disabled(isDisabled)  // Disable button if isDisabled is true
    }
}
