import SwiftUI

struct RootView: View {
    @State private var libraryModel = EvidenceLibraryModel()
    @State private var selectedTab: Int

    init() {
        _selectedTab = State(initialValue: ProcessInfo.processInfo.arguments.contains("--evidence-tab") ? 1 : 0)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Label("tab.answer", systemImage: "sparkles")
                }
                .tag(0)

            EvidenceLibraryView(model: libraryModel)
                .tabItem {
                    Label("tab.evidence", systemImage: "archivebox.fill")
                }
                .tag(1)
        }
    }
}
