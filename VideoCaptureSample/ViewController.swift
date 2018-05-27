/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of iOS view controller that demonstrates applying vImage operation to video frames.
*/

import UIKit
import AVFoundation
import Accelerate.vImage

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    @IBOutlet var imageView: UIImageView!
    
    var cgImageFormat = vImage_CGImageFormat(
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        colorSpace: nil,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue),
        version: 0,
        decode: nil,
        renderingIntent: .defaultIntent)
    
    var converter: vImageConverter?
    
    var sourceBuffers = [vImage_Buffer]()
    var destinationBuffer = vImage_Buffer()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureSession()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        captureSession.startRunning()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        captureSession.stopRunning()
    }
    
    deinit {
        free(destinationBuffer.data)
    }
    
    let captureSession = AVCaptureSession()
    
    func configureSession() {
        captureSession.sessionPreset = AVCaptureSession.Preset.photo
        
        let backCamera = AVCaptureDevice.default(for: AVMediaType.video)
        
        do {
            let input = try AVCaptureDeviceInput(device: backCamera!)
            captureSession.addInput(input)
        } catch {
            print("can't access camera")
            return
        }
        
        let videoOutput = AVCaptureVideoDataOutput()
        
        let dataOutputQueue = DispatchQueue(label: "video data queue",
                                            qos: .userInitiated,
                                            attributes: [],
                                            autoreleaseFrequency: .workItem)
        
        videoOutput.setSampleBufferDelegate(self,
                                            queue: dataOutputQueue)
        
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
            captureSession.startRunning()
        }
    }
    
    // AVCaptureVideoDataOutputSampleBufferDelegate
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        
        guard let pixelBuffer = sampleBuffer.imageBuffer else {
            return
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer,
                                     CVPixelBufferLockFlags.readOnly)
        
        displayEqualizedPixelBuffer(pixelBuffer: pixelBuffer)
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer,
                                       CVPixelBufferLockFlags.readOnly)
    }
    
    func displayEqualizedPixelBuffer(pixelBuffer: CVPixelBuffer) {
        var error = kvImageNoError
        
        if converter == nil {
            let cvImageFormat = vImageCVImageFormat_CreateWithCVPixelBuffer(pixelBuffer).takeRetainedValue()
            
            vImageCVImageFormat_SetColorSpace(cvImageFormat,
                                              CGColorSpaceCreateDeviceRGB())
            
            let unmanagedConverter = vImageConverter_CreateForCVToCGImageFormat(
                cvImageFormat,
                &cgImageFormat,
                nil,
                vImage_Flags(kvImageNoFlags),
                &error)!
            
            guard error == kvImageNoError else {
                return
            }
            
            converter = unmanagedConverter.takeRetainedValue()
        }
        
        if sourceBuffers.isEmpty {
            let numberOfSourceBuffers = Int(vImageConverter_GetNumberOfSourceBuffers(converter!))
            sourceBuffers = [vImage_Buffer](repeating: vImage_Buffer(),
                                            count: numberOfSourceBuffers)
        }
        
        error = vImageBuffer_InitForCopyFromCVPixelBuffer(
            &sourceBuffers,
            converter!,
            pixelBuffer,
            vImage_Flags(kvImageNoAllocate))
        
        guard error == kvImageNoError else {
            return
        }
        
        
        if destinationBuffer.data == nil {
            error = vImageBuffer_Init(&destinationBuffer,
                                      UInt(CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)),
                                      UInt(CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)),
                                      cgImageFormat.bitsPerPixel,
                                      vImage_Flags(kvImageNoFlags))
            
            guard error == kvImageNoError else {
                return
            }
        }
        
        error = vImageConvert_AnyToAny(converter!,
                                       &sourceBuffers,
                                       &destinationBuffer,
                                       nil,
                                       vImage_Flags(kvImageNoFlags))
        
        guard error == kvImageNoError else {
            return
        }
        
        error = vImageEqualization_ARGB8888(&destinationBuffer,
                                            &destinationBuffer,
                                            vImage_Flags(kvImageLeaveAlphaUnchanged))
        
        guard error == kvImageNoError else {
            return
        }
        
        let cgImage = vImageCreateCGImageFromBuffer(
            &destinationBuffer,
            &cgImageFormat,
            nil,
            nil,
            vImage_Flags(kvImageNoFlags),
            &error)
        
        if let cgImage = cgImage, error == kvImageNoError {
            DispatchQueue.main.async {
                self.imageView.image = UIImage(cgImage: cgImage.takeRetainedValue())
            }
        }
    }
}

