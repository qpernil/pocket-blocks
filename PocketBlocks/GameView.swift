import SwiftUI
import Combine
import UIKit

private enum Palette {
    static let paper = Color(red: 0.96, green: 0.95, blue: 0.91)
    static let ink = Color(red: 0.13, green: 0.19, blue: 0.23)
    static let board = Color(red: 0.10, green: 0.15, blue: 0.19)
    static let accent = Color(red: 0.85, green: 0.28, blue: 0.17)
    static let bricks: [Color] = [.clear,
        Color(red: 0.39, green: 0.80, blue: 0.84),
        Color(red: 0.98, green: 0.79, blue: 0.35),
        Color(red: 0.73, green: 0.60, blue: 0.90),
        Color(red: 0.57, green: 0.77, blue: 0.51),
        Color(red: 0.94, green: 0.47, blue: 0.43),
        Color(red: 0.43, green: 0.60, blue: 0.90),
        Color(red: 0.97, green: 0.64, blue: 0.36)]
}

@MainActor struct GameView: View {
    @State private var game = GameEngine(best: UserDefaults.standard.integer(forKey: "bestScore"))
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("soundEnabled") private var soundEnabled = true
    private let sounds = GameSounds.shared
    @State private var lastTick = Date()
    @State private var gesturePiece: Int?
    @State private var horizontalSteps = 0
    @State private var gestureIsVertical = false
    @State private var gestureDidTravel = false
    private let timer = Timer.publish(every: 1.0 / 60, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 8) {
                header.frame(height: 46)
                GeometryReader { boardArea in
                    let size = boardArea.size
                    ZStack {
                        board
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .contentShape(Rectangle())
                            .gesture(touchControls(width: size.width))
                            .accessibilityLabel("Game board")
                            .accessibilityValue("\(game.lines) lines cleared, score \(game.score)")
                        if game.phase != .playing { overlay(size: size) }
                    }
                }
                controls.frame(height: 40)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .background(Palette.paper.ignoresSafeArea())
        .preferredColorScheme(.light)
        .onReceive(timer) { now in
            game.tick(now.timeIntervalSince(lastTick)); lastTick = now
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { game.pause(); resetGesture(); sounds.stopAll() }
            lastTick = Date()
        }
        .onChange(of: game.best) { _, value in UserDefaults.standard.set(value, forKey: "bestScore") }
        .onChange(of: game.lockEvent) { _, _ in
            sounds.stopFall()
            playSound(.land)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        .onChange(of: game.isDropping) { _, dropping in
            if dropping && soundEnabled && scenePhase == .active {
                sounds.playFall(duration: game.fastDropDuration)
            } else { sounds.stopFall() }
        }
        .onChange(of: game.lines) { previous, current in
            if current > previous { playSound(current - previous >= 4 ? .clearFour : .clear) }
        }
        .onChange(of: game.phase) { _, phase in
            if phase == .over { sounds.stopFall(); playSound(.gameOver) }
            if phase == .paused { sounds.stopAll() }
        }
        .onChange(of: soundEnabled) { _, enabled in
            sounds.setEnabled(enabled)
            if enabled { playSound(.rotate) }
        }
        .onChange(of: game.clearEvent) { _, _ in UINotificationFeedbackGenerator().notificationOccurred(.success) }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("blocks.").font(.system(size: 22, weight: .black, design: .rounded)).tracking(-1)
                Text("BEST \(game.best.formatted())")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
            }
            .lineLimit(1).minimumScaleFactor(0.65)
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
            stat("SCORE", game.score.formatted())
            stat("LINES", String(game.lines))
            stat(game.level == GameEngine.maximumLevel ? "LV MAX" : "LV", String(game.level))
            nextPiece
            Button {
                if game.phase == .playing { game.pause() }
                else if game.phase == .paused { game.resume() }
                resetGesture()
            } label: {
                Image(systemName: game.phase == .paused ? "play.fill" : "pause.fill")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 44, height: 44)
            }
            .disabled(game.phase == .ready || game.phase == .over)
            .accessibilityLabel(game.phase == .paused ? "Resume game" : "Pause game")
        }
        .foregroundStyle(Palette.ink)
    }

    private var nextPiece: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text("NEXT").font(.system(size: 8, weight: .bold, design: .monospaced))
            Canvas { context, size in
                let cells = game.next.cells
                let minX = cells.map(\.x).min() ?? 0
                let maxX = cells.map(\.x).max() ?? 0
                let minY = cells.map(\.y).min() ?? 0
                let side: CGFloat = 8
                let offset = size.width - CGFloat(maxX - minX + 1) * side
                for cell in cells {
                    let rect = CGRect(x: offset + CGFloat(cell.x - minX) * side,
                                      y: CGFloat(cell.y - minY) * side, width: side - 1, height: side - 1)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(Palette.bricks[game.next.rawValue]))
                }
            }.frame(width: 32, height: 16)
        }.accessibilityLabel("Next piece \(String(describing: game.next))")
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 8, weight: .bold, design: .monospaced)).tracking(1)
            Text(value).font(.system(size: 17, weight: .bold, design: .rounded)).monospacedDigit()
        }.lineLimit(1).minimumScaleFactor(0.6).accessibilityElement(children: .combine)
    }

    private var board: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.board))
            let unit = CGSize(width: size.width / CGFloat(GameEngine.columns),
                              height: size.height / CGFloat(GameEngine.rows))
            for row in 0..<GameEngine.rows {
                for col in 0..<GameEngine.columns {
                    let rect = CGRect(x: CGFloat(col) * unit.width, y: CGFloat(row) * unit.height, width: unit.width, height: unit.height)
                    context.stroke(Path(rect), with: .color(.white.opacity(0.035)), lineWidth: 0.5)
                    let value = game.board[row][col]
                    if value != 0 { drawBrick(context: &context, cell: Cell(x: col, y: row), unit: unit, value: value) }
                }
            }
            if let ghost = game.ghost, game.phase != .ready {
                for cell in ghost.occupied where cell.y >= 0 {
                    let rect = CGRect(x: CGFloat(cell.x) * unit.width + 3, y: CGFloat(cell.y) * unit.height + 3, width: unit.width - 6, height: unit.height - 6)
                    context.stroke(Path(roundedRect: rect, cornerRadius: 4), with: .color(Palette.bricks[ghost.kind.rawValue].opacity(0.38)), lineWidth: 1.5)
                }
            }
            if let active = game.active {
                for cell in active.occupied {
                    drawBrick(context: &context, cell: cell, unit: unit, value: active.kind.rawValue,
                              verticalOffset: CGFloat(game.dropOffset))
                }
            }
        }
    }

    private func drawBrick(context: inout GraphicsContext, cell: Cell, unit: CGSize, value: Int, verticalOffset: CGFloat = 0) {
        let rect = CGRect(x: CGFloat(cell.x) * unit.width + 1.5, y: (CGFloat(cell.y) + verticalOffset) * unit.height + 1.5, width: unit.width - 3, height: unit.height - 3)
        context.fill(Path(roundedRect: rect, cornerRadius: 4), with: .color(Palette.bricks[value]))
        let shine = CGRect(x: rect.minX + 3, y: rect.minY + 2, width: max(1, rect.width - 6), height: 2)
        context.fill(Path(roundedRect: shine, cornerRadius: 1), with: .color(.white.opacity(0.3)))
    }

    private func overlay(size: CGSize) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Palette.board.opacity(0.93))
            VStack(spacing: 18) {
                Image(systemName: game.phase == .paused ? "pause.circle" : "square.stack.3d.up.fill")
                    .font(.system(size: 35, weight: .light)).foregroundStyle(Palette.bricks[2])
                Text(game.phase == .ready ? "A little room\nto play." : game.phase == .paused ? "Take a breather." : "Nice stacking.")
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center).foregroundStyle(.white)
                Text(game.phase == .ready ? "Drag left or right to move.\nTap left / right to rotate either way.\nFlick down for a quick fall." : game.phase == .paused ? "Your blocks can wait." : "Score \(game.score.formatted()) · \(game.lines) lines")
                    .font(.system(size: 14)).multilineTextAlignment(.center).foregroundStyle(.white.opacity(0.6))
                Button {
                    resetGesture(); lastTick = Date()
                    if game.phase == .paused { game.resume() } else { game.start(); playSound(.start) }
                } label: {
                    HStack(spacing: 12) {
                        Text(game.phase == .ready ? "Let's play" : game.phase == .paused ? "Keep playing" : "Play again")
                        Image(systemName: "arrow.right")
                    }
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .padding(.horizontal, 24).padding(.vertical, 16)
                    .background(Palette.bricks[2], in: Capsule()).foregroundStyle(Palette.ink)
                }
                if game.phase == .paused {
                    Button("Start a new game") { resetGesture(); game.start(); playSound(.start) }
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.65))
                        .padding(8)
                }
                Button { soundEnabled.toggle() } label: {
                    Label(soundEnabled ? "Sound on" : "Sound off",
                          systemImage: soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 16).frame(minHeight: 44)
                }
                .accessibilityLabel("Sound effects")
                .accessibilityValue(soundEnabled ? "On" : "Off")
                .accessibilityHint("Double tap to toggle sound effects")
            }.padding(20)
        }
        .frame(width: size.width, height: size.height)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            control("arrow.left", label: "Move left") { game.move(-1) }
            control("arrow.counterclockwise", label: "Rotate counterclockwise") { rotate(clockwise: false) }
            control("arrow.clockwise", label: "Rotate clockwise") { rotate() }
            control("arrow.right", label: "Move right") { game.move(1) }
            control("arrow.down.to.line", label: "Drop piece") { game.drop() }
        }
        .disabled(game.phase != .playing)
        .opacity(game.phase == .playing ? 1 : 0.35)
    }

    private func control(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Palette.ink).frame(maxWidth: .infinity).frame(height: 40)
                .background(Palette.ink.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }.accessibilityLabel(label)
    }

    private func playSound(_ effect: GameSounds.Effect) {
        if soundEnabled && scenePhase == .active { sounds.play(effect) }
    }

    private func rotate(clockwise: Bool = true) {
        if game.rotate(clockwise: clockwise) { playSound(.rotate) }
    }

    private func resetGesture() { gesturePiece = nil; horizontalSteps = 0; gestureIsVertical = false; gestureDidTravel = false }

    private func touchControls(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard game.phase == .playing else { return }
                if gesturePiece == nil { gesturePiece = game.pieceID }
                guard gesturePiece == game.pieceID else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                if abs(dx) >= 10 || abs(dy) >= 10 { gestureDidTravel = true }
                if dy > 18 && abs(dy) > abs(dx) * 1.3 { gestureIsVertical = true }
                if !gestureIsVertical {
                    let steps = Int(dx / max(14, width / 10))
                    let difference = steps - horizontalSteps
                    if difference != 0 {
                        for _ in 0..<min(abs(difference), 10) { game.move(difference > 0 ? 1 : -1) }
                        horizontalSteps = steps
                    }
                }
            }
            .onEnded { value in
                defer { resetGesture() }
                guard game.phase == .playing, gesturePiece == game.pieceID else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                let flick = value.velocity.height > 350 || value.predictedEndTranslation.height - dy > 60
                if dy > 28 && dy > abs(dx) * 1.2 && flick { game.drop() }
                else if !gestureDidTravel && abs(dx) < 10 && abs(dy) < 10 {
                    rotate(clockwise: value.startLocation.x >= width / 2)
                }
            }
    }
}
