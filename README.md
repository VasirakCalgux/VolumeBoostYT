# VolumeBoostYT

A powerful iOS tweak that provides an independent, gesture-based volume control for the YouTube app, completely separate from the system volume.

## Features
- **Independent Audio Amplification:** Boost the YouTube internal volume up to 2000% (20x multiplier) without touching the iOS system volume.
- **Native Screen Edge Gesture:** Seamlessly swipe inwards from the right edge of the screen, then drag up and down to adjust the volume.
- **HUD Indicator:** Displays a temporary visual percentage overlay so you know exactly how loud the volume is.
- **Universal Hooking:** Instead of placing a bloated UI overlay over the screen, the tweak hooks directly into `- [UIWindow sendEvent:]` to mathematically intercept screen touches. This perfectly preserves YouTube's native fullscreen auto-rotation and layout behaviors.
- **In-App Settings Integration:** Enable or disable the tweak natively from within the YouTube Settings menu, integrated perfectly into the Shared "Tweaks" category.
- **Universal Compatibility:** Works seamlessly with AVPlayer, AVAudioPlayer, and modern AVSampleBufferAudioRenderer pipelines. Includes fallback logic to survive sideloading app-sandbox modifications like LiveContainer.

## Tested Environments
- **Rootless Jailbreak Targets:** Compatible with standard Theos build processes.
- **Sideloaded Targets:** Can be injected via tools like LiveContainer into decrypted YouTube IPAs.

## Building / Compilation
This project uses [Theos](https://github.com/theos/theos).
1. Install Theos and its dependencies.
2. Clone this repository: `git clone https://github.com/vasirakcalgux/VolumeBoostYT.git`
3. cd into the directory: `cd VolumeBoostYT`
4. Run `make clean && make package` or compile it to a `.dylib` for sideloading.

