import Foundation
import HealthKit

actor HealthKitWriter {
    static let shared = HealthKitWriter()
    private let service = HealthKitService.shared

    private init() {}

    // MARK: - Meal Logging

    func logMeal(_ meal: ScannedMeal, at date: Date = Date()) async throws {
        let samples = meal.toHealthKitSamples(at: date)
        guard !samples.isEmpty else { return }
        let types = Set(samples.compactMap { $0.sampleType as? HKSampleType })
        try await ensureWriteAuthorization(for: types)
        try await service.saveSamples(samples)
    }

    // MARK: - Water Logging

    func logWater(milliliters: Double, at date: Date = Date()) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }
        guard milliliters > 0 else { return }
        let waterType = HKQuantityType(.dietaryWater)
        try await ensureWriteAuthorization(for: [waterType])
        let quantity = HKQuantity(unit: .liter(), doubleValue: milliliters / 1000.0)
        let sample = HKQuantitySample(type: waterType, quantity: quantity, start: date, end: date)
        try await service.saveSamples([sample])
    }

    // MARK: - Weight Logging

    func logWeight(kilograms: Double, at date: Date = Date()) async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitError.notAvailable
        }
        guard kilograms > 0 else { return }
        let weightType = HKQuantityType(.bodyMass)
        try await ensureWriteAuthorization(for: [weightType])
        let quantity = HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kilograms)
        let sample = HKQuantitySample(type: weightType, quantity: quantity, start: date, end: date)
        try await service.saveSamples([sample])
    }

    // MARK: - Authorization

    private func ensureWriteAuthorization(for types: Set<HKSampleType>) async throws {
        try await service.requestWriteAuthorization(for: types)
    }
}
