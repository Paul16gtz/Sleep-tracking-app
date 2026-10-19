import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            Text("Heute Nacht")
                .tabItem {
                    Label("Heute Nacht", systemImage: "moon.zzz.fill")
                }
            Text("Nächte")
                .tabItem {
                    Label("Nächte", systemImage: "list.bullet")
                }
        }
    }
}
