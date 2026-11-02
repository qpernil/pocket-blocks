# Pocket Blocks

A small native iPhone falling-block game built with SwiftUI. No dependencies, accounts, network access, or purchases.

Developed by Per Nilsson with assistance from OpenAI Codex.

## Run on iPhone

1. Open `PocketBlocks.xcodeproj` in Xcode 15 or later.
2. The project uses automatic signing with the configured development team (`Q4X2Q59C2D`). Under **Signing & Capabilities**, select another team and a unique bundle identifier if building with a different Apple account.
3. Connect your iPhone, select it as the run destination, and press **Run**. iOS 17 or later is required.

For a simulator, select an installed iPhone simulator and press Run; no development team is required.

## Play

The 10-by-20 board fills the space between a compact score bar and the controls, with an eight-point side margin. Cell proportions adapt to the available screen space.

- Drag anywhere on the board to move the falling piece left or right.
- Tap the left half of the board to rotate counterclockwise, or the right half to rotate clockwise. Opposite turns undo one another in open space.
- Flick downward for a quick animated fall to the outlined landing position. The drop button does the same. The piece settles before the next one appears.
- The five buttons provide left movement, counterclockwise rotation, clockwise rotation, right movement, and fast drop, including VoiceOver labels.
- Complete horizontal rows to clear them. Every ten rows increases the level until level 6 at 50 rows. Natural falling speed starts at 0.78 seconds per row and settles at 0.30 seconds per row. The score bar shows **LV MAX 6** at the ceiling. Play and scoring continue at that level without further acceleration.
- Original synthesized sounds accompany turns, fast falls, landings, row clears, and game over. A fast fall uses an accelerating descending whistle followed by a landing thump. Toggle **Sound on / Sound off** on the start, pause, or game-over screen; the choice is saved. Effects respect the iPhone Silent switch and mix with other audio.
- Pause with the top-right button. Leaving the app pauses automatically; resume when ready.

A seven-piece shuffled bag supplies pieces. Rotations use a fixed pivot: four turns in either direction restore the same occupied cells and position in open space. Small wall and floor kicks may shift a piece when needed to fit. A short landing delay allows final adjustments, with a limit on resets. Fast falls take roughly 0.1–0.28 seconds depending on distance, accelerate smoothly, and pause with the game. Movement and rotation are held during the fall. Completed rows score 100/300/500/800 points times the level; a fast drop adds two points per row. The best score is saved locally. An interrupted game is not restored after the app is terminated.

## Source

`GameEngine.swift` contains the independent board, collision, rotation, scoring, and timing logic. `GameView.swift` draws the board and translates touch gestures into game actions. `GameSounds.swift` generates and preloads short PCM effects using AVFoundation; it requires no downloaded audio assets. The app uses no third-party libraries and no backend.

## Check the engine

From the project directory:

```sh
mkdir -p build
swiftc PocketBlocks/GameEngine.swift Tests/EngineTests.swift -o build/engine-tests
./build/engine-tests
```

The app is signed and installed on the connected iPhone 16 Pro. Device, simulator, and engine verification are recorded in `VALIDATION.md`.
