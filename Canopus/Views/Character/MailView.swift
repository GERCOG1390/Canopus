import SwiftUI
import EVEAuth

// MARK: - Mail label definition

private enum MailLabel: Int, CaseIterable, Identifiable, Hashable {
    case inbox = 1, sent = 2, corp = 4, alliance = 8
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .inbox:    return String(localized: "Inbox")
        case .sent:     return String(localized: "Sent")
        case .corp:     return String(localized: "Corporation")
        case .alliance: return String(localized: "Alliance")
        }
    }
}

// MARK: - Mail list

struct MailView: View {
    let characterService: CharacterService

    @State private var selectedLabel: MailLabel = .inbox
    @State private var mails: [ESIMailHeader] = []
    @State private var names: [Int: String] = [:]
    @State private var unreadCounts: [Int: Int] = [:]
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var hasMore = true
    @State private var error: Error?

    private var filtered: [ESIMailHeader] {
        mails.filter { $0.labels?.contains(selectedLabel.rawValue) == true }
    }

    var body: some View {
        ZStack {
            Color.eveBackground.ignoresSafeArea()
            VStack(spacing: 0) {
                labelPicker
                Rectangle().fill(C.border).frame(height: 1)
                mailList
            }
            if isLoading { ProgressView().tint(Color.eveCyan) }
        }
        .navigationTitle("Mail")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.eveBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await initialLoad() }
        .alert("Error", isPresented: Binding(
            get: { error != nil }, set: { if !$0 { error = nil } })
        ) {
            Button("Retry") { Task { await initialLoad() } }
            Button("Dismiss", role: .cancel) {}
        } message: { Text(error?.localizedDescription ?? "") }
    }

    // MARK: - Label picker

    private var labelPicker: some View {
        CanopusTabs(
            tabs: MailLabel.allCases.map { label in
                let unread = unreadCounts[label.rawValue] ?? 0
                return (label, unread > 0 ? "\(label.title) \(unread)" : label.title)
            },
            selection: $selectedLabel
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(C.bg)
    }

    // MARK: - Mail list

    private var mailList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if filtered.isEmpty && !isLoading {
                    EmptyState("No Mail", icon: "win_evemail") { Text("Nothing in \(selectedLabel.title)") }
                    .foregroundStyle(Color.eveText)
                    .padding(.top, 60)
                } else {
                    ForEach(filtered) { mail in
                        NavigationLink(value: mail) {
                            mailRow(mail)
                        }
                        .buttonStyle(.plain)
                        Color.white.opacity(0.055).frame(height: 1)
                    }

                    if hasMore && !filtered.isEmpty {
                        loadMoreButton
                    }
                }
            }
            .padding(.bottom, EVELayout.scrollBottomClearance)
        }
        .navigationDestination(for: ESIMailHeader.self) { mail in
            MailDetailView(characterService: characterService, header: mail, senderName: names[mail.from])
        }
    }

    private func mailRow(_ mail: ESIMailHeader) -> some View {
        let isUnread = mail.isRead == false
        return HStack(alignment: .top, spacing: 12) {
            // Unread indicator
            Circle()
                .fill(isUnread ? Color.eveAmber : Color.clear)
                .frame(width: 6, height: 6)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(names[mail.from] ?? "ID \(mail.from)")
                        .font(.system(size: 13, weight: isUnread ? .semibold : .regular))
                        .foregroundStyle(isUnread ? Color.eveText : Color.eveText.opacity(0.70))
                        .lineLimit(1)
                    Spacer()
                    Text(mail.timestamp, style: .relative)
                        .font(.ui(11)).monospacedDigit()
                        .foregroundStyle(Color.eveText.opacity(0.35))
                }
                Text(mail.subject)
                    .font(.system(size: 12, weight: isUnread ? .medium : .regular))
                    .foregroundStyle(isUnread ? Color.eveText.opacity(0.85) : Color.eveText.opacity(0.48))
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 13)
        .background(Color.eveBackground)
    }

    private var loadMoreButton: some View {
        Button {
            Task { await loadMore() }
        } label: {
            HStack(spacing: 8) {
                if isLoadingMore { ProgressView().tint(Color.eveCyan).scaleEffect(0.8) }
                Text("LOAD MORE")
                    .font(.ui(11, .semibold))
                    .tracking(1.6)
                    .foregroundStyle(Color.eveCyan)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .buttonStyle(.plain)
        .disabled(isLoadingMore)
    }

    // MARK: - Load

    private func initialLoad() async {
        isLoading = true
        mails = []
        hasMore = true
        error = nil
        defer { isLoading = false }
        do {
            async let labelsFetch = characterService.mailLabels()
            async let mailFetch   = characterService.mailHeaders()
            let (labelsResp, headers) = try await (labelsFetch, mailFetch)

            for label in labelsResp.labels {
                unreadCounts[label.labelId] = label.unreadCount ?? 0
            }

            mails = headers.sorted { $0.timestamp > $1.timestamp }
            hasMore = !headers.isEmpty && headers.count % 50 == 0

            await resolveNames(in: headers)
        } catch {
            if !error.isCancellation { self.error = error }
        }
    }

    private func loadMore() async {
        guard !isLoadingMore, hasMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let lastId = mails.map(\.mailId).min()
        do {
            let more = try await characterService.mailHeaders(lastMailId: lastId)
            let newMails = more.filter { m in !mails.contains(where: { $0.mailId == m.mailId }) }
            mails += newMails.sorted { $0.timestamp > $1.timestamp }
            hasMore = !more.isEmpty && more.count % 50 == 0
            await resolveNames(in: newMails)
        } catch {
            if !error.isCancellation { self.error = error }
        }
    }

    private func resolveNames(in headers: [ESIMailHeader]) async {
        let unknown = Set(headers.map(\.from)).subtracting(names.keys)
        guard !unknown.isEmpty else { return }
        if let resolved = try? await characterService.resolveNames(ids: Array(unknown)) {
            for r in resolved { names[r.id] = r.name }
        }
    }
}

// MARK: - Mail detail

struct MailDetailView: View {
    let characterService: CharacterService
    let header: ESIMailHeader
    let senderName: String?

    @State private var body_: ESIMailBody?
    @State private var isLoading = true
    @State private var recipientNames: [Int: String] = [:]

    private var bodyText: String {
        body_?.body.strippedEVEHTML ?? ""
    }

    var body: some View {
        ZStack {
            Color.eveBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Header card
                    VStack(alignment: .leading, spacing: 10) {
                        Text(header.subject)
                            .font(.ui(19, .semibold))
                            .foregroundStyle(Color.eveText)

                        Color.eveAmber.opacity(0.14).frame(height: 1)

                        metaRow(label: "FROM", value: senderName ?? "ID \(header.from)")
                        thinDiv
                        metaRow(label: "DATE", value: header.timestamp.formatted(
                            date: .abbreviated, time: .shortened))
                        if let recips = body_?.recipients, !recips.isEmpty {
                            thinDiv
                            metaRow(label: "TO", value: recips.prefix(5).map {
                                recipientNames[$0.recipientId] ?? $0.recipientType.capitalized
                            }.joined(separator: ", "))
                        }
                    }
                    .padding(18)
                    .background(Color.eveCard)

                    Color.eveAmber.opacity(0.14).frame(height: 1)

                    // Body
                    if isLoading {
                        ProgressView().tint(Color.eveCyan)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else {
                        Text(bodyText.isEmpty ? "(No content)" : bodyText)
                            .font(.ui(15))
                            .foregroundStyle(bodyText.isEmpty
                                            ? Color.eveText.opacity(0.35)
                                            : Color.eveText.opacity(0.85))
                            .lineSpacing(5)
                            .padding(20)
                    }
                }
                .padding(.bottom, EVELayout.scrollBottomClearance)
            }
        }
        .navigationTitle("Letter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.eveBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await load() }
    }

    private func metaRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(LocalizedStringKey(label))
                .font(.ui(11, .semibold))
                .tracking(1.6)
                .foregroundStyle(Color.eveText.opacity(0.35))
                .frame(width: 46, alignment: .leading)
            Text(value)
                .font(.ui(13.5))
                .foregroundStyle(Color.eveText.opacity(0.80))
                .multilineTextAlignment(.leading)
        }
    }

    private var thinDiv: some View {
        Color.white.opacity(0.06).frame(height: 1)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard let mail = try? await characterService.mailBody(mailId: header.mailId) else { return }
        body_ = mail

        // Mark as read in the background
        if header.isRead == false {
            try? await characterService.markMailRead(mailId: header.mailId, preserving: mail.labels)
        }

        // Resolve recipient names
        let ids = mail.recipients.map(\.recipientId)
        if let resolved = try? await characterService.resolveNames(ids: ids) {
            for r in resolved { recipientNames[r.id] = r.name }
        }
    }
}
