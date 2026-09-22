import SwiftUI

@main
struct PadelApp: App {
    @StateObject private var scorer: PadelScorer
    @StateObject private var remote: RemoteController

    init() {
        let s = PadelScorer()
        _scorer = StateObject(wrappedValue: s)
        _remote = StateObject(wrappedValue: RemoteController(scorer: s))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(scorer)
                .environmentObject(remote)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var scorer: PadelScorer
    @EnvironmentObject var remote: RemoteController
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    scoreboard

                    Text(remote.active
                         ? "Reloj activo: Siguiente = Nosotros · Anterior = Ellos · Play/Pausa = Deshacer"
                         : "Tocá «Empezar» para controlar el marcador desde el reloj")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 12) {
                        Button { remote.addPoint(.us) } label: {
                            Text("+ Nosotros").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)

                        Button { remote.addPoint(.them) } label: {
                            Text("+ Ellos").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                    .controlSize(.large)

                    Button("Deshacer último punto") { remote.undo() }
                        .buttonStyle(.bordered)

                    Button {
                        if remote.active { remote.stop() } else { remote.start() }
                    } label: {
                        Text(remote.active ? "Detener control desde el reloj" : "Empezar (control desde el reloj)")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    settingsBox

                    Button("Nuevo partido", role: .destructive) { confirmReset = true }
                }
                .padding()
            }
            .navigationTitle("Marcador de pádel")
            .confirmationDialog("¿Empezar un partido nuevo?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Sí, reiniciar", role: .destructive) { remote.reset() }
            }
        }
    }

    private var scoreboard: some View {
        VStack(spacing: 8) {
            if let w = scorer.state.winner {
                Text(w == .us ? "¡Ganaron! 🏆" : "Partido perdido")
                    .font(.title.bold())
            }
            HStack {
                teamColumn("Nosotros", .us)
                Divider().frame(height: 120)
                teamColumn("Ellos", .them)
            }
            if scorer.state.inTiebreak {
                Text("TIE-BREAK").font(.headline).foregroundStyle(.red)
            }
            if !scorer.state.finishedSets.isEmpty {
                Text("Sets: " + scorer.setsLine).font(.subheadline)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func teamColumn(_ name: String, _ team: Team) -> some View {
        VStack(spacing: 4) {
            Text(name).font(.headline)
            Text(scorer.pointText(team))
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text("Games \(scorer.state.games[team.rawValue])").font(.subheadline)
            Text("Sets \(scorer.state.sets[team.rawValue])")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var settingsBox: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Punto de oro (sin ventajas)", isOn: $scorer.settings.goldenPoint)
            Picker("Partido", selection: $scorer.settings.setsToWin) {
                Text("1 set").tag(1)
                Text("Al mejor de 3").tag(2)
            }
            .pickerStyle(.segmented)
            Toggle("Avisar al reloj con notificación", isOn: $remote.notificationsOn)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
