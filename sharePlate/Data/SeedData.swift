//
//  SeedData.swift
//  sharePlate
//
//  Curated Chicagoland food resources used to seed the local store on first
//  launch. Coordinates and hours are approximate placeholders intended for a
//  prototype and can be corrected later.
//

import Foundation

enum SeedData {
    static func resources() -> [FoodResource] {
        [
            FoodResource(
                name: "Greater Chicago Food Depository",
                address: "4100 W Ann Lurie Pl, Chicago, IL 60632",
                latitude: 41.8123, longitude: -87.7237,
                hours: "Mon–Fri 8:00 AM – 4:00 PM",
                phone: "773-247-3663",
                summary: "Chicago's food bank, distributing to a network of pantries and programs across Cook County.",
                type: .pantry
            ),
            FoodResource(
                name: "Lakeview Pantry",
                address: "3945 N Sheridan Rd, Chicago, IL 60613",
                latitude: 41.9536, longitude: -87.6545,
                hours: "Mon–Sat 9:00 AM – 1:00 PM",
                phone: "773-525-1777",
                summary: "Long-running North Side pantry offering groceries and social services.",
                type: .pantry
            ),
            FoodResource(
                name: "Nourishing Hope (Lakeview)",
                address: "3945 N Sheridan Rd, Chicago, IL 60613",
                latitude: 41.9534, longitude: -87.6540,
                hours: "Mon–Fri 10:00 AM – 2:00 PM",
                phone: "773-549-5111",
                summary: "Groceries, meals, and mental wellness support for Chicago neighbors.",
                type: .mealProgram
            ),
            FoodResource(
                name: "Common Pantry",
                address: "3744 N Damen Ave, Chicago, IL 60618",
                latitude: 41.9494, longitude: -87.6790,
                hours: "Wed 4:00 PM – 7:00 PM, Sat 9:00 AM – 12:00 PM",
                phone: "773-327-0553",
                summary: "Chicago's oldest continuously operating food pantry.",
                type: .pantry
            ),
            FoodResource(
                name: "The Love Fridge – Logan Square",
                address: "2257 N California Ave, Chicago, IL 60647",
                latitude: 41.9226, longitude: -87.6975,
                hours: "Open 24 hours",
                phone: nil,
                summary: "Community refrigerator stocked by neighbors. Take what you need, leave what you can.",
                type: .communityFridge
            ),
            FoodResource(
                name: "The Love Fridge – Pilsen",
                address: "1850 S Throop St, Chicago, IL 60608",
                latitude: 41.8567, longitude: -87.6593,
                hours: "Open 24 hours",
                phone: nil,
                summary: "Mutual-aid community fridge open to all, any time.",
                type: .communityFridge
            ),
            FoodResource(
                name: "The Love Fridge – Rogers Park",
                address: "1447 W Morse Ave, Chicago, IL 60626",
                latitude: 42.0080, longitude: -87.6679,
                hours: "Open 24 hours",
                phone: nil,
                summary: "Neighborhood fridge and pantry box, free and always accessible.",
                type: .communityFridge
            ),
            FoodResource(
                name: "Franciscan Outreach – Marquard Center",
                address: "2715 W Harrison St, Chicago, IL 60612",
                latitude: 41.8730, longitude: -87.6940,
                hours: "Daily 6:00 AM – 7:00 PM",
                phone: "312-738-2230",
                summary: "Daily hot meals and shelter services on the West Side.",
                type: .mealProgram
            ),
            FoodResource(
                name: "A Just Harvest",
                address: "7649 N Paulina St, Chicago, IL 60626",
                latitude: 42.0186, longitude: -87.6739,
                hours: "Daily 4:00 PM – 6:00 PM",
                phone: "773-262-2297",
                summary: "Community kitchen serving free hot meals 365 days a year.",
                type: .mealProgram
            ),
            FoodResource(
                name: "Bottomless Closet / Sarah's Circle Meals",
                address: "4750 N Sheridan Rd, Chicago, IL 60640",
                latitude: 41.9680, longitude: -87.6555,
                hours: "Mon–Fri 8:00 AM – 4:00 PM",
                phone: "773-728-1991",
                summary: "Meals and support services for women experiencing homelessness.",
                type: .mealProgram
            ),
            FoodResource(
                name: "New Life Centers – Little Village",
                address: "2657 S Lawndale Ave, Chicago, IL 60623",
                latitude: 41.8438, longitude: -87.7180,
                hours: "Tue & Thu 10:00 AM – 1:00 PM",
                phone: "773-948-7330",
                summary: "Food distribution and youth programs in Little Village.",
                type: .pantry
            ),
            FoodResource(
                name: "Cornerstone Community Outreach",
                address: "4628 N Clifton Ave, Chicago, IL 60640",
                latitude: 41.9658, longitude: -87.6570,
                hours: "Daily 7:00 AM – 6:00 PM",
                phone: "773-271-8163",
                summary: "Meals and shelter in Uptown for families and individuals.",
                type: .mealProgram
            ),
            FoodResource(
                name: "Greater Chicago Food Depository Mobile Pantry – Englewood",
                address: "6201 S Halsted St, Chicago, IL 60621",
                latitude: 41.7818, longitude: -87.6433,
                hours: "2nd Wed monthly 10:00 AM – 12:00 PM",
                phone: "773-247-3663",
                summary: "Rotating mobile produce distribution serving Englewood.",
                type: .mobileDistribution
            ),
            FoodResource(
                name: "Top Box Foods Mobile Distribution",
                address: "7222 S Exchange Ave, Chicago, IL 60649",
                latitude: 41.7639, longitude: -87.5519,
                hours: "1st Sat monthly 9:00 AM – 11:00 AM",
                phone: "312-281-9100",
                summary: "Affordable and free food boxes distributed across the South Side.",
                type: .mobileDistribution
            ),
            FoodResource(
                name: "The Love Fridge – Bronzeville",
                address: "4659 S King Dr, Chicago, IL 60653",
                latitude: 41.8095, longitude: -87.6166,
                hours: "Open 24 hours",
                phone: nil,
                summary: "Free community fridge stocked by neighbors in Bronzeville.",
                type: .communityFridge
            ),
            FoodResource(
                name: "Above and Beyond Family Recovery Pantry",
                address: "2942 W Lake St, Chicago, IL 60612",
                latitude: 41.8853, longitude: -87.6987,
                hours: "Wed 1:00 PM – 3:00 PM",
                phone: "773-940-2960",
                summary: "Pantry serving the East Garfield Park neighborhood.",
                type: .pantry
            ),
            FoodResource(
                name: "Beth Emet Soup Kitchen (Evanston)",
                address: "1224 Dempster St, Evanston, IL 60202",
                latitude: 42.0411, longitude: -87.6912,
                hours: "Sun 4:30 PM – 6:00 PM",
                phone: "847-869-4230",
                summary: "Free community dinner served weekly in Evanston.",
                type: .mealProgram
            ),
            FoodResource(
                name: "Oak Park River Forest Food Pantry",
                address: "848 Lake St, Oak Park, IL 60301",
                latitude: 41.8880, longitude: -87.7960,
                hours: "Tue & Thu 9:00 AM – 12:00 PM, Sat 9:00 AM – 11:00 AM",
                phone: "708-386-1324",
                summary: "Choice pantry serving Oak Park and surrounding suburbs.",
                type: .pantry
            ),
            FoodResource(
                name: "Northern Illinois Food Bank – West Suburban Center",
                address: "273 Dearborn Ct, Geneva, IL 60134",
                latitude: 41.8869, longitude: -88.3320,
                hours: "Mon–Fri 8:00 AM – 4:30 PM",
                phone: "630-443-6910",
                summary: "Regional food bank supplying pantries across the western suburbs.",
                type: .pantry
            ),
            FoodResource(
                name: "Cicero Community Mobile Market",
                address: "2250 S 49th Ave, Cicero, IL 60804",
                latitude: 41.8480, longitude: -87.7560,
                hours: "3rd Fri monthly 1:00 PM – 3:00 PM",
                phone: nil,
                summary: "Mobile fresh-produce market serving Cicero residents.",
                type: .mobileDistribution
            )
        ]
    }
}
