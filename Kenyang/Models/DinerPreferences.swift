import Foundation

enum DinerPreferences {
    static let platesKey = "onboarding.plates"
    static let onboardedKey = "onboarding.completed"
    static let defaultPlates: Double = 3
    static let plateChoices: [Double] = [2, 3, 4, 5, 6]

    static var platesPerMeal: Double {
        let stored = UserDefaults.standard.double(forKey: platesKey)
        return stored > 0 ? stored : defaultPlates
    }

    static var maxSatiety: Double { platesPerMeal * CapacityEngine.platesToSatiety }
}
