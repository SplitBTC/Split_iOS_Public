//
//  TitleView.swift
//  Split Rewards
//
//  Created by TeeVee on 1/20/25.
//
import SwiftUI

struct TitleView: View {
    var title: String

    var body: some View {
        Text(title)
            .font(.title)
            .fontWeight(.heavy)
            .foregroundColor(.splitBrandBlue)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal)
    }
}

struct TitleView_Previews: PreviewProvider {
    static var previews: some View {
        TitleView(title: "Checkout")
    }
}
