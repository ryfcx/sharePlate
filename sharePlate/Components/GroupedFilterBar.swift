//
//  groupedfilterbar.swift
//  shareplate
//

import SwiftUI

struct GroupedFilterBar<Leading: View>: View {
    @Binding var selected: Set<MapFilterOption>
    @ViewBuilder var leading: () -> Leading

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                leading()

                ForEach(MapFilterCategory.allCases) { category in
                    filterDivider
                    categoryGroup(category)
                }
            }
        }
    }

    private var filterDivider: some View {
        Rectangle()
            .fill(Theme.Palette.hairline)
            .frame(width: 1, height: 20)
    }

    private func categoryGroup(_ category: MapFilterCategory) -> some View {
        HStack(spacing: 4) {
            Text(category.displayName)
                .font(AppFont.caption)
                .foregroundStyle(Theme.Palette.mutedText)

            ForEach(category.options) { option in
                FilterChip(
                    title: option.displayName,
                    systemImage: option.systemImage,
                    isSelected: selected.contains(option),
                    tint: option.tint
                ) {
                    toggle(option)
                }
            }
        }
    }

    private func toggle(_ option: MapFilterOption) {
        withoutAnimation {
            if selected.contains(option) {
                selected.remove(option)
            } else {
                selected.insert(option)
            }
        }
    }
}

extension GroupedFilterBar where Leading == EmptyView {
    init(selected: Binding<Set<MapFilterOption>>) {
        self._selected = selected
        self.leading = { EmptyView() }
    }
}
