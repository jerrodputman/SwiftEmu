# SwiftEmu

A simple frontend for emulators written in Swift and SDL.

## Emulators supported
- [SwiftNES](https://github.com/jerrodputman/SwiftNES)

## Usage
SwiftEmu is a simple frontend that can be launched from the command-line. 

```zsh
git clone https://github.com/jerrodputman/SwiftEmu
cd SwiftEmu
swift build -c release
cd .build/release
./SwiftEmu path/to/game
```

Note: Building the release config is *highly* recommended at the moment to get decent framerates.
