//
//  LegalView.swift
//  Split Rewards
//
//  Created by TeeVee on 1/17/25.
//
import SwiftUI
import JWTDecode

struct LegalView: View {
    @EnvironmentObject var appState: AppState
    @State private var showPrivacyPolicySheet = false // State for presenting the Privacy Policy sheet
    @State private var showUserAgreementSheet = false
    let pink = Color.splitBrandPink
           
    var body: some View {
        NavigationStack {
                VStack(spacing: 20) {
                    
                    // User Agreement button
                    Button(action: {
                        showUserAgreementSheet = true
                        print("User Agreement tapped")
                    }) {
                        Text("User Agreement")
                            .font(.title2)
                            .foregroundColor(.splitBrandBlue)
                            .fontWeight(.heavy)
                    }
                    .sheet(isPresented: $showUserAgreementSheet) {
                        UserAgreementSheetView()
                            .presentationDetents([.fraction(1.0), .large]) // Set sheet height to 75% of the screen
                    }
                    
                    // Privacy Policy button
                    Button(action: {
                        showPrivacyPolicySheet = true // Present the Privacy Policy sheet
                    }) {
                        Text("Privacy Policy")
                            .font(.title2)
                            .foregroundColor(.splitBrandBlue)
                            .fontWeight(.heavy)
                    }
                    .sheet(isPresented: $showPrivacyPolicySheet) {
                        PrivacyPolicySheetView()
                            .presentationDetents([.fraction(1.0), .large]) // Set sheet height to 75% of the screen
                    }
                    .padding(.bottom, 50)
                    
                    }
                .frame(alignment: .center)
                    
            }
            .ignoresSafeArea()
            .navigationTitle("Legal")
            }
        }
    





