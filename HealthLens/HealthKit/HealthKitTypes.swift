import HealthKit
import SwiftUI

// MARK: - HealthCategory

enum HealthCategory: String, CaseIterable, Codable, Hashable {
    case activity     = "activity"
    case body         = "body"
    case heart        = "heart"
    case sleep        = "sleep"
    case nutrition    = "nutrition"
    case vitals       = "vitals"
    case mindfulness  = "mindfulness"
    case reproductive = "reproductive"
    case labs         = "labs"
    case environment  = "environment"

    var displayName: String {
        switch self {
        case .activity:     return "Activity"
        case .body:         return "Body"
        case .heart:        return "Heart"
        case .sleep:        return "Sleep"
        case .nutrition:    return "Nutrition"
        case .vitals:       return "Vitals"
        case .mindfulness:  return "Mindfulness"
        case .reproductive: return "Reproductive"
        case .labs:         return "Lab Results"
        case .environment:  return "Environment"
        }
    }

    var systemImage: String {
        switch self {
        case .activity:     return "figure.walk"
        case .body:         return "figure.arms.open"
        case .heart:        return "heart.fill"
        case .sleep:        return "moon.zzz.fill"
        case .nutrition:    return "fork.knife"
        case .vitals:       return "waveform.path.ecg"
        case .mindfulness:  return "brain.head.profile"
        case .reproductive: return "person.crop.circle"
        case .labs:         return "cross.vial.fill"
        case .environment:  return "ear.badge.waveform"
        }
    }

    // Permission sensitivity tier for gradual requests
    var permissionTier: Int {
        switch self {
        case .activity, .body:                      return 0  // Onboarding
        case .heart, .sleep, .nutrition:            return 1  // First query
        case .vitals, .mindfulness, .labs:          return 1
        case .environment:                          return 1
        case .reproductive:                         return 2  // Explicit opt-in
        }
    }

    // MARK: - HealthKit Type Mappings

    var quantityTypes: [HKQuantityType] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        switch self {
        case .activity:
            return [
                HKQuantityType(.stepCount),
                HKQuantityType(.distanceWalkingRunning),
                HKQuantityType(.activeEnergyBurned),
                HKQuantityType(.basalEnergyBurned),
                HKQuantityType(.flightsClimbed),
                HKQuantityType(.appleExerciseTime),
                HKQuantityType(.appleStandTime),
                HKQuantityType(.distanceCycling),
                HKQuantityType(.distanceSwimming),
                HKQuantityType(.distanceDownhillSnowSports),
                HKQuantityType(.pushCount),
                HKQuantityType(.swimmingStrokeCount),
                HKQuantityType(.walkingSpeed),
                HKQuantityType(.walkingStepLength),
                HKQuantityType(.walkingAsymmetryPercentage),
                HKQuantityType(.walkingDoubleSupportPercentage),
                HKQuantityType(.stairAscentSpeed),
                HKQuantityType(.stairDescentSpeed),
                HKQuantityType(.sixMinuteWalkTestDistance),
                HKQuantityType(.runningSpeed),
                HKQuantityType(.runningPower),
                HKQuantityType(.runningGroundContactTime),
                HKQuantityType(.runningStrideLength),
                HKQuantityType(.runningVerticalOscillation),
                HKQuantityType(.physicalEffort),
                HKQuantityType(.underwaterDepth),
                HKQuantityType(.appleWalkingSteadiness),
                HKQuantityType(.numberOfTimesFallen),
            ]
        case .body:
            return [
                HKQuantityType(.bodyMass),
                HKQuantityType(.bodyMassIndex),
                HKQuantityType(.height),
                HKQuantityType(.bodyFatPercentage),
                HKQuantityType(.leanBodyMass),
                HKQuantityType(.waistCircumference),
                HKQuantityType(.appleSleepingWristTemperature),
                HKQuantityType(.electrodermalActivity),
            ]
        case .heart:
            return [
                HKQuantityType(.heartRate),
                HKQuantityType(.heartRateVariabilitySDNN),
                HKQuantityType(.restingHeartRate),
                HKQuantityType(.walkingHeartRateAverage),
                HKQuantityType(.vo2Max),
                HKQuantityType(.peripheralPerfusionIndex),
                HKQuantityType(.atrialFibrillationBurden),
                HKQuantityType(.heartRateRecoveryOneMinute),
            ]
        case .sleep:
            return []
        case .nutrition:
            return [
                // Macronutrients
                HKQuantityType(.dietaryEnergyConsumed),
                HKQuantityType(.dietaryCarbohydrates),
                HKQuantityType(.dietaryFatTotal),
                HKQuantityType(.dietaryFatSaturated),
                HKQuantityType(.dietaryFatMonounsaturated),
                HKQuantityType(.dietaryFatPolyunsaturated),
                HKQuantityType(.dietaryProtein),
                HKQuantityType(.dietaryFiber),
                HKQuantityType(.dietarySugar),
                HKQuantityType(.dietaryCholesterol),
                HKQuantityType(.numberOfAlcoholicBeverages),
                HKQuantityType(.dietaryWater),
                HKQuantityType(.dietaryCaffeine),
                HKQuantityType(.dietarySodium),
                // Fat-soluble vitamins
                HKQuantityType(.dietaryVitaminA),
                HKQuantityType(.dietaryVitaminD),
                HKQuantityType(.dietaryVitaminE),
                HKQuantityType(.dietaryVitaminK),
                // Water-soluble vitamins
                HKQuantityType(.dietaryVitaminC),
                HKQuantityType(.dietaryThiamin),
                HKQuantityType(.dietaryRiboflavin),
                HKQuantityType(.dietaryNiacin),
                HKQuantityType(.dietaryPantothenicAcid),
                HKQuantityType(.dietaryVitaminB6),
                HKQuantityType(.dietaryBiotin),
                HKQuantityType(.dietaryFolate),
                HKQuantityType(.dietaryVitaminB12),
                // Minerals
                HKQuantityType(.dietaryCalcium),
                HKQuantityType(.dietaryChloride),
                HKQuantityType(.dietaryChromium),
                HKQuantityType(.dietaryCopper),
                HKQuantityType(.dietaryIodine),
                HKQuantityType(.dietaryIron),
                HKQuantityType(.dietaryMagnesium),
                HKQuantityType(.dietaryManganese),
                HKQuantityType(.dietaryMolybdenum),
                HKQuantityType(.dietaryPhosphorus),
                HKQuantityType(.dietaryPotassium),
                HKQuantityType(.dietarySelenium),
                HKQuantityType(.dietaryZinc),
            ]
        case .vitals:
            return [
                HKQuantityType(.bloodPressureSystolic),
                HKQuantityType(.bloodPressureDiastolic),
                HKQuantityType(.oxygenSaturation),
                HKQuantityType(.respiratoryRate),
                HKQuantityType(.bodyTemperature),
                HKQuantityType(.bloodAlcoholContent),
                HKQuantityType(.forcedVitalCapacity),
                HKQuantityType(.forcedExpiratoryVolume1),
                HKQuantityType(.peakExpiratoryFlowRate),
                HKQuantityType(.uvExposure),
            ]
        case .mindfulness:
            return []
        case .reproductive:
            return [
                HKQuantityType(.basalBodyTemperature),
            ]
        case .labs:
            return [
                HKQuantityType(.bloodGlucose),
            ]
        case .environment:
            return [
                HKQuantityType(.environmentalAudioExposure),
                HKQuantityType(.headphoneAudioExposure),
            ]
        }
    }

    var categoryTypes: [HKCategoryType] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        switch self {
        case .sleep:
            return [HKCategoryType(.sleepAnalysis)]
        case .mindfulness:
            return [
                HKCategoryType(.mindfulSession),
                HKCategoryType(.handwashingEvent),
                HKCategoryType(.toothbrushingEvent),
            ]
        case .heart:
            return [
                HKCategoryType(.highHeartRateEvent),
                HKCategoryType(.lowHeartRateEvent),
                HKCategoryType(.irregularHeartRhythmEvent),
                HKCategoryType(.lowCardioFitnessEvent),
            ]
        case .reproductive:
            return [
                HKCategoryType(.menstrualFlow),
                HKCategoryType(.ovulationTestResult),
                HKCategoryType(.intermenstrualBleeding),
                HKCategoryType(.sexualActivity),
                HKCategoryType(.contraceptive),
                HKCategoryType(.lactation),
                HKCategoryType(.pregnancyTestResult),
                HKCategoryType(.progesteroneTestResult),
            ]
        case .activity:
            return [
                HKCategoryType(.appleStandHour),
            ]
        default:
            return []
        }
    }

    var correlationTypes: [HKCorrelationType] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        switch self {
        case .vitals:
            return [HKCorrelationType(.bloodPressure)]
        default:
            return []
        }
    }

    var allReadTypes: Set<HKObjectType> {
        var result: Set<HKObjectType> = []
        quantityTypes.forEach { result.insert($0) }
        categoryTypes.forEach { result.insert($0) }
        // HKCorrelationType (e.g. bloodPressure) CANNOT be passed to requestAuthorization —
        // HealthKit throws NSInvalidArgumentException. The component quantity types
        // (bloodPressureSystolic / bloodPressureDiastolic) are already in quantityTypes.
        if self == .activity {
            result.insert(HKObjectType.workoutType())
            result.insert(HKObjectType.activitySummaryType())
        }
        if self == .heart {
            result.insert(HKObjectType.electrocardiogramType())
        }
        if self == .mindfulness {
            if #available(iOS 18.0, *) {
                result.insert(HKObjectType.stateOfMindType())
            }
        }
        return result
    }
}

// MARK: - Preferred unit per quantity type

extension HKQuantityType {
    var preferredUnit: HKUnit {
        switch self {
        // Activity
        case HKQuantityType(.stepCount):                    return .count()
        case HKQuantityType(.distanceWalkingRunning):       return .meterUnit(with: .kilo)
        case HKQuantityType(.distanceCycling):              return .meterUnit(with: .kilo)
        case HKQuantityType(.distanceSwimming):             return .meterUnit(with: .kilo)
        case HKQuantityType(.distanceDownhillSnowSports):   return .meterUnit(with: .kilo)
        case HKQuantityType(.activeEnergyBurned):           return .kilocalorie()
        case HKQuantityType(.basalEnergyBurned):            return .kilocalorie()
        case HKQuantityType(.flightsClimbed):               return .count()
        case HKQuantityType(.appleExerciseTime):            return .minute()
        case HKQuantityType(.appleStandTime):               return .minute()
        case HKQuantityType(.pushCount):                    return .count()
        case HKQuantityType(.swimmingStrokeCount):          return .count()
        case HKQuantityType(.walkingSpeed):                 return HKUnit(from: "m/s")
        case HKQuantityType(.walkingStepLength):            return .meter()
        case HKQuantityType(.walkingAsymmetryPercentage):   return .percent()
        case HKQuantityType(.walkingDoubleSupportPercentage): return .percent()
        case HKQuantityType(.stairAscentSpeed):             return HKUnit(from: "m/s")
        case HKQuantityType(.stairDescentSpeed):            return HKUnit(from: "m/s")
        case HKQuantityType(.sixMinuteWalkTestDistance):    return .meter()
        case HKQuantityType(.runningSpeed):                 return HKUnit(from: "m/s")
        case HKQuantityType(.runningPower):                 return HKUnit(from: "W")
        case HKQuantityType(.runningGroundContactTime):     return .secondUnit(with: .milli)
        case HKQuantityType(.runningStrideLength):          return .meter()
        case HKQuantityType(.runningVerticalOscillation):   return .meterUnit(with: .centi)
        case HKQuantityType(.physicalEffort):               return HKUnit(from: "kcal/hr·kg")
        case HKQuantityType(.underwaterDepth):              return .meter()
        case HKQuantityType(.appleWalkingSteadiness):       return .percent()
        case HKQuantityType(.numberOfTimesFallen):          return .count()
        // Body
        case HKQuantityType(.bodyMass):                     return .gramUnit(with: .kilo)
        case HKQuantityType(.bodyMassIndex):                return HKUnit(from: "kg/m^2")
        case HKQuantityType(.height):                       return .meter()
        case HKQuantityType(.bodyFatPercentage):            return .percent()
        case HKQuantityType(.leanBodyMass):                 return .gramUnit(with: .kilo)
        case HKQuantityType(.waistCircumference):           return .meter()
        case HKQuantityType(.appleSleepingWristTemperature): return .degreeCelsius()
        case HKQuantityType(.electrodermalActivity):        return HKUnit(from: "mcS")
        // Heart
        case HKQuantityType(.heartRate):                    return HKUnit(from: "count/min")
        case HKQuantityType(.heartRateVariabilitySDNN):     return .secondUnit(with: .milli)
        case HKQuantityType(.restingHeartRate):             return HKUnit(from: "count/min")
        case HKQuantityType(.walkingHeartRateAverage):      return HKUnit(from: "count/min")
        case HKQuantityType(.vo2Max):                       return HKUnit(from: "mL/kg·min")
        case HKQuantityType(.peripheralPerfusionIndex):     return .percent()
        case HKQuantityType(.atrialFibrillationBurden):     return .percent()
        case HKQuantityType(.heartRateRecoveryOneMinute):   return HKUnit(from: "count/min")
        // Nutrition — macros
        case HKQuantityType(.dietaryEnergyConsumed):        return .kilocalorie()
        case HKQuantityType(.dietaryCarbohydrates):         return .gram()
        case HKQuantityType(.dietaryFatTotal):              return .gram()
        case HKQuantityType(.dietaryFatSaturated):          return .gram()
        case HKQuantityType(.dietaryFatMonounsaturated):    return .gram()
        case HKQuantityType(.dietaryFatPolyunsaturated):    return .gram()
        case HKQuantityType(.dietaryProtein):               return .gram()
        case HKQuantityType(.dietaryFiber):                 return .gram()
        case HKQuantityType(.dietarySugar):                 return .gram()
        case HKQuantityType(.dietaryCholesterol):           return .gramUnit(with: .milli)
        case HKQuantityType(.numberOfAlcoholicBeverages):   return .count()
        case HKQuantityType(.dietaryWater):                 return .literUnit(with: .milli)
        case HKQuantityType(.dietarySodium):                return .gramUnit(with: .milli)
        case HKQuantityType(.dietaryCaffeine):              return .gramUnit(with: .milli)
        // Nutrition — fat-soluble vitamins (mcg)
        case HKQuantityType(.dietaryVitaminA):              return .gramUnit(with: .micro)
        case HKQuantityType(.dietaryVitaminD):              return .gramUnit(with: .micro)
        case HKQuantityType(.dietaryVitaminE):              return .gramUnit(with: .milli)
        case HKQuantityType(.dietaryVitaminK):              return .gramUnit(with: .micro)
        // Nutrition — water-soluble vitamins
        case HKQuantityType(.dietaryVitaminC):              return .gramUnit(with: .milli)
        case HKQuantityType(.dietaryThiamin):               return .gramUnit(with: .milli)
        case HKQuantityType(.dietaryRiboflavin):            return .gramUnit(with: .milli)
        case HKQuantityType(.dietaryNiacin):                return .gramUnit(with: .milli)
        case HKQuantityType(.dietaryPantothenicAcid):       return .gramUnit(with: .milli)
        case HKQuantityType(.dietaryVitaminB6):             return .gramUnit(with: .milli)
        case HKQuantityType(.dietaryBiotin):                return .gramUnit(with: .micro)
        case HKQuantityType(.dietaryFolate):                return .gramUnit(with: .micro)
        case HKQuantityType(.dietaryVitaminB12):            return .gramUnit(with: .micro)
        // Nutrition — minerals (mg)
        case HKQuantityType(.dietaryCalcium):               return .gramUnit(with: .milli)
        case HKQuantityType(.dietaryChloride):              return .gramUnit(with: .milli)
        case HKQuantityType(.dietaryChromium):              return .gramUnit(with: .micro)
        case HKQuantityType(.dietaryCopper):                return .gramUnit(with: .milli)
        case HKQuantityType(.dietaryIodine):                return .gramUnit(with: .micro)
        case HKQuantityType(.dietaryIron):                  return .gramUnit(with: .milli)
        case HKQuantityType(.dietaryMagnesium):             return .gramUnit(with: .milli)
        case HKQuantityType(.dietaryManganese):             return .gramUnit(with: .milli)
        case HKQuantityType(.dietaryMolybdenum):            return .gramUnit(with: .micro)
        case HKQuantityType(.dietaryPhosphorus):            return .gramUnit(with: .milli)
        case HKQuantityType(.dietaryPotassium):             return .gramUnit(with: .milli)
        case HKQuantityType(.dietarySelenium):              return .gramUnit(with: .micro)
        case HKQuantityType(.dietaryZinc):                  return .gramUnit(with: .milli)
        // Vitals
        case HKQuantityType(.bloodPressureSystolic):        return .millimeterOfMercury()
        case HKQuantityType(.bloodPressureDiastolic):       return .millimeterOfMercury()
        case HKQuantityType(.oxygenSaturation):             return .percent()
        case HKQuantityType(.respiratoryRate):              return HKUnit(from: "count/min")
        case HKQuantityType(.bodyTemperature):              return .degreeCelsius()
        case HKQuantityType(.bloodAlcoholContent):          return .percent()
        case HKQuantityType(.forcedVitalCapacity):          return .liter()
        case HKQuantityType(.forcedExpiratoryVolume1):      return .liter()
        case HKQuantityType(.peakExpiratoryFlowRate):       return HKUnit(from: "L/min")
        case HKQuantityType(.uvExposure):                   return .count()
        // Reproductive
        case HKQuantityType(.basalBodyTemperature):         return .degreeCelsius()
        // Labs
        case HKQuantityType(.bloodGlucose):                 return HKUnit(from: "mg/dL")
        // Environment
        case HKQuantityType(.environmentalAudioExposure):   return HKUnit(from: "dBASPL")
        case HKQuantityType(.headphoneAudioExposure):       return HKUnit(from: "dBASPL")
        default:                                            return .count()
        }
    }

    var defaultStatisticsOptions: HKStatisticsOptions {
        switch self {
        // Cumulative (sum over interval)
        // Activity — all cumulative (totals accumulated over the interval)
        case HKQuantityType(.stepCount),
             HKQuantityType(.distanceWalkingRunning),
             HKQuantityType(.distanceCycling),
             HKQuantityType(.distanceSwimming),
             HKQuantityType(.distanceDownhillSnowSports),
             HKQuantityType(.activeEnergyBurned),
             HKQuantityType(.basalEnergyBurned),
             HKQuantityType(.flightsClimbed),
             HKQuantityType(.appleExerciseTime),
             HKQuantityType(.appleStandTime),
             HKQuantityType(.pushCount),
             HKQuantityType(.swimmingStrokeCount),
             HKQuantityType(.numberOfTimesFallen),
             // Nutrition — all cumulative (daily intake totals)
             HKQuantityType(.dietaryEnergyConsumed),
             HKQuantityType(.dietaryCarbohydrates),
             HKQuantityType(.dietaryFatTotal),
             HKQuantityType(.dietaryFatSaturated),
             HKQuantityType(.dietaryFatMonounsaturated),
             HKQuantityType(.dietaryFatPolyunsaturated),
             HKQuantityType(.dietaryProtein),
             HKQuantityType(.dietaryFiber),
             HKQuantityType(.dietarySugar),
             HKQuantityType(.dietaryCholesterol),
             HKQuantityType(.numberOfAlcoholicBeverages),
             HKQuantityType(.dietaryWater),
             HKQuantityType(.dietarySodium),
             HKQuantityType(.dietaryCaffeine),
             HKQuantityType(.dietaryVitaminA),
             HKQuantityType(.dietaryVitaminC),
             HKQuantityType(.dietaryVitaminD),
             HKQuantityType(.dietaryVitaminE),
             HKQuantityType(.dietaryVitaminK),
             HKQuantityType(.dietaryThiamin),
             HKQuantityType(.dietaryRiboflavin),
             HKQuantityType(.dietaryNiacin),
             HKQuantityType(.dietaryPantothenicAcid),
             HKQuantityType(.dietaryVitaminB6),
             HKQuantityType(.dietaryBiotin),
             HKQuantityType(.dietaryFolate),
             HKQuantityType(.dietaryVitaminB12),
             HKQuantityType(.dietaryCalcium),
             HKQuantityType(.dietaryChloride),
             HKQuantityType(.dietaryChromium),
             HKQuantityType(.dietaryCopper),
             HKQuantityType(.dietaryIodine),
             HKQuantityType(.dietaryIron),
             HKQuantityType(.dietaryMagnesium),
             HKQuantityType(.dietaryManganese),
             HKQuantityType(.dietaryMolybdenum),
             HKQuantityType(.dietaryPhosphorus),
             HKQuantityType(.dietaryPotassium),
             HKQuantityType(.dietarySelenium),
             HKQuantityType(.dietaryZinc):
            return .cumulativeSum
        // Discrete types — instantaneous point-in-time readings — fall through to default (.discreteAverage)
        // underwaterDepth: discrete (depth at a moment), uvExposure: discrete (UV index at a moment),
        // environmentalAudioExposure: discrete, headphoneAudioExposure: discrete,
        // all vitals / body / heart / running metrics: discrete
        default:
            return .discreteAverage
        }
    }

    /// True for quantity types where Apple Watch computes and stores a single sample
    /// per day (or less frequently) rather than a continuous stream of readings.
    ///
    /// `HKStatisticsCollectionQuery` can silently return empty for these types
    /// because the sample's `startDate` (the moment the Watch finalised the
    /// calculation, e.g. 3 AM) may not align with the expected daily bucket.
    /// Using `HKSampleQuery` directly avoids this date-attribution quirk.
    var isComputedDaily: Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        switch self {
        case HKQuantityType(.restingHeartRate),            // Apple Watch: once per day
             HKQuantityType(.walkingHeartRateAverage),     // Apple Watch: once per day
             HKQuantityType(.vo2Max),                      // Apple Watch: when estimated
             HKQuantityType(.heartRateRecoveryOneMinute),  // After qualifying workouts
             HKQuantityType(.appleSleepingWristTemperature): // Apple Watch: once per night
            return true
        default:
            return false
        }
    }

    var displayName: String {
        switch self {
        // Activity
        case HKQuantityType(.stepCount):                    return "Steps"
        case HKQuantityType(.distanceWalkingRunning):       return "Walking Distance"
        case HKQuantityType(.distanceCycling):              return "Cycling Distance"
        case HKQuantityType(.distanceSwimming):             return "Swimming Distance"
        case HKQuantityType(.distanceDownhillSnowSports):   return "Snow Sports Distance"
        case HKQuantityType(.activeEnergyBurned):           return "Active Calories"
        case HKQuantityType(.basalEnergyBurned):            return "Resting Calories"
        case HKQuantityType(.flightsClimbed):               return "Flights Climbed"
        case HKQuantityType(.appleExerciseTime):            return "Exercise Minutes"
        case HKQuantityType(.appleStandTime):               return "Stand Time"
        case HKQuantityType(.pushCount):                    return "Push Count"
        case HKQuantityType(.swimmingStrokeCount):          return "Swimming Strokes"
        case HKQuantityType(.walkingSpeed):                 return "Walking Speed"
        case HKQuantityType(.walkingStepLength):            return "Step Length"
        case HKQuantityType(.walkingAsymmetryPercentage):   return "Walking Asymmetry"
        case HKQuantityType(.walkingDoubleSupportPercentage): return "Double Support Time"
        case HKQuantityType(.stairAscentSpeed):             return "Stair Ascent Speed"
        case HKQuantityType(.stairDescentSpeed):            return "Stair Descent Speed"
        case HKQuantityType(.sixMinuteWalkTestDistance):    return "6-Minute Walk"
        case HKQuantityType(.runningSpeed):                 return "Running Speed"
        case HKQuantityType(.runningPower):                 return "Running Power"
        case HKQuantityType(.runningGroundContactTime):     return "Ground Contact Time"
        case HKQuantityType(.runningStrideLength):          return "Stride Length"
        case HKQuantityType(.runningVerticalOscillation):   return "Vertical Oscillation"
        case HKQuantityType(.physicalEffort):               return "Physical Effort"
        case HKQuantityType(.underwaterDepth):              return "Underwater Depth"
        case HKQuantityType(.appleWalkingSteadiness):       return "Walking Steadiness"
        case HKQuantityType(.numberOfTimesFallen):          return "Times Fallen"
        // Body
        case HKQuantityType(.bodyMass):                     return "Weight"
        case HKQuantityType(.bodyMassIndex):                return "BMI"
        case HKQuantityType(.height):                       return "Height"
        case HKQuantityType(.bodyFatPercentage):            return "Body Fat %"
        case HKQuantityType(.leanBodyMass):                 return "Lean Mass"
        case HKQuantityType(.waistCircumference):           return "Waist"
        case HKQuantityType(.appleSleepingWristTemperature): return "Wrist Temperature (Sleep)"
        case HKQuantityType(.electrodermalActivity):        return "Electrodermal Activity"
        // Heart
        case HKQuantityType(.heartRate):                    return "Heart Rate"
        case HKQuantityType(.heartRateVariabilitySDNN):     return "HRV"
        case HKQuantityType(.restingHeartRate):             return "Resting HR"
        case HKQuantityType(.walkingHeartRateAverage):      return "Walking HR"
        case HKQuantityType(.vo2Max):                       return "VO₂ Max"
        case HKQuantityType(.peripheralPerfusionIndex):     return "Peripheral Perfusion"
        case HKQuantityType(.atrialFibrillationBurden):     return "AFib Burden"
        case HKQuantityType(.heartRateRecoveryOneMinute):   return "HR Recovery (1 min)"
        // Nutrition — macros
        case HKQuantityType(.dietaryEnergyConsumed):        return "Calories"
        case HKQuantityType(.dietaryCarbohydrates):         return "Carbohydrates"
        case HKQuantityType(.dietaryFatTotal):              return "Fat"
        case HKQuantityType(.dietaryFatSaturated):          return "Saturated Fat"
        case HKQuantityType(.dietaryFatMonounsaturated):    return "Monounsaturated Fat"
        case HKQuantityType(.dietaryFatPolyunsaturated):    return "Polyunsaturated Fat"
        case HKQuantityType(.dietaryProtein):               return "Protein"
        case HKQuantityType(.dietaryFiber):                 return "Fiber"
        case HKQuantityType(.dietarySugar):                 return "Sugar"
        case HKQuantityType(.dietaryCholesterol):           return "Cholesterol"
        case HKQuantityType(.numberOfAlcoholicBeverages):   return "Alcoholic Beverages"
        case HKQuantityType(.dietaryWater):                 return "Water"
        case HKQuantityType(.dietarySodium):                return "Sodium"
        case HKQuantityType(.dietaryCaffeine):              return "Caffeine"
        // Nutrition — vitamins
        case HKQuantityType(.dietaryVitaminA):              return "Vitamin A"
        case HKQuantityType(.dietaryVitaminD):              return "Vitamin D"
        case HKQuantityType(.dietaryVitaminE):              return "Vitamin E"
        case HKQuantityType(.dietaryVitaminK):              return "Vitamin K"
        case HKQuantityType(.dietaryVitaminC):              return "Vitamin C"
        case HKQuantityType(.dietaryThiamin):               return "Thiamin (B1)"
        case HKQuantityType(.dietaryRiboflavin):            return "Riboflavin (B2)"
        case HKQuantityType(.dietaryNiacin):                return "Niacin (B3)"
        case HKQuantityType(.dietaryPantothenicAcid):       return "Pantothenic Acid (B5)"
        case HKQuantityType(.dietaryVitaminB6):             return "Vitamin B6"
        case HKQuantityType(.dietaryBiotin):                return "Biotin (B7)"
        case HKQuantityType(.dietaryFolate):                return "Folate (B9)"
        case HKQuantityType(.dietaryVitaminB12):            return "Vitamin B12"
        // Nutrition — minerals
        case HKQuantityType(.dietaryCalcium):               return "Calcium"
        case HKQuantityType(.dietaryChloride):              return "Chloride"
        case HKQuantityType(.dietaryChromium):              return "Chromium"
        case HKQuantityType(.dietaryCopper):                return "Copper"
        case HKQuantityType(.dietaryIodine):                return "Iodine"
        case HKQuantityType(.dietaryIron):                  return "Iron"
        case HKQuantityType(.dietaryMagnesium):             return "Magnesium"
        case HKQuantityType(.dietaryManganese):             return "Manganese"
        case HKQuantityType(.dietaryMolybdenum):            return "Molybdenum"
        case HKQuantityType(.dietaryPhosphorus):            return "Phosphorus"
        case HKQuantityType(.dietaryPotassium):             return "Potassium"
        case HKQuantityType(.dietarySelenium):              return "Selenium"
        case HKQuantityType(.dietaryZinc):                  return "Zinc"
        // Vitals
        case HKQuantityType(.bloodPressureSystolic):        return "Systolic BP"
        case HKQuantityType(.bloodPressureDiastolic):       return "Diastolic BP"
        case HKQuantityType(.oxygenSaturation):             return "Blood Oxygen"
        case HKQuantityType(.respiratoryRate):              return "Respiratory Rate"
        case HKQuantityType(.bodyTemperature):              return "Body Temp"
        case HKQuantityType(.bloodAlcoholContent):          return "Blood Alcohol"
        case HKQuantityType(.forcedVitalCapacity):          return "Forced Vital Capacity"
        case HKQuantityType(.forcedExpiratoryVolume1):      return "FEV1"
        case HKQuantityType(.peakExpiratoryFlowRate):       return "Peak Flow Rate"
        case HKQuantityType(.uvExposure):                   return "UV Exposure"
        // Reproductive
        case HKQuantityType(.basalBodyTemperature):         return "Basal Body Temp"
        // Labs
        case HKQuantityType(.bloodGlucose):                 return "Blood Glucose"
        // Environment
        case HKQuantityType(.environmentalAudioExposure):   return "Environmental Audio"
        case HKQuantityType(.headphoneAudioExposure):       return "Headphone Audio"
        default:                                            return identifier
        }
    }
}
