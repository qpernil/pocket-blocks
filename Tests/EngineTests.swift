import Foundation

@main struct EngineTests {
    static func main() {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            guard condition() else { fatalError(message) }
        }
        let game = GameEngine()
        func visibleY() -> Double { Double(game.active!.y) + game.dropOffset }
        func checkVisiblePieceFits() {
            check(game.fits(game.active!), "Current grid position fits")
            if game.isDropping && game.dropOffset > 0 {
                var lower = game.active!; lower.y += 1
                check(game.fits(lower), "Fractional falling cells do not overlap the row below")
            }
        }
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
        let midPosition = visibleY()
        check(midPosition > Double(origin.y) && midPosition < Double(destination.y), "Piece is visibly between start and landing")
        check(game.score == 0 && game.pieceID == animationID, "No scoring or spawning before landing")
        check(game.move(1) && game.move(-1), "Horizontal movement stays available during fast fall")
        for _ in 0..<4 { check(game.rotate(), "Rotation stays available during fast fall") }
        check(abs(visibleY() - midPosition) < 0.000001, "Open-space movement and turns preserve vertical position")
        game.drop()
        check(game.dropOffset == midFall, "Repeated flick does not restart the fall")
        game.pause(); game.tick(0.1)
        check(!game.move(1) && !game.rotate(), "Pausing the game freezes movement and rotation during a fall")
        check(game.dropOffset == midFall && visibleY() == midPosition && game.isDropping, "Pause freezes the fall")
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

        // Input does not restart the acceleration clock or shorten the travelled distance.
        game.start(); var steeringPiece = Piece(.t); steeringPiece.y = 0; game.active = steeringPiece
        let originalDistance = game.ghost!.y - steeringPiece.y
        game.drop()
        let originalDuration = game.fastDropDuration
        game.tick(0.08)
        check(game.move(1) && game.rotate(), "Steering and turning both work mid-flight")
        game.drop(); game.tick(0.04)
        let expectedPosition = Double(originalDistance) * pow(0.12 / originalDuration, 2)
        check(abs(visibleY() - expectedPosition) < 0.000001, "Moves, turns, and repeated drops cannot brake or restart descent")
        check(game.fastDropDuration == originalDuration, "Input preserves the original acceleration timing")
        let turnedLanding = game.ghost!
        let turnedCells = turnedLanding.occupied
        let turnedID = game.pieceID
        for _ in 0..<20 where game.isDropping { game.tick(0.05) }
        check(turnedCells.allSatisfy { game.board[$0.y][$0.x] == Tetromino.t.rawValue }, "Rotated piece locks at its updated projection")
        check(game.score == (turnedLanding.y - steeringPiece.y) * 2 && game.pieceID == turnedID + 1,
              "Steered, rotated drop scores its actual descent and spawns once")

        // A fractional-height move must fit both rows the drawn cells overlap.
        game.start(); var square = Piece(.o); square.y = 0; game.active = square
        game.board[3][6] = 3
        game.drop(); game.tick(game.fastDropDuration * sqrt(1.5 / 18))
        check(abs(visibleY() - 1.5) < 0.000001, "Collision scenario reaches a fractional row")
        var misleadingGridPosition = game.active!; misleadingGridPosition.x += 1
        check(game.fits(misleadingGridPosition), "Integer-only collision test would miss the side obstacle")
        check(!game.move(1), "Sideways movement cannot clip through a stack at fractional height")
        check(game.move(-1), "Unobstructed movement remains available at the same height")
        checkVisiblePieceFits()
        game.start(); game.active = square; game.drop(); game.tick(0.05)
        for _ in 0..<20 { game.move(-1) }
        check(game.active!.occupied.map(\.x).min() == 0 && !game.move(-1), "Fast fall respects the left wall")
        for _ in 0..<20 { game.move(1) }
        check(game.active!.occupied.map(\.x).max() == 9 && !game.move(1), "Fast fall respects the right wall")

        // Sliding off a high landing target extends the same accelerating flight.
        game.start(); game.active = square
        game.board[5][4] = 3; game.board[5][5] = 3
        game.drop(); let shortDuration = game.fastDropDuration
        game.tick(0.05)
        check(game.move(1) && game.move(1), "Piece can steer away from the initial stack")
        let deeperLanding = game.ghost!
        game.tick(shortDuration - 0.05)
        check(game.isDropping && game.score == 0 && abs(visibleY() - 3) < 0.000001,
              "Passing the original target keeps falling without stopping or teleporting")
        for _ in 0..<20 where game.isDropping { game.tick(0.05) }
        check(deeperLanding.occupied.allSatisfy { game.board[$0.y][$0.x] == Tetromino.o.rawValue }, "Steering into a deeper lane reaches its floor")
        check(game.score == 36 && game.board[5][4] == 3, "Deeper landing counts actual rows and preserves the old stack")

        // A higher target stops the fall exactly on contact, even across a large tick.
        game.start(); game.active = square
        game.board[10][6] = 3; game.board[10][7] = 3
        game.drop(); game.tick(0.08)
        check(game.move(1) && game.move(1), "Piece can steer above a higher stack")
        let higherLanding = game.ghost!
        let higherID = game.pieceID
        let higherLocks = game.lockEvent
        for _ in 0..<3 where game.isDropping { game.tick(0.1) }
        check(higherLanding.occupied.allSatisfy { game.board[$0.y][$0.x] == Tetromino.o.rawValue } && game.board[10][6] == 3,
              "Changed landing target cannot be tunnelled through")
        check(game.score == 16 && game.pieceID == higherID + 1 && game.lockEvent == higherLocks + 1,
              "Higher landing scores and locks exactly once")

        // Collisions use the current height, allowing a slide underneath an overhang.
        game.start(); game.active = square; game.board[1][6] = 3
        game.drop(); game.tick(0.1)
        check(game.move(1), "A piece that has passed an overhang can move underneath it")
        checkVisiblePieceFits()

        game.start(); game.active = steeringPiece
        game.drop(); game.tick(0.05)
        let beforeBlockedTurn = game.active!
        game.board = Array(repeating: Array(repeating: 3, count: 10), count: 20)
        for cell in beforeBlockedTurn.occupied {
            game.board[cell.y][cell.x] = 0
            game.board[cell.y + 1][cell.x] = 0
        }
        for clockwise in [false, true] {
            check(!game.rotate(clockwise: clockwise), "A blocked fast-fall rotation is rejected in either direction")
            check(game.active!.occupied == beforeBlockedTurn.occupied, "Rejected turn preserves the falling piece")
            checkVisiblePieceFits()
        }

        // Every shape can move and turn during flight without entering occupied cells.
        for kind in Tetromino.allCases {
            for _ in 0..<20 {
                game.start(); game.active = Piece(kind)
                for col in 0..<10 {
                    // A legal resting board has no completed rows before this piece locks.
                    let height = col == 0 ? 0 : Int.random(in: 0...8)
                    for row in (20 - height)..<20 { game.board[row][col] = 3 }
                }
                game.drop()
                for _ in 0..<100 where game.isDropping {
                    game.move(Bool.random() ? 1 : -1)
                    game.rotate(clockwise: Bool.random())
                    checkVisiblePieceFits()
                    game.tick(Double.random(in: 0.005...0.03))
                }
                check(!game.isDropping, "Steering and turning cannot hold a fast fall indefinitely")
                check(game.board.count == 20 && game.board.allSatisfy { $0.count == 10 }, "Steered flight preserves board dimensions")
            }
        }
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
