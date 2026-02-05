import SwiftUI

struct TradingView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                Text("Trading")
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Trading")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

#Preview {
    TradingView()
}
