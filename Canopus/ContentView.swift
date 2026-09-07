import SwiftUI
import Domain
import EVEAuth
import AuthenticationServices

// MARK: - Tab definition

enum EVETab: Int, CaseIterable, Identifiable {
    case home, skills, assets, wallet, items
    var id: Int { rawValue }

    var label: String {
        switch self {
        case .home:   return "HOME"
        case .skills: return "SKILLS"
        case .assets: return "ASSETS"
        case .wallet: return "WALLET"
        case .items:  return "ITEMS"
        }
    }

    var icon: String {
        switch self {
        case .home:   return "house.fill"
        case .skills: return "brain.head.profile"
        case .assets: return "shippingbox.fill"
        case .wallet: return "creditcard.fill"
        case .items:  return "cube.fill"
        }
    }
}

// MARK: - Root view

struct ContentView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.webAuthenticationSession) private var webAuthSession
    @State private var selectedTab: EVETab = .home
    @State private var itemsSearchText = ""

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.eveBackground.ignoresSafeArea()

            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 55) }

            HUDTabBar(selected: $selectedTab)
        }
        .eveScanlinesOverlay()
        .preferredColorScheme(.dark)
        .task { env.loadIfNeeded() }
    }

    // MARK: - Tab content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .home:
            NavigationStack {
                if env.characterStore.characters.isEmpty {
                    LoginView()
                        .navigationTitle("Canopus")
                        .background(Color.eveBackground)
                } else {
                    CharacterRootView(switchToTab: { selectedTab = $0 })
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                addButton
                            }
                        }
                }
            }

        case .skills:
            NavigationStack {
                if env.characterStore.selectedService != nil {
                    SkillQueueView()
                } else {
                    noCharacterView
                }
            }

        case .assets:
            NavigationStack {
                if let svc = env.characterStore.selectedService {
                    AssetsView(characterService: svc)
                } else {
                    noCharacterView
                }
            }

        case .wallet:
            NavigationStack {
                if let svc = env.characterStore.selectedService {
                    WalletTabView(characterService: svc)
                } else {
                    noCharacterView
                }
            }

        case .items:
            NavigationStack {
                itemsBrowser
                    .navigationTitle("Items")
                    .searchable(text: $itemsSearchText, prompt: "Search types…")
                    .navigationDestination(for: ItemCategory.self) { GroupListView(category: $0) }
                    .navigationDestination(for: ItemGroup.self) { TypeListView(group: $0) }
                    .navigationDestination(for: ItemType.self) {
                        TypeDetailView(typeId: $0.id, typeName: $0.name)
                    }
            }
        }
    }

    @ViewBuilder
    private var itemsBrowser: some View {
        switch env.loadState {
        case .idle, .loading:
            ProgressView("Loading database…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.eveBackground)
        case .failed(let error):
            ContentUnavailableView("Database unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text(error.localizedDescription))
        case .ready:
            if itemsSearchText.isEmpty { CategoryListView() }
            else { SearchResultsView(query: itemsSearchText) }
        }
    }

    private var noCharacterView: some View {
        ContentUnavailableView("No Character",
            systemImage: "person.crop.circle.badge.exclamationmark",
            description: Text("Log in on the Home tab first."))
        .background(Color.eveBackground)
    }

    private var addButton: some View {
        Button {
            Task {
                try? await env.characterStore.addCharacter { url in
                    try await webAuthSession.authenticate(
                        using: url, callbackURLScheme: EVEConstants.callbackScheme)
                }
            }
        } label: {
            Image(systemName: "plus").foregroundStyle(Color.eveAmber)
        }
    }
}

// MARK: - HUD Tab Bar

struct HUDTabBar: View {
    @Binding var selected: EVETab

    var body: some View {
        VStack(spacing: 0) {
            Color.eveAmber.opacity(0.20).frame(height: 1)

            HStack(spacing: 0) {
                ForEach(EVETab.allCases) { tab in
                    tabButton(tab)
                }
            }
            .frame(height: 54)
            .background(Color.eveBackground.opacity(0.96))

            Color.eveBackground.opacity(0.96)
                .frame(height: 28) // safe area bottom fill
        }
    }

    private func tabButton(_ tab: EVETab) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.12)) { selected = tab }
        } label: {
            let active = selected == tab
            VStack(spacing: 5) {
                Rectangle()
                    .fill(active ? Color.eveAmber : Color.clear)
                    .frame(height: 2)
                    .padding(.horizontal, 10)

                Image(systemName: tab.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(active ? Color.eveAmber : Color.eveText.opacity(0.42))
                    .frame(width: 22, height: 20)
                    .overlay(
                        CutCorner(size: 5)
                            .stroke(active ? Color.eveAmber : Color.eveText.opacity(0.22),
                                    lineWidth: 1.1)
                    )

                Text(tab.label)
                    .font(.system(size: 8.5, weight: .semibold))
                    .tracking(1.3)
                    .foregroundStyle(active ? Color.eveAmber : Color.eveText.opacity(0.42))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
