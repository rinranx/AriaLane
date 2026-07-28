import SwiftUI

extension TaskTagColor {
    var color: Color {
        switch self {
        case .blue: LaneColor.accent
        case .indigo: Color(nsColor: .systemIndigo)
        case .purple: Color(nsColor: .systemPurple)
        case .mint: LaneColor.mint
        case .green: Color(nsColor: .systemGreen)
        case .orange: LaneColor.amber
        case .red: LaneColor.danger
        case .gray: Color.secondary
        }
    }
}

struct TaskTagChip: View {
    let tag: TaskTag
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 4 : 5) {
            Circle()
                .fill(tag.color.color)
                .frame(width: compact ? 5 : 6, height: compact ? 5 : 6)

            Text(tag.displayName)
                .font(LaneFont.interface(compact ? 9 : 10, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 2 : 4)
        .background(
            tag.color.color.opacity(0.09),
            in: Capsule(style: .continuous)
        )
        .overlay {
            Capsule(style: .continuous)
                .stroke(tag.color.color.opacity(0.18), lineWidth: 0.5)
        }
    }
}

struct TaskTagBadgeRow: View {
    @EnvironmentObject private var organization: TaskOrganizationStore

    let entityID: UUID
    var limit = 2

    var body: some View {
        if let entity = organization.entity(id: entityID) {
            let visibleTags = Array(organization.tags(for: entity).prefix(limit))
            if !visibleTags.isEmpty {
                HStack(spacing: 5) {
                    ForEach(visibleTags) { tag in
                        TaskTagChip(tag: tag, compact: true)
                    }

                    let remaining = entity.tagIDs.count - visibleTags.count
                    if remaining > 0 {
                        Text("+\(remaining)")
                            .font(LaneFont.utility(9, weight: .regular))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}

struct TaskTagMenu: View {
    @EnvironmentObject private var organization: TaskOrganizationStore

    let entityIDs: Set<UUID>
    var title = L10n.string("标签")

    @State private var isCreatingTag = false

    var body: some View {
        Menu {
            tagCommands

            if !organization.tags.isEmpty {
                Divider()
            }

            Button(L10n.string("新建标签…")) {
                isCreatingTag = true
            }
        } label: {
            Label(title, systemImage: "tag")
        }
        .disabled(entityIDs.isEmpty)
        .sheet(isPresented: $isCreatingTag) {
            TagEditorView(tag: nil) { name, color in
                guard let tag = organization.createTag(name: name, color: color) else {
                    return false
                }
                organization.addTag(tag.id, to: entityIDs)
                return true
            }
            .environmentObject(organization)
        }
    }

    @ViewBuilder
    private var tagCommands: some View {
        if organization.tags.isEmpty {
            Text(L10n.string("还没有标签"))
        } else {
            ForEach(organization.tags) { tag in
                Button {
                    organization.toggleTag(tag.id, for: entityIDs)
                } label: {
                    if organization.allEntities(entityIDs, haveTag: tag.id) {
                        Label(tag.displayName, systemImage: "checkmark")
                    } else {
                        Label(tag.displayName, systemImage: "circle.fill")
                    }
                }
            }
        }
    }
}

struct TaskTagCommandMenu: View {
    @EnvironmentObject private var organization: TaskOrganizationStore

    let entityIDs: Set<UUID>

    var body: some View {
        Menu(L10n.string("标签")) {
            if organization.tags.isEmpty {
                Text(L10n.string("请从侧栏新建标签"))
            } else {
                ForEach(organization.tags) { tag in
                    Button {
                        organization.toggleTag(tag.id, for: entityIDs)
                    } label: {
                        if organization.allEntities(entityIDs, haveTag: tag.id) {
                            Label(tag.displayName, systemImage: "checkmark")
                        } else {
                            Text(tag.displayName)
                        }
                    }
                }
            }
        }
        .disabled(entityIDs.isEmpty)
    }
}

struct TaskTagsSection: View {
    @EnvironmentObject private var organization: TaskOrganizationStore

    let entityID: UUID

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L10n.string("标签"), systemImage: "tag")
                    .font(LaneFont.interface(12, weight: .semibold))

                Spacer()

                TaskTagMenu(entityIDs: [entityID], title: L10n.string("编辑"))
                    .menuStyle(.borderlessButton)
                    .fixedSize()
            }

            if let entity = organization.entity(id: entityID) {
                let tags = organization.tags(for: entity)
                if tags.isEmpty {
                    Text(L10n.string("尚未添加标签"))
                        .font(LaneFont.interface(10))
                        .foregroundStyle(.tertiary)
                } else {
                    FlowLayout(spacing: 6) {
                        ForEach(tags) { tag in
                            TaskTagChip(tag: tag)
                        }
                    }
                }
            }
        }
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        layout(
            proposal: proposal,
            subviews: subviews,
            place: nil
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        _ = layout(
            proposal: ProposedViewSize(width: bounds.width, height: proposal.height),
            subviews: subviews,
            place: { subview, point, size in
                subview.place(
                    at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                    proposal: ProposedViewSize(size)
                )
            }
        )
    }

    private func layout(
        proposal: ProposedViewSize,
        subviews: Subviews,
        place: ((LayoutSubview, CGPoint, CGSize) -> Void)?
    ) -> CGSize {
        let availableWidth = proposal.width ?? .infinity
        var cursor = CGPoint.zero
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if cursor.x > 0, cursor.x + size.width > availableWidth {
                cursor.x = 0
                cursor.y += rowHeight + spacing
                rowHeight = 0
            }
            place?(subview, cursor, size)
            cursor.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, max(cursor.x - spacing, 0))
        }

        return CGSize(
            width: availableWidth.isFinite ? availableWidth : usedWidth,
            height: cursor.y + rowHeight
        )
    }
}
