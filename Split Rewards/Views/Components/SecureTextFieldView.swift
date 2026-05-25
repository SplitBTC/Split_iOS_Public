//
//  SecureTextFieldView.swift
//  Split Rewards
//  Created by TeeVee on 1/16/25.
//
import SwiftUI

struct SecureTextFieldView: View {
    var placeholder: String
    @Binding var text: String

    var body: some View {
        SecureField(placeholder, text: $text)
            .foregroundColor(.black)
            .autocapitalization(.none)
            .padding()
            .textInputAutocapitalization(.never)
            .keyboardType(.emailAddress)
            .background(Color.white)
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8) // Add vertical padding for better spacing
    }
}


