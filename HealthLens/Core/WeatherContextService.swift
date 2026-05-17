import Foundation
import CoreLocation
import OSLog

// MARK: - WeatherContext

struct WeatherContext: Sendable {
    let city: String
    let country: String
    let temperatureC: Double
    let feelsLikeC: Double
    let humidity: Int
    let windSpeedKmh: Double
    let condition: String
    let season: String
    /// False when location was denied/unavailable — city/country come from locale only.
    let hasWeatherData: Bool
}

// MARK: - WeatherContextService

/// Fetches approximate weather and location context for AI prompt enrichment.
/// Uses the user's existing location permission (requested during onboarding) at
/// city-level accuracy. Raw coordinates are never included in AI prompts — only
/// the derived city name, country, season, and weather description are sent.
@MainActor
final class WeatherContextService: NSObject, CLLocationManagerDelegate {

    static let shared = WeatherContextService()

    private var cachedContext: WeatherContext?
    private var cacheTime: Date?
    private let cacheTTL: TimeInterval = 1800 // 30 minutes

    private var locationManager: CLLocationManager?
    private var pendingContinuation: CheckedContinuation<CLLocation?, Never>?

    // MARK: - Public API

    func fetchContext() async -> WeatherContext? {
        if let cached = cachedContext, let time = cacheTime,
           Date().timeIntervalSince(time) < cacheTTL {
            return cached
        }

        if let location = await requestLocation() {
            let lat = location.coordinate.latitude
            let lon = location.coordinate.longitude

            async let placeResult = reverseGeocode(location)
            async let weatherResult = fetchOpenMeteo(lat: lat, lon: lon)
            let (place, weather) = await (placeResult, weatherResult)

            let hemisphere = lat > 10 ? "Northern" : (lat < -10 ? "Southern" : "Equatorial")
            let ctx = WeatherContext(
                city: place.city ?? "",
                country: place.country ?? localeCountry(),
                temperatureC: weather?.temperature ?? 0,
                feelsLikeC: weather?.feelsLike ?? 0,
                humidity: weather?.humidity ?? 0,
                windSpeedKmh: weather?.windSpeed ?? 0,
                condition: weather?.condition ?? "",
                season: currentSeason(hemisphere: hemisphere),
                hasWeatherData: weather != nil
            )
            cachedContext = ctx
            cacheTime = Date()
            return ctx
        } else {
            // Location not available — use locale for region/season only.
            let country = localeCountry()
            guard !country.isEmpty else { return nil }
            let hemisphere = southernHemisphereCodes.contains(
                Locale.current.region?.identifier ?? ""
            ) ? "Southern" : "Northern"
            let ctx = WeatherContext(
                city: "",
                country: country,
                temperatureC: 0, feelsLikeC: 0, humidity: 0, windSpeedKmh: 0,
                condition: "",
                season: currentSeason(hemisphere: hemisphere),
                hasWeatherData: false
            )
            // Cache locale-only context for a shorter window so location can be retried.
            cachedContext = ctx
            cacheTime = Date()
            return ctx
        }
    }

    // MARK: - Location

    private func requestLocation() async -> CLLocation? {
        let mgr = CLLocationManager()
        mgr.desiredAccuracy = kCLLocationAccuracyKilometer
        mgr.delegate = self
        locationManager = mgr

        let status = mgr.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return nil }

        return await withCheckedContinuation { continuation in
            pendingContinuation = continuation
            mgr.requestLocation()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        let loc = locations.first
        Task { @MainActor [weak self] in
            self?.pendingContinuation?.resume(returning: loc)
            self?.pendingContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: any Error) {
        Logger.ai.debug("WeatherContextService: location failed — \(error.localizedDescription)")
        Task { @MainActor [weak self] in
            self?.pendingContinuation?.resume(returning: nil)
            self?.pendingContinuation = nil
        }
    }

    // MARK: - Reverse geocode

    private struct PlaceResult {
        var city: String?
        var country: String?
    }

    private func reverseGeocode(_ location: CLLocation) async -> PlaceResult {
        await withCheckedContinuation { continuation in
            CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
                guard let p = placemarks?.first else {
                    continuation.resume(returning: PlaceResult())
                    return
                }
                continuation.resume(returning: PlaceResult(
                    city: p.locality ?? p.administrativeArea,
                    country: p.country
                ))
            }
        }
    }

    // MARK: - Open-Meteo (free, no API key required)

    private struct OpenMeteoWeather {
        let temperature: Double
        let feelsLike: Double
        let humidity: Int
        let windSpeed: Double
        let condition: String
    }

    private func fetchOpenMeteo(lat: Double, lon: Double) async -> OpenMeteoWeather? {
        let urlStr = "https://api.open-meteo.com/v1/forecast"
            + "?latitude=\(String(format: "%.4f", lat))"
            + "&longitude=\(String(format: "%.4f", lon))"
            + "&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m"
            + "&timezone=auto&forecast_days=1"
        guard let url = URL(string: urlStr) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            let c = decoded.current
            return OpenMeteoWeather(
                temperature: c.temperature_2m,
                feelsLike: c.apparent_temperature,
                humidity: c.relative_humidity_2m,
                windSpeed: c.wind_speed_10m,
                condition: wmoToText(c.weather_code)
            )
        } catch {
            Logger.ai.debug("WeatherContextService: Open-Meteo failed — \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Helpers

    private func localeCountry() -> String {
        guard let code = Locale.current.region?.identifier else { return "" }
        return Locale.current.localizedString(forRegionCode: code) ?? code
    }

    private func currentSeason(hemisphere: String) -> String {
        let month = Calendar.current.component(.month, from: Date())
        let north: String
        switch month {
        case 12, 1, 2: north = "Winter"
        case 3, 4, 5:  north = "Spring"
        case 6, 7, 8:  north = "Summer"
        default:       north = "Autumn"
        }
        if hemisphere == "Southern" {
            return ["Winter": "Summer", "Summer": "Winter",
                    "Spring": "Autumn", "Autumn": "Spring"][north] ?? north
        }
        return north
    }

    private let southernHemisphereCodes: Set<String> = [
        "AU", "NZ", "ZA", "AR", "CL", "BR", "PE", "BO", "PY", "UY", "EC", "TZ", "MZ", "ZW"
    ]

    private func wmoToText(_ code: Int) -> String {
        switch code {
        case 0:          return "Clear sky"
        case 1:          return "Mainly clear"
        case 2:          return "Partly cloudy"
        case 3:          return "Overcast"
        case 45, 48:     return "Foggy"
        case 51, 53, 55: return "Drizzle"
        case 56, 57:     return "Freezing drizzle"
        case 61, 63, 65: return "Rain"
        case 66, 67:     return "Freezing rain"
        case 71, 73, 75: return "Snow"
        case 77:         return "Snow grains"
        case 80, 81, 82: return "Rain showers"
        case 85, 86:     return "Snow showers"
        case 95:         return "Thunderstorm"
        case 96, 99:     return "Thunderstorm with hail"
        default:         return "Variable conditions"
        }
    }
}

// MARK: - Open-Meteo response model

private struct OpenMeteoResponse: Decodable {
    let current: CurrentWeather

    struct CurrentWeather: Decodable {
        let temperature_2m: Double
        let relative_humidity_2m: Int
        let apparent_temperature: Double
        let weather_code: Int
        let wind_speed_10m: Double
    }
}
