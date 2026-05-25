//
//  RenameExternalWalletSheet.swift
//  Split Rewards
//
//  Created by TeeVee on 5/6/26.
//

import SwiftUI

struct RenameExternalWalletSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let initialName: String
    @Binding var text: String
    let onSave: () -> Void

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            Color.splitSoftBackground
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.title2.bold())
                    .foregroundColor(.white)

                TextField(initialName, text: $text)
                    .textInputAutocapitalization(.words)
                    .foregroundColor(.white)
                    .padding(14)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button {
                    guard canSave else { return }
                    onSave()
                    dismiss()
                } label: {
                    Text("Save")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(canSave ? Color.splitBrandBlue : Color.white.opacity(0.14))
                        )
                }
                .disabled(!canSave)

                Spacer(minLength: 0)
            }
            .padding(18)
        }
        .onAppear {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                text = initialName
            }
        }
    }
}
