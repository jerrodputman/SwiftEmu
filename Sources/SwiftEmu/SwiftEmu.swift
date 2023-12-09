// Copyright (c) 2023 Jerrod Putman
//
// Permission is hereby granted, free of charge, to any person obtaining
// a copy of this software and associated documentation files (the
// "Software"), to deal in the Software without restriction, including
// without limitation the rights to use, copy, modify, merge, publish,
// distribute, sublicense, and/or sell copies of the Software, and to
// permit persons to whom the Software is furnished to do so, subject to
// the following conditions:
//
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
// MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
// LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
// OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
// WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import Foundation
import SDL
import SwiftNES

enum SwiftEmuError: Error {
    case unableToInitializeSDL(String)
    case unableToCreateWindow(String)
    case unableToCreateRenderer(String)
}

@main
final class SwiftEmu {
    static func main() throws {
        let emu = try SwiftEmu()
        emu.run()
    }
    
    init() throws {
        let SDL_INIT_EVERYTHING = SDL_INIT_TIMER | SDL_INIT_AUDIO | SDL_INIT_VIDEO | SDL_INIT_EVENTS | SDL_INIT_JOYSTICK | SDL_INIT_GAMECONTROLLER
        
        // Initialize SDL.
        guard SDL_Init(SDL_INIT_EVERYTHING) == 0 else {
            throw SwiftEmuError.unableToInitializeSDL(SDL_GetErrorString())
        }
        
        // Create the application window.
        guard let window = SDL_CreateWindow(
            "SwiftEmu",
            Int32(SDL_WINDOWPOS_CENTERED_MASK),
            Int32(SDL_WINDOWPOS_CENTERED_MASK),
            800, 600,
            SDL_WINDOW_SHOWN.rawValue | SDL_WINDOW_RESIZABLE.rawValue) else {
            throw SwiftEmuError.unableToCreateWindow(SDL_GetErrorString())
        }
        
        // Create the renderer.
        guard let renderer = SDL_CreateRenderer(window, -1, SDL_RENDERER_PRESENTVSYNC.rawValue) else {
            throw SwiftEmuError.unableToCreateRenderer(SDL_GetErrorString())
        }
        
        // Use nearest neighbor scaling because we want big, chunky pixels.
        // We can apply filters in the post-processing stage.
        SDL_SetHint(SDL_HINT_RENDER_SCALE_QUALITY, "nearest")
        
        self.window = window
        self.renderer = renderer
        self.isRunning = true

        // Create the hardware.
        let hardware = try NES()
        self.hardware = hardware
        
        // Create the control pad.
        let controlPad = ControlPad()
        self.controlPad = controlPad
        
        // Create the cartridge from the file data.
        let cartridgePath = CommandLine.arguments[1]
        let cartridgeData = try Data(contentsOf: URL(fileURLWithPath: cartridgePath))
        hardware.cartridge = try Cartridge(data: cartridgeData)
        
        // Connect the control pad to the hardware.
        hardware.controller1 = controlPad
        
        // Connect the video output to the receiver.
        hardware.videoReceiver = self
        
        // Reset the hardware.
        hardware.reset()
    }
    
    deinit {
        if let videoTexture {
            SDL_DestroyTexture(videoTexture)
        }
        
        SDL_DestroyRenderer(renderer)
        SDL_DestroyWindow(window)
        SDL_Quit()
    }
    
    func run() {
        while isRunning {
            let start = SDL_GetPerformanceCounter()
            
            processInput()
            update()
            render()
            
            let end = SDL_GetPerformanceCounter()
            
            let elapsedMilliseconds = Double(end - start) / Double(SDL_GetPerformanceFrequency()) * 1000.0

            SDL_Delay(UInt32(max(0, 16.6667 - elapsedMilliseconds)))
        }
    }
    
    
    // MARK: - Private
    
    private let window: OpaquePointer
    private let renderer: OpaquePointer
    private var isRunning: Bool
    
    private let hardware: NES
    private let controlPad: ControlPad
    
    private var pixelBuffer: [UInt32] = []
    private var videoTexture: OpaquePointer?
    private var videoOutputParams: VideoOutputParameters?
    
    
    private func processInput() {
        var event = SDL_Event()
        
        // Process all events.
        while SDL_PollEvent(&event) > 0 {
            switch SDL_EventType(event.type) {
            case SDL_QUIT:
                isRunning = false
            case SDL_KEYDOWN where event.key.keysym.sym == SDLK_ESCAPE.rawValue:
                isRunning = false
            default:
                continue
            }
        }
        
        if let keyboardState = SDL_GetKeyboardState(nil) {
            processControlPadButton(keyboardState: keyboardState, scanCode: SDL_SCANCODE_Z, buttons: .a)
            processControlPadButton(keyboardState: keyboardState, scanCode: SDL_SCANCODE_X, buttons: .b)
            processControlPadButton(keyboardState: keyboardState, scanCode: SDL_SCANCODE_A, buttons: .select)
            processControlPadButton(keyboardState: keyboardState, scanCode: SDL_SCANCODE_S, buttons: .start)
            processControlPadButton(keyboardState: keyboardState, scanCode: SDL_SCANCODE_UP, buttons: .up)
            processControlPadButton(keyboardState: keyboardState, scanCode: SDL_SCANCODE_DOWN, buttons: .down)
            processControlPadButton(keyboardState: keyboardState, scanCode: SDL_SCANCODE_LEFT, buttons: .left)
            processControlPadButton(keyboardState: keyboardState, scanCode: SDL_SCANCODE_RIGHT, buttons: .right)
        }
    }
    
    private func update() {
        hardware.update(elapsedTime: 1.0 / 60.0)
    }
    
    private func render() {
        guard let videoTexture,
            let videoOutputParams else { return }
        
        let pixelBufferAddress = pixelBuffer.withUnsafeBytes { $0.baseAddress }
        
        SDL_UpdateTexture(videoTexture,
                          nil,
                          pixelBufferAddress,
                          Int32(videoOutputParams.resolution.width) * Int32(MemoryLayout<UInt32>.stride))

        SDL_RenderClear(renderer)
        SDL_RenderCopy(renderer, videoTexture, nil, nil)
        SDL_RenderPresent(renderer)
    }
    
    private func processControlPadButton(keyboardState: UnsafePointer<UInt8>, scanCode: SDL_Scancode, buttons: ControlPad.Buttons) {
        if keyboardState.advanced(by: Int(scanCode.rawValue)).pointee > 0 {
            controlPad.pressedButtons.insert(buttons)
        } else {
            controlPad.pressedButtons.remove(buttons)
        }
    }
}

extension SwiftEmu: VideoReceiver {
    func setVideoOutputParameters(_ params: VideoOutputParameters) {
        videoOutputParams = params
        pixelBuffer = Array(repeating: 0, count: Int(params.resolution.width * params.resolution.height))
        
        SDL_RenderSetLogicalSize(renderer,
                                 Int32(params.resolution.width),
                                 Int32(params.resolution.height))
        
        videoTexture =  SDL_CreateTexture(renderer,
                                          SDL_PIXELFORMAT_ARGB8888.rawValue,
                                          Int32(SDL_TEXTUREACCESS_STREAMING.rawValue),
                                          Int32(params.resolution.width),
                                          Int32(params.resolution.height))
    }
    
    func setPixel(atX x: Int, y: Int, withColor color: UInt32) {
        guard let videoOutputParams,
              x >= 0,
              y >= 0,
              x < videoOutputParams.resolution.width,
              y < videoOutputParams.resolution.height else { return }
        
        pixelBuffer[y * Int(videoOutputParams.resolution.width) + x] = color
    }
}

func SDL_GetErrorString() -> String {
    String(cString: SDL_GetError())
}
