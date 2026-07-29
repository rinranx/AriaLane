import AppKit
import SwiftUI

struct WebLinkExtractionView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var pageInput = ""
    @State private var scope = WebLinkExtractionScope.downloads
    @State private var rendersJavaScript = false
    @State private var links: [ExtractedWebLink] = []
    @State private var selectedURLs = Set<String>()
    @State private var failures: [WebLinkExtractionFailure] = []
    @State private var isExtracting = false
    @State private var hasExtracted = false
    @State private var extractionTask: Task<Void, Never>?

    let onAdd: ([String]) -> Void

    private var parsedPages: ParsedWebPageInput {
        WebPageInputParser.parse(pageInput)
    }

    private var selectedLinks: [String] {
        links.compactMap { selectedURLs.contains($0.url) ? $0.url : nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 22)
                .padding(.vertical, 18)

            Divider()
                .opacity(0.62)

            VStack(alignment: .leading, spacing: 14) {
                pageEditor
                extractionOptions
                resultContent
            }
            .padding(20)

            Divider()
                .opacity(0.62)

            footer
                .padding(.horizontal, 20)
                .frame(height: 62)
                .background(LaneColor.surface)
        }
        .frame(width: 720, height: 620)
        .background(LaneColor.canvas)
        .interactiveDismissDisabled(isExtracting)
        .onDisappear {
            extractionTask?.cancel()
        }
        .onChange(of: pageInput) { _, _ in
            clearResultsAfterInputChange()
        }
        .onChange(of: scope) { _, _ in
            clearResultsAfterInputChange()
        }
        .onChange(of: rendersJavaScript) { _, _ in
            clearResultsAfterInputChange()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(LaneColor.accent)
                .frame(width: 38, height: 38)
                .background(
                    LaneColor.accent.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 10)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.string("从网页提取链接"))
                    .font(LaneFont.display(20))
                Text(L10n.string("批量读取网页，选择要加入 AriaLane 的下载地址"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
            .disabled(isExtracting)
            .help(L10n.string("关闭"))
        }
    }

    private var pageEditor: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(L10n.string("网页地址"))
                    .font(.system(size: 11, weight: .semibold))

                Spacer()

                Button {
                    pastePageAddresses()
                } label: {
                    Label(
                        L10n.string("粘贴"),
                        systemImage: "doc.on.clipboard"
                    )
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(LaneColor.accent)
                .disabled(isExtracting)
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $pageInput)
                    .font(LaneFont.utility(12, weight: .regular))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .disabled(isExtracting)

                if pageInput.isEmpty {
                    Text(
                        "https://example.com/downloads\n"
                            + "https://mirror.example.com/releases"
                    )
                    .font(LaneFont.utility(12, weight: .regular))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
                }
            }
            .frame(height: 78)
            .background(
                LaneColor.fill1,
                in: RoundedRectangle(cornerRadius: 11)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 11)
                    .stroke(
                        parsedPages.rejectedCount > 0
                            || parsedPages.omittedCount > 0
                            ? LaneColor.amber.opacity(0.65)
                            : Color.clear,
                        lineWidth: 1
                    )
            }

            Text(pageInputSummary)
                .font(.system(size: 10))
                .foregroundStyle(
                    parsedPages.rejectedCount > 0
                        || parsedPages.omittedCount > 0
                        ? LaneColor.amber
                        : .secondary
                )
        }
    }

    private var extractionOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Picker(L10n.string("提取范围"), selection: $scope) {
                    ForEach(WebLinkExtractionScope.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 235)
                .disabled(isExtracting)

                Toggle(
                    L10n.string("渲染 JavaScript"),
                    isOn: $rendersJavaScript
                )
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.system(size: 11, weight: .medium))
                .disabled(isExtracting)
                .help(
                    L10n.string("加载网页脚本后再读取链接，适合动态网页，但速度更慢")
                )

                Spacer()

                Button {
                    if isExtracting {
                        cancelExtraction()
                    } else {
                        startExtraction()
                    }
                } label: {
                    if isExtracting {
                        Label(L10n.string("停止"), systemImage: "stop.fill")
                    } else {
                        Label(
                            L10n.string("开始提取"),
                            systemImage: "sparkle.magnifyingglass"
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(parsedPages.urls.isEmpty && !isExtracting)
            }

            Text(scope.detail)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var resultContent: some View {
        if isExtracting {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.regular)
                Text(
                    rendersJavaScript
                        ? L10n.string("正在加载并分析 \(parsedPages.urls.count) 个网页…")
                        : L10n.string("正在读取并分析 \(parsedPages.urls.count) 个网页…")
                )
                .font(.system(size: 12, weight: .medium))
                Text(
                    rendersJavaScript
                        ? L10n.string("动态网页会逐页处理，请稍候")
                        : L10n.string("最多同时读取 4 个网页")
                )
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LaneColor.fill1,
                in: RoundedRectangle(cornerRadius: 13)
            )
        } else if hasExtracted, links.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "globe")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.secondary)
                Text(L10n.string("没有找到符合条件的链接"))
                    .font(.system(size: 13, weight: .semibold))
                Text(emptyResultDetail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                failureSummary
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LaneColor.fill1,
                in: RoundedRectangle(cornerRadius: 13)
            )
        } else if hasExtracted {
            resultList
        } else {
            VStack(spacing: 10) {
                Image(systemName: "rectangle.and.text.magnifyingglass")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(LaneColor.accent)
                Text(L10n.string("输入网页地址后开始提取"))
                    .font(.system(size: 13, weight: .semibold))
                Text(
                    L10n.string("每行一个网页地址，一次最多处理 20 个网页")
                )
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LaneColor.accent.opacity(0.035),
                in: RoundedRectangle(cornerRadius: 13)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 13)
                    .stroke(LaneColor.line, lineWidth: 1)
            }
        }
    }

    private var resultList: some View {
        VStack(spacing: 0) {
            HStack {
                Text(L10n.string("找到 \(links.count) 个链接"))
                    .font(.system(size: 11, weight: .semibold))

                if !failures.isEmpty {
                    failureSummary
                        .padding(.leading, 6)
                }

                Spacer()

                Button(L10n.string("全选")) {
                    selectedURLs = Set(links.map(\.url))
                }
                .buttonStyle(.plain)
                .foregroundStyle(LaneColor.accent)
                .disabled(selectedURLs.count == links.count)

                Button(L10n.string("全不选")) {
                    selectedURLs.removeAll()
                }
                .buttonStyle(.plain)
                .foregroundStyle(LaneColor.accent)
                .disabled(selectedURLs.isEmpty)
            }
            .font(.system(size: 10))
            .padding(.horizontal, 12)
            .frame(height: 36)

            Divider()
                .opacity(0.55)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(links) { link in
                        resultRow(for: link)

                        if link.id != links.last?.id {
                            Divider()
                                .padding(.leading, 42)
                                .opacity(0.45)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LaneColor.fill1,
            in: RoundedRectangle(cornerRadius: 13)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(LaneColor.line, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 13))
    }

    private func resultRow(for link: ExtractedWebLink) -> some View {
        let isSelected = selectedURLs.contains(link.url)

        return Button {
            if isSelected {
                selectedURLs.remove(link.url)
            } else {
                selectedURLs.insert(link.url)
            }
        } label: {
            HStack(spacing: 11) {
                Image(
                    systemName: isSelected
                        ? "checkmark.square.fill"
                        : "square"
                )
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(
                    isSelected ? LaneColor.accent : .secondary
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(link.displayTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(link.locationDescription)
                        .font(LaneFont.utility(9, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 10)

                Text(link.sourceHost)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(maxWidth: 130, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 47)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(link.displayTitle)
        .accessibilityValue(
            isSelected ? L10n.string("已勾选") : L10n.string("未勾选")
        )
    }

    @ViewBuilder
    private var failureSummary: some View {
        if !failures.isEmpty {
            Label(
                L10n.string("\(failures.count) 个网页读取失败"),
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(LaneColor.amber)
            .help(
                failures.map {
                    "\($0.pageURL)\n\($0.message)"
                }.joined(separator: "\n\n")
            )
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Label(
                rendersJavaScript
                    ? L10n.string("动态模式会在隔离的临时网页会话中执行脚本")
                    : L10n.string("只读取网页 HTML，不会执行网页脚本"),
                systemImage: "lock.shield"
            )
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
            .lineLimit(1)

            Spacer()

            Button(L10n.string("取消")) {
                cancelExtraction()
                dismiss()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .keyboardShortcut(.cancelAction)

            Button(addButtonTitle) {
                let urls = selectedLinks
                guard !urls.isEmpty else { return }
                onAdd(urls)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(selectedURLs.isEmpty || isExtracting)
        }
    }

    private var pageInputSummary: String {
        if pageInput.trimmed.isEmpty {
            return L10n.string("每行一个 HTTP 或 HTTPS 网页地址")
        }
        if parsedPages.urls.isEmpty {
            return L10n.string("没有识别到有效的网页地址")
        }
        if parsedPages.rejectedCount > 0, parsedPages.omittedCount > 0 {
            return L10n.string(
                "将处理 \(parsedPages.urls.count) 个网页，忽略 \(parsedPages.rejectedCount) 行，超出上限 \(parsedPages.omittedCount) 个"
            )
        }
        if parsedPages.rejectedCount > 0 {
            return L10n.string(
                "将处理 \(parsedPages.urls.count) 个网页，忽略 \(parsedPages.rejectedCount) 行"
            )
        }
        if parsedPages.omittedCount > 0 {
            return L10n.string(
                "将处理前 \(parsedPages.urls.count) 个网页，超出上限 \(parsedPages.omittedCount) 个"
            )
        }
        return L10n.string("将处理 \(parsedPages.urls.count) 个网页")
    }

    private var emptyResultDetail: String {
        if !failures.isEmpty, failures.count == parsedPages.urls.count {
            return L10n.string("所有网页都读取失败，请检查地址、网络或访问权限")
        }
        if scope == .downloads {
            return L10n.string("可以切换到“全部链接”，或为动态网页启用 JavaScript")
        }
        return L10n.string("网页中没有 AriaLane 支持的协议链接")
    }

    private var addButtonTitle: String {
        selectedURLs.count > 1
            ? L10n.string("添加 \(selectedURLs.count) 个链接")
            : L10n.string("添加链接")
    }

    private func pastePageAddresses() {
        guard let value = NSPasteboard.general.string(forType: .string) else {
            return
        }
        pageInput = value
    }

    private func startExtraction() {
        let pages = parsedPages.urls
        guard !pages.isEmpty else { return }

        extractionTask?.cancel()
        links = []
        selectedURLs = []
        failures = []
        hasExtracted = false
        isExtracting = true

        let selectedScope = scope
        let shouldRenderJavaScript = rendersJavaScript
        extractionTask = Task { @MainActor in
            let batch: WebLinkExtractionBatch
            if shouldRenderJavaScript {
                batch = await RenderedWebPageLinkExtractor.extract(
                    from: pages,
                    scope: selectedScope
                )
            } else {
                batch = await WebPageLinkExtractor.extract(
                    from: pages,
                    scope: selectedScope
                )
            }

            guard !Task.isCancelled else {
                isExtracting = false
                return
            }
            links = batch.links
            selectedURLs = Set(batch.links.map(\.url))
            failures = batch.failures
            hasExtracted = true
            isExtracting = false
            extractionTask = nil
        }
    }

    private func cancelExtraction() {
        extractionTask?.cancel()
        extractionTask = nil
        isExtracting = false
    }

    private func clearResultsAfterInputChange() {
        guard !isExtracting, hasExtracted else { return }
        links = []
        selectedURLs = []
        failures = []
        hasExtracted = false
    }
}
