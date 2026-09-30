import Foundation

struct BuffetMenu: Sendable {
    struct Dish: Sendable {
        let name: String
        let category: MenuCategory
        let section: String
        var tier = 0
    }

    let venueName: String
    let tierName: String
    let pricePerHead: Double
    let seatingMinutes: Int
    let dishes: [Dish]

    /// Gyu-Kaku Standard Buffet. Paid toppings are left out, so no price appears during
    /// the meal, and so are the single kimchi and namuru plates the assorted plates repeat.
    static let `default` = BuffetMenu(
        venueName: "Gyu-Kaku",
        tierName: "Standard",
        pricePerHead: 248_800,
        seatingMinutes: 90,
        dishes: [
            Dish(name: "Beef Curry Pan", category: .fried, section: "APPETIZER & AGEMONO"),
            Dish(name: "Beef Takoyaki", category: .fried, section: "APPETIZER & AGEMONO"),
            Dish(name: "Juicy Beef Stew", category: .soup, section: "APPETIZER & AGEMONO"),
            Dish(name: "Corn Pop Shake", category: .fried, section: "APPETIZER & AGEMONO"),
            Dish(name: "Potato Salad", category: .vegetable, section: "APPETIZER & AGEMONO"),
            Dish(name: "Crispy Nori Ten", category: .fried, section: "APPETIZER & AGEMONO"),
            Dish(name: "Calamari with Tar Tar Sauce", category: .fried, section: "APPETIZER & AGEMONO"),
            Dish(name: "Chicken Karaage", category: .fried, section: "APPETIZER & AGEMONO"),
            Dish(name: "French Fries", category: .fried, section: "APPETIZER & AGEMONO"),
            Dish(name: "Mini Sausage Stick", category: .fried, section: "APPETIZER & AGEMONO"),
            Dish(name: "Kimuchi Trio", category: .vegetable, section: "APPETIZER & AGEMONO"),
            Dish(name: "Assorted Kimuchi", category: .vegetable, section: "APPETIZER & AGEMONO"),
            Dish(name: "Assorted Namuru", category: .vegetable, section: "APPETIZER & AGEMONO"),
            Dish(name: "Gyu-Kaku Cabbage", category: .vegetable, section: "APPETIZER & AGEMONO"),
            Dish(name: "Edamame", category: .vegetable, section: "APPETIZER & AGEMONO"),

            Dish(name: "Umakara Miso Harami", category: .meat, section: "STANDARD MEAT"),
            Dish(name: "Diced Garlic Miso Steak", category: .meat, section: "STANDARD MEAT"),
            Dish(name: "Dragon Karubi", category: .meat, section: "STANDARD MEAT"),
            Dish(name: "Garlic Miso Diamond Harami", category: .meat, section: "STANDARD MEAT"),
            Dish(name: "Diced Garlic Butter Steak", category: .meat, section: "STANDARD MEAT"),
            Dish(name: "Juicy Beef Pot", category: .meat, section: "STANDARD MEAT"),
            Dish(name: "Suki Shabu", category: .meat, section: "STANDARD MEAT"),
            Dish(name: "Spicy Suki Shabu", category: .meat, section: "STANDARD MEAT"),
            Dish(name: "Karubi", category: .meat, section: "STANDARD MEAT"),
            Dish(name: "Teriyaki Chicken", category: .meat, section: "STANDARD MEAT"),
            Dish(name: "Spicy Coriander Sauce Chicken", category: .meat, section: "STANDARD MEAT"),

            Dish(name: "Gyu-Kaku Homemade Curry", category: .soup, section: "GRILL APPETIZER"),
            Dish(name: "Squid on a Stick", category: .meat, section: "GRILL APPETIZER"),
            Dish(name: "Squid with Spicy Coriander Sauce", category: .meat, section: "GRILL APPETIZER"),
            Dish(name: "Beef Cheese Sausage", category: .meat, section: "GRILL APPETIZER"),
            Dish(name: "Garlic Butter Foil", category: .vegetable, section: "GRILL APPETIZER"),
            Dish(name: "Corn Foil", category: .vegetable, section: "GRILL APPETIZER"),
            Dish(name: "Assorted Vegetables", category: .vegetable, section: "GRILL APPETIZER"),

            Dish(name: "Veggie Wrap", category: .vegetable, section: "SALAD"),
            Dish(name: "Wakame Salad", category: .vegetable, section: "SALAD"),
            Dish(name: "Mini Caesar Salad", category: .vegetable, section: "SALAD"),

            Dish(name: "Seafood Tacos", category: .raw, section: "SUSHI"),
            Dish(name: "Aburi Salmon Roll", category: .raw, section: "SUSHI"),
            Dish(name: "Unagi Roll", category: .raw, section: "SUSHI"),

            Dish(name: "Spicy Seafood Jjampong", category: .starch, section: "RICE & NOODLE"),
            Dish(name: "Bibimbab", category: .starch, section: "RICE & NOODLE"),
            Dish(name: "Garlic Fried Rice", category: .starch, section: "RICE & NOODLE"),
            Dish(name: "Gyu-Kaku Rice", category: .starch, section: "RICE & NOODLE"),
            Dish(name: "Steamed Rice", category: .starch, section: "RICE & NOODLE"),
            Dish(name: "Gomanegi Ramen", category: .starch, section: "RICE & NOODLE"),

            Dish(name: "Miso Soup", category: .soup, section: "SOUP"),
            Dish(name: "Wakame Soup", category: .soup, section: "SOUP"),
            Dish(name: "Egg Soup", category: .soup, section: "SOUP"),

            Dish(name: "Fizzy Popping Yogurt Ice Cream", category: .dessert, section: "DESSERT"),
            Dish(name: "Gyu-Kaku Milk Pudding", category: .dessert, section: "DESSERT"),
            Dish(name: "Ice Cream on Milk Pudding", category: .dessert, section: "DESSERT"),
            Dish(name: "Gyu-Kaku Ice Cream", category: .dessert, section: "DESSERT"),
            Dish(name: "Fruits", category: .dessert, section: "DESSERT")
        ]
    )
}
