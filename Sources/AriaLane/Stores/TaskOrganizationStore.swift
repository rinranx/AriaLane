import Combine
import Foundation

@MainActor
final class TaskOrganizationStore: ObservableObject {
    @Published private(set) var tags: [TaskTag]
    @Published private(set) var smartFolders: [SmartFolder]
    @Published private(set) var entities: [TaskEntityRecord]
    @Published private(set) var liveAttemptKeys: Set<TaskAttemptKey> = []
    @Published var persistenceError: String?

    let loadingMessage: String?

    private let repository: TaskOrganizationRepository
    private var archive: TaskOrganizationArchive

    init(repository: TaskOrganizationRepository = TaskOrganizationRepository()) {
        self.repository = repository

        let result: ArchiveLoadResult<TaskOrganizationArchive>
        do {
            result = try repository.loadResult()
        } catch {
            result = ArchiveLoadResult(value: TaskOrganizationArchive(), recovery: nil)
            loadingMessage = L10n.string("无法读取标签与智能文件夹：\(error.localizedDescription)")
            archive = result.value
            tags = result.value.tags
            smartFolders = result.value.smartFolders
            entities = result.value.entities
            return
        }

        archive = result.value
        tags = result.value.tags
        smartFolders = result.value.smartFolders
        entities = result.value.entities
        switch result.recovery {
        case .restoredBackup:
            loadingMessage = L10n.string("标签与智能文件夹文件损坏，已从安全备份恢复")
        case .resetCorruptedFile(let fileURL):
            if let fileURL {
                loadingMessage =
                    L10n.string("标签与智能文件夹文件损坏，已保留为 \(fileURL.lastPathComponent) 并重新开始")
            } else {
                loadingMessage = L10n.string("标签与智能文件夹文件损坏，已使用空存档继续")
            }
        case nil:
            loadingMessage = nil
        }
    }

    func dismissPersistenceError() {
        persistenceError = nil
    }

    @discardableResult
    func createTag(name: String, color: TaskTagColor) -> TaskTag? {
        let name = name.trimmed
        guard !name.isEmpty,
              !archive.tags.contains(where: {
                  $0.displayName.caseInsensitiveCompare(name) == .orderedSame
              }) else {
            return nil
        }
        let tag = TaskTag(name: name, color: color)
        guard commit({ $0.tags.append(tag) }) else { return nil }
        return tag
    }

    @discardableResult
    func updateTag(id: UUID, name: String, color: TaskTagColor) -> Bool {
        let name = name.trimmed
        guard !name.isEmpty,
              !archive.tags.contains(where: {
                  $0.id != id
                      && $0.displayName.caseInsensitiveCompare(name) == .orderedSame
              }) else {
            return false
        }
        return commit { archive in
            guard let index = archive.tags.firstIndex(where: { $0.id == id }) else {
                return
            }
            archive.tags[index].name = name
            archive.tags[index].color = color
        }
    }

    func deleteTag(id: UUID) {
        _ = commit { archive in
            archive.tags.removeAll { $0.id == id }
            for index in archive.entities.indices {
                archive.entities[index].tagIDs.remove(id)
            }
            let rawID = id.uuidString
            for folderIndex in archive.smartFolders.indices {
                for ruleIndex in archive.smartFolders[folderIndex].rules.indices
                    where archive.smartFolders[folderIndex].rules[ruleIndex].field == .tag {
                    archive.smartFolders[folderIndex]
                        .rules[ruleIndex]
                        .selectedValues
                        .remove(rawID)
                }
            }
        }
    }

    @discardableResult
    func createSmartFolder(
        name: String,
        matchMode: SmartFolderMatchMode,
        rules: [SmartFolderRule]
    ) -> SmartFolder? {
        let name = name.trimmed
        guard !name.isEmpty, rules.contains(where: \.isConfigured) else {
            return nil
        }
        let folder = SmartFolder(name: name, matchMode: matchMode, rules: rules)
        guard commit({ $0.smartFolders.append(folder) }) else { return nil }
        return folder
    }

    @discardableResult
    func updateSmartFolder(
        id: UUID,
        name: String,
        matchMode: SmartFolderMatchMode,
        rules: [SmartFolderRule]
    ) -> Bool {
        let name = name.trimmed
        guard !name.isEmpty, rules.contains(where: \.isConfigured) else {
            return false
        }
        return commit { archive in
            guard let index = archive.smartFolders.firstIndex(where: { $0.id == id }) else {
                return
            }
            archive.smartFolders[index].name = name
            archive.smartFolders[index].matchMode = matchMode
            archive.smartFolders[index].rules = rules
        }
    }

    func deleteSmartFolder(id: UUID) {
        _ = commit { archive in
            archive.smartFolders.removeAll { $0.id == id }
        }
    }

    func tag(id: UUID) -> TaskTag? {
        tags.first { $0.id == id }
    }

    func smartFolder(id: UUID) -> SmartFolder? {
        smartFolders.first { $0.id == id }
    }

    func entity(id: UUID) -> TaskEntityRecord? {
        entities.first { $0.id == id }
    }

    func entityID(gid: String, profileID: UUID?) -> UUID? {
        let exact = TaskAttemptKey(serverProfileID: profileID, gid: gid)
        if let entity = entities.first(where: { $0.attempts.contains(exact) }) {
            return entity.id
        }
        return entities.first {
            $0.attempts.contains {
                $0.gid == gid && $0.serverProfileID == nil
            }
        }?.id
    }

    func entityIDs(gids: Set<String>, profileID: UUID?) -> Set<UUID> {
        Set(gids.compactMap { entityID(gid: $0, profileID: profileID) })
    }

    func tags(for entity: TaskEntityRecord) -> [TaskTag] {
        tags.filter { entity.tagIDs.contains($0.id) }
    }

    func tags(gid: String, profileID: UUID?) -> [TaskTag] {
        guard let id = entityID(gid: gid, profileID: profileID),
              let entity = entity(id: id) else {
            return []
        }
        return tags(for: entity)
    }

    func allEntities(_ entityIDs: Set<UUID>, haveTag tagID: UUID) -> Bool {
        guard !entityIDs.isEmpty else { return false }
        let matching = entities.filter { entityIDs.contains($0.id) }
        return matching.count == entityIDs.count
            && matching.allSatisfy { $0.tagIDs.contains(tagID) }
    }

    func toggleTag(_ tagID: UUID, for entityIDs: Set<UUID>) {
        guard archive.tags.contains(where: { $0.id == tagID }),
              !entityIDs.isEmpty else {
            return
        }
        let shouldRemove = allEntities(entityIDs, haveTag: tagID)
        _ = commit { archive in
            for index in archive.entities.indices
                where entityIDs.contains(archive.entities[index].id) {
                if shouldRemove {
                    archive.entities[index].tagIDs.remove(tagID)
                } else {
                    archive.entities[index].tagIDs.insert(tagID)
                }
            }
        }
    }

    func addTag(_ tagID: UUID, to entityIDs: Set<UUID>) {
        guard archive.tags.contains(where: { $0.id == tagID }) else { return }
        _ = commit { archive in
            for index in archive.entities.indices
                where entityIDs.contains(archive.entities[index].id) {
                archive.entities[index].tagIDs.insert(tagID)
            }
        }
    }

    func entities(for selection: SidebarSelection) -> [TaskEntityRecord] {
        switch selection {
        case .tag(let id):
            return entities.filter { $0.tagIDs.contains(id) }
        case .smartFolder(let id):
            guard let folder = smartFolder(id: id) else { return [] }
            return entities.filter { folder.matches($0) }
        case .filter:
            return []
        }
    }

    func count(for tag: TaskTag) -> Int {
        entities.lazy.filter { $0.tagIDs.contains(tag.id) }.count
    }

    func count(for folder: SmartFolder) -> Int {
        entities.lazy.filter { folder.matches($0) }.count
    }

    func previewCount(
        matchMode: SmartFolderMatchMode,
        rules: [SmartFolderRule]
    ) -> Int {
        let folder = SmartFolder(name: L10n.string("预览"), matchMode: matchMode, rules: rules)
        return entities.lazy.filter { folder.matches($0) }.count
    }

    func liveTransfer(
        for entity: TaskEntityRecord,
        in transfers: [TransferItem],
        profileID: UUID?
    ) -> TransferItem? {
        let gids = Set(
            entity.attempts.lazy
                .filter {
                    $0.serverProfileID == profileID || $0.serverProfileID == nil
                }
                .map(\.gid)
        )
        return transfers.first { gids.contains($0.gid) }
    }

    func historyEntry(
        for entity: TaskEntityRecord,
        in entries: [DownloadHistoryEntry]
    ) -> DownloadHistoryEntry? {
        if let primaryGID = entity.primaryAttempt?.gid,
           let entry = entries.first(where: { $0.gid == primaryGID }) {
            return entry
        }
        let gids = Set(entity.attempts.map(\.gid))
        return entries.first { gids.contains($0.gid) }
    }

    func reconcileHistory(_ entries: [DownloadHistoryEntry], at date: Date = Date()) {
        var next = archive
        var didChange = false
        for entry in entries {
            didChange = mergeHistory(
                entry,
                into: &next,
                preferredProfileID: nil,
                fallbackDate: date
            ) || didChange
        }
        if didChange {
            persist(next)
        }
    }

    func reconcile(
        transfers: [TransferItem],
        historyEntries: [DownloadHistoryEntry],
        profileID: UUID?,
        excludingGIDs: Set<String> = [],
        at date: Date = Date()
    ) {
        let includedTransfers = transfers.filter { !excludingGIDs.contains($0.gid) }
        let nextLiveKeys = Set(
            includedTransfers.map {
                TaskAttemptKey(serverProfileID: profileID, gid: $0.gid)
            }
        )
        if liveAttemptKeys != nextLiveKeys {
            liveAttemptKeys = nextLiveKeys
        }

        var next = archive
        var didChange = false
        for item in includedTransfers {
            let key = TaskAttemptKey(serverProfileID: profileID, gid: item.gid)
            if let index = entityIndex(for: key, in: next, acceptingUnknownProfile: true) {
                var entity = next.entities[index]
                let previous = entity
                upgradeUnknownAttempt(for: key, in: &entity)
                entity.attempts.insert(key)
                entity.primaryAttempt = key
                apply(item, to: &entity, observedAt: date)
                if entity != previous {
                    next.entities[index] = entity
                    didChange = true
                }
            } else {
                next.entities.append(makeEntity(from: item, key: key, observedAt: date))
                didChange = true
            }
        }

        for entry in historyEntries {
            didChange = mergeHistory(
                entry,
                into: &next,
                preferredProfileID: profileID,
                fallbackDate: date
            ) || didChange
        }

        let liveGIDs = Set(includedTransfers.map(\.gid))
        let previousCount = next.entities.count
        next.entities.removeAll { entity in
            guard !entity.hasHistory,
                  let primary = entity.primaryAttempt,
                  primary.serverProfileID == profileID,
                  !liveGIDs.contains(primary.gid) else {
                return false
            }
            return !entity.attempts.contains {
                $0.serverProfileID == profileID && liveGIDs.contains($0.gid)
            }
        }
        didChange = didChange || next.entities.count != previousCount

        if didChange {
            persist(next)
        }
    }

    func registerSubmission(
        _ entry: PendingDownload,
        activeProfileID: UUID?
    ) {
        let profileID = entry.targetProfileID ?? activeProfileID
        let key = TaskAttemptKey(
            serverProfileID: profileID,
            gid: entry.submissionGID
        )
        var next = archive

        let replacedIndex = entry.replacesGID.flatMap { replacedGID in
            entityIndex(
                for: TaskAttemptKey(serverProfileID: profileID, gid: replacedGID),
                in: next,
                acceptingUnknownProfile: true
            )
        }
        if let index = replacedIndex
            ?? entityIndex(for: key, in: next, acceptingUnknownProfile: true) {
            var entity = next.entities[index]
            upgradeUnknownAttempt(for: key, in: &entity)
            entity.attempts.insert(key)
            entity.primaryAttempt = key
            if entity.sourceURI == nil {
                entity.sourceURI = entry.url
                entity.sourceDomain = TaskDomain.normalizedHost(from: entry.url)
            }
            if entity.transferProtocol == .unknown {
                entity.transferProtocol = TaskTransferProtocol.infer(fromURI: entry.url)
            }
            entity.lifecycle = .waiting
            next.entities[index] = entity
        } else {
            let protocolKind = TaskTransferProtocol.infer(fromURI: entry.url)
            let name = TaskOrganizationStore.displayName(for: entry.url)
            next.entities.append(
                TaskEntityRecord(
                    attempts: [key],
                    primaryAttempt: key,
                    name: name,
                    sourceURI: entry.url,
                    destinationPath: entry.taskOptions.directory,
                    byteCount: 0,
                    contentType: TaskContentType.classify(path: name),
                    transferProtocol: protocolKind,
                    lifecycle: .waiting,
                    addedAt: entry.createdAt,
                    addedAtIsInferred: false
                )
            )
        }
        persist(next)
    }

    func registerRetry(
        from oldGID: String,
        to newGID: String,
        sourceURI: String,
        profileID: UUID?
    ) {
        let oldKey = TaskAttemptKey(serverProfileID: profileID, gid: oldGID)
        let newKey = TaskAttemptKey(serverProfileID: profileID, gid: newGID)
        var next = archive

        if let index = entityIndex(
            for: oldKey,
            in: next,
            acceptingUnknownProfile: true
        ) {
            var entity = next.entities[index]
            upgradeUnknownAttempt(for: oldKey, in: &entity)
            entity.attempts.insert(oldKey)
            entity.attempts.insert(newKey)
            entity.primaryAttempt = newKey
            entity.lifecycle = .waiting
            if entity.transferProtocol == .unknown {
                entity.transferProtocol = TaskTransferProtocol.infer(fromURI: sourceURI)
            }
            next.entities[index] = entity
        } else {
            let name = Self.displayName(for: sourceURI)
            next.entities.append(
                TaskEntityRecord(
                    attempts: [oldKey, newKey],
                    primaryAttempt: newKey,
                    name: name,
                    sourceURI: sourceURI,
                    destinationPath: "",
                    byteCount: 0,
                    contentType: TaskContentType.classify(path: name),
                    transferProtocol: TaskTransferProtocol.infer(fromURI: sourceURI),
                    lifecycle: .waiting,
                    addedAt: Date(),
                    addedAtIsInferred: true
                )
            )
        }
        persist(next)
    }

    func registerImported(
        draft: PendingDownloadImport,
        choices: [ImportedFileChoice],
        profileID: UUID?,
        at date: Date = Date()
    ) {
        let selected = choices.filter(\.isSelected)
        let grouped = Dictionary(grouping: selected, by: \.gid)
        var next = archive

        for gid in draft.gids where grouped[gid] != nil || choices.isEmpty {
            let key = TaskAttemptKey(serverProfileID: profileID, gid: gid)
            let primaryFile = grouped[gid]?.max {
                $0.byteCount < $1.byteCount
            }
            let name = primaryFile.map {
                URL(fileURLWithPath: $0.path).lastPathComponent
            } ?? draft.title
            let path = primaryFile?.path ?? ""
            let protocolKind: TaskTransferProtocol =
                draft.kind == .torrent ? .torrent : .metalink

            if let index = entityIndex(
                for: key,
                in: next,
                acceptingUnknownProfile: true
            ) {
                var entity = next.entities[index]
                upgradeUnknownAttempt(for: key, in: &entity)
                entity.attempts.insert(key)
                entity.primaryAttempt = key
                entity.name = name
                entity.destinationPath = path
                entity.byteCount = max(
                    entity.byteCount,
                    grouped[gid]?.reduce(Int64(0)) { $0 + $1.byteCount } ?? 0
                )
                entity.contentType = TaskContentType.classify(path: path)
                entity.transferProtocol = protocolKind
                entity.lifecycle = .waiting
                entity.addedAt = date
                entity.addedAtIsInferred = false
                next.entities[index] = entity
            } else {
                next.entities.append(
                    TaskEntityRecord(
                        attempts: [key],
                        primaryAttempt: key,
                        name: name,
                        sourceURI: nil,
                        destinationPath: path,
                        byteCount: grouped[gid]?.reduce(Int64(0)) {
                            $0 + $1.byteCount
                        } ?? 0,
                        contentType: TaskContentType.classify(path: path),
                        transferProtocol: protocolKind,
                        lifecycle: .waiting,
                        addedAt: date,
                        addedAtIsInferred: false
                    )
                )
            }
        }
        persist(next)
    }

    func removeLiveAttempt(
        gid: String,
        profileID: UUID?,
        historyGIDs: Set<String>
    ) {
        let key = TaskAttemptKey(serverProfileID: profileID, gid: gid)
        liveAttemptKeys.remove(key)
        var next = archive
        guard let index = entityIndex(
            for: key,
            in: next,
            acceptingUnknownProfile: true
        ) else {
            return
        }
        var entity = next.entities[index]

        if !historyGIDs.contains(gid) {
            entity.attempts = entity.attempts.filter {
                !($0 == key || ($0.gid == gid && $0.serverProfileID == nil))
            }
        }

        entity.hasHistory = entity.attempts.contains {
            historyGIDs.contains($0.gid)
        }
        if let primary = entity.primaryAttempt,
           !entity.attempts.contains(primary) {
            entity.primaryAttempt = preferredAttempt(
                in: entity,
                historyGIDs: historyGIDs
            )
        }

        if entity.attempts.isEmpty {
            next.entities.remove(at: index)
        } else {
            next.entities[index] = entity
        }
        persist(next)
    }

    func removeHistory(
        gids: Set<String>,
        remainingHistoryGIDs: Set<String>
    ) {
        guard !gids.isEmpty else { return }
        var next = archive
        for index in next.entities.indices {
            guard next.entities[index].attempts.contains(where: {
                gids.contains($0.gid)
            }) else {
                continue
            }

            var entity = next.entities[index]
            entity.attempts = entity.attempts.filter { attempt in
                guard gids.contains(attempt.gid) else { return true }
                return isLiveAttempt(attempt)
            }
            entity.hasHistory = entity.attempts.contains {
                remainingHistoryGIDs.contains($0.gid)
            }
            if let primary = entity.primaryAttempt,
               !entity.attempts.contains(primary) {
                entity.primaryAttempt = preferredAttempt(
                    in: entity,
                    historyGIDs: remainingHistoryGIDs
                )
            }
            next.entities[index] = entity
        }
        next.entities.removeAll { $0.attempts.isEmpty && !$0.hasHistory }
        persist(next)
    }

    private func commit(
        _ mutation: (inout TaskOrganizationArchive) -> Void
    ) -> Bool {
        var next = archive
        mutation(&next)
        guard next != archive else { return true }
        return persist(next)
    }

    @discardableResult
    private func persist(_ next: TaskOrganizationArchive) -> Bool {
        guard next != archive else { return true }
        do {
            try repository.save(next)
            archive = next
            publish()
            return true
        } catch {
            persistenceError = error.localizedDescription
            return false
        }
    }

    private func publish() {
        tags = archive.tags
        smartFolders = archive.smartFolders
        entities = archive.entities
    }

    private func entityIndex(
        for key: TaskAttemptKey,
        in archive: TaskOrganizationArchive,
        acceptingUnknownProfile: Bool
    ) -> Int? {
        if let exact = archive.entities.firstIndex(where: {
            $0.attempts.contains(key)
        }) {
            return exact
        }
        guard acceptingUnknownProfile else { return nil }
        return archive.entities.firstIndex {
            $0.attempts.contains {
                $0.gid == key.gid && $0.serverProfileID == nil
            }
        }
    }

    private func upgradeUnknownAttempt(
        for key: TaskAttemptKey,
        in entity: inout TaskEntityRecord
    ) {
        entity.attempts = entity.attempts.filter {
            !($0.gid == key.gid && $0.serverProfileID == nil)
        }
    }

    private func makeEntity(
        from item: TransferItem,
        key: TaskAttemptKey,
        observedAt date: Date
    ) -> TaskEntityRecord {
        let lifecycle = TaskLifecycle.infer(from: item)
        return TaskEntityRecord(
            attempts: [key],
            primaryAttempt: key,
            name: item.displayName,
            sourceURI: item.sourceURI,
            destinationPath: item.displayPath,
            byteCount: item.totalByteCount,
            contentType: TaskContentType.classify(files: item.files),
            transferProtocol: TaskTransferProtocol.infer(from: item),
            lifecycle: lifecycle,
            addedAt: date,
            addedAtIsInferred: true,
            completedAt: lifecycle.isTerminal ? date : nil,
            detail: item.userFacingError
        )
    }

    private func apply(
        _ item: TransferItem,
        to entity: inout TaskEntityRecord,
        observedAt date: Date
    ) {
        entity.name = item.displayName
        if let sourceURI = item.sourceURI {
            entity.sourceURI = sourceURI
            entity.sourceDomain = TaskDomain.normalizedHost(from: sourceURI)
        }
        if item.displayPath != "—" {
            entity.destinationPath = item.displayPath
        }
        entity.byteCount = max(item.totalByteCount, entity.byteCount)
        let contentType = TaskContentType.classify(files: item.files)
        if contentType != .unknown {
            entity.contentType = contentType
        }
        let protocolKind = TaskTransferProtocol.infer(from: item)
        if protocolKind != .unknown,
           entity.transferProtocol == .unknown
            || (
                protocolKind == .torrent
                    && (entity.transferProtocol == .http
                        || entity.transferProtocol == .ftp)
            ) {
            entity.transferProtocol = protocolKind
        }
        entity.lifecycle = TaskLifecycle.infer(from: item)
        entity.detail = item.userFacingError
        if entity.lifecycle.isTerminal, entity.completedAt == nil {
            entity.completedAt = date
        }
    }

    @discardableResult
    private func mergeHistory(
        _ entry: DownloadHistoryEntry,
        into archive: inout TaskOrganizationArchive,
        preferredProfileID: UUID?,
        fallbackDate: Date
    ) -> Bool {
        let preferredKey = TaskAttemptKey(
            serverProfileID: preferredProfileID,
            gid: entry.gid
        )
        let index = entityIndex(
            for: preferredKey,
            in: archive,
            acceptingUnknownProfile: true
        ) ?? archive.entities.firstIndex {
            $0.attempts.contains { $0.gid == entry.gid }
        }

        if let index {
            var entity = archive.entities[index]
            let previous = entity
            entity.name = entry.name
            if let sourceURI = entry.sourceURI {
                entity.sourceURI = sourceURI
                entity.sourceDomain = TaskDomain.normalizedHost(from: sourceURI)
            }
            if entry.destinationPath != "—" {
                entity.destinationPath = entry.destinationPath
            }
            entity.byteCount = max(entity.byteCount, entry.byteCount)
            let contentType = TaskContentType.classify(path: entry.destinationPath)
            if entity.contentType == .unknown, contentType != .unknown {
                entity.contentType = contentType
            }
            if entity.transferProtocol == .unknown {
                entity.transferProtocol = TaskTransferProtocol.infer(
                    fromURI: entry.sourceURI
                )
            }
            entity.lifecycle = TaskLifecycle.infer(from: entry.outcome)
            entity.completedAt = entry.recordedAt
            entity.detail = entry.detail
            entity.hasHistory = true
            if entity != previous {
                archive.entities[index] = entity
                return true
            }
            return false
        }

        let key = TaskAttemptKey(serverProfileID: nil, gid: entry.gid)
        let protocolKind = TaskTransferProtocol.infer(fromURI: entry.sourceURI)
        archive.entities.append(
            TaskEntityRecord(
                attempts: [key],
                primaryAttempt: key,
                name: entry.name,
                sourceURI: entry.sourceURI,
                destinationPath: entry.destinationPath,
                byteCount: entry.byteCount,
                contentType: TaskContentType.classify(path: entry.destinationPath),
                transferProtocol: protocolKind,
                lifecycle: TaskLifecycle.infer(from: entry.outcome),
                addedAt: entry.recordedAt,
                addedAtIsInferred: true,
                completedAt: entry.recordedAt,
                detail: entry.detail,
                hasHistory: true
            )
        )
        _ = fallbackDate
        return true
    }

    private func isLiveAttempt(_ attempt: TaskAttemptKey) -> Bool {
        if liveAttemptKeys.contains(attempt) {
            return true
        }
        guard attempt.serverProfileID == nil else { return false }
        return liveAttemptKeys.contains { $0.gid == attempt.gid }
    }

    private func preferredAttempt(
        in entity: TaskEntityRecord,
        historyGIDs: Set<String>
    ) -> TaskAttemptKey? {
        entity.attempts.first(where: isLiveAttempt)
            ?? entity.attempts.first {
                historyGIDs.contains($0.gid)
            }
            ?? entity.attempts.first
    }

    private static func displayName(for source: String) -> String {
        if source.lowercased().hasPrefix("magnet:"),
           let components = URLComponents(string: source),
           let name = components.queryItems?.first(where: { $0.name == "dn" })?.value,
           !name.isEmpty {
            return name
        }
        guard let url = URL(string: source) else { return L10n.string("未命名下载") }
        let name = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        return name.isEmpty ? (url.host ?? L10n.string("未命名下载")) : name
    }
}
