import Foundation

/// OpenStreetMap's opening_hours, the part almost every shop uses: weekdays ("Mo-Fr", "Sa,Su", "Fr-Mo"), times
/// ("08:00-12:00,13:30-18:00", past midnight as "22:00-02:00"), "24/7", "off" or "closed", rules separated by ";"
/// where a later rule replaces the earlier ones on its days. Public and school holidays (PH, SH) are left out.
///
/// Anything else (months, dates, sunrise, open ends, comments) makes `parse` give nil: the app then shows the text
/// as OpenStreetMap has it, rather than a guess. The same reader as the Android app's.
public struct OpeningHours {
    /// For each weekday from Monday, its openings in minutes from its midnight; an end past 1440 is the next day.
    private let days: [[Span]]
    // the whole week in minutes from Monday 00:00, an opening over midnight as one; Sunday night goes on to Monday
    private let week: [Span]

    private init(days: [[Span]]) {
        self.days = days
        self.week = OpeningHours.weekSpans(days)
    }

    public func isAlwaysOpen() -> Bool {
        return week.count == 1 && week[0].start == 0 && week[0].end == OpeningHours.weekMinutes
    }

    /// Open or closed at `date` on the clock of `calendar`, and for how long.
    public func status(at date: Date, calendar: Calendar = .current) -> Status {
        return status(atMinute: OpeningHours.minuteOfWeek(date, calendar))
    }

    /// "Open · Closes 20:00", "Closed · Opens Mon 10:00" and the like, the times as the phone writes them.
    public func statusText(at date: Date, calendar: Calendar = .current, locale: Locale = .current) -> StatusText {
        let minute = OpeningHours.minuteOfWeek(date, calendar)
        let status = status(atMinute: minute)
        guard let inMinutes = status.changeInMinutes else {
            if status.open {
                return StatusText(tone: .open, headline: "Open 24 hours", rest: "")
            }
            return StatusText(tone: .closed, headline: "Closed", rest: "")
        }
        // counted on the week, not on the calendar: a change of summer time does not move a shop's hours
        let change = minute + inMinutes
        let formatter = OpeningHours.timeFormatter(locale)
        let time = OpeningHours.time(change % OpeningHours.dayMinutes, formatter)
        let day = OpeningHours.shortDays[(change / OpeningHours.dayMinutes) % 7]
        if status.open {
            if inMinutes <= OpeningHours.soonMinutes {
                return StatusText(tone: .soon, headline: "Closes soon", rest: time)
            }
            // closing after midnight is still tonight's closing
            if inMinutes < OpeningHours.dayMinutes {
                return StatusText(tone: .open, headline: "Open", rest: "Closes " + time)
            }
            return StatusText(tone: .open, headline: "Open", rest: "Closes " + day + " " + time)
        }
        if inMinutes <= OpeningHours.soonMinutes {
            return StatusText(tone: .soon, headline: "Opens soon", rest: time)
        }
        let daysAhead = change / OpeningHours.dayMinutes - minute / OpeningHours.dayMinutes
        if daysAhead == 0 {
            return StatusText(tone: .closed, headline: "Closed", rest: "Opens " + time)
        }
        if daysAhead == 1 {
            return StatusText(tone: .closed, headline: "Closed", rest: "Opens tomorrow " + time)
        }
        return StatusText(tone: .closed, headline: "Closed", rest: "Opens " + day + " " + time)
    }

    /// Monday to Sunday: the day's name and its times, "10:00–20:00", "Closed" or "Open 24 hours".
    public func weekRows(locale: Locale = .current) -> [WeekRow] {
        let formatter = OpeningHours.timeFormatter(locale)
        var rows: [WeekRow] = []
        for day in 0..<7 {
            let spans = days[day]
            var text = "Closed"
            if spans.count == 1 && spans[0].start == 0 && spans[0].end >= OpeningHours.dayMinutes {
                text = "Open 24 hours"
            } else if !spans.isEmpty {
                var parts: [String] = []
                for span in spans {
                    parts.append(OpeningHours.time(span.start, formatter) + "–" + OpeningHours.time(span.end, formatter))
                }
                text = parts.joined(separator: ", ")
            }
            rows.append(WeekRow(day: OpeningHours.dayNames[day], hours: text))
        }
        return rows
    }

    /// Open or closed, and in how many minutes that changes; nil when it never does.
    public struct Status: Equatable {
        public let open: Bool
        public let changeInMinutes: Int?
    }

    /// `headline` in the colour of `tone`, then `rest`: "Open" and "Closes 20:00".
    public struct StatusText: Equatable {
        public enum Tone {
            case open
            case soon
            case closed
        }

        public let tone: Tone
        public let headline: String
        public let rest: String

        /// "Open · Closes 20:00", or the headline alone.
        public var text: String {
            if rest.isEmpty {
                return headline
            }
            return headline + " · " + rest
        }
    }

    /// One day of the week and its times, as the details show them.
    public struct WeekRow: Equatable {
        public let day: String
        public let hours: String
    }

    /// From `start` to `end` minutes, the end not included.
    private struct Span {
        let start: Int
        let end: Int
    }

    private static let dayMinutes = 24 * 60
    private static let weekMinutes = 7 * dayMinutes

    // within an hour of closing or opening, as Google Maps says it
    private static let soonMinutes = 60

    private static let dayCodes = ["mo", "tu", "we", "th", "fr", "sa", "su"]
    private static let holidayCodes = ["ph", "sh"]
    private static let shortDays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    private static let dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    private static let token = Pattern(#"24/7|[0-9]{1,2}:[0-9]{2}|[A-Za-z]+|\|\||\S"#)

    /// The opening hours in `text`, or nil when it uses more of the format than this app reads.
    public static func parse(_ text: String) -> OpeningHours? {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nil
        }
        var days: [[Span]] = Array(repeating: [], count: 7)
        var tokens: [String] = []
        for match in token.allMatches(text) {
            tokens.append(match.value)
        }
        tokens.append(";")
        var rule: [String] = []
        for token in tokens {
            // "||" is a fallback rule: read like the others
            if token == ";" || token == "||" {
                if !rule.isEmpty {
                    var reader = RuleReader(tokens: rule)
                    if !reader.apply(to: &days) {
                        return nil
                    }
                }
                rule = []
            } else {
                rule.append(token)
            }
        }
        var sorted: [[Span]] = []
        for spans in days {
            sorted.append(spans.sorted { first, second in
                return first.start < second.start
            })
        }
        return OpeningHours(days: sorted)
    }

    private func status(atMinute minute: Int) -> Status {
        if isAlwaysOpen() {
            return Status(open: true, changeInMinutes: nil)
        }
        if week.isEmpty {
            return Status(open: false, changeInMinutes: nil)
        }
        for span in week {
            if minute >= span.start && minute < span.end {
                var end = span.end
                // open on Sunday night: until Monday's first closing
                if end == OpeningHours.weekMinutes && week[0].start == 0 {
                    end = OpeningHours.weekMinutes + week[0].end
                }
                return Status(open: true, changeInMinutes: end - minute)
            }
        }
        for span in week {
            if span.start > minute {
                return Status(open: false, changeInMinutes: span.start - minute)
            }
        }
        return Status(open: false, changeInMinutes: OpeningHours.weekMinutes - minute + week[0].start)
    }

    /// Minutes from Monday 00:00 on the clock of `calendar`.
    private static func minuteOfWeek(_ date: Date, _ calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        // weekday 1 is Sunday in every calendar Foundation has
        let day = ((parts.weekday ?? 2) + 5) % 7
        return day * dayMinutes + (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// The openings of the whole week from Monday 00:00, overlapping and touching ones merged.
    private static func weekSpans(_ days: [[Span]]) -> [Span] {
        var spans: [Span] = []
        for day in 0..<7 {
            for span in days[day] {
                let start = day * dayMinutes + span.start
                let end = day * dayMinutes + span.end
                if end > weekMinutes {
                    spans.append(Span(start: start, end: weekMinutes))
                    spans.append(Span(start: 0, end: end - weekMinutes))
                } else {
                    spans.append(Span(start: start, end: end))
                }
            }
        }
        spans.sort { first, second in
            return first.start < second.start
        }
        var merged: [Span] = []
        for span in spans {
            if let last = merged.last, span.start <= last.end {
                merged[merged.count - 1] = Span(start: last.start, end: max(last.end, span.end))
            } else {
                merged.append(span)
            }
        }
        return merged
    }

    /// The short time style of `locale`: "20:00" in Switzerland, "8:00 PM" in the United States.
    private static func timeFormatter(_ locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }

    private static func time(_ minuteOfDay: Int, _ formatter: DateFormatter) -> String {
        let minute = minuteOfDay % dayMinutes
        let text = formatter.string(from: Date(timeIntervalSince1970: TimeInterval(minute * 60)))
        // the midnight that ends a day: "20:00–24:00", not "20:00–00:00"
        if minuteOfDay == dayMinutes && (text == "00:00" || text == "0:00") {
            return "24:00"
        }
        return text
    }

    /// One rule between semicolons. Its first part replaces the times of its days; a part after a comma that
    /// starts with a day ("Mo-Fr 08:00-12:00, Sa 09:00-12:00") adds to the times of its own.
    private struct RuleReader {
        let tokens: [String]
        private var index = 0

        init(tokens: [String]) {
            self.tokens = tokens
        }

        /// False when the rule cannot be read.
        mutating func apply(to days: inout [[Span]]) -> Bool {
            var first = true
            while true {
                guard let part = readPart() else {
                    return false
                }
                for day in part.days {
                    if first {
                        days[day] = []
                    }
                    days[day].append(contentsOf: part.spans)
                }
                if index >= tokens.count {
                    return true
                }
                if tokens[index] != "," || !isDay(peek(1)) {
                    return false
                }
                index += 1
                first = false
            }
        }

        private struct Part {
            let days: [Int]
            let spans: [Span]
        }

        private mutating func readPart() -> Part? {
            // the days: none at all means every day; holidays alone, none the app can tell
            var days: [Int] = []
            var named = false
            while isDay(peek(0)) {
                named = true
                let code = tokens[index].lowercased()
                index += 1
                if OpeningHours.holidayCodes.contains(code) {
                    // nothing
                } else if peek(0) == "-", let endCode = peek(1)?.lowercased(), let end = OpeningHours.dayCodes.firstIndex(of: endCode) {
                    index += 2
                    var day = OpeningHours.dayCodes.firstIndex(of: code) ?? 0
                    days.append(day)
                    while day != end {
                        day = (day + 1) % 7
                        days.append(day)
                    }
                } else if let day = OpeningHours.dayCodes.firstIndex(of: code) {
                    days.append(day)
                }
                // a comma between days, not the one before the next part's days after some times
                if peek(0) == "," && isDay(peek(1)) {
                    index += 1
                } else {
                    break
                }
            }
            if !named {
                days = Array(0..<7)
            }
            // "Mo-Fr: 08:00-18:00" is often written so
            if peek(0) == ":" {
                index += 1
            }

            var spans: [Span] = []
            if peek(0) == "24/7" {
                index += 1
                spans.append(Span(start: 0, end: OpeningHours.dayMinutes))
            } else if isTime(peek(0)) {
                while true {
                    guard let span = readSpan() else {
                        return nil
                    }
                    spans.append(span)
                    if peek(0) == "," && isTime(peek(1)) {
                        index += 1
                    } else {
                        break
                    }
                }
            }

            let word = peek(0)?.lowercased()
            if word == "off" || word == "closed" {
                index += 1
                // closing a part of a day is rare, and not worth a guess
                if !spans.isEmpty {
                    return nil
                }
                return Part(days: distinct(days), spans: [])
            }
            if word == "open" {
                index += 1
            }
            if spans.isEmpty {
                // "Mo-Fr" alone is the whole day; a rule with neither days nor times is not one this app reads
                if !named {
                    return nil
                }
                spans.append(Span(start: 0, end: OpeningHours.dayMinutes))
            }
            return Part(days: distinct(days), spans: spans)
        }

        private mutating func readSpan() -> Span? {
            if !isTime(peek(0)) || peek(1) != "-" || !isTime(peek(2)) {
                return nil
            }
            let startMinutes = minutes(tokens[index])
            let endMinutes = minutes(tokens[index + 2])
            index += 3
            guard let start = startMinutes, var end = endMinutes else {
                return nil
            }
            if start >= OpeningHours.dayMinutes || end > 2 * OpeningHours.dayMinutes {
                return nil
            }
            if end <= start {
                end += OpeningHours.dayMinutes
            }
            return Span(start: start, end: end)
        }

        private func peek(_ ahead: Int) -> String? {
            let position = index + ahead
            if position < 0 || position >= tokens.count {
                return nil
            }
            return tokens[position]
        }

        private func isDay(_ token: String?) -> Bool {
            guard let code = token?.lowercased() else {
                return false
            }
            return OpeningHours.dayCodes.contains(code) || OpeningHours.holidayCodes.contains(code)
        }

        private func isTime(_ token: String?) -> Bool {
            guard let token = token, token.count >= 4, let first = token.first else {
                return false
            }
            return first.isASCII && first.isNumber && token.contains(":")
        }

        private func minutes(_ time: String) -> Int? {
            let parts = time.split(separator: ":")
            if parts.count != 2 {
                return nil
            }
            guard let hour = Int(parts[0]), let minute = Int(parts[1]) else {
                return nil
            }
            if minute >= 60 {
                return nil
            }
            return hour * 60 + minute
        }

        private func distinct(_ days: [Int]) -> [Int] {
            var result: [Int] = []
            for day in days {
                if !result.contains(day) {
                    result.append(day)
                }
            }
            return result
        }
    }
}
