import Foundation

enum ExpiryFormatting {
    static func resetDeadline(
        _ date: Date,
        now: Date = Date(),
        locale: Locale = Locale(identifier: "en_GB"),
        timeZone: TimeZone = .autoupdatingCurrent,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        let interval = date.timeIntervalSince(now)
        guard interval > 0 else {
            return "Expired"
        }

        if interval < 86_400 {
            let totalMinutes = max(1, Int(ceil(interval / 60)))
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60

            if hours == 0 {
                return "in \(minutes) \(minutes == 1 ? "minute" : "minutes")"
            }
            if minutes == 0 {
                return "in \(hours) \(hours == 1 ? "hour" : "hours")"
            }
            return "in \(hours) \(hours == 1 ? "hour" : "hours") \(minutes) \(minutes == 1 ? "minute" : "minutes")"
        }

        let includeYear = calendar.component(.year, from: date)
            != calendar.component(.year, from: now)
        let day = formatted(
            date,
            template: includeYear ? "d MMMM yyyy" : "d MMMM",
            locale: locale,
            timeZone: timeZone,
            calendar: calendar
        )
        let time = formatted(
            date,
            template: "HH:mm",
            locale: locale,
            timeZone: timeZone,
            calendar: calendar
        )
        return "\(day) at \(time)"
    }

    static func compactDeadline(
        _ date: Date,
        now: Date = Date(),
        locale: Locale = Locale(identifier: "en_GB"),
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        let interval = date.timeIntervalSince(now)
        guard interval > 0 else {
            return "now"
        }

        if interval < 3_600 {
            let totalSeconds = max(1, Int(ceil(interval)))
            let minutes = totalSeconds / 60
            let seconds = totalSeconds % 60
            return minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
        }
        if interval < 86_400 {
            let totalMinutes = max(1, Int(ceil(interval / 60)))
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
        }
        if interval <= 2 * 86_400 {
            let totalHours = max(24, Int(interval / 3_600))
            let days = totalHours / 24
            let hours = totalHours % 24
            return hours == 0 ? "\(days)d" : "\(days)d \(hours)h"
        }
        return formatted(
            date,
            template: "d MMM",
            locale: locale,
            timeZone: timeZone
        )
    }

    static func usageReset(
        _ date: Date,
        locale: Locale = Locale(identifier: "en_GB"),
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        let day = formatted(
            date,
            template: "d MMMM",
            locale: locale,
            timeZone: timeZone
        )
        let time = formatted(
            date,
            template: "HH:mm",
            locale: locale,
            timeZone: timeZone
        )
        return "\(day) at \(time)"
    }

    static func lastUpdated(
        _ date: Date,
        now: Date = Date(),
        locale: Locale = Locale(identifier: "en_GB")
    ) -> String {
        let elapsed = max(0, now.timeIntervalSince(date))
        if elapsed < 60 {
            return "Updated now"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        return "Updated \(formatter.localizedString(for: date, relativeTo: now))"
    }

    private static func formatted(
        _ date: Date,
        template: String,
        locale: Locale,
        timeZone: TimeZone,
        calendar: Calendar = .autoupdatingCurrent
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.calendar = calendar
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}
