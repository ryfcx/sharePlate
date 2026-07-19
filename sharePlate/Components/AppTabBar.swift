//
//  AppTabBar.swift
//  sharePlate
//
//  Custom bottom navigation — flat, fixed to the screen edge, no system tab bar.
//

import SwiftUI

enum AppTab: CaseIterable, Identifiable {
    case map
    case resources
    case freeFood
    case activity

    var id: Self { self }

    var title: String {
        switch self {
        case .map: return "Map"
        case .resources: return "Resources"
        case .freeFood: return "Food"
        case .activity: return "Activity"
        }
    }

    var symbol: String {
        switch self {
        case .map: return "map"
        case .resources: return "list.bullet"
        case .freeFood: return "takeoutbag.and.cup.and.straw"
        case .activity: return "person.crop.circle"
        }
    }
}

struct AppTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.Palette.hairline)
                .frame(height: 1)

            HStack(spacing: 0) {
                ForEach(AppTab.allCases) { tab in
                    tabButton(tab)
                }
            }
            .frame(height: 54)
            .background(Theme.Palette.cardBackground)
        }
        .background(Theme.Palette.cardBackground.ignoresSafeArea(edges: .bottom))
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selection == tab

        return Button {
            withoutAnimation { selection = tab }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 19, weight: isSelected ? .semibold : .regular))
                    .symbolVariant(isSelected ? .fill : .none)
                Text(tab.title)
                    .font(AppFont.tabLabel)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .foregroundStyle(isSelected ? Theme.Palette.primaryGreen : Theme.Palette.mutedText)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
