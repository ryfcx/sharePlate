//
//  ListingPhotoCache.swift
//  sharePlate
//
//  In-memory cache so listing photos decode once and load instantly in lists.
//

import UIKit

enum ListingPhotoCache {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 120
        cache.totalCostLimit = 80 * 1024 * 1024
        return cache
    }()

    static func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    static func store(_ image: UIImage, forKey key: String) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale)
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }
}
