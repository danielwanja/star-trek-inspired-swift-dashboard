import SwiftUI

// Weather widgets (Open-Meteo data relayed by the Mac). Everything is
// stored in metric and converted here according to the synced unit flag.

private func severityColor(_ code: Int) -> AstraColorRole {
    switch WeatherCode.severity(code) {
    case 0: .gold
    case 1: .cyan
    case 2: .blue
    default: .rose
    }
}

private func uvColor(_ index: Double) -> AstraColorRole {
    if index >= 8 { return .red }
    if index >= 6 { return .rose }
    if index >= 3 { return .gold }
    return .mint
}

private func aqiColor(_ aqi: Int) -> AstraColorRole {
    switch aqi {
    case ..<51: .mint
    case ..<101: .gold
    case ..<151: .apricot
    case ..<201: .rose
    default: .red
    }
}

/// Empty state shared by the weather widgets.
private struct WeatherUnavailable: View {
    var telemetry: WeatherTelemetry

    var body: some View {
        WidgetNote(
            title: telemetry.locations.isEmpty && telemetry.lastError == nil ? "Awaiting weather link" : "Weather unavailable",
            detail: telemetry.lastError ?? "Add a location under EDIT › SOURCES on the Mac"
        )
    }
}

// MARK: - Current conditions

struct WeatherNowWidget: View {
    @Environment(LiveDataHub.self) private var liveData
    @Environment(\.astraTheme) private var theme

    var body: some View {
        let telemetry = liveData.weather
        if let place = telemetry.primary {
            let metric = telemetry.usesMetricUnits
            let current = place.current
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        TagChip(text: place.location.name, color: .teal)
                        if !place.location.region.isEmpty {
                            Text(place.location.region.uppercased())
                                .font(theme.typography.data(size: 11))
                                .foregroundStyle(theme.palette.mutedText)
                                .lineLimit(1)
                        }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(Formatters.temperature(current.temperature, metric: metric))
                            .font(theme.typography.display(size: 52))
                            .tracking(theme.typography.displayTracking)
                        Image(systemName: WeatherCode.symbol(current.weatherCode, isDay: current.isDay))
                            .font(.system(size: 30, weight: .regular))
                            .foregroundStyle(theme.color(severityColor(current.weatherCode)))
                    }
                    Text(WeatherCode.description(current.weatherCode).uppercased())
                        .font(theme.typography.data(size: 14))
                        .foregroundStyle(theme.color(severityColor(current.weatherCode)))
                    Text("FEELS \(Formatters.temperature(current.apparentTemperature, metric: metric)) · \(Formatters.shortTime(liveData.now, timeZone: place.timeZone)) LOCAL")
                        .font(theme.typography.systemData(size: 11, weight: .semibold))
                        .foregroundStyle(theme.palette.mutedText)
                }
                .frame(minWidth: 190, alignment: .leading)

                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        MicroStat(label: "WIND", value: "\(Formatters.windSpeed(current.windSpeed, metric: metric)) \(Formatters.compass(current.windDirection))", color: .cyan)
                        MicroStat(label: "GUSTS", value: Formatters.windSpeed(current.windGusts, metric: metric), color: .blue)
                        MicroStat(label: "HUMIDITY", value: "\(Int(current.humidity))%", color: .violet)
                    }
                    HStack(spacing: 8) {
                        MicroStat(label: "PRESSURE", value: Formatters.pressure(current.pressure, metric: metric), color: .gold)
                        MicroStat(label: "UV", value: Formatters.fixed(current.uvIndex, digits: 1), color: uvColor(current.uvIndex))
                        MicroStat(label: "CLOUD", value: "\(Int(current.cloudCover))%", color: .teal)
                    }
                    MetricLine(label: "Humidity", value: "\(Int(current.humidity))%", progress: current.humidity / 100, color: .violet)
                    MetricLine(label: "Cloud cover", value: "\(Int(current.cloudCover))%", progress: current.cloudCover / 100, color: .teal)
                }
            }
        } else {
            WeatherUnavailable(telemetry: telemetry)
        }
    }
}

// MARK: - Hourly outlook

struct HourlyOutlookWidget: View {
    @Environment(LiveDataHub.self) private var liveData
    @Environment(\.astraTheme) private var theme

    var body: some View {
        let telemetry = liveData.weather
        if let place = telemetry.primary {
            let hours = upcoming(place)
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    TagChip(text: place.location.name, color: .teal)
                    if let high = hours.map(\.temperature).max(), let low = hours.map(\.temperature).min() {
                        MicroStat(label: "HIGH", value: Formatters.temperature(high, metric: telemetry.usesMetricUnits), color: .gold)
                        MicroStat(label: "LOW", value: Formatters.temperature(low, metric: telemetry.usesMetricUnits), color: .cyan)
                    }
                    MicroStat(label: "RAIN MAX", value: "\(Int(hours.map(\.precipitationProbability).max() ?? 0))%", color: .blue)
                }
                HourlyChart(hours: hours, timeZone: place.timeZone, metric: telemetry.usesMetricUnits)
                    .frame(height: 118)
            }
        } else {
            WeatherUnavailable(telemetry: telemetry)
        }
    }

    private func upcoming(_ place: LocationWeather) -> [WeatherHour] {
        let now = liveData.now
        let future = place.hourly.filter { $0.time >= now.addingTimeInterval(-3600) }
        return Array(future.prefix(12))
    }
}

/// Temperature curve over precipitation-probability bars, hour labels
/// underneath, condition symbols on top. One Canvas, redrawn on data.
struct HourlyChart: View {
    @Environment(\.astraTheme) private var theme
    var hours: [WeatherHour]
    var timeZone: TimeZone
    var metric: Bool

    var body: some View {
        Canvas { context, size in
            guard hours.count > 1 else { return }
            let labelBand: CGFloat = 16
            let symbolBand: CGFloat = 20
            let chartTop = symbolBand + 4
            let chartBottom = size.height - labelBand - 2
            let chartHeight = chartBottom - chartTop
            let slot = size.width / CGFloat(hours.count)
            let temps = hours.map(\.temperature)
            let minTemp = (temps.min() ?? 0) - 1
            let maxTemp = (temps.max() ?? 1) + 1
            let span = max(1, maxTemp - minTemp)

            // Precipitation bars.
            for (index, hour) in hours.enumerated() {
                let x = CGFloat(index) * slot + 3
                let height = chartHeight * CGFloat(hour.precipitationProbability / 100)
                let rect = CGRect(x: x, y: chartBottom - height, width: max(2, slot - 6), height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(theme.color(.blue).opacity(0.28)))
            }

            // Temperature line + points.
            var line = Path()
            for (index, hour) in hours.enumerated() {
                let x = CGFloat(index) * slot + slot / 2
                let y = chartBottom - chartHeight * CGFloat((hour.temperature - minTemp) / span)
                if index == 0 { line.move(to: CGPoint(x: x, y: y)) } else { line.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(line, with: .color(theme.color(.gold)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

            for (index, hour) in hours.enumerated() {
                let x = CGFloat(index) * slot + slot / 2
                let y = chartBottom - chartHeight * CGFloat((hour.temperature - minTemp) / span)
                context.fill(Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)), with: .color(theme.color(.gold)))

                let temp = context.resolve(
                    Text(Formatters.temperature(hour.temperature, metric: metric))
                        .font(theme.typography.data(size: 11))
                        .foregroundStyle(theme.palette.text)
                )
                context.draw(temp, at: CGPoint(x: x, y: y - 7), anchor: .bottom)

                let label = context.resolve(
                    Text(Formatters.hourLabel(hour.time, timeZone: timeZone))
                        .font(theme.typography.data(size: 11))
                        .foregroundStyle(theme.palette.mutedText)
                )
                context.draw(label, at: CGPoint(x: x, y: size.height), anchor: .bottom)

                var symbol = context.resolve(Image(systemName: WeatherCode.symbol(hour.weatherCode)))
                symbol.shading = .color(theme.color(severityColor(hour.weatherCode)))
                context.draw(symbol, in: CGRect(x: x - 8, y: 0, width: 16, height: 16))
            }
        }
    }
}

// MARK: - Forecast

struct ForecastWidget: View {
    @Environment(LiveDataHub.self) private var liveData
    @Environment(\.astraTheme) private var theme

    var body: some View {
        let telemetry = liveData.weather
        if let place = telemetry.primary, !place.daily.isEmpty {
            let metric = telemetry.usesMetricUnits
            let days = Array(place.daily.prefix(5))
            let overallMin = days.map(\.minTemperature).min() ?? 0
            let overallMax = days.map(\.maxTemperature).max() ?? 1
            HStack(spacing: 8) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    VStack(spacing: 6) {
                        Text(index == 0 ? "TODAY" : Formatters.shortWeekday(day.date, timeZone: place.timeZone))
                            .font(theme.typography.data(size: 12))
                            .foregroundStyle(index == 0 ? theme.color(.teal) : theme.palette.mutedText)
                        Image(systemName: WeatherCode.symbol(day.weatherCode))
                            .font(.system(size: 22))
                            .foregroundStyle(theme.color(severityColor(day.weatherCode)))
                            .frame(height: 26)
                        Text(Formatters.temperature(day.maxTemperature, metric: metric))
                            .font(theme.typography.display(size: 18))
                        TemperatureRange(low: day.minTemperature, high: day.maxTemperature, overallLow: overallMin, overallHigh: overallMax)
                            .frame(height: 6)
                        Text(Formatters.temperature(day.minTemperature, metric: metric))
                            .font(theme.typography.data(size: 13))
                            .foregroundStyle(theme.palette.mutedText)
                        HStack(spacing: 3) {
                            Image(systemName: "drop.fill")
                                .font(.system(size: 9))
                                .foregroundStyle(theme.color(.blue))
                            Text("\(Int(day.precipitationProbability))%")
                                .font(theme.typography.data(size: 11))
                                .foregroundStyle(theme.palette.mutedText)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(theme.palette.screen.opacity(index == 0 ? 0.7 : 0.45), in: RoundedRectangle(cornerRadius: theme.metrics.dataRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: theme.metrics.dataRadius, style: .continuous)
                            .stroke(theme.color(.teal).opacity(index == 0 ? 0.5 : 0.18), lineWidth: 1)
                    )
                }
            }
        } else {
            WeatherUnavailable(telemetry: telemetry)
        }
    }
}

/// Horizontal bar placing a day's min…max within the week's range.
struct TemperatureRange: View {
    @Environment(\.astraTheme) private var theme
    var low: Double
    var high: Double
    var overallLow: Double
    var overallHigh: Double

    var body: some View {
        GeometryReader { proxy in
            let span = max(1, overallHigh - overallLow)
            let start = CGFloat((low - overallLow) / span) * proxy.size.width
            let end = CGFloat((high - overallLow) / span) * proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(theme.inactiveCell(.gold))
                Capsule()
                    .fill(LinearGradient(colors: [theme.color(.cyan), theme.color(.gold)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(6, end - start))
                    .offset(x: start)
            }
        }
        .padding(.horizontal, 10)
    }
}

// MARK: - Air quality

struct AirQualityWidget: View {
    @Environment(LiveDataHub.self) private var liveData
    @Environment(\.astraTheme) private var theme

    var body: some View {
        let telemetry = liveData.weather
        if let place = telemetry.primary, let air = place.air {
            HStack(spacing: 14) {
                ConsoleRing(value: Double(air.usAQI) / 300, color: aqiColor(air.usAQI), label: "US AQI")
                    .frame(width: 116, height: 116)
                    .overlay(alignment: .bottom) {
                        Text("\(air.usAQI)")
                            .font(theme.typography.display(size: 12))
                            .foregroundStyle(theme.palette.mutedText)
                            .offset(y: 14)
                    }
                VStack(spacing: 9) {
                    Text(air.category.uppercased())
                        .font(theme.typography.data(size: 13))
                        .foregroundStyle(theme.color(aqiColor(air.usAQI)))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    MetricLine(label: "PM2.5", value: "\(Formatters.fixed(air.pm25)) µg", progress: air.pm25 / 75, color: aqiColor(air.usAQI))
                    MetricLine(label: "PM10", value: "\(Formatters.fixed(air.pm10)) µg", progress: air.pm10 / 150, color: .violet)
                    MetricLine(label: "Ozone", value: "\(Formatters.fixed(air.ozone)) µg", progress: air.ozone / 180, color: .cyan)
                }
            }
        } else {
            WeatherUnavailable(telemetry: telemetry)
        }
    }
}

// MARK: - Sun cycle

struct SunCycleWidget: View {
    @Environment(LiveDataHub.self) private var liveData
    @Environment(\.astraTheme) private var theme

    var body: some View {
        let telemetry = liveData.weather
        if let place = telemetry.primary, let today = place.daily.first {
            let now = liveData.now
            let daylight = today.sunset.timeIntervalSince(today.sunrise)
            VStack(spacing: 8) {
                SunArc(sunrise: today.sunrise, sunset: today.sunset, now: now)
                    .frame(height: 70)
                HStack(spacing: 8) {
                    MicroStat(label: "SUNRISE", value: Formatters.shortTime(today.sunrise, timeZone: place.timeZone), color: .gold)
                    MicroStat(label: "SUNSET", value: Formatters.shortTime(today.sunset, timeZone: place.timeZone), color: .apricot)
                    MicroStat(label: "DAYLIGHT", value: Formatters.duration(daylight), color: .teal)
                }
                Text(nextEvent(today: today, tomorrow: place.daily.dropFirst().first, now: now))
                    .font(theme.typography.systemData(size: 11, weight: .semibold))
                    .foregroundStyle(theme.palette.mutedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            WeatherUnavailable(telemetry: telemetry)
        }
    }

    private func nextEvent(today: WeatherDay, tomorrow: WeatherDay?, now: Date) -> String {
        if now < today.sunrise {
            return "SUNRISE IN \(Formatters.duration(today.sunrise.timeIntervalSince(now)))"
        }
        if now < today.sunset {
            return "SUNSET IN \(Formatters.duration(today.sunset.timeIntervalSince(now)))"
        }
        if let tomorrow {
            return "SUNRISE IN \(Formatters.duration(tomorrow.sunrise.timeIntervalSince(now)))"
        }
        return "NIGHT"
    }
}

/// Day arc with the sun's current position; night shows the moon below
/// the horizon line.
struct SunArc: View {
    @Environment(\.astraTheme) private var theme
    var sunrise: Date
    var sunset: Date
    var now: Date

    var body: some View {
        Canvas { context, size in
            let horizonY = size.height - 10
            let radiusX = size.width / 2 - 14
            let radiusY = size.height - 22
            let center = CGPoint(x: size.width / 2, y: horizonY)

            var arc = Path()
            for step in 0...60 {
                let t = Double(step) / 60
                let angle = Double.pi * (1 - t)
                let point = CGPoint(x: center.x + radiusX * CGFloat(cos(angle)), y: center.y - radiusY * CGFloat(sin(angle)))
                if step == 0 { arc.move(to: point) } else { arc.addLine(to: point) }
            }
            context.stroke(arc, with: .color(theme.color(.gold).opacity(0.35)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))

            var horizon = Path()
            horizon.move(to: CGPoint(x: 0, y: horizonY))
            horizon.addLine(to: CGPoint(x: size.width, y: horizonY))
            context.stroke(horizon, with: .color(theme.palette.text.opacity(0.18)), lineWidth: 1)

            let dayLength = max(1, sunset.timeIntervalSince(sunrise))
            let progress = now.timeIntervalSince(sunrise) / dayLength
            if progress >= 0 && progress <= 1 {
                let angle = Double.pi * (1 - progress)
                let sun = CGPoint(x: center.x + radiusX * CGFloat(cos(angle)), y: center.y - radiusY * CGFloat(sin(angle)))
                context.fill(Path(ellipseIn: CGRect(x: sun.x - 12, y: sun.y - 12, width: 24, height: 24)), with: .color(theme.color(.gold).opacity(0.25)))
                context.fill(Path(ellipseIn: CGRect(x: sun.x - 6, y: sun.y - 6, width: 12, height: 12)), with: .color(theme.color(.gold)))
            } else {
                var moon = context.resolve(Image(systemName: "moon.stars.fill"))
                moon.shading = .color(theme.color(.violet))
                context.draw(moon, in: CGRect(x: center.x - 9, y: horizonY - 30, width: 18, height: 18))
            }
        }
    }
}

// MARK: - Multi-city

struct MultiCityWidget: View {
    @Environment(LiveDataHub.self) private var liveData
    @Environment(\.astraTheme) private var theme

    var body: some View {
        let telemetry = liveData.weather
        if telemetry.locations.isEmpty {
            WeatherUnavailable(telemetry: telemetry)
        } else {
            let metric = telemetry.usesMetricUnits
            VStack(spacing: 6) {
                ForEach(telemetry.locations.prefix(6)) { place in
                    HStack(spacing: 10) {
                        Image(systemName: WeatherCode.symbol(place.current.weatherCode, isDay: place.current.isDay))
                            .font(.system(size: 18))
                            .foregroundStyle(theme.color(severityColor(place.current.weatherCode)))
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(place.location.name.uppercased())
                                .font(theme.typography.display(size: 14, weight: .bold))
                                .lineLimit(1)
                            Text(place.location.region.uppercased())
                                .font(theme.typography.systemData(size: 11, weight: .semibold))
                                .foregroundStyle(theme.palette.mutedText)
                                .lineLimit(1)
                        }
                        .frame(minWidth: 110, alignment: .leading)
                        Text(Formatters.shortTime(liveData.now, timeZone: place.timeZone))
                            .font(theme.typography.data(size: 13))
                            .foregroundStyle(theme.color(.violet))
                            .monospacedDigit()
                        Spacer(minLength: 4)
                        Text(WeatherCode.description(place.current.weatherCode).uppercased())
                            .font(theme.typography.data(size: 12))
                            .foregroundStyle(theme.palette.mutedText)
                            .lineLimit(1)
                        Text(Formatters.windSpeed(place.current.windSpeed, metric: metric))
                            .font(theme.typography.data(size: 12))
                            .foregroundStyle(theme.color(.cyan))
                            .frame(width: 70, alignment: .trailing)
                        Text(Formatters.temperature(place.current.temperature, metric: metric))
                            .font(theme.typography.display(size: 20))
                            .frame(width: 58, alignment: .trailing)
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(theme.palette.panelHighlight.opacity(0.45), in: AstraPartialRoundedRectangle(leadingRadius: 10, trailingRadius: 4))
                }
            }
        }
    }
}
