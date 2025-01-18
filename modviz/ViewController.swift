import Cocoa
import MetalKit

class ViewController: NSViewController, MTKViewDelegate {

    var metalView: MTKView!
    var metalDevice: MTLDevice!
    var commandQueue: MTLCommandQueue!
    var pipelineState: MTLRenderPipelineState!
    var vertexBuffer: MTLBuffer!
    
    var uniformBuffer: MTLBuffer!
    var rotation: Float = 0


    override func viewDidLoad() {
        assert(metalView == nil)
        super.viewDidLoad()

        // Create the Metal device
        metalDevice = MTLCreateSystemDefaultDevice()
        guard metalDevice != nil else {
            print("Metal is not supported on this device")
            return
        }

        // Configure the MTKView
        metalView = MTKView(frame: view.bounds, device: metalDevice)
        metalView.autoresizingMask = [.width, .height] // Make sure it resizes with the window
        metalView.delegate = self
        view.addSubview(metalView) // Add the MTKView to the main view

        // Set up command queue and pipeline state
        commandQueue = metalDevice.makeCommandQueue()
        setupPipelineState()
        createVertexBuffer()
        
        uniformBuffer = metalDevice.makeBuffer(length: MemoryLayout<Float>.stride, options: [])

    }

    func updateUniforms() {
        rotation += 0.01
        let rotationPtr = uniformBuffer.contents().bindMemory(to: Float.self, capacity: 1)
        rotationPtr.pointee = rotation
    }
    
    func setupPipelineState() {
        print("setupPipelineState")
        // Load all the shader files with a .metal file extension in the project
        guard let library = metalDevice.makeDefaultLibrary() else { fatalError() }

        // Function to compile the shaders into a pipeline state
        let vertexFunction = library.makeFunction(name: "vertex_shader")
        let fragmentFunction = library.makeFunction(name: "fragment_shader")

        // Pipeline configuration
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.label = "Simple Pipeline"
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalView.colorPixelFormat
        

        // Compile the pipeline configuration
        do {
            pipelineState = try metalDevice.makeRenderPipelineState(descriptor: pipelineDescriptor)
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
             0,  1, 0, 1,
        ]

        vertexBuffer = metalDevice.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Float>.stride, options: [])
    }

    // MTKViewDelegate methods

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        print("mtkView")
        // Respond to drawable size changes (e.g., window resize)
    }

    // Called often!
    func draw(in view: MTKView) {

        guard let drawable = view.currentDrawable else { return }
        updateUniforms()

        let renderPassDescriptor = view.currentRenderPassDescriptor
        
        // Sets the background?
//        renderPassDescriptor?.colorAttachments[0].clearColor = MTLClearColorMake(1.0, 0.0, 0.0, 1.0) // Red color

        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor!) else { return }

        renderEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
