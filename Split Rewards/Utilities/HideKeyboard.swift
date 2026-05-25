//
//  HideKeyboard.swift
//  Split Rewards
//
//  Created by TeeVee on 6/3/25.
//
import SwiftUI

#if canImport(UIKit)
extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
    
    func dismissKeyboardBefore(_ action: @escaping () -> Void) {
        hideKeyboard()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            action()
        }
    }
}
#endif


