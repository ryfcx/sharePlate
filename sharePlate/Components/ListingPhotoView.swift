//
//  listingphotoview.swift
//  shareplate
//
//  shows listing photo from cache or storage
//

import SwiftUI
import SwiftData

struct ListingPhotoView: View {
    @Environment(LocalDataStore.self) private var store
    @Environment(SessionContext.self) private var session

    let listing: FoodListing
    var height: CGFloat?
    var thumbnailSize: CGFloat?

    @State private var remoteImage: UIImage?
    @State private var failedToLoad = false

    var body: some View {
        Group {
            if let image = resolvedImage {
                styledImage(Image(uiImage: image))
            } else if canViewPhoto, listing.photoURL != nil, !failedToLoad {
                loadingPlaceholder
            } else {
                categoryPlaceholder
            }
        }
        .task(id: loadKey) {
            await loadRemotePhotoIfNeeded()
        }
    }

    private var loadKey: String {
        listing.photoURL ?? listing.remoteID ?? listing.title
    }

    private var resolvedImage: UIImage? {
        guard canViewPhoto else { return nil }
        if let localImage { return localImage }
        if let remoteImage { return remoteImage }
        if let stored = listing.photoURL, let cached = ListingPhotoCache.image(forKey: stored) {
            return cached
        }
        return nil
    }

    private var localImage: UIImage? {
        guard let data = listing.photo else { return nil }
        return UIImage(data: data)
    }

    @ViewBuilder
    private func styledImage(_ image: Image) -> some View {
        if let thumbnailSize {
            image
                .resizable()
                .scaledToFill()
                .frame(width: thumbnailSize, height: thumbnailSize)
                .clipped()
        } else if let height {
            GeometryReader { proxy in
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: height)
                    .clipped()
            }
            .frame(height: height)
            .boxBorder()
        } else {
            image
                .resizable()
                .scaledToFill()
        }
    }

    private var loadingPlaceholder: some View {
        placeholderContainer {
            ProgressView()
                .tint(Theme.Palette.accentOrange)
        }
    }

    private var categoryPlaceholder: some View {
        placeholderContainer {
            Image(systemName: listing.category.symbol)
                .font(.system(size: thumbnailSize == nil ? 44 : 22))
                .foregroundStyle(Theme.Palette.accentOrange)
        }
    }

    @ViewBuilder
    private func placeholderContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if let thumbnailSize {
            Rectangle()
                .fill(Theme.Palette.accentOrange.opacity(0.15))
                .frame(width: thumbnailSize, height: thumbnailSize)
                .boxBorder()
                .overlay { content() }
        } else {
            Rectangle()
                .fill(Theme.Palette.accentOrange.opacity(0.15))
                .frame(maxWidth: .infinity)
                .frame(height: height ?? 160)
                .boxBorder()
                .overlay { content() }
        }
    }

    private func loadRemotePhotoIfNeeded() async {
        guard canViewPhoto else { return }
        guard resolvedImage == nil else { return }
        guard let stored = listing.photoURL, !stored.isEmpty else { return }

        if let cached = ListingPhotoCache.image(forKey: stored) {
            remoteImage = cached
            return
        }

        do {
            let data = try await SupabasePhotoService.download(storedValue: stored)
            guard !Task.isCancelled, session.allowsDataAccess, canViewPhoto, listing.modelContext != nil else { return }
            guard let image = UIImage(data: data) else {
                failedToLoad = true
                return
            }
            ListingPhotoCache.store(image, forKey: stored)
            remoteImage = image
            store.cachePhoto(listing, data: data)
        } catch {
            failedToLoad = true
        }
    }

    private var canViewPhoto: Bool {
        listing.isApprovedForSharing || session.matches(listing.postedByDeviceID)
    }
}
