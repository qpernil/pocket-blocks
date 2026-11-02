import Foundation
import Observation

struct Cell: Equatable, Hashable {
    var x: Int
    var y: Int
}

enum Tetromino: Int, CaseIterable {
    case i = 1, o, t, s, z, j, l
    var cells: [Cell] {
        switch self {
        case .i: return [Cell(x: 0, y: 1), Cell(x: 1, y: 1), Cell(x: 2, y: 1), Cell(x: 3, y: 1)]
        case .o: return [Cell(x: 1, y: 0), Cell(x: 2, y: 0), Cell(x: 1, y: 1), Cell(x: 2, y: 1)]
        case .t: return [Cell(x: 1, y: 0), Cell(x: 0, y: 1), Cell(x: 1, y: 1), Cell(x: 2, y: 1)]
        case .s: return [Cell(x: 1, y: 0), Cell(x: 2, y: 0), Cell(x: 0, y: 1), Cell(x: 1, y: 1)]
        case .z: return [Cell(x: 0, y: 0), Cell(x: 1, y: 0), Cell(x: 1, y: 1), Cell(x: 2, y: 1)]
        case .j: return [Cell(x: 0, y: 0), Cell(x: 0, y: 1), Cell(x: 1, y: 1), Cell(x: 2, y: 1)]
        case .l: return [Cell(x: 2, y: 0), Cell(x: 0, y: 1), Cell(x: 1, y: 1), Cell(x: 2, y: 1)]
        }
    }
}

struct Piece {
    var kind: Tetromino
    var cells: [Cell]
    var x = 3
    var y = -1
    init(_ kind: Tetromino) { self.kind = kind; cells = kind.cells }
    var occupied: [Cell] { cells.map { Cell(x: $0.x + x, y: $0.y + y) } }
}

@Observable final class GameEngine {
    enum Phase { case ready, playing, paused, over }
    static let columns = 10
    static let rows = 20
    static let maximumLevel = 6
    static let minimumFallInterval = 0.30
    var board = Array(repeating: Array(repeating: 0, count: columns), count: rows)
    var phase: Phase = .ready
    var active: Piece?
    var next: Tetromino = .t
    var score = 0
    var lines = 0
    var best: Int
    var pieceID = 0
    var lockEvent = 0
    var clearEvent = 0
    var level: Int { min(Self.maximumLevel, lines / 10 + 1) }
    var fallInterval: Double { max(Self.minimumFallInterval, 0.78 * pow(0.8, Double(level - 1))) }
    // Fractional rows let the Canvas draw a continuous fall between grid cells.
    private(set) var dropOffset: Double = 0
    var isDropping: Bool { fastDrop != nil }
    var fastDropDuration: Double { fastDrop?.duration ?? 0 }
    private struct FastDrop {
        let landing: Piece
        let distance: Int
        let duration: Double
        var elapsed: Double = 0
    }
    private var fastDrop: FastDrop?
    private var bag: [Tetromino] = []
    private var fallTime: Double = 0
    private var groundTime: Double = 0
    private var lockResets = 0

    init(best: Int = 0) { self.best = best }

    func start() {
        board = Array(repeating: Array(repeating: 0, count: Self.columns), count: Self.rows)
        score = 0; lines = 0; bag = []; phase = .playing
        next = draw(); spawn()
    }

    private func draw() -> Tetromino {
        if bag.isEmpty { bag = Tetromino.allCases.shuffled() }
        return bag.removeLast()
    }

    private func spawn() {
        active = Piece(next); next = draw(); pieceID += 1
        fallTime = 0; groundTime = 0; lockResets = 0
        fastDrop = nil; dropOffset = 0
        if let active, !fits(active) { phase = .over }
    }

    func fits(_ piece: Piece) -> Bool {
        piece.occupied.allSatisfy { cell in
            cell.x >= 0 && cell.x < Self.columns && cell.y < Self.rows &&
            (cell.y < 0 || board[cell.y][cell.x] == 0)
        }
    }

    var ghost: Piece? {
        guard var piece = active else { return nil }
        while true {
            var lower = piece; lower.y += 1
            if !fits(lower) { return piece }
            piece = lower
        }
    }

    @discardableResult func move(_ direction: Int) -> Bool {
        guard phase == .playing, !isDropping, var piece = active else { return false }
        let grounded = isGrounded(piece)
        piece.x += direction
        guard fits(piece) else { return false }
        active = piece
        resetLock(wasGrounded: grounded)
        return true
    }

    @discardableResult func rotate(clockwise: Bool = true) -> Bool {
        guard phase == .playing, !isDropping, let original = active else { return false }
        if original.kind == .o { return false }
        var rotated = original
        let edge = original.kind == .i ? 3 : 2
        rotated.cells = original.cells.map {
            clockwise ? Cell(x: edge - $0.y, y: $0.x) : Cell(x: $0.y, y: edge - $0.x)
        }
        // Small wall/floor kicks make rotations comfortable near the edges.
        for kick in [Cell(x: 0, y: 0), Cell(x: -1, y: 0), Cell(x: 1, y: 0),
                     Cell(x: -2, y: 0), Cell(x: 2, y: 0), Cell(x: 0, y: -1), Cell(x: 0, y: -2)] {
            var candidate = rotated
            candidate.x += kick.x; candidate.y += kick.y
            if fits(candidate) {
                active = candidate
                resetLock(wasGrounded: isGrounded(original))
                return true
            }
        }
        return false
    }

    private func resetLock(wasGrounded: Bool) {
        if wasGrounded && lockResets < 15 { groundTime = 0; lockResets += 1 }
    }

    private func isGrounded(_ piece: Piece) -> Bool {
        var lower = piece; lower.y += 1
        return !fits(lower)
    }

    func drop() {
        guard phase == .playing, !isDropping, let original = active, let landing = ghost else { return }
        let distance = max(0, landing.y - original.y)
        guard distance > 0 else { lock(); return }
        // Short drops stay snappy; a full-board fall remains easy to see.
        fastDrop = FastDrop(landing: landing, distance: distance,
                            duration: min(0.28, 0.10 + Double(distance) * 0.01))
    }

    func tick(_ elapsed: Double) {
        guard phase == .playing, var piece = active else { return }
        let dt = min(max(elapsed, 0), 0.1)
        if var drop = fastDrop {
            drop.elapsed += dt
            let progress = min(1, drop.elapsed / drop.duration)
            dropOffset = Double(drop.distance) * progress * progress
            fastDrop = drop
            if progress >= 1 {
                active = drop.landing
                fastDrop = nil; dropOffset = 0
                score += drop.distance * 2
                lock()
            }
            return
        }
        fallTime += dt
        if fallTime >= fallInterval {
            fallTime -= fallInterval
            piece.y += 1
            if fits(piece) { active = piece }
        }
        if let current = active, isGrounded(current) {
            groundTime += dt
            if groundTime >= 0.45 { lock() }
        } else { groundTime = 0 }
    }

    private func lock() {
        guard let piece = active else { return }
        guard piece.occupied.allSatisfy({ $0.y >= 0 }) else {
            phase = .over; updateBest(); return
        }
        for cell in piece.occupied { board[cell.y][cell.x] = piece.kind.rawValue }
        let remaining = board.filter { $0.contains(0) }
        let cleared = Self.rows - remaining.count
        if cleared > 0 {
            board = Array(repeating: Array(repeating: 0, count: Self.columns), count: cleared) + remaining
            score += [0, 100, 300, 500, 800][cleared] * level
            lines += cleared; clearEvent += 1
        }
        lockEvent += 1; updateBest(); spawn()
    }

    private func updateBest() { best = max(best, score) }
    func pause() { if phase == .playing { phase = .paused } }
    func resume() { if phase == .paused { phase = .playing } }
}
