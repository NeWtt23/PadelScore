import Foundation

enum Team: Int, Codable {
    case us = 0
    case them = 1

    var other: Team { self == .us ? .them : .us }
}

struct MatchSettings: Codable, Equatable {
    var goldenPoint: Bool = false   // true = punto de oro, false = con ventajas
    var setsToWin: Int = 2          // 1 = un solo set, 2 = al mejor de 3
}

struct MatchState: Codable, Equatable {
    var points = [0, 0]
    var games = [0, 0]
    var sets = [0, 0]
    var finishedSets: [[Int]] = []
    var inTiebreak = false
    var winner: Team? = nil
}

final class PadelScorer: ObservableObject {
    @Published private(set) var state = MatchState()
    @Published var settings = MatchSettings() {
        didSet { save() }
    }

    private var history: [MatchState] = []
    private let stateKey = "matchState"
    private let settingsKey = "matchSettings"

    init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: stateKey),
           let saved = try? JSONDecoder().decode(MatchState.self, from: data) {
            state = saved
        }
        if let data = defaults.data(forKey: settingsKey),
           let saved = try? JSONDecoder().decode(MatchSettings.self, from: data) {
            settings = saved
        }
    }

    // MARK: - Acciones

    func point(for team: Team) {
        guard state.winner == nil else { return }
        history.append(state)
        if history.count > 500 { history.removeFirst() }

        var s = state
        let t = team.rawValue
        let o = team.other.rawValue
        s.points[t] += 1

        if s.inTiebreak {
            if s.points[t] >= 7 && s.points[t] - s.points[o] >= 2 {
                winGame(&s, team)
            }
        } else if settings.goldenPoint {
            if s.points[t] >= 4 {
                winGame(&s, team)
            }
        } else {
            if s.points[t] >= 4 && s.points[t] - s.points[o] >= 2 {
                winGame(&s, team)
            } else if s.points[t] >= 4 && s.points[t] == s.points[o] {
                s.points = [3, 3] // vuelve a iguales
            }
        }

        state = s
        save()
    }

    func undo() {
        guard let last = history.popLast() else { return }
        state = last
        save()
    }

    func reset() {
        history.removeAll()
        state = MatchState()
        save()
    }

    private func winGame(_ s: inout MatchState, _ team: Team) {
        let t = team.rawValue
        let o = team.other.rawValue
        s.points = [0, 0]
        s.games[t] += 1

        let setWon: Bool
        if s.inTiebreak {
            setWon = true
        } else {
            setWon = s.games[t] >= 6 && s.games[t] - s.games[o] >= 2
        }

        if setWon {
            s.finishedSets.append(s.games)
            s.sets[t] += 1
            s.games = [0, 0]
            s.inTiebreak = false
            if s.sets[t] >= settings.setsToWin {
                s.winner = team
            }
        } else if s.games[0] == 6 && s.games[1] == 6 {
            s.inTiebreak = true
        }
    }

    // MARK: - Textos

    func pointText(_ team: Team) -> String {
        let t = state.points[team.rawValue]
        let o = state.points[team.other.rawValue]
        if state.inTiebreak { return "\(t)" }
        if t >= 3 && o >= 3 {
            if t == o { return "40" }
            return t > o ? "AD" : "40"
        }
        return ["0", "15", "30", "40"][min(t, 3)]
    }

    var setsLine: String {
        state.finishedSets.map { "\($0[0])-\($0[1])" }.joined(separator: " ")
    }

    /// Texto corto que se muestra en el reloj.
    var summary: String {
        if let w = state.winner {
            return (w == .us ? "GANAMOS " : "Perdimos ") + setsLine
        }
        var pts = "\(pointText(.us))-\(pointText(.them))"
        if state.inTiebreak {
            pts += " TB"
        } else if settings.goldenPoint && state.points == [3, 3] {
            pts += " ORO"
        }
        return "\(pts) | \(state.games[0])-\(state.games[1]) | S \(state.sets[0])-\(state.sets[1])"
    }

    private func save() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: stateKey) }
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: settingsKey) }
    }
}
