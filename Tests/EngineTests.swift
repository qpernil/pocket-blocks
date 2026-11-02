import Foundation

@main struct EngineTests {
    static func main() {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            guard condition() else { fatalError(message) }
        }
        let game = GameEngine()
        func dropAndLand() {
            game.drop()
            for _ in 0..<10 where game.isDropping { game.tick(0.05) }
        }
        check(game.phase == .ready, "Starts ready")
        game.start()
        check(game.active != nil && game.phase == .playing, "Starts a piece")
        let first = game.active!.kind
        var seen: Set<Int> = [first.rawValue]
        for _ in 0..<6 {
            game.board = Array(repeating: Array(repeating: 0, count: 10), count: 20)
            dropAndLand(); seen.insert(game.active!.kind.rawValue)
        }
        check(seen.count == 7, "Seven-bag contains each piece once")
        game.start(); game.active = Piece(.t)
        for _ in 0..<20 { game.move(-1) }
        check(game.active!.occupied.map(\.x).min() == 0, "Left boundary")
        check(game.rotate(), "Rotation at wall")
        check(game.fits(game.active!), "Wall rotation fits")
        for _ in 0..<20 { game.move(1) }
        check(game.active!.occupied.map(\.x).max() == 9, "Right boundary")
        let beforeRotation = game.active!.cells
        for _ in 0..<4 { game.rotate() }
        check(game.active!.cells == beforeRotation, "Four rotations restore orientation")
        // Rotation uses the same fixed pivot in either direction.
        for kind in Tetromino.allCases {
            for orientation in 0..<4 {
                for clockwise in [false, true] {
                    game.start()
                    var centered = Piece(kind); centered.x = 3; centered.y = 7
                    game.active = centered
                    for _ in 0..<orientation { game.rotate() }
                    let before = game.active!
                    for _ in 0..<4 { game.rotate(clockwise: clockwise) }
                    let after = game.active!
                    check(Set(after.occupied) == Set(before.occupied), "Four turns restore identical board cells in either direction")
                    check(after.x == before.x && after.y == before.y, "Four turns preserve position in either direction")
                    game.rotate(clockwise: clockwise); game.rotate(clockwise: !clockwise)
                    check(Set(game.active!.occupied) == Set(before.occupied), "Opposite turns undo one another in open space")
                }
            }
        }
        // Near edges, shifts are allowed, but every accepted rotation must fit.
        for kind in Tetromino.allCases {
            for direction in [-1, 1] {
                for clockwise in [false, true] {
                    game.start(); var edgePiece = Piece(kind); edgePiece.y = 7; game.active = edgePiece
                    for _ in 0..<20 { game.move(direction) }
                    for _ in 0..<8 {
                        game.rotate(clockwise: clockwise)
                        check(game.fits(game.active!), "Edge rotations remain on the board in either direction")
                    }
                    game.active = game.ghost!
                    for _ in 0..<8 {
                        game.rotate(clockwise: clockwise)
                        check(game.fits(game.active!), "Floor rotations remain on the board in either direction")
                    }
                }
            }
        }
        game.start(); var trapped = Piece(.t); trapped.y = 7; game.active = trapped
        game.board = Array(repeating: Array(repeating: 2, count: 10), count: 20)
        for cell in trapped.occupied { game.board[cell.y][cell.x] = 0 }
        for clockwise in [false, true] {
            check(!game.rotate(clockwise: clockwise), "Blocked rotation is rejected in either direction")
            check(game.active!.occupied == trapped.occupied, "Rejected rotation leaves position and orientation intact")
        }
        game.start(); game.active = Piece(.t)
        let landing = game.ghost!
        check(game.fits(landing), "Ghost fits")
        var below = landing; below.y += 1
        check(!game.fits(below), "Ghost is lowest position")
        let id = game.pieceID; dropAndLand()
        check(game.pieceID == id + 1, "Drop locks and spawns exactly once")
        check(game.board.flatMap { $0 }.filter { $0 != 0 }.count == 4, "Drop retains four cells")
        game.pause(); let paused = game.active!
        game.tick(0.1); game.move(1); game.rotate(); game.drop()
        check(game.active!.occupied == paused.occupied, "Paused actions do nothing")
        game.resume(); check(game.phase == .playing, "Resumes")
        for count in 1...4 {
            game.start()
            for row in (20-count)..<20 {
                game.board[row] = Array(repeating: 2, count: 10)
                game.board[row][4] = 0
            }
            var vertical = Piece(.i)
            vertical.cells = (0..<4).map { Cell(x: 1, y: $0) }
            vertical.x = 3; vertical.y = 16
            game.active = vertical
            dropAndLand()
            check(game.lines == count, "Clears \(count) rows")
            check(game.score == [0,100,300,500,800][count], "Scores \(count) rows")
            check(game.board.count == 20, "Board height stays constant")
            check(game.board.prefix(count).allSatisfy { $0.allSatisfy { $0 == 0 } }, "Empty rows added at top")
            check(game.board.flatMap { $0 }.filter { $0 != 0 }.count == 4 - count, "Uncleared cells survive collapse")
        }
        game.start(); game.lines = 9
        game.board[19] = Array(repeating: 2, count: 10); game.board[19][4] = 0
        var vertical = Piece(.i)
        vertical.cells = (0..<4).map { Cell(x: 1, y: $0) }; vertical.x = 3; vertical.y = 16
        game.active = vertical; dropAndLand()
        check(game.level == 2 && game.score == 100, "Level advances after scoring at old level")
        // Difficulty settles at a playable ceiling; progress and scoring continue.
        game.start(); game.lines = 49
        game.board[19] = Array(repeating: 2, count: 10); game.board[19][4] = 0
        var thresholdPiece = Piece(.i)
        thresholdPiece.cells = (0..<4).map { Cell(x: 1, y: $0) }
        thresholdPiece.x = 3; thresholdPiece.y = 16; game.active = thresholdPiece
        check(game.level == 5 && game.fallInterval > 0.30, "Speed still progresses below the ceiling")
        dropAndLand()
        check(game.lines == 50 && game.level == 6, "Fiftieth cleared row reaches the final level")
        check(abs(game.fallInterval - 0.30) < 0.000001, "Final speed is one row every 0.30 seconds")
        check(game.score == 500, "Threshold clear scores at the preceding level")
        game.board = Array(repeating: Array(repeating: 0, count: 10), count: 20)
        game.board[19] = Array(repeating: 2, count: 10); game.board[19][4] = 0
        game.active = thresholdPiece; dropAndLand()
        check(game.phase == .playing && game.lines == 51 && game.score == 1100, "Play and level-six scoring continue after the cap")
        for cleared in [59, 60, 100, 1000, 100000] {
            game.lines = cleared
            check(game.level == 6 && abs(game.fallInterval - 0.30) < 0.000001, "Further clears never exceed the difficulty cap")
        }
        game.start(); game.lines = 1000; game.active = Piece(.o)
        let initialY = game.active!.y
        for _ in 0..<15 { game.tick(0.1) }
        check(game.active!.y == initialY + 5, "Actual high-level gravity drops five rows in 1.5 seconds")
        game.start(); var bottom = Piece(.o); bottom.y = 18; game.active = bottom
        for _ in 0..<4 { game.tick(0.1) }
        check(game.board.flatMap { $0 }.allSatisfy { $0 == 0 }, "Landing delay allows adjustment")
        game.tick(0.1)
        check(game.board.flatMap { $0 }.filter { $0 != 0 }.count == 4, "Landing locks after delay")
        game.start(); game.active = Piece(.o)
        game.board[1][4] = 3; game.board[1][5] = 3
        dropAndLand()
        check(game.phase == .over, "Lock above top ends game")
        let savedBest = game.best
        game.start()
        check(game.score == 0 && game.lines == 0 && game.best == savedBest, "Restart preserves best only")
        game.start(); game.active = Piece(.t)
        let origin = game.active!
        let destination = game.ghost!
        let animationID = game.pieceID
        let lockCount = game.lockEvent
        game.drop()
        check(game.isDropping && game.active!.occupied == origin.occupied, "Flick begins a fall without teleporting")
        check(game.board.flatMap { $0 }.allSatisfy { $0 == 0 }, "Board stays empty until landing")
        game.tick(1.0 / 60)
        check(game.dropOffset > 0 && game.dropOffset < 1, "Fall begins with fractional row motion")
        game.tick(0.08)
        let midFall = game.dropOffset
        check(midFall > 0 && midFall < Double(destination.y - origin.y), "Piece is visibly between start and landing")
        check(game.score == 0 && game.pieceID == animationID, "No scoring or spawning before landing")
        check(!game.move(1) && !game.rotate(), "Flight locks horizontal movement and rotation")
        game.drop()
        check(game.dropOffset == midFall, "Repeated flick does not restart the fall")
        game.pause(); game.tick(0.1)
        check(game.dropOffset == midFall && game.isDropping, "Pause freezes the fall")
        game.resume()
        for _ in 0..<10 where game.isDropping { game.tick(0.05) }
        check(!game.isDropping && game.dropOffset == 0, "Landing clears visual offset")
        check(game.pieceID == animationID + 1 && game.lockEvent == lockCount + 1, "Animated landing locks and spawns once")
        check(game.score == (destination.y - origin.y) * 2, "Animated drop awards distance once")
        check(destination.occupied.allSatisfy { game.board[$0.y][$0.x] == origin.kind.rawValue }, "Animated piece settles at projected landing")
        game.drop(); game.tick(0.05); game.start()
        check(!game.isDropping && game.dropOffset == 0, "Restart cancels a fall")
        game.start(); game.active = Piece(.o); game.board[19][4] = 2; game.board[19][5] = 2
        let stackedLanding = game.ghost!
        dropAndLand()
        check(stackedLanding.occupied.allSatisfy { game.board[$0.y][$0.x] == 2 } && game.board[19][4] == 2, "Animated fall lands on a stack without tunneling")
        // Random legal play should never corrupt board dimensions or create invalid active pieces.
        for _ in 0..<20 {
            game.start()
            for _ in 0..<1000 {
                if game.phase == .over { break }
                switch Int.random(in: 0..<5) {
                case 0: game.move(-1)
                case 1: game.move(1)
                case 2: game.rotate()
                case 3: dropAndLand()
                default: game.tick(0.1)
                }
                check(game.board.count == 20 && game.board.allSatisfy { $0.count == 10 }, "Board invariant")
                if game.phase == .playing { check(game.fits(game.active!), "Active piece invariant") }
            }
        }
        print("Passed \(checks) engine checks")
    }
}
