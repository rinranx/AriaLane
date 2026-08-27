import Foundation

enum LibraryCatalogServiceError: LocalizedError {
    case allSourcesFailed([String])
    case downloadsUnavailable
    case noSourcesEnabled
    case sourceDisabled(String)
    case customSourceUnavailable

    var errorDescription: String? {
        switch self {
        case .allSourcesFailed(let messages):
            L10n.string("所有资源来源均搜索失败：\(messages.joined(separator: "；"))")
        case .downloadsUnavailable:
            L10n.string("此条目没有可验证的直接下载来源")
        case .noSourcesEnabled:
            L10n.string("没有启用的资源来源")
        case .sourceDisabled(let name):
            L10n.string("“\(name)”已在设置中停用")
        case .customSourceUnavailable:
            L10n.string("自定义来源已停用或不存在")
        }
    }
}

struct LibraryCatalogService {
    let internetArchive: InternetArchiveService
    let projectGutenberg: ProjectGutenbergService
    let openLibrary: OpenLibraryService
    let customOPDS: CustomOPDSService
    let enabledBuiltInSources: Set<BuiltInLibrarySource>
    let customSources: [CustomLibrarySource]

    init(
        session: URLSession = .shared,
        enabledBuiltInSources: Set<BuiltInLibrarySource> = Set(
            BuiltInLibrarySource.allCases
        ),
        customSources: [CustomLibrarySource] = []
    ) {
        internetArchive = InternetArchiveService(session: session)
        projectGutenberg = ProjectGutenbergService(session: session)
        openLibrary = OpenLibraryService(session: session)
        customOPDS = CustomOPDSService(session: session)
        self.enabledBuiltInSources = enabledBuiltInSources
        self.customSources = customSources
    }

    func search(
        query: String,
        scope: LibrarySearchScope
    ) async throws -> LibraryResourceSearchPage {
        switch scope {
        case .internetArchive:
            try ensureEnabled(.internetArchive)
            return try await internetArchive.search(query: query, limit: 30)
        case .projectGutenberg:
            try ensureEnabled(.projectGutenberg)
            return try await projectGutenberg.search(query: query, limit: 25)
        case .openLibrary:
            try ensureEnabled(.openLibrary)
            return try await openLibrary.search(query: query, limit: 30)
        case .custom(let id):
            guard let source = customSources.first(where: {
                $0.id == id && $0.isEnabled
            }) else {
                throw LibraryCatalogServiceError.customSourceUnavailable
            }
            return try await customOPDS.search(
                source: source,
                query: query,
                limit: 30
            )
        case .all:
            return try await searchAll(query: query)
        }
    }

    func downloads(for resource: LibraryResource) async throws -> LibraryResourceDownloads {
        switch resource.downloadLocator {
        case .internetArchive(let identifier):
            try ensureEnabled(.internetArchive)
            return try await internetArchive.downloads(identifier: identifier)
        case .projectGutenberg(let bookID):
            try ensureEnabled(.projectGutenberg)
            return try await projectGutenberg.downloads(bookID: bookID)
        case .custom(let downloads):
            return downloads
        case .unavailable:
            throw LibraryCatalogServiceError.downloadsUnavailable
        }
    }

    private func searchAll(query: String) async throws -> LibraryResourceSearchPage {
        async let archiveOutcome = builtInOutcome(
            source: .internetArchive,
            query: query
        )
        async let gutenbergOutcome = builtInOutcome(
            source: .projectGutenberg,
            query: query
        )
        async let openLibraryOutcome = builtInOutcome(
            source: .openLibrary,
            query: query
        )
        async let customOutcomeList = customOutcomes(query: query)

        let (archive, gutenberg, openLibrary, custom) = await (
            archiveOutcome,
            gutenbergOutcome,
            openLibraryOutcome,
            customOutcomeList
        )
        let outcomes = [archive, gutenberg, openLibrary].compactMap { $0 } + custom

        guard !outcomes.isEmpty else {
            throw LibraryCatalogServiceError.noSourcesEnabled
        }

        let successfulPages = outcomes.compactMap(\.page)

        guard !successfulPages.isEmpty else {
            throw LibraryCatalogServiceError.allSourcesFailed(
                outcomes.compactMap(\.errorMessage)
            )
        }

        return LibraryResourceSearchPage(
            resources: successfulPages.flatMap(\.resources),
            totalCount: successfulPages.reduce(0) { $0 + $1.totalCount },
            unavailableProviders: outcomes.compactMap {
                $0.page == nil ? $0.provider : nil
            }
        )
    }

    private func builtInOutcome(
        source: BuiltInLibrarySource,
        query: String
    ) async -> ProviderSearchOutcome? {
        guard enabledBuiltInSources.contains(source) else { return nil }

        do {
            let page: LibraryResourceSearchPage
            switch source {
            case .internetArchive:
                page = try await internetArchive.search(query: query, limit: 15)
            case .projectGutenberg:
                page = try await projectGutenberg.search(query: query, limit: 15)
            case .openLibrary:
                page = try await openLibrary.search(query: query, limit: 15)
            }

            return ProviderSearchOutcome(
                provider: source.provider,
                page: page,
                errorMessage: nil
            )
        } catch {
            return ProviderSearchOutcome(
                provider: source.provider,
                page: nil,
                errorMessage: error.localizedDescription
            )
        }
    }

    private func ensureEnabled(_ source: BuiltInLibrarySource) throws {
        guard enabledBuiltInSources.contains(source) else {
            throw LibraryCatalogServiceError.sourceDisabled(
                source.provider.title
            )
        }
    }

    private func customOutcomes(query: String) async -> [ProviderSearchOutcome] {
        let enabledSources = customSources.filter(\.isEnabled)
        return await withTaskGroup(
            of: IndexedProviderSearchOutcome.self,
            returning: [ProviderSearchOutcome].self
        ) { group in
            for (index, source) in enabledSources.enumerated() {
                group.addTask {
                    let outcome: ProviderSearchOutcome
                    do {
                        outcome = ProviderSearchOutcome(
                            provider: .custom(source),
                            page: try await customOPDS.search(
                                source: source,
                                query: query,
                                limit: 15
                            ),
                            errorMessage: nil
                        )
                    } catch {
                        outcome = ProviderSearchOutcome(
                            provider: .custom(source),
                            page: nil,
                            errorMessage: "\(source.displayName)：\(error.localizedDescription)"
                        )
                    }
                    return IndexedProviderSearchOutcome(
                        index: index,
                        outcome: outcome
                    )
                }
            }

            var outcomes: [IndexedProviderSearchOutcome] = []
            for await outcome in group {
                outcomes.append(outcome)
            }
            return outcomes.sorted { $0.index < $1.index }.map(\.outcome)
        }
    }
}

private struct ProviderSearchOutcome: Sendable {
    let provider: LibraryResourceProvider
    let page: LibraryResourceSearchPage?
    let errorMessage: String?
}

private struct IndexedProviderSearchOutcome: Sendable {
    let index: Int
    let outcome: ProviderSearchOutcome
}
