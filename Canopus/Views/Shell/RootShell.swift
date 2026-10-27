// App shell with the desktop's sections: Pilot · Combat · Economy · Space, plus the database and settings.
// iPhone: a tab bar with one tab per section, each opening on the section's pages. iPad: the desktop's
// sidebar (sections with their pages) next to the page.

import AuthenticationServices
import EVEAuth
import SwiftUI
import UIKit

// MARK: - Pages and sections

enum Page: String, Hashable, CaseIterable, Identifiable {
    case character, skills, mail, clones
    case intel, fitting, killboard
    case wallet, orders, industry, mining, loyalty, contracts, assets
    case map
    case database
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .character: "Character"
        case .skills: "Skills"
        case .mail: "Mail"
        case .clones: "Clones & implants"
        case .intel: "Intel"
        case .fitting: "Fitting"
        case .killboard: "PvP"
        case .wallet: "Wallet"
        case .orders: "Market orders"
        case .industry: "Industry"
        case .mining: "Mining ledger"
        case .loyalty: "Loyalty points"
        case .contracts: "Contracts"
        case .assets: "Assets"
        case .map: "Map"
        case .database: "Database"
        case .settings: "Settings"
        }
    }

    /// SF Symbols close to the desktop's sidebar icons.
    var icon: String {
        switch self {
        case .character: "person"
        case .skills: "brain.head.profile"
        case .mail: "envelope"
        case .clones: "person.2"
        case .intel: "dot.radiowaves.left.and.right"
        case .fitting: "hexagon"
        case .killboard: "scope"
        case .wallet: "creditcard"
        case .orders: "chart.line.uptrend.xyaxis"
        case .industry: "gearshape.2"
        case .mining: "cube"
        case .loyalty: "seal"
        case .contracts: "doc.text"
        case .assets: "shippingbox"
        case .map: "map"
        case .database: "books.vertical"
        case .settings: "slider.horizontal.3"
        }
    }

    /// Pages that come with a later phase (docs/ROADMAP.md).
    var comingSoon: Bool { self == .intel || self == .map }
}

enum NavSection: String, CaseIterable, Identifiable {
    case pilot, combat, economy, space, more

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pilot: "Pilot"
        case .combat: "Combat"
        case .economy: "Economy"
        case .space: "Space"
        case .more: "More"
        }
    }

    var icon: String {
        switch self {
        case .pilot: "person.crop.circle"
        case .combat: "scope"
        case .economy: "chart.bar"
        case .space: "map"
        case .more: "ellipsis.circle"
        }
    }

    var pages: [Page] {
        switch self {
        case .pilot: [.character, .skills, .mail, .clones]
        case .combat: [.intel, .fitting, .killboard]
        case .economy: [.wallet, .orders, .industry, .mining, .loyalty, .contracts, .assets]
        case .space: [.map]
        case .more: [.database, .settings]
        }
    }
}

// MARK: - Root

struct RootShell: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var section: NavSection = .pilot
    @State private var sidebarPage: Page? = .character
    /// Per-section navigation stacks on iPhone, so switching tabs keeps where each one was.
    @State private var paths: [NavSection: NavigationPath] = [:]

    var body: some View {
        ZStack {
            if sizeClass == .regular {
                splitView
            } else {
                tabView
            }
            if env.showSDEUpdateSheet {
                SDEUpdateView()
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .zIndex(999)
            }
        }
        .background(C.bg)
        .animation(.easeInOut(duration: 0.25), value: env.showSDEUpdateSheet)
        .task {
            env.loadIfNeeded()
            #if DEBUG
            // Debug builds: `-startPage skills` opens a page at launch (screenshots, UI checks).
            if let p = UserDefaults.standard.string(forKey: "startPage").flatMap(Page.init(rawValue:)) { open(p) }
            #endif
        }
    }

    // iPhone: one tab per section.
    private var tabView: some View {
        TabView(selection: $section) {
            ForEach(NavSection.allCases) { s in
                NavigationStack(path: path(s)) {
                    SectionHub(section: s, open: open)
                        .navigationDestination(for: Page.self) { PageView(page: $0, open: open) }
                }
                .tabItem { Label(LocalizedStringKey(s.title), systemImage: s.icon) }
                .tag(s)
            }
        }
    }

    // iPad: the desktop sidebar.
    private var splitView: some View {
        NavigationSplitView {
            List(selection: $sidebarPage) {
                ForEach(NavSection.allCases) { s in
                    SwiftUI.Section {
                        ForEach(s.pages) { p in
                            Label(LocalizedStringKey(p.title), systemImage: p.icon).tag(p)
                        }
                    } header: {
                        Text(LocalizedStringKey(s.title))
                    }
                }
            }
            .navigationTitle("Canopus")
            .scrollContentBackground(.hidden)
            .background(C.nav)
        } detail: {
            NavigationStack {
                PageView(page: sidebarPage ?? .character, open: open)
                    .navigationDestination(for: Page.self) { PageView(page: $0, open: open) }
            }
            .id(sidebarPage)
        }
    }

    private func path(_ s: NavSection) -> Binding<NavigationPath> {
        Binding(get: { paths[s] ?? NavigationPath() }, set: { paths[s] = $0 })
    }

    /// Opens a page from anywhere (the character overview's "skills", "wallet" links).
    private func open(_ page: Page) {
        if sizeClass == .regular {
            sidebarPage = page
            return
        }
        guard let s = NavSection.allCases.first(where: { $0.pages.contains(page) }) else { return }
        section = s
        var p = NavigationPath()
        if s.pages.first != page || page != .character { p.append(page) }
        paths[s] = p
    }
}

// MARK: - NavSection hub (iPhone)

/// The first screen of a tab: the section's pages as desktop-style rows. Pilot opens on the character.
struct SectionHub: View {
    let section: NavSection
    let open: (Page) -> Void

    var body: some View {
        if section == .pilot {
            PageView(page: .character, open: open)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(section.title)
                    VStack(spacing: 0) {
                        ForEach(section.pages) { p in
                            NavigationLink(value: p) { PageRow(page: p) }
                                .buttonStyle(.plain)
                            if p != section.pages.last {
                                Rectangle().fill(C.border).frame(height: 1).padding(.leading, 52)
                            }
                        }
                    }
                    .canopusSurface(padding: nil)
                }
                .padding(16)
            }
            .background(C.bg)
            .navigationTitle(LocalizedStringKey(section.title))
        }
    }
}

struct PageRow: View {
    let page: Page

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: page.icon)
                .font(.system(size: 16))
                .foregroundStyle(C.accentText)
                .frame(width: 22)
            Text(LocalizedStringKey(page.title))
                .font(.ui(15))
                .foregroundStyle(C.text)
            Spacer()
            if page.comingSoon {
                Pill(text: "Soon", color: C.muted)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(C.faint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }
}

// MARK: - Page content

struct PageView: View {
    @Environment(AppEnvironment.self) private var env
    let page: Page
    let open: (Page) -> Void

    var body: some View {
        content
            .background(C.bg)
    }

    @ViewBuilder
    private var content: some View {
        switch page {
        case .database:
            DatabasePage()
        case .settings:
            SettingsPage()
        case .intel:
            ComingSoon(page: page, text: "Local and d-scan checks, pilot lookup and the live kill radar from the desktop app.")
        case .map:
            ComingSoon(page: page, text: "Routes with danger checks, kills and jumps by system, sovereignty.")
        default:
            if let svc = env.characterStore.selectedService {
                characterPage(svc)
            } else {
                LoginView()
                    .navigationTitle(LocalizedStringKey(page.title))
            }
        }
    }

    @ViewBuilder
    private func characterPage(_ s: CharacterService) -> some View {
        switch page {
        case .character:
            CharacterRootView(switchToTab: { tab in
                switch tab {
                case .skills: open(.skills)
                case .wallet: open(.wallet)
                case .assets: open(.assets)
                case .items: open(.database)
                case .home: open(.character)
                }
            })
        case .skills: SkillsView()
        case .mail: MailView(characterService: s)
        case .clones: CloneView(characterService: s)
        case .fitting: FittingsView(characterService: s)
        case .killboard: KillBoardView(characterService: s)
        case .wallet: WalletTabView(characterService: s)
        case .orders: MarketOrdersView(characterService: s)
        case .industry: IndustryView(characterService: s)
        case .mining: MiningLedgerView(characterService: s)
        case .loyalty: LoyaltyPointsView(characterService: s)
        case .contracts: ContractsView(characterService: s)
        case .assets: AssetsView(characterService: s)
        default: EmptyView()
        }
    }
}

/// A page that arrives with a later phase: says what it will do, like the desktop's.
struct ComingSoon: View {
    let page: Page
    let text: String

    var body: some View {
        ScrollView {
            Card(page.title) {
                VStack(alignment: .leading, spacing: 10) {
                    Pill(text: "Soon", color: C.accent)
                    Text(LocalizedStringKey(text))
                        .font(.ui(15))
                        .foregroundStyle(C.text2)
                }
            }
            .padding(16)
        }
        .navigationTitle(LocalizedStringKey(page.title))
    }
}

// MARK: - UIKit appearance

enum CanopusAppearance {
    /// Navigation and tab bars in the desktop colors and fonts.
    static func apply() {
        let nav = UINavigationBarAppearance()
        nav.configureWithOpaqueBackground()
        nav.backgroundColor = UIColor(C.bg)
        nav.shadowColor = UIColor(C.border)
        nav.titleTextAttributes = [
            .foregroundColor: UIColor(C.text),
            .font: UIFont(name: "Exo 2", size: 17)?.withWeight(.semibold) ?? .systemFont(ofSize: 17, weight: .semibold)
        ]
        nav.largeTitleTextAttributes = [
            .foregroundColor: UIColor(C.text),
            .font: UIFont(name: "Exo 2", size: 30)?.withWeight(.semibold) ?? .systemFont(ofSize: 30, weight: .semibold)
        ]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav

        let tab = UITabBarAppearance()
        tab.configureWithOpaqueBackground()
        tab.backgroundColor = UIColor(C.nav)
        tab.shadowColor = UIColor(C.border)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
    }
}

private extension UIFont {
    /// A variable font at a weight (UIFont(name:) gives the default instance).
    func withWeight(_ weight: UIFont.Weight) -> UIFont {
        let d = fontDescriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
        return UIFont(descriptor: d, size: pointSize)
    }
}
