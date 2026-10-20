import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            TonightView()
                .tabItem {
                    Label("Heute Nacht", systemImage: "moon.zzz.fill")
                }
            NightsListView()
                .tabItem {
                    Label("Nächte", systemImage: "list.bullet")
                }
        }
    }
}
