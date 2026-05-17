import Foundation
import Observation

@Observable
final class MealLogStore {
    static let shared = MealLogStore()
    private(set) var meals: [ScannedMeal] = []

    private let storageKey = "com.healthlens.loggedMeals"
    private init() { load() }

    func add(_ meal: ScannedMeal) {
        meals.insert(meal, at: 0)
        if meals.count > 90 { meals = Array(meals.prefix(90)) }
        persist()
    }

    func delete(at offsets: IndexSet) {
        meals.remove(atOffsets: offsets)
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(meals) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([ScannedMeal].self, from: data)
        else { return }
        meals = saved
    }
}
