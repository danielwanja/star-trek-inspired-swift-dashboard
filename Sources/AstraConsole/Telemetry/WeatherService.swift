import Foundation

/// Open-Meteo client. No API key; forecast, air quality and geocoding are
/// separate endpoints. Everything is fetched in metric and converted at
/// display time, so switching units never refetches.
enum WeatherService {
    struct GeocodeResult: Sendable, Equatable, Identifiable {
        var id: String { "\(latitude),\(longitude)" }
        var name: String
        var region: String
        var latitude: Double
        var longitude: Double

        var location: WeatherLocation {
            WeatherLocation(name: name, region: region, latitude: latitude, longitude: longitude)
        }
    }

    enum WeatherError: Error {
        case badResponse
        case decoding(String)
    }

    private static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 12
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }

    // MARK: Geocoding (used by the Sources panel)

    static func geocode(_ query: String) async throws -> [GeocodeResult] {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "6"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json")
        ]
        let (data, response) = try await session().data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw WeatherError.badResponse }
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let results = (object?["results"] as? [[String: Any]]) ?? []
        return results.compactMap { item in
            guard let name = item["name"] as? String,
                  let latitude = item["latitude"] as? Double,
                  let longitude = item["longitude"] as? Double else { return nil }
            let region = [item["admin1"] as? String, item["country"] as? String]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            return GeocodeResult(name: name, region: region, latitude: latitude, longitude: longitude)
        }
    }

    // MARK: Forecast + air quality

    static func fetch(_ location: WeatherLocation) async throws -> LocationWeather {
        async let forecast = fetchForecast(location)
        async let air: AirQuality? = try? await fetchAirQuality(location)
        var result = try await forecast
        result.air = await air
        return result
    }

    private static func fetchForecast(_ location: WeatherLocation) async throws -> LocationWeather {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.latitude)),
            URLQueryItem(name: "longitude", value: String(location.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,relative_humidity_2m,apparent_temperature,is_day,precipitation,weather_code,cloud_cover,pressure_msl,wind_speed_10m,wind_direction_10m,wind_gusts_10m,uv_index"),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,weather_code"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,sunrise,sunset,precipitation_probability_max,uv_index_max"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "forecast_days", value: "6"),
            URLQueryItem(name: "timeformat", value: "unixtime")
        ]
        let (data, response) = try await session().data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw WeatherError.badResponse }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WeatherError.decoding("forecast root")
        }
        let timeZoneID = (object["timezone"] as? String) ?? TimeZone.current.identifier

        guard let current = object["current"] as? [String: Any] else { throw WeatherError.decoding("current") }
        func number(_ dict: [String: Any], _ key: String) -> Double {
            (dict[key] as? NSNumber)?.doubleValue ?? 0
        }
        let currentWeather = WeatherCurrent(
            time: Date(timeIntervalSince1970: number(current, "time")),
            temperature: number(current, "temperature_2m"),
            apparentTemperature: number(current, "apparent_temperature"),
            humidity: number(current, "relative_humidity_2m"),
            windSpeed: number(current, "wind_speed_10m"),
            windDirection: number(current, "wind_direction_10m"),
            windGusts: number(current, "wind_gusts_10m"),
            pressure: number(current, "pressure_msl"),
            uvIndex: number(current, "uv_index"),
            cloudCover: number(current, "cloud_cover"),
            precipitation: number(current, "precipitation"),
            weatherCode: Int(number(current, "weather_code")),
            isDay: number(current, "is_day") > 0.5
        )

        func series(_ dict: [String: Any]?, _ key: String) -> [Double] {
            ((dict?[key] as? [Any]) ?? []).map { ($0 as? NSNumber)?.doubleValue ?? 0 }
        }
        let hourly = object["hourly"] as? [String: Any]
        let hourTimes = series(hourly, "time")
        let hourTemps = series(hourly, "temperature_2m")
        let hourPrecip = series(hourly, "precipitation_probability")
        let hourCodes = series(hourly, "weather_code")
        var hours: [WeatherHour] = []
        for index in hourTimes.indices where index < hourTemps.count {
            hours.append(WeatherHour(
                time: Date(timeIntervalSince1970: hourTimes[index]),
                temperature: hourTemps[index],
                precipitationProbability: index < hourPrecip.count ? hourPrecip[index] : 0,
                weatherCode: index < hourCodes.count ? Int(hourCodes[index]) : 0
            ))
        }

        let daily = object["daily"] as? [String: Any]
        let dayTimes = series(daily, "time")
        let dayMax = series(daily, "temperature_2m_max")
        let dayMin = series(daily, "temperature_2m_min")
        let dayCodes = series(daily, "weather_code")
        let sunrises = series(daily, "sunrise")
        let sunsets = series(daily, "sunset")
        let dayPrecip = series(daily, "precipitation_probability_max")
        let dayUV = series(daily, "uv_index_max")
        var days: [WeatherDay] = []
        for index in dayTimes.indices where index < dayMax.count && index < dayMin.count {
            days.append(WeatherDay(
                date: Date(timeIntervalSince1970: dayTimes[index]),
                minTemperature: dayMin[index],
                maxTemperature: dayMax[index],
                weatherCode: index < dayCodes.count ? Int(dayCodes[index]) : 0,
                sunrise: Date(timeIntervalSince1970: index < sunrises.count ? sunrises[index] : dayTimes[index]),
                sunset: Date(timeIntervalSince1970: index < sunsets.count ? sunsets[index] : dayTimes[index]),
                precipitationProbability: index < dayPrecip.count ? dayPrecip[index] : 0,
                uvIndexMax: index < dayUV.count ? dayUV[index] : 0
            ))
        }

        return LocationWeather(
            location: location,
            timeZoneID: timeZoneID,
            current: currentWeather,
            hourly: hours,
            daily: days,
            air: nil,
            fetchedAt: Date()
        )
    }

    private static func fetchAirQuality(_ location: WeatherLocation) async throws -> AirQuality {
        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(location.latitude)),
            URLQueryItem(name: "longitude", value: String(location.longitude)),
            URLQueryItem(name: "current", value: "us_aqi,pm2_5,pm10,ozone,nitrogen_dioxide"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        let (data, response) = try await session().data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw WeatherError.badResponse }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = object["current"] as? [String: Any] else {
            throw WeatherError.decoding("air quality")
        }
        func number(_ key: String) -> Double {
            (current[key] as? NSNumber)?.doubleValue ?? 0
        }
        return AirQuality(
            usAQI: Int(number("us_aqi")),
            pm25: number("pm2_5"),
            pm10: number("pm10"),
            ozone: number("ozone"),
            nitrogenDioxide: number("nitrogen_dioxide")
        )
    }

    /// Fetches every location; failures leave the previous entry (if any)
    /// in place and are reported in `lastError`.
    static func refresh(_ locations: [WeatherLocation], previous: WeatherTelemetry, usesMetricUnits: Bool) async -> WeatherTelemetry {
        var results: [LocationWeather] = []
        var lastError: String?
        for location in locations {
            do {
                results.append(try await fetch(location))
            } catch {
                lastError = "\(location.name): \(error.localizedDescription)"
                if let kept = previous.locations.first(where: { $0.location.id == location.id }) {
                    results.append(kept)
                }
            }
        }
        return WeatherTelemetry(locations: results, usesMetricUnits: usesMetricUnits, lastError: lastError)
    }
}
