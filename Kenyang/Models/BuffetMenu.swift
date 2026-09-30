import Foundation

/// The menu a session starts from.
///
/// Every start path reads `.default`: the start screen, the home-screen widget, Siri and
/// the tier screen. The menu is printed and fixed per venue, so it is data, not something
/// asked for at the table.
struct BuffetMenu: Sendable {
    typealias Item = (name: String, category: MenuCategory, printed: String, tier: Int)

    let venueName: String
    let tierName: String
    /// Rupiah per adult head, before tax and service.
    let pricePerHead: Double
    /// Printed on the menu as "Table 90 minutes".
    let seatingMinutes: Int
    let items: [Item]

    /// Gyu-Kaku Standard Buffet, from the printed menu.
    ///
    /// Left out on purpose: the paid toppings (Negi, Mix Cheese), because a price inside
    /// the meal is a reason to spend, and the single kimchi and namuru plates, which are
    /// the parts of Kimuchi Trio, Assorted Kimuchi and Assorted Namuru listed again.
    static let `default` = BuffetMenu(
        venueName: "Gyu-Kaku",
        tierName: "Standard",
        pricePerHead: 248_800,
        seatingMinutes: 90,
        items: [
            ("Beef Curry Pan", .fried, "APPETIZER & AGEMONO", 0),
            ("Beef Takoyaki", .fried, "APPETIZER & AGEMONO", 0),
            ("Juicy Beef Stew", .soup, "APPETIZER & AGEMONO", 0),
            ("Corn Pop Shake", .fried, "APPETIZER & AGEMONO", 0),
            ("Potato Salad", .vegetable, "APPETIZER & AGEMONO", 0),
            ("Crispy Nori Ten", .fried, "APPETIZER & AGEMONO", 0),
            ("Calamari with Tar Tar Sauce", .fried, "APPETIZER & AGEMONO", 0),
            ("Chicken Karaage", .fried, "APPETIZER & AGEMONO", 0),
            ("French Fries", .fried, "APPETIZER & AGEMONO", 0),
            ("Mini Sausage Stick", .fried, "APPETIZER & AGEMONO", 0),
            ("Kimuchi Trio", .vegetable, "APPETIZER & AGEMONO", 0),
            ("Assorted Kimuchi", .vegetable, "APPETIZER & AGEMONO", 0),
            ("Assorted Namuru", .vegetable, "APPETIZER & AGEMONO", 0),
            ("Gyu-Kaku Cabbage", .vegetable, "APPETIZER & AGEMONO", 0),
            ("Edamame", .vegetable, "APPETIZER & AGEMONO", 0),

            ("Umakara Miso Harami", .meat, "STANDARD MEAT", 0),
            ("Diced Garlic Miso Steak", .meat, "STANDARD MEAT", 0),
            ("Dragon Karubi", .meat, "STANDARD MEAT", 0),
            ("Garlic Miso Diamond Harami", .meat, "STANDARD MEAT", 0),
            ("Diced Garlic Butter Steak", .meat, "STANDARD MEAT", 0),
            ("Juicy Beef Pot", .meat, "STANDARD MEAT", 0),
            ("Suki Shabu", .meat, "STANDARD MEAT", 0),
            ("Spicy Suki Shabu", .meat, "STANDARD MEAT", 0),
            ("Karubi", .meat, "STANDARD MEAT", 0),
            ("Teriyaki Chicken", .meat, "STANDARD MEAT", 0),
            ("Spicy Coriander Sauce Chicken", .meat, "STANDARD MEAT", 0),

            ("Gyu-Kaku Homemade Curry", .soup, "GRILL APPETIZER", 0),
            ("Squid on a Stick", .meat, "GRILL APPETIZER", 0),
            ("Squid with Spicy Coriander Sauce", .meat, "GRILL APPETIZER", 0),
            ("Beef Cheese Sausage", .meat, "GRILL APPETIZER", 0),
            ("Garlic Butter Foil", .vegetable, "GRILL APPETIZER", 0),
            ("Corn Foil", .vegetable, "GRILL APPETIZER", 0),
            ("Assorted Vegetables", .vegetable, "GRILL APPETIZER", 0),

            ("Veggie Wrap", .vegetable, "SALAD", 0),
            ("Wakame Salad", .vegetable, "SALAD", 0),
            ("Mini Caesar Salad", .vegetable, "SALAD", 0),

            ("Seafood Tacos", .raw, "SUSHI", 0),
            ("Aburi Salmon Roll", .raw, "SUSHI", 0),
            ("Unagi Roll", .raw, "SUSHI", 0),

            ("Spicy Seafood Jjampong", .starch, "RICE & NOODLE", 0),
            ("Bibimbab", .starch, "RICE & NOODLE", 0),
            ("Garlic Fried Rice", .starch, "RICE & NOODLE", 0),
            ("Gyu-Kaku Rice", .starch, "RICE & NOODLE", 0),
            ("Steamed Rice", .starch, "RICE & NOODLE", 0),
            ("Gomanegi Ramen", .starch, "RICE & NOODLE", 0),

            ("Miso Soup", .soup, "SOUP", 0),
            ("Wakame Soup", .soup, "SOUP", 0),
            ("Egg Soup", .soup, "SOUP", 0),

            ("Fizzy Popping Yogurt Ice Cream", .dessert, "DESSERT", 0),
            ("Gyu-Kaku Milk Pudding", .dessert, "DESSERT", 0),
            ("Ice Cream on Milk Pudding", .dessert, "DESSERT", 0),
            ("Gyu-Kaku Ice Cream", .dessert, "DESSERT", 0),
            ("Fruits", .dessert, "DESSERT", 0)
        ]
    )
}
