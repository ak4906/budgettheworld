//
//  TxnDetailCatalog.swift
//  BudgetTheWorld
//
//  Suggestion lists for the optional transaction detail fields (subcategory + merchant).
//  These are only shortcuts — the fields are free text, so you can be as generic or as
//  precise as you like, and type anything that isn't listed.
//

import Foundation

enum TxnDetailCatalog {
    /// Suggested subcategories for a top-level category.
    static func subcategories(for category: SpendCategory) -> [String] {
        switch category {
        case .food:
            return ["Restaurant", "Fast food", "Delivery", "Coffee/Tea", "Boba", "Snacks", "Alcohol", "Soda", "Smoothie", "Deli", "Tip"]
        case .groceries:
            return ["Produce", "Dairy", "Meat", "Pantry", "Frozen", "Snacks", "Drinks", "Bakery", "Tax"]
        case .transportation:
            return ["Subway", "Bus", "Train", "Amtrak", "Metro-North", "Rideshare", "Uber", "Lyft", "Tolls", "Gas", "Parking"]
        case .utilities:
            return ["Electricity", "Water", "Gas", "Internet", "Phone", "Trash"]
        case .rent:
            return ["Rent", "Utilities", "Broker fee", "Deposit"]
        case .fun:
            return ["Movies", "Concerts", "Bars", "Games", "Events", "Hobbies"]
        case .subscriptions:
            return ["Netflix", "Spotify", "Apple Music", "Crunchyroll", "Disney+", "Hulu", "YouTube", "iCloud", "Cloud storage", "News", "Gym"]
        case .tech:
            return ["Software", "Devices", "Accessories", "Apps", "Repairs"]
        case .clothing:
            return ["Shirts", "Pants", "Underwear", "Socks", "Shoes", "Outerwear", "Accessories"]
        case .household:
            return ["Toiletries", "Cleaning supplies", "Kitchen", "Laundry", "Paper goods", "Decor"]
        case .personalCare:
            return ["Toothpaste", "Haircut", "Skincare", "Shampoo", "Grooming", "Cosmetics"]
        case .healthcare:
            return ["Doctor", "Pharmacy", "Dental", "Vision", "Therapy", "Copay"]
        case .insurance:
            return ["Renter's", "Health", "Dental", "Vision", "Auto", "Life"]
        case .travel:
            return ["Flights", "Hotel", "Airbnb", "Rental car", "Baggage", "Activities"]
        case .gifts:
            return ["Birthday", "Holiday", "Wedding", "Charity"]
        case .education:
            return ["Tuition", "Books", "Courses", "Exam fees", "Supplies"]
        case .fees:
            return ["Bank fee", "ATM", "Late fee", "Interest", "Service charge"]
        case .pets:
            return ["Food", "Vet", "Toys", "Grooming", "Supplies"]
        case .furniture:
            return ["Bed", "Desk", "Chair", "Storage", "Lighting", "Decor"]
        case .savings, .income, .other:
            return []
        }
    }

    /// Common stores/locations to suggest; the UI merges these with the user's own history.
    static let defaultMerchants: [String] = [
        "Target", "Walmart", "Amazon", "Costco",
        "Trader Joe's", "Whole Foods", "Westside Market", "H Mart", "Key Food",
        "CVS", "Duane Reade", "Walgreens",
        "Starbucks", "Dunkin", "McDonald's", "Chipotle", "Sweetgreen",
        "Uber", "Lyft", "MTA", "Amtrak", "Metro-North",
        "Netflix", "Spotify", "Apple", "Steam"
    ]
}
