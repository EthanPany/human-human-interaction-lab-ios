import SwiftUI

/// Search, filters and grouping for the People list. Pure: the list view
/// owns one and asks it for the sections to show.
struct PeopleQuery: Equatable {
    enum Match: String, CaseIterable, Identifiable {
        case all, matched, notMatched
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "Everyone"
            case .matched: return "Matches"
            case .notMatched: return "Not matches"
            }
        }
    }

    enum Dates: String, CaseIterable, Identifiable {
        case any, today, week, month, custom
        var id: String { rawValue }
        var title: String {
            switch self {
            case .any: return "Any time"
            case .today: return "Today"
            case .week: return "Last 7 days"
            case .month: return "Last 30 days"
            case .custom: return "Custom range"
            }
        }
    }

    enum Grouping: String, CaseIterable, Identifiable {
        case none, event, date, match
        var id: String { rawValue }
        var title: String {
            switch self {
            case .none: return "None"
            case .event: return "Event"
            case .date: return "Date"
            case .match: return "Match strength"
            }
        }
    }

    var match: Match = .all
    var metInPerson = false
    var sharedInfo = false
    var dates: Dates = .any
    var from = Calendar.current.date(byAdding: .day, value: -7, to: .now) ?? .now
    var to = Date.now

    /// Anything narrowing the list (grouping and search don't count).
    var isFiltering: Bool { match != .all || metInPerson || sharedInfo || dates != .any }

    mutating func clear() {
        match = .all
        metInPerson = false
        sharedInfo = false
        dates = .any
    }

    /// Short words for the active filters ("Matches", "Met in person", ...).
    var activeLabels: [String] {
        var out: [String] = []
        if match != .all { out.append(match.title) }
        if metInPerson { out.append("Met in person") }
        if sharedInfo { out.append("Shared info") }
        if dates == .custom {
            out.append("\(from.formatted(date: .abbreviated, time: .omitted)) to \(to.formatted(date: .abbreviated, time: .omitted))")
        } else if dates != .any {
            out.append(dates.title)
        }
        return out
    }

    // MARK: Filtering

    func apply(_ people: [PersonSummary], search: String, now: Date = .now) -> [PersonSummary] {
        let words = search.split(whereSeparator: \.isWhitespace).map(String.init)
        let range = dateRange(now: now)
        return people.filter { p in
            switch match {
            case .all: break
            case .matched: if p.matched != true { return false }
            case .notMatched: if p.matched == true { return false }
            }
            if metInPerson && p.metAt == nil { return false }
            if sharedInfo && p.sharedWithMe != true && p.sharedByMe != true { return false }
            if let range, !range.contains(Self.when(p)) { return false }
            return words.allSatisfy { word in Self.searchText(p).localizedStandardContains(word) }
        }
    }

    /// When someone counts as met: first time in person, else when they joined the list.
    static func when(_ p: PersonSummary) -> Date { p.metDate ?? p.connectedDate }

    /// Name, role, company, tags, topics and notes (every summary).
    static func searchText(_ p: PersonSummary) -> String {
        ([p.name, p.headline, p.company, p.location, p.lastSummary, p.notes].compactMap { $0 }
            + p.tags + (p.topics ?? [])).joined(separator: " ")
    }

    private func dateRange(now: Date) -> ClosedRange<Date>? {
        let calendar = Calendar.current
        switch dates {
        case .any: return nil
        case .today: return calendar.startOfDay(for: now)...now.addingTimeInterval(60)
        case .week: return (calendar.date(byAdding: .day, value: -7, to: now) ?? now)...now.addingTimeInterval(60)
        case .month: return (calendar.date(byAdding: .day, value: -30, to: now) ?? now)...now.addingTimeInterval(60)
        case .custom:
            let start = calendar.startOfDay(for: min(from, to))
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: max(from, to))) ?? max(from, to)
            return start...end
        }
    }

    // MARK: Grouping

    struct Group: Identifiable {
        let id: String
        let title: String?
        let people: [PersonSummary]
    }

    /// Meetings more than this far apart are separate events.
    static let eventGap: TimeInterval = 6 * 3600

    func groups(_ people: [PersonSummary], by grouping: Grouping, now: Date = .now) -> [Group] {
        switch grouping {
        case .none:
            return [Group(id: "all", title: nil, people: people)]
        case .date:
            let calendar = Calendar.current
            let byDay = Dictionary(grouping: people) { calendar.startOfDay(for: Self.when($0)) }
            return byDay.keys.sorted(by: >).map { day in
                Group(id: "day-\(day.timeIntervalSince1970)", title: Self.dayTitle(day, now: now),
                      people: byDay[day]!.sorted { Self.when($0) > Self.when($1) })
            }
        case .event:
            return Self.events(people)
        case .match:
            let order: [(String, (PersonSummary) -> Bool)] = [
                ("Strong match", { ($0.matchScore ?? 0) >= 0.7 }),
                ("Match", { $0.matched == true }),
                ("Not a match", { $0.matched == false || $0.matchScore != nil }),
                ("Not scored yet", { _ in true }),
            ]
            var left = people
            var out: [Group] = []
            for (title, test) in order {
                let picked = left.filter(test).sorted { ($0.matchScore ?? 0) > ($1.matchScore ?? 0) }
                left.removeAll(where: test)
                if !picked.isEmpty { out.append(Group(id: title, title: title, people: picked)) }
            }
            return out
        }
    }

    /// Events: people met close together in time (no gap over 6 hours), newest
    /// first. People never met in person go last.
    static func events(_ people: [PersonSummary]) -> [Group] {
        let met = people.filter { $0.metAt != nil }.sorted { when($0) < when($1) }
        var clusters: [[PersonSummary]] = []
        for p in met {
            if let last = clusters.last?.last, when(p).timeIntervalSince(when(last)) <= eventGap {
                clusters[clusters.count - 1].append(p)
            } else {
                clusters.append([p])
            }
        }
        var out = clusters.reversed().map { cluster -> Group in
            let start = when(cluster.first!)
            let end = when(cluster.last!)
            let day = start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            let hours = "\(start.formatted(date: .omitted, time: .shortened)) to \(end.formatted(date: .omitted, time: .shortened))"
            return Group(id: "event-\(start.timeIntervalSince1970)",
                         title: cluster.count > 1 ? "Event, \(day), \(hours)" : "Event, \(day)",
                         people: cluster.reversed())
        }
        let notMet = people.filter { $0.metAt == nil }
        if !notMet.isEmpty { out.append(Group(id: "not-met", title: "Not met in person", people: notMet)) }
        return out
    }

    static func dayTitle(_ day: Date, now: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return day.formatted(date: .complete, time: .omitted)
    }
}

/// The filter and group by menu in the People toolbar.
struct PeopleFilterMenu: View {
    @Binding var query: PeopleQuery
    @Binding var grouping: PeopleQuery.Grouping
    @Binding var showCustomDates: Bool

    var body: some View {
        Menu {
            Picker("Show", selection: $query.match) {
                ForEach(PeopleQuery.Match.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Met in person", systemImage: "figure.wave", isOn: $query.metInPerson)
            Toggle("Has shared info", systemImage: "person.crop.rectangle.stack", isOn: $query.sharedInfo)
            Menu("When: \(query.dates.title)", systemImage: "calendar") {
                Picker("When", selection: Binding(
                    get: { query.dates },
                    set: { value in
                        query.dates = value
                        if value == .custom { showCustomDates = true }
                    }
                )) {
                    ForEach(PeopleQuery.Dates.allCases) { Text($0.title).tag($0) }
                }
            }
            Menu("Group by: \(grouping.title)", systemImage: "square.stack") {
                Picker("Group by", selection: $grouping) {
                    ForEach(PeopleQuery.Grouping.allCases) { Text($0.title).tag($0) }
                }
            }
            if query.isFiltering {
                Button("Clear filters", systemImage: "xmark.circle", role: .destructive) { query.clear() }
            }
        } label: {
            Label("Filter and group",
                  systemImage: query.isFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
        .onChange(of: query) { Feedback.shared.play(.tap) }
        .onChange(of: grouping) { Feedback.shared.play(.tap) }
        .accessibilityIdentifier("Filter and group")
    }
}

/// Custom date range for the People filter.
struct PeopleDateRangeSheet: View {
    @Binding var query: PeopleQuery
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("From", selection: $query.from, displayedComponents: .date)
                DatePicker("To", selection: $query.to, in: query.from..., displayedComponents: .date)
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle("Met between")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}
