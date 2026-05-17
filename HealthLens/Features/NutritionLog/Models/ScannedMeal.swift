import Foundation
import HealthKit

struct NutritionPayload: Codable, Equatable {
    var calories: Double
    var protein: Double
    var carbohydrates: Double
    var fat: Double
    var fiber: Double
    var sugar: Double
    var saturatedFat: Double
    var monounsaturatedFat: Double  // grams → dietaryFatMonounsaturated
    var polyunsaturatedFat: Double  // grams → dietaryFatPolyunsaturated
    var sodium: Double
    var cholesterol: Double
    var potassium: Double
    var calcium: Double
    var iron: Double
    var zinc: Double                // mg → dietaryZinc
    var magnesium: Double           // mg → dietaryMagnesium
    var vitaminA: Double            // mcg → dietaryVitaminA
    var vitaminC: Double
    var vitaminD: Double            // mcg → dietaryVitaminD
    var vitaminB6: Double           // mg → dietaryVitaminB6
    var vitaminB12: Double          // mcg → dietaryVitaminB12
    var folate: Double              // mcg → dietaryFolate
    var water: Double

    init(
        calories: Double = 0,
        protein: Double = 0,
        carbohydrates: Double = 0,
        fat: Double = 0,
        fiber: Double = 0,
        sugar: Double = 0,
        saturatedFat: Double = 0,
        monounsaturatedFat: Double = 0,
        polyunsaturatedFat: Double = 0,
        sodium: Double = 0,
        cholesterol: Double = 0,
        potassium: Double = 0,
        calcium: Double = 0,
        iron: Double = 0,
        zinc: Double = 0,
        magnesium: Double = 0,
        vitaminA: Double = 0,
        vitaminC: Double = 0,
        vitaminD: Double = 0,
        vitaminB6: Double = 0,
        vitaminB12: Double = 0,
        folate: Double = 0,
        water: Double = 0
    ) {
        self.calories = calories
        self.protein = protein
        self.carbohydrates = carbohydrates
        self.fat = fat
        self.fiber = fiber
        self.sugar = sugar
        self.saturatedFat = saturatedFat
        self.monounsaturatedFat = monounsaturatedFat
        self.polyunsaturatedFat = polyunsaturatedFat
        self.sodium = sodium
        self.cholesterol = cholesterol
        self.potassium = potassium
        self.calcium = calcium
        self.iron = iron
        self.zinc = zinc
        self.magnesium = magnesium
        self.vitaminA = vitaminA
        self.vitaminC = vitaminC
        self.vitaminD = vitaminD
        self.vitaminB6 = vitaminB6
        self.vitaminB12 = vitaminB12
        self.folate = folate
        self.water = water
    }
}

struct ScannedMeal: Identifiable, Codable, Equatable {
    var id: UUID
    var foodName: String
    var description: String
    var servingSize: String
    var confidence: String  // "high", "medium", "low"
    var nutrition: NutritionPayload
    var scannedAt: Date
    var imageData: Data?
    var loggedToHealthKit: Bool

    init(
        id: UUID = UUID(),
        foodName: String,
        description: String = "",
        servingSize: String = "",
        confidence: String = "medium",
        nutrition: NutritionPayload,
        scannedAt: Date = Date(),
        imageData: Data? = nil,
        loggedToHealthKit: Bool = false
    ) {
        self.id = id
        self.foodName = foodName
        self.description = description
        self.servingSize = servingSize
        self.confidence = confidence
        self.nutrition = nutrition
        self.scannedAt = scannedAt
        self.imageData = imageData
        self.loggedToHealthKit = loggedToHealthKit
    }

    // MARK: - HealthKit conversion

    func toHealthKitSamples(at date: Date) -> [HKQuantitySample] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        var samples: [HKQuantitySample] = []
        let metadata: [String: Any] = [
            HKMetadataKeyFoodType: foodName,
            "ScannedMealID": id.uuidString
        ]

        func make(_ identifier: HKQuantityTypeIdentifier, value: Double, unit: HKUnit) -> HKQuantitySample? {
            guard value > 0 else { return nil }
            let type = HKQuantityType(identifier)
            let quantity = HKQuantity(unit: unit, doubleValue: value)
            return HKQuantitySample(type: type, quantity: quantity, start: date, end: date, metadata: metadata)
        }

        let n = nutrition
        let candidates: [HKQuantitySample?] = [
            make(.dietaryEnergyConsumed,        value: n.calories,          unit: .kilocalorie()),
            make(.dietaryProtein,               value: n.protein,            unit: .gram()),
            make(.dietaryCarbohydrates,         value: n.carbohydrates,      unit: .gram()),
            make(.dietaryFatTotal,              value: n.fat,                unit: .gram()),
            make(.dietaryFiber,                 value: n.fiber,              unit: .gram()),
            make(.dietarySugar,                 value: n.sugar,              unit: .gram()),
            make(.dietaryFatSaturated,          value: n.saturatedFat,       unit: .gram()),
            make(.dietaryFatMonounsaturated,    value: n.monounsaturatedFat, unit: .gram()),
            make(.dietaryFatPolyunsaturated,    value: n.polyunsaturatedFat, unit: .gram()),
            make(.dietarySodium,                value: n.sodium,             unit: .gramUnit(with: .milli)),
            make(.dietaryCholesterol,           value: n.cholesterol,        unit: .gramUnit(with: .milli)),
            make(.dietaryPotassium,             value: n.potassium,          unit: .gramUnit(with: .milli)),
            make(.dietaryCalcium,               value: n.calcium,            unit: .gramUnit(with: .milli)),
            make(.dietaryIron,                  value: n.iron,               unit: .gramUnit(with: .milli)),
            make(.dietaryZinc,                  value: n.zinc,               unit: .gramUnit(with: .milli)),
            make(.dietaryMagnesium,             value: n.magnesium,          unit: .gramUnit(with: .milli)),
            make(.dietaryVitaminA,              value: n.vitaminA,           unit: .gramUnit(with: .micro)),
            make(.dietaryVitaminC,              value: n.vitaminC,           unit: .gramUnit(with: .milli)),
            make(.dietaryVitaminD,              value: n.vitaminD,           unit: .gramUnit(with: .micro)),
            make(.dietaryVitaminB6,             value: n.vitaminB6,          unit: .gramUnit(with: .milli)),
            make(.dietaryVitaminB12,            value: n.vitaminB12,         unit: .gramUnit(with: .micro)),
            make(.dietaryFolate,                value: n.folate,             unit: .gramUnit(with: .micro)),
            make(.dietaryWater,                 value: n.water / 1000.0,     unit: .liter()),
        ]
        samples = candidates.compactMap { $0 }
        return samples
    }

    // MARK: - Serving scaling
}

extension NutritionPayload {
    func scaled(by factor: Double) -> NutritionPayload {
        NutritionPayload(
            calories:           calories           * factor,
            protein:            protein            * factor,
            carbohydrates:      carbohydrates      * factor,
            fat:                fat                * factor,
            fiber:              fiber              * factor,
            sugar:              sugar              * factor,
            saturatedFat:       saturatedFat       * factor,
            monounsaturatedFat: monounsaturatedFat * factor,
            polyunsaturatedFat: polyunsaturatedFat * factor,
            sodium:             sodium             * factor,
            cholesterol:        cholesterol        * factor,
            potassium:          potassium          * factor,
            calcium:            calcium            * factor,
            iron:               iron               * factor,
            zinc:               zinc               * factor,
            magnesium:          magnesium          * factor,
            vitaminA:           vitaminA           * factor,
            vitaminC:           vitaminC           * factor,
            vitaminD:           vitaminD           * factor,
            vitaminB6:          vitaminB6          * factor,
            vitaminB12:         vitaminB12         * factor,
            folate:             folate             * factor,
            water:              water              * factor
        )
    }
}

extension ScannedMeal {
    var confidenceColor: String {
        switch confidence.lowercased() {
        case "high":   return "green"
        case "medium": return "orange"
        default:       return "red"
        }
    }
}
