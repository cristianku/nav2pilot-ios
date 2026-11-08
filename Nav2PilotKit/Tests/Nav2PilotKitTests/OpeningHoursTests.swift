import XCTest
@testable import Nav2PilotKit

private let monday = 0
private let wednesday = 2
private let thursday = 3
private let friday = 4
private let saturday = 5
private let sunday = 6

private let swiss = Locale(identifier: "de_CH")

private var zurich: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Zurich")!
    return calendar
}

// IKEA Pratteln in OpenStreetMap, 7 November 2026
private let ikea = "Mo-We 10:00-20:00; Th-Fr 10:00-21:00; Sa 09:00-20:00"

/// 9 November 2026 is a Monday.
private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    let parts = DateComponents(year: 2026, month: 11, day: 9 + day, hour: hour, minute: minute)
    return zurich.date(from: parts)!
}

/// The same cases as the Android app's OpeningHoursTest.
final class OpeningHoursTests: XCTestCase {
    private func text(_ hours: String, _ now: Date) -> String {
        return OpeningHours.parse(hours)!.statusText(at: now, calendar: zurich, locale: swiss).text
    }

    private func week(_ hours: String) -> [OpeningHours.WeekRow] {
        return OpeningHours.parse(hours)!.weekRows(locale: swiss)
    }

    func testOpenUntilTheEveningThenSoonClosing() {
        XCTAssertEqual("Open · Closes 20:00", text(ikea, at(saturday, 15)))
        XCTAssertEqual("Closes soon · 20:00", text(ikea, at(saturday, 19, 30)))
        XCTAssertEqual("Open · Closes 21:00", text(ikea, at(thursday, 10)))
    }

    func testClosedSaysWhenItOpens() {
        // Saturday night: nothing on Sunday
        XCTAssertEqual("Closed · Opens Mon 10:00", text(ikea, at(saturday, 21)))
        XCTAssertEqual("Closed · Opens tomorrow 10:00", text(ikea, at(sunday, 22)))
        XCTAssertEqual("Closed · Opens 10:00", text(ikea, at(monday, 8)))
        XCTAssertEqual("Opens soon · 10:00", text(ikea, at(monday, 9, 30)))
    }

    func testTheWeekFromMonday() {
        let rows = week(ikea)

        XCTAssertEqual(7, rows.count)
        XCTAssertEqual(OpeningHours.WeekRow(day: "Monday", hours: "10:00–20:00"), rows[monday])
        XCTAssertEqual(OpeningHours.WeekRow(day: "Thursday", hours: "10:00–21:00"), rows[thursday])
        XCTAssertEqual(OpeningHours.WeekRow(day: "Saturday", hours: "09:00–20:00"), rows[saturday])
        XCTAssertEqual(OpeningHours.WeekRow(day: "Sunday", hours: "Closed"), rows[sunday])
    }

    func testAlwaysOpen() {
        for hours in ["24/7", "Mo-Su 00:00-24:00", "24/7; PH off"] {
            let parsed = OpeningHours.parse(hours)!
            XCTAssertTrue(parsed.isAlwaysOpen(), hours)
            XCTAssertEqual("Open 24 hours", parsed.statusText(at: at(wednesday, 3), calendar: zurich, locale: swiss).text)
            XCTAssertEqual("Open 24 hours", parsed.weekRows(locale: swiss)[sunday].hours)
        }
    }

    func testPastMidnightIsTheSameEvening() {
        let bar = "Fr-Sa 18:00-02:00"

        XCTAssertEqual("Open · Closes 02:00", text(bar, at(friday, 23)))
        // Saturday 00:30 is still Friday's night
        XCTAssertEqual("Open · Closes 02:00", text(bar, at(saturday, 0, 30)))
        XCTAssertEqual("Closed · Opens 18:00", text(bar, at(saturday, 3)))
        XCTAssertEqual(OpeningHours.WeekRow(day: "Friday", hours: "18:00–02:00"), week(bar)[friday])
    }

    func testSundayNightGoesOnToMonday() {
        XCTAssertEqual("Open · Closes 02:00", text("Su 22:00-02:00", at(monday, 0, 30)))
        // Sunday until midnight and Monday from midnight: one opening
        XCTAssertEqual("Open · Closes 08:00", text("Mo 00:00-08:00; Su 20:00-24:00", at(sunday, 21)))
        XCTAssertEqual(OpeningHours.WeekRow(day: "Sunday", hours: "20:00–24:00"), week("Mo 00:00-08:00; Su 20:00-24:00")[sunday])
    }

    func testOpenUntilAnotherDayNamesIt() {
        XCTAssertEqual("Open · Closes Wed 18:00", text("Mo 08:00-24:00; Tu 00:00-24:00; We 00:00-18:00", at(monday, 9)))
    }

    func testALaterRuleReplacesTheEarlierOnItsDays() {
        let rows = week("Mo-Fr 08:00-18:00; We off; Fr 08:00-12:00")

        XCTAssertEqual("08:00–18:00", rows[monday].hours)
        XCTAssertEqual("Closed", rows[wednesday].hours)
        XCTAssertEqual("08:00–12:00", rows[friday].hours)
    }

    func testACommaBeforeADayAddsARule() {
        let rows = week("Mo-Fr 08:00-12:00, Sa 09:00-11:00")

        XCTAssertEqual("08:00–12:00", rows[friday].hours)
        XCTAssertEqual("09:00–11:00", rows[saturday].hours)
        XCTAssertEqual("Closed", rows[sunday].hours)
    }

    func testALunchBreak() {
        let hours = "Mo-Fr 08:00-12:00,13:30-18:00; Sa 08:00-12:00"

        XCTAssertEqual("Closed · Opens 13:30", text(hours, at(monday, 12, 15)))
        XCTAssertEqual("Opens soon · 13:30", text(hours, at(monday, 12, 45)))
        XCTAssertEqual("08:00–12:00, 13:30–18:00", week(hours)[monday].hours)
    }

    func testHolidaysAreLeftOut() {
        XCTAssertEqual("09:00–21:00", week("Mo-Sa 09:00-21:00; PH closed")[saturday].hours)

        let sundays = week("Mo-Sa 07:00-20:00; Su,PH off")
        XCTAssertEqual("07:00–20:00", sundays[saturday].hours)
        XCTAssertEqual("Closed", sundays[sunday].hours)

        XCTAssertEqual("07:00–20:00", week("Mo-Su 07:00-20:00; PH 10:00-16:00")[sunday].hours)
    }

    func testCommonLooseSpellings() {
        XCTAssertEqual("08:00–17:00", week("mo-fr: 08:00-17:00")[monday].hours)
        XCTAssertEqual("08:00–17:00", week("Mo-Fr 08:00-17:00 open")[monday].hours)
        // days across the weekend
        let weekend = week("Fr-Mo 10:00-16:00")
        XCTAssertEqual("10:00–16:00", weekend[sunday].hours)
        XCTAssertEqual("10:00–16:00", weekend[monday].hours)
        XCTAssertEqual("Closed", weekend[wednesday].hours)
        // times alone: every day
        XCTAssertEqual("06:00–22:00", week("06:00-22:00")[sunday].hours)
    }

    func testNeverOpen() {
        let parsed = OpeningHours.parse("off")!

        XCTAssertFalse(parsed.status(at: at(monday, 12), calendar: zurich).open)
        XCTAssertEqual("Closed", parsed.statusText(at: at(monday, 12), calendar: zurich, locale: swiss).text)
    }

    func testWhatTheAppDoesNotReadGivesNil() {
        let unread = [
            "",
            "Jan-Mar Mo-Fr 08:00-12:00",
            "Mo-Fr 08:00-18:00 \"by appointment\"",
            "sunrise-sunset",
            "Mo-Fr 08:00+",
            "Mo 25:00-26:00",
            "Mo 10:70-12:00",
            "Mo-Fr 12:00-14:00 off",
            "Mo[1] 10:00-12:00",
        ]
        for hours in unread {
            XCTAssertNil(OpeningHours.parse(hours), hours)
        }
    }

    func testTheTimesAsThePhoneWritesThem() {
        let american = OpeningHours.parse(ikea)!.statusText(at: at(saturday, 15), calendar: zurich, locale: Locale(identifier: "en_US"))

        XCTAssertEqual("Open", american.headline)
        XCTAssertTrue(american.rest.hasPrefix("Closes 8:00") && american.rest.hasSuffix("PM"), american.rest)
        XCTAssertFalse(OpeningHours.parse(ikea)!.weekRows(locale: Locale(identifier: "en_US"))[monday].hours.isEmpty)
    }

    func testTheToneColoursTheHeadline() {
        let hours = OpeningHours.parse(ikea)!

        XCTAssertEqual(.open, hours.statusText(at: at(saturday, 15), calendar: zurich, locale: swiss).tone)
        XCTAssertEqual(.soon, hours.statusText(at: at(saturday, 19, 30), calendar: zurich, locale: swiss).tone)
        XCTAssertEqual(.closed, hours.statusText(at: at(saturday, 21), calendar: zurich, locale: swiss).tone)
    }

    func testTheClockOfTheCalendarCounts() {
        // 14:00 in UTC is 15:00 in Zurich on a November Saturday
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let saturdayAfternoon = at(saturday, 15)

        XCTAssertEqual(OpeningHours.Status(open: true, changeInMinutes: 300), OpeningHours.parse(ikea)!.status(at: saturdayAfternoon, calendar: zurich))
        XCTAssertEqual(OpeningHours.Status(open: true, changeInMinutes: 360), OpeningHours.parse(ikea)!.status(at: saturdayAfternoon, calendar: utc))
    }
}
