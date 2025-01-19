import AVFoundation
import Accelerate
import Cocoa
import MetalKit

//let AUDIO_FILE: String? = "/Users/fabian/Documents/coding/nds_viz/hm.wav"

struct UniformData {
    var rotation: Float
    var color: SIMD3<Float>
}


class ViewController: NSViewController, MTKViewDelegate {

    var metalView: MTKView!
    var metalDevice: MTLDevice!
    var commandQueue: MTLCommandQueue!
    var pipelineState: MTLRenderPipelineState!
    var vertexBuffer: MTLBuffer!

    var uniformBuffer: MTLBuffer!
    var rotation: Float = 0

    var audioFile: AVAudioFile?
    var audioBuffer: ShiftingBuffer<Float>!

    let bassFrequencyRange: ClosedRange<Float> = 20...200  // Adjust as needed
    let bassThreshold: Float = 40  // Adjust this value based on your audio and desired sensitivity
    let colorFadeDuration: Float = 0.05  // Duration for the color to fade back to normal
    let bassHitColor = SIMD3<Float>(0.0, 1.0, 0.0)  // Green
    let normalColor = SIMD3<Float>(0.5, 0.8, 0.9)  // Example: A blueish color
    var isBassDetected = false
    var timeSinceBassHit: Float = 0.0
    
    // This works out for audio of 44.1kHz and 60FPS (== 735 audio frames per video frame)
    // We will stock this as a rolling buffer (?)
    let fftSize = 1024

    var audioPlayer: AVAudioPlayer?

    var lastDrawTime: CFTimeInterval = 0

    func loadAudioFile() {
        //        if let audioFileURL = AUDIO_FILE {
        //            do {
        //                let fileURL = URL(fileURLWithPath: audioFileURL)
        //                audioFile = try AVAudioFile(forReading: fileURL)
        //                print("Audio file loaded successfully: \(audioFileURL)")
        //            } catch {
        //                print("Error loading audio file: \(error)")
        //                fatalError()
        //            }
        //            return
        //        }

        let openPanel = NSOpenPanel()
        openPanel.allowedFileTypes = ["wav"]  // Allow only .wav files
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false

        if openPanel.runModal() == .OK {
            // Get the selected file URL
            if let fileURL = openPanel.url {
                do {
                    audioFile = try AVAudioFile(forReading: fileURL)
                    print("Audio file loaded successfully: \(fileURL.path())")

                    audioPlayer = try AVAudioPlayer(contentsOf: fileURL)
                    audioPlayer?.prepareToPlay()  // Prepare for playback
                } catch {
                    print("Error loading audio file: \(error)")
                    fatalError()
                }
            }
        }
    }

    override func viewDidLoad() {
        assert(metalView == nil)
        audioBuffer = ShiftingBuffer<Float>(size: fftSize, defaultValue: 0.0)
        
        super.viewDidLoad()

        // Create the Metal device
        metalDevice = MTLCreateSystemDefaultDevice()
        guard metalDevice != nil else {
            print("Metal is not supported on this device")
            return
        }

        // Configure the MTKView
        metalView = MTKView(frame: view.bounds, device: metalDevice)
        metalView.autoresizingMask = [.width, .height]  // Make sure it resizes with the window
        metalView.delegate = self
        view.addSubview(metalView)  // Add the MTKView to the main view

        // Set up command queue and pipeline state
        commandQueue = metalDevice.makeCommandQueue()
        setupPipelineState()
        createVertexBuffer()
        createUniformBuffer()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.loadAudioFile()
        }
    }

    func createUniformBuffer() {
        uniformBuffer = metalDevice.makeBuffer(
            length: MemoryLayout<UniformData>.stride, options: [])
    }

    func updateUniforms() {
        rotation += 0.01

        if isBassDetected {
            timeSinceBassHit = 0.0
            isBassDetected = false
        }

        // Interpolate color based on time since last bass hit
        let blendFactor = min(1.0, timeSinceBassHit / colorFadeDuration)
        let currentColor = SIMD3<Float>(
            (1.0 - blendFactor) * bassHitColor.x + blendFactor * normalColor.x,
            (1.0 - blendFactor) * bassHitColor.y + blendFactor * normalColor.y,
            (1.0 - blendFactor) * bassHitColor.z + blendFactor * normalColor.z
        )

        // Update the buffer's contents
        var uniformData = UniformData(rotation: rotation, color: currentColor)
        uniformBuffer.contents().copyMemory(
            from: &uniformData, byteCount: MemoryLayout<UniformData>.stride)

        // Increment time since last bass hit
        timeSinceBassHit += 0.016  // Adjust this increment based on your desired fade duration
    }

    func setupPipelineState() {
        print("setupPipelineState")
        // Load all the shader files with a .metal file extension in the project
        guard let library = metalDevice.makeDefaultLibrary() else {
            fatalError()
        }

        // Function to compile the shaders into a pipeline state
        let vertexFunction = library.makeFunction(name: "vertex_shader")
        let fragmentFunction = library.makeFunction(name: "fragment_shader")

        // Pipeline configuration
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "Simple Pipeline"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat =
            metalView.colorPixelFormat

        // Compile the pipeline configuration
        do {
            pipelineState = try metalDevice.makeRenderPipelineState(
                descriptor: pipelineDescriptor)
        } catch let error {
            print("Failed to create pipeline state, error \(error)")
            return
        }
    }

    func createVertexBuffer() {
        print("createVertexBuffer")
        let vertices: [Float] = [
            -1, -1, 0, 1,
            1, -1, 0, 1,
            0, 1, 0, 1,
        ]

        vertexBuffer = metalDevice.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Float>.stride
        )
    }

    // MTKViewDelegate methods
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        print("mtkView")
        // Respond to drawable size changes (e.g., window resize)
    }

    func fetchAudio(timePassedInSec: TimeInterval) {
        guard let audioFile = self.audioFile else {
            // TODO: print warning or sth
            return
        }

        // Read audio samples into the buffer
        let audioFormat = audioFile.processingFormat
        let sampleRate = Float(audioFile.fileFormat.sampleRate)
        let numFramesToRead = AVAudioFrameCount((Float(timePassedInSec) * sampleRate).rounded(.up))
        if numFramesToRead > fftSize {
            print("WARN: Will drop frames, requested \(numFramesToRead)")
        }
        
        let frequencyResolution = sampleRate / Float(fftSize)
        
        if Int(audioFile.length - audioFile.framePosition) < fftSize {
//        let numFramesToRead = AVAudioFrameCount(
//            min(
//                fftSize,
//                // TODO: Rewrite as conditional
//                Int(audioFile.length - audioFile.framePosition)))
//        if numFramesToRead != fftSize {
            // TODO: probably means audio is done. should stop playback
            print("Error: Could not load requested frames. \(numFramesToRead) != \(fftSize)")
            return
        }

        print("Reading \(numFramesToRead) frames")
        let buffer = AVAudioPCMBuffer(
            pcmFormat: audioFormat, frameCapacity: numFramesToRead)!
        try! audioFile.read(into: buffer, frameCount: numFramesToRead)

        //        var real = [Float](repeating: 0, count: Int(frameLength))
        //        var imaginary = [Float](repeating: 0, count: Int(frameLength))
        //        var splitComplex = DSPSplitComplex(realp: &real, imagp: &imaginary)

        // Convert audio data to float array
        for i in 0..<Int(numFramesToRead) {
            audioBuffer.append(buffer.floatChannelData![0][i])
        }

        // Create FFT setup
        let log2n = vDSP_Length(log2(Float(fftSize)))
        guard
            let fftSetup = vDSP.FFT(
                log2n: log2n, radix: .radix2, ofType: DSPSplitComplex.self)
        else {
            fatalError("Failed to create FFT setup")
        }

        // Perform FFT
        // Create the buffers for FFT input/output
        var forwardInputReal = audioBuffer.get()
        // Perform FFT using vDSP
        // Fill realIn with audioBuffer data (windowing might be needed here)
//        for i in 0..<fftSize {
//            forwardInputReal[i] = audioBuffer[i]
//        }
        var forwardInputImag = [Float](repeating: 0, count: Int(fftSize))
        var forwardOutputReal = [Float](repeating: 0, count: Int(fftSize))
        var forwardOutputImag = [Float](repeating: 0, count: Int(fftSize))

        // Use withUnsafeMutableBufferPointer for safe pointer access
        let magnitudes = forwardInputReal.withUnsafeMutableBufferPointer {
            forwardInputRealPtr in
            forwardInputImag.withUnsafeMutableBufferPointer {
                forwardInputImagPtr in
                forwardOutputReal.withUnsafeMutableBufferPointer {
                    forwardOutputRealPtr in
                    forwardOutputImag.withUnsafeMutableBufferPointer {
                        forwardOutputImagPtr in
                        // Create a `DSPSplitComplex` to contain the signal.
                        let inp = DSPSplitComplex(
                            realp: forwardInputRealPtr.baseAddress!,
                            imagp: forwardInputImagPtr.baseAddress!)
                        // Create a `DSPSplitComplex` to receive the FFT result.
                        var otp = DSPSplitComplex(
                            realp: forwardOutputRealPtr.baseAddress!,
                            imagp: forwardOutputImagPtr.baseAddress!)

                        fftSetup.transform(
                            input: inp, output: &otp, direction: .forward)

                        // Calculate magnitudes (amplitudes)
                        var magnitudes = [Float](
                            repeating: 0, count: fftSize / 2)
                        vDSP.absolute(otp, result: &magnitudes)
                        return magnitudes
                    }
                }
            }
        }

        let bassStartIndex = Int(
            bassFrequencyRange.lowerBound / frequencyResolution)
        let bassEndIndex = Int(
            bassFrequencyRange.upperBound / frequencyResolution)

        var bassAmplitude: Float = 0
        for i in bassStartIndex..<bassEndIndex {
            bassAmplitude += magnitudes[i]
        }
        bassAmplitude /= Float(bassEndIndex - bassStartIndex)

        if bassAmplitude > bassThreshold {
            isBassDetected = true
            print("Ampl: \(bassAmplitude) > \(bassThreshold)")
        } else {
            print("Ampl: \(bassAmplitude) <= \(bassThreshold)")
        }

    }

    // Called often!
    func draw(in view: MTKView) {

        guard let drawable = view.currentDrawable else { return }

        let currentTime = CACurrentMediaTime()
        let deltaTime: TimeInterval = currentTime - lastDrawTime
        lastDrawTime = currentTime
        print("\(deltaTime)")

        updateUniforms()

        if audioPlayer?.isPlaying == false {
            audioPlayer?.play()
        }

        let renderPassDescriptor = view.currentRenderPassDescriptor

        // Sets the background?
        //        renderPassDescriptor?.colorAttachments[0].clearColor = MTLClearColorMake(1.0, 0.0, 0.0, 1.0) // Red color

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        guard
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: renderPassDescriptor!)
        else { return }

        fetchAudio(timePassedInSec: deltaTime)
        updateUniforms()

        //        renderEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)

        renderEncoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 1)

        renderEncoder.drawPrimitives(
            type: .triangle, vertexStart: 0, vertexCount: 3)

        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
