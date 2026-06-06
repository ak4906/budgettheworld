//
//  Categorizer.swift
//  BudgetTheWorld
//
//  On-device keyword categorization. Guesses a top-level category from a transaction's
//  description so manual entry (and later Plaid feeds) land in the right bucket without any
//  cloud processing. Order matters: earlier rules win.
//

import Foundation

enum Categorizer {
    private static let rules: [(keywords: [String], category: SpendCategory)] = [
        // Income first so a payroll descriptor isn't mistaken for a same-named merchant.
        (["payroll", "direct deposit", "paycheck"], .income),
        (["uber eats", "doordash", "grubhub", "starbucks", "dunkin", "coffee", "boba", "cafe", "tea",
          "mcdonald", "chipotle", "restaurant", "pizza", "grill", "kitchen", "sushi", "taco", "deli", "bakery", "sweetgreen"], .food),
        (["trader joe", "whole foods", "safeway", "kroger", "aldi", "grocery", "supermarket", "costco", "wegmans", "h mart", "westside market", "key food"], .groceries),
        (["chevron", "shell", "exxon", "bp ", "gas", "mta", "metro-north", "metro", "subway", "uber", "lyft", "transit", "bart", "parking", "toll", "amtrak", "train"], .transportation),
        (["rent", "landlord", "property mgmt", "apartment"], .rent),
        (["wifi", "internet", "comcast", "xfinity", "verizon", "at&t", "t-mobile", "electric", "utility", "con ed", "water bill", "phone bill"], .utilities),
        (["netflix", "spotify", "hulu", "disney+", "crunchyroll", "apple music", "youtube premium", "icloud", "subscription", "patreon", "prime video"], .subscriptions),
        (["uniqlo", "h&m", "zara", "nike", "adidas", "shoe", "clothing", "apparel", "lululemon"], .clothing),
        (["walgreens", "duane reade", "cvs pharmacy", "pharmacy", "doctor", "dental", "clinic", "hospital", "copay"], .healthcare),
        (["toothpaste", "shampoo", "haircut", "barber", "salon", "skincare", "cosmetics"], .personalCare),
        (["insurance", "geico", "state farm", "lemonade"], .insurance),
        (["delta", "united airlines", "american airlines", "jetblue", "airbnb", "hotel", "flight", "expedia"], .travel),
        (["apple store", "best buy", "software", "app store", "github", "openai", "adobe"], .tech),
        (["ikea", "wayfair", "home depot", "furniture", "mattress", "bed frame", "container store"], .furniture),
        (["detergent", "cleaning", "paper towel", "trash bag", "household"], .household),
        (["gift", "present"], .gifts),
        (["tuition", "textbook", "course", "udemy", "coursera", "exam fee"], .education),
        (["bank fee", "atm fee", "late fee", "overdraft", "service charge"], .fees),
        (["petco", "petsmart", "chewy", "vet", "pet food"], .pets),
        (["cinema", "movie", "steam", "playstation", "xbox", "concert", " bar ", "ticket", "game"], .fun),
        (["amazon", "target", "walmart"], .other),
    ]

    static func category(for description: String) -> SpendCategory {
        let lower = " " + description.lowercased() + " "
        for rule in rules where rule.keywords.contains(where: { lower.contains($0) }) {
            return rule.category
        }
        return .other
    }
}
