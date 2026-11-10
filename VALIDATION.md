# Validation

Engine, audio, and build checks verified on 10 November 2026 using Xcode 27.2 and Apple Swift 6.4.2. Minimum deployment target: iOS 17.0.

## Game logic

The engine executable passed 7,495 checks in the recorded run and passed ten consecutive runs, including randomized fast-fall steering on legal boards. The total varies with randomized legal play.

- All seven piece types, in all four starting orientations, return to identical occupied cells and board coordinates after four rotations in either direction in open space. Opposite turns undo one another. Wall and floor adjustments remain allowed; accepted rotations stay within the board, and blocked rotations leave the piece unchanged.
- Animated fast falls begin at the current piece position. Intermediate frames track the current grid row and fractional row offset, with scoring, locking, and spawning deferred until landing.
- Movement and rotation remain available during fast falls through both gestures and buttons. The original acceleration clock continues through input, including ordinary rotation kicks; repeated drop requests do not restart it. Fractional-height collision checks cover both adjacent grid rows, and the landing projection follows the current position and orientation.
- A fall locks and scores actual descended rows once, pauses and resumes, resets on restart, and lands on higher stacks or deeper gaps without crossing occupied cells.
- Difficulty reaches level 6 at the fiftieth cleared row and stays at 0.30 seconds per row even after many further clears. A timed simulation confirmed five rows of natural descent in 1.5 seconds at the cap. Play continues, and subsequent row clears retain the level-six scoring multiplier.
- Seven-piece bag, side boundaries, landing projection, one through four simultaneous row clears, row collapse, scoring, level transitions, landing delay, top-out, pause/resume, restart, and randomized board invariants passed.

## Audio

Audio execution uses one serial background queue on all supported iOS versions. Session configuration and activation, waveform generation, player creation and preparation, and playback and stopping stay off the main thread. Initialization is queued before playback commands; mute and stop commands retain their submission order. Queue preconditions guard preparation and the internal stop operations.

Audio validation passed 306 checks across 24 variants. The audio code also passed Swift 6 complete concurrency checking with warnings treated as errors for both macOS and the iOS 17 deployment target. Runtime verification confirmed the absence of the reported UI-unresponsiveness warnings.

- Generated six short effects and eighteen fall-whistle durations (0.11–0.28 seconds). All 24 PCM WAV variants decoded and prepared successfully with AVAudioPlayer, with matching duration, 44.1 kHz sample rate, and mono format.
- The descending whistle follows the animation's quadratic progress. Its measured pitch decreased across four successive windows (approximately 2,129, 1,743, 1,143, and 629 Hz), without clipped samples or discontinuous start/end samples. The landing thump lasts 130 ms and is triggered by the actual lock event.
- Simulator checks exercised rotation, animated fall, landing, pause/resume during a fall, and the accessible sound toggle. Muting remained in effect after termination and relaunch; re-enabling restored the On state.
- Ambient audio mode respects Silent mode and mixes with other audio. Sounds are stopped when pausing, muting, or leaving the active app.

## Continuous integration

The repository includes a GitHub Actions workflow for standalone engine and audio checks, a simulator Release build, and an unsigned iPhone Release build. CI uses Xcode 27.1 on the standard Apple silicon runner. Audio validation inspects WAV structure, decoder compatibility, sample rate, channels, duration, clipping, non-silence, endpoints, and descending fall-whistle pitch without starting audio playback. The exact workflow check and build commands passed locally with Xcode 27.2 on 2 November 2026: 3,436 engine checks, 306 audio checks across 24 variants, and both Release builds. Hosted run results are available in the repository’s Actions tab.

## App and deployment

- Debug simulator and unsigned iPhone Release builds passed. Fast-fall steering has not been independently verified on a physical device.
- Installed and launched on the iPhone 17e simulator with iOS 27.2. Visually checked the expanded board, compact score bar, controls, piece preview, landing outline, and start overlay.
- Exercised left-side and right-side taps on the simulator and visually confirmed counterclockwise and clockwise turns. Separate rotation buttons are visible and expose direction-specific accessibility labels.
- Exercised downward flicks on the simulator and confirmed completed landings, scoring, and next-piece spawning. Animation progression and its timing were checked by engine regression tests.
- Physical-device installation and launch succeeded on iOS 27.2. Visual checks confirmed the expanded board, narrow side margins, direction-specific rotation controls, and touch instructions. The sound-enabled build preserved the existing best score after updating.

Physical touch feel, haptic feedback, and the audible mix through the physical phone speakers have not been independently verified.
