//
//  CameraViewModel.swift
//  iosManualRawCamera
//
//  Created by Jonathan Thomas on 2025-10-14.
//

import AVFoundation
import SwiftUI
import Photos
import Combine
import ImageIO

enum ExportFormat: String, CaseIterable, Identifiable {
    case raw = "RAW"
    case jpeg = "JPEG"
    case rawAndJpeg = "RAW + JPEG"
    
    var id: String { self.rawValue }
    
    var shortName: String {
        switch self {
        case .raw: return "RAW"
        case .jpeg: return "JPEG"
        case .rawAndJpeg: return "R+J"
        }
    }
}

struct CameraLens: Identifiable, Equatable {
    let id: String
    let deviceType: AVCaptureDevice.DeviceType
    let focalLength: Int
    
    var displayName: String {
        return "\(focalLength)mm"
    }
}

class CameraViewModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    static let defaultPipelineConfig: String = """
       #### Pixel Pipeline ####

       [[pipeline_modules]]
       name = "Demosaic"
       algorithm = "Markesteijn"

       [[pipeline_modules]]
       name = "CFACoeffs"

       [[pipeline_modules]]
       name = "HighlightReconstruction"

       [[pipeline_modules]]
       name = "Vignette"
       strength = 0.95

       [[pipeline_modules]]
       name = "BaselineExposureCompensation"

       [[pipeline_modules]]
       name = "Exp"
       ev = 1

       [[pipeline_modules]]
       name = "Contrast"
       c = 1.3

       [[pipeline_modules]]
       name = "CST"
       target_color_space = "AcesCg"

       [[pipeline_modules]]
       name = "LCH"
       lc = 1
       cc = 1.25
       hc = 1

       [[pipeline_modules]]
       name = "ToneMap"

       [[pipeline_modules]]
       name = "CST"
       target_color_space = "Srgb"
       """

    func resetPipelineConfigToDefault() {
        self.pipelineConfigToml = CameraViewModel.defaultPipelineConfig
    }

    var captureSession: AVCaptureSession?
    private var photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "session queue")
    private var device: AVCaptureDevice?
    
    var deviceFocusPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)
    var deviceExposurePoint: CGPoint = CGPoint(x: 0.5, y: 0.5)
    
    @Published var availableLenses: [CameraLens] = []
    @Published var selectedLens: CameraLens? {
        didSet {
            if let lens = selectedLens, oldValue?.id != lens.id {
                switchLens(lens)
            }
        }
    }
    
    @Published var cameraPosition: AVCaptureDevice.Position = .back
    
    @Published var pendingProcessingCount: Int = 0
    private let processingQueue = DispatchQueue(label: "com.pichromatic.processing", qos: .userInitiated)
    
    @Published var minISO: Double = 0
    @Published var maxISO: Double = 0
    @Published var minShutterSpeed: Int = 0 //slowest
    @Published var maxShutterSpeed: Int = 0 //fastest
    @Published var lastCapturedThumbnail: UIImage?
    @Published var lastPhotoMetadataJson: String? = nil
    @Published var exportFormat: ExportFormat {
        didSet {
            UserDefaults.standard.set(exportFormat.rawValue, forKey: "exportFormat")
        }
    }
    @Published var mirrorSelfieOutput: Bool {
        didSet {
            UserDefaults.standard.set(mirrorSelfieOutput, forKey: "mirrorSelfieOutput")
        }
    }
    @Published var pipelineConfigToml: String {
        didSet {
            UserDefaults.standard.set(pipelineConfigToml, forKey: "pipelineConfigToml")
        }
    }
    
    @Published var isCapturing = false
    @Published var isExposureLocked: Bool = false
    @Published var isFocusLocked: Bool = false
    @Published var lastCapturedAssetLocalIdentifier: String?
    @Published var exposureCompensation: Double = 0.0 {
        didSet {
            UserDefaults.standard.set(exposureCompensation, forKey: "exposureCompensation")
            updateExposureSettings()
        }
    }
    @Published var isAutoExposure: Bool {
        didSet {
            UserDefaults.standard.set(isAutoExposure, forKey: "isAutoExposure")
            updateExposureSettings()
        }
    }
    @Published var iso: Double {
       didSet {
           UserDefaults.standard.set(iso, forKey: "iso")
           updateExposureSettings()
       }
    }
    @Published var shutterSpeed: CMTime {
        didSet {
            UserDefaults.standard.set(Int(shutterSpeed.timescale), forKey: "shutterSpeed")
            updateExposureSettings()
        }
    }
    
    
    override init() {
        
        // Default values
       let defaultIso = 100.0
       let defaultShutterSpeed = 100
       
       if let storedIso = UserDefaults.standard.object(forKey: "iso") as? Double {
           self.iso = storedIso
       } else {
           self.iso = defaultIso
       }
       
       if let storedTimescale = UserDefaults.standard.object(forKey: "shutterSpeed") as? Int {
           self.shutterSpeed = CMTime(value: 1, timescale: Int32(storedTimescale))
       } else {
           self.shutterSpeed = CMTime(value: 1, timescale: Int32(defaultShutterSpeed))
       }
              if let storedAutoExp = UserDefaults.standard.object(forKey: "isAutoExposure") as? Bool {
            self.isAutoExposure = storedAutoExp
        } else {
            self.isAutoExposure = false
        }
        
        if let storedEV = UserDefaults.standard.object(forKey: "exposureCompensation") as? Double {
            self.exposureCompensation = storedEV
        } else {
            self.exposureCompensation = 0.0
        }
              if let storedFormatRaw = UserDefaults.standard.string(forKey: "exportFormat"),
           let storedFormat = ExportFormat(rawValue: storedFormatRaw) {
            self.exportFormat = storedFormat
        } else {
            self.exportFormat = .rawAndJpeg
        }
        
        if let storedMirrorSelfie = UserDefaults.standard.object(forKey: "mirrorSelfieOutput") as? Bool {
            self.mirrorSelfieOutput = storedMirrorSelfie
        } else {
            self.mirrorSelfieOutput = true
        }
       
        if let storedToml = UserDefaults.standard.string(forKey: "pipelineConfigToml") {
            self.pipelineConfigToml = storedToml
        } else {
            self.pipelineConfigToml = CameraViewModel.defaultPipelineConfig
        }
       
       super.init()
       checkPermissions()
    }
    
    //request camera access
    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            print("camera access authorized")
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    print("camera access authorized")
                }
            }
        default:
            print("Camera access denied or restricted.")
        }
    }
    
    func triggerCaptureRealizedFeedback() {
        DispatchQueue.main.async {
            #if !targetEnvironment(simulator)
            // Medium impact haptic feedback for shutter release
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.prepare()
            generator.impactOccurred()
            #endif
        }
    }
    
    func openLastPhotoInSystemGallery() {
        if let url = URL(string: "photos-redirect://") {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
    
    func triggerPipelineFinishedFeedback() {
        // No feedback when the pipeline finishes
    }
    
    //setup camera session, completion handler to indicate when finished
    func setupCamera(_ flashEnabled: Bool, _ focusPoint: CGPoint?, completion: @escaping (Result<Void, Error>) -> Void) { //maybe make throwing
        sessionQueue.async {
            self.captureSession = AVCaptureSession()
            guard let captureSession = self.captureSession else {
                print("capture session not yet running")
                return }
            captureSession.beginConfiguration()
            captureSession.sessionPreset = .photo
            
            //can specify which lens
            self.updateAvailableLenses()
            let lensToUse = self.selectedLens?.deviceType ?? .builtInWideAngleCamera
            let positionToUse = self.cameraPosition
            let deviceTypeToUse = (positionToUse == .front) ? .builtInWideAngleCamera : lensToUse
            guard let device = AVCaptureDevice.default(deviceTypeToUse, for: .video, position: positionToUse) else {
                print("Selected device not available. Defaulting to Wide Angle back camera.")
                guard let defaultDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                    print("No back camera found.")
                    return
                }
                self.device = defaultDevice
                return
            }
            self.device = device
            
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if captureSession.canAddInput(input) {
                    captureSession.addInput(input)
                }
                
                if captureSession.canAddOutput(self.photoOutput) {
                    captureSession.addOutput(self.photoOutput)
                }
                
                //MARK: set manual/auto exposure settings
                try device.lockForConfiguration()
                
                if self.isAutoExposure {
                    if device.isExposureModeSupported(.continuousAutoExposure) {
                        device.exposureMode = .continuousAutoExposure
                        device.setExposureTargetBias(Float(self.exposureCompensation), completionHandler: nil)
                    }
                } else {
                    device.exposureMode = .custom
                    device.setExposureModeCustom(duration: self.shutterSpeed, iso: Float(self.iso), completionHandler: nil)
                }
                
                // set focus point if provided
                if let focusPoint = focusPoint, device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = focusPoint
                    device.focusMode = .autoFocus
                } else {
                    //otherwise use autofocus
                    device.focusMode = .continuousAutoFocus
                }
                
                device.isSubjectAreaChangeMonitoringEnabled = false
                
                //fire flash on picture
                //device.torchMode = .on
                
                device.unlockForConfiguration()
                
                captureSession.commitConfiguration()
                captureSession.startRunning() //this might need to be in a background thread to prevent freezing
                
                if !captureSession.isRunning {
                    print("Failed to start camera session")
                    return
                }
                
                
                //MARK: torch continously on
                //DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if flashEnabled {
                    DispatchQueue.main.async {
                        do {
                            //try device.lockForConfiguration()
                            try device.setTorchModeOn(level: 1.0)
                            //device.unlockForConfiguration()
                        } catch {
                            print("flash failed to fire")
                        }
                    }
                }
                
                print("Camera session started")
                completion(.success(()))
                
            } catch {
                print("Error setting up camera: \(error)")
                completion(.failure(error))
            }
        }
    }
    
    func capturePhoto(_ flashEnabled: Bool, _ arEnabled: Bool , _ focusPoint: CGPoint?) {
        guard !isCapturing else { return }
        isCapturing = true
        
        //in AR modes, need to setup camera on each picture
        if arEnabled {
            // Setup camera first, capture code runs on completion
            setupCamera(flashEnabled, focusPoint) { result in
                switch result {
                case .success:
                    self.capturePhotoWithSettings()
                    
                    
                case .failure(let error):
                    print("Error setting up camera: \(error)")
                    self.isCapturing = false
                }
            }
        } else {
            //skip setup and go straight to capture
            self.capturePhotoWithSettings()
        }
    }
    
    func toggleExposureLock() {
        guard let device = self.device else { return }
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                if self.isExposureLocked {
                    // Unlock
                    if self.isAutoExposure {
                        if device.isExposureModeSupported(.continuousAutoExposure) {
                            device.exposureMode = .continuousAutoExposure
                        }
                    } else {
                        if device.isExposureModeSupported(.custom) {
                            device.exposureMode = .custom
                        }
                    }
                    DispatchQueue.main.async {
                        self.isExposureLocked = false
                    }
                } else {
                    // Lock
                    if device.isExposureModeSupported(.locked) {
                        device.exposureMode = .locked
                    }
                    DispatchQueue.main.async {
                        self.isExposureLocked = true
                    }
                }
                device.unlockForConfiguration()
            } catch {
                print("Error locking exposure configuration: \(error)")
            }
        }
    }
    
    func toggleFocusLock() {
        guard let device = self.device else { return }
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                if self.isFocusLocked {
                    // Unlock
                    if device.isFocusModeSupported(.continuousAutoFocus) {
                        device.focusMode = .continuousAutoFocus
                    }
                    DispatchQueue.main.async {
                        self.isFocusLocked = false
                    }
                } else {
                    // Lock
                    if device.isFocusModeSupported(.locked) {
                        device.focusMode = .locked
                    }
                    DispatchQueue.main.async {
                        self.isFocusLocked = true
                    }
                }
                device.unlockForConfiguration()
            } catch {
                print("Error locking focus configuration: \(error)")
            }
        }
    }

    func updateFocusAndExposure(focusPoint: CGPoint?, exposurePoint: CGPoint?, isFocusPoint: Bool, isExposurePoint: Bool) {
        guard let device = self.device else {
            print("No camera device available to update focus/exposure")
            return
        }
        
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                
                // Handle Focus Point
                if self.isFocusLocked {
                    // Skip updating focus mode if focus is locked
                } else if isFocusPoint, let fPoint = focusPoint, device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = fPoint
                    device.focusMode = .autoFocus
                } else if !isFocusPoint {
                    if device.isFocusPointOfInterestSupported {
                        device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
                    }
                    if device.isFocusModeSupported(.continuousAutoFocus) {
                        device.focusMode = .continuousAutoFocus
                    }
                }
                
                // Handle Exposure Point (Spot Metering)
                if self.isExposureLocked {
                    // Skip updating exposure mode if exposure is locked
                } else if isExposurePoint, let ePoint = exposurePoint, device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = ePoint
                    device.exposureMode = self.isAutoExposure ? .continuousAutoExposure : .custom
                } else if !isExposurePoint {
                    if device.isExposurePointOfInterestSupported {
                        device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
                    }
                    if device.isExposureModeSupported(.continuousAutoExposure) && self.isAutoExposure {
                        device.exposureMode = .continuousAutoExposure
                    }
                }
                
                device.isSubjectAreaChangeMonitoringEnabled = (isFocusPoint || isExposurePoint)
                device.unlockForConfiguration()
                print("Updated focus/exposure. FocusPoint: \(String(describing: focusPoint)), ExposurePoint: \(String(describing: exposurePoint))")
            } catch {
                print("Error updating focus/exposure: \(error)")
            }
        }
    }
    
    
    //once camera setup is complete initiate capture
    func capturePhotoWithSettings() {
        //ui changes on main thread
        DispatchQueue.main.async {
            guard let captureSession = self.captureSession, captureSession.isRunning else {
                print("Capture session not running")
                self.isCapturing = false
                return
            }
            
            //check if we have camera access back from ARKit
            guard let _ = self.photoOutput.connection(with: .video) else {
                print("Photo output not properly configured")
                self.isCapturing = false
                return
            }
            
            guard !self.photoOutput.availableRawPhotoPixelFormatTypes.isEmpty else {
                print("RAW capture not supported")
                self.isCapturing = false
                return
            }
            
            if let rawFormat = self.photoOutput.availableRawPhotoPixelFormatTypes.first {
                let settings = AVCapturePhotoSettings(rawPixelFormatType: rawFormat)
                settings.flashMode = .off
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            } else {
                print("No RAW format available")
                self.isCapturing = false
            }
        }
    }
    
    
    //Update exp settings in current session
    func updateExposureSettings() {
        guard let device = self.device else {
            print("No camera device available")
            return
        }
        
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                if self.isAutoExposure {
                    if device.isExposureModeSupported(.continuousAutoExposure) {
                        device.exposureMode = .continuousAutoExposure
                        device.setExposureTargetBias(Float(self.exposureCompensation), completionHandler: nil)
                        print("Exposure settings updated: Auto Exposure (Bias: \(self.exposureCompensation))")
                    } else {
                        print("Continuous Auto Exposure not supported on this device")
                    }
                } else {
                    device.exposureMode = .custom
                    device.setExposureModeCustom(duration: self.shutterSpeed, iso: Float(self.iso), completionHandler: nil)
                    print("Exposure settings updated: Manual (ISO \(self.iso), Shutter \(self.shutterSpeed.timescale))")
                }
                device.unlockForConfiguration()
            } catch {
                print("Error updating exposure settings: \(error)")
            }
        }
    }
    
    
    //func to toggle continous torch
    func setupTorch(_ flashOn: Bool) {
        
        sessionQueue.async {
            // Use the existing device instance rather than getting a new one
            guard let device = self.device else {
                print("Torch is not available - no device.")
                return
            }
            
            // Check if torch is available on this device
            guard device.hasTorch && device.isTorchAvailable else {
                print("Torch is not available on this device.")
                return
            }
            
            do {
                try device.lockForConfiguration()
                
                if flashOn {
                    try device.setTorchModeOn(level: 1.0)
                    print("Torch turned on")
                } else {
                    device.torchMode = .off
                    print("Torch turned off")
                }
                
                device.unlockForConfiguration()
            } catch {
                print("Flash failed to fire: \(error)")
            }
        }
    }
    
    
    
    func updateAvailableLenses() {
        let deviceTypes: [AVCaptureDevice.DeviceType] = [
            .builtInUltraWideCamera,
            .builtInWideAngleCamera,
            .builtInTelephotoCamera
        ]
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .video,
            position: .back
        )
        
        let devices = discoverySession.devices
        var lenses: [CameraLens] = []
        for device in devices {
            // Get the nominal focal length.
            let focalLength: Int
            if #available(iOS 26.0, *) {
                let nominal = device.nominalFocalLengthIn35mmFilm
                if nominal > 0 {
                    focalLength = Int(round(nominal))
                } else {
                    focalLength = defaultFocalLength(for: device.deviceType)
                }
            } else {
                focalLength = defaultFocalLength(for: device.deviceType)
            }
            
            let lens = CameraLens(
                id: device.uniqueID,
                deviceType: device.deviceType,
                focalLength: focalLength
            )
            
            if !lenses.contains(where: { $0.deviceType == device.deviceType }) {
                lenses.append(lens)
            }
        }
        
        lenses.sort(by: { $0.focalLength < $1.focalLength })
        
        if lenses.isEmpty {
            lenses = [CameraLens(id: "default_wide", deviceType: .builtInWideAngleCamera, focalLength: 24)]
        }
        
        DispatchQueue.main.async {
            self.availableLenses = lenses
            
            if self.selectedLens == nil {
                if let wideLens = lenses.first(where: { $0.deviceType == .builtInWideAngleCamera }) {
                    self.selectedLens = wideLens
                } else {
                    self.selectedLens = lenses.first
                }
            } else {
                if !lenses.contains(where: { $0.id == self.selectedLens?.id }) {
                    if let matchingType = lenses.first(where: { $0.deviceType == self.selectedLens?.deviceType }) {
                        self.selectedLens = matchingType
                    } else {
                        self.selectedLens = lenses.first
                    }
                }
            }
        }
    }
    
    private func defaultFocalLength(for deviceType: AVCaptureDevice.DeviceType) -> Int {
        switch deviceType {
        case .builtInUltraWideCamera: return 13
        case .builtInWideAngleCamera: return 24
        case .builtInTelephotoCamera: return 77
        default: return 24
        }
    }
    
    func switchLens(_ lens: CameraLens) {
        sessionQueue.async {
            guard let captureSession = self.captureSession else { return }
            captureSession.beginConfiguration()
            
            // Remove existing input(s)
            if let inputs = captureSession.inputs as? [AVCaptureDeviceInput] {
                for input in inputs {
                    captureSession.removeInput(input)
                }
            }
            
            // Get new device
            guard let newDevice = AVCaptureDevice.default(lens.deviceType, for: .video, position: .back) else {
                print("Lens \(lens.displayName) not found, using default wide camera.")
                captureSession.commitConfiguration()
                return
            }
            self.device = newDevice
            
            do {
                let input = try AVCaptureDeviceInput(device: newDevice)
                if captureSession.canAddInput(input) {
                    captureSession.addInput(input)
                }
                
                // Re-apply custom settings if in manual mode
                try newDevice.lockForConfiguration()
                if self.isAutoExposure {
                    if newDevice.isExposureModeSupported(.continuousAutoExposure) {
                        newDevice.exposureMode = .continuousAutoExposure
                        newDevice.setExposureTargetBias(Float(self.exposureCompensation), completionHandler: nil)
                    }
                } else {
                    newDevice.exposureMode = .custom
                    newDevice.setExposureModeCustom(duration: self.shutterSpeed, iso: Float(self.iso), completionHandler: nil)
                }
                newDevice.focusMode = .continuousAutoFocus
                newDevice.unlockForConfiguration()
                
                captureSession.commitConfiguration()
                print("Switched to lens: \(lens.displayName)")
                
                // Re-query spec limits because different lenses have different ISO / Shutter Speed boundaries!
                self.getDeviceSpecs()
                
            } catch {
                print("Error switching lens: \(error)")
                captureSession.commitConfiguration()
            }
        }
    }
    
    func toggleCameraPosition() {
        let newPosition: AVCaptureDevice.Position = (cameraPosition == .back) ? .front : .back
        
        sessionQueue.async {
            guard let captureSession = self.captureSession else { return }
            captureSession.beginConfiguration()
            
            // Remove existing input(s)
            if let inputs = captureSession.inputs as? [AVCaptureDeviceInput] {
                for input in inputs {
                    captureSession.removeInput(input)
                }
            }
            
            // Get new device
            let newDevice: AVCaptureDevice?
            if newPosition == .front {
                newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            } else {
                newDevice = AVCaptureDevice.default(self.selectedLens?.deviceType ?? .builtInWideAngleCamera, for: .video, position: .back)
            }
            
            guard let device = newDevice else {
                print("Could not find camera device for position \(newPosition)")
                captureSession.commitConfiguration()
                return
            }
            self.device = device
            
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if captureSession.canAddInput(input) {
                    captureSession.addInput(input)
                }
                
                // Re-apply custom settings if in manual mode
                try device.lockForConfiguration()
                if self.isAutoExposure {
                    if device.isExposureModeSupported(.continuousAutoExposure) {
                        device.exposureMode = .continuousAutoExposure
                        device.setExposureTargetBias(Float(self.exposureCompensation), completionHandler: nil)
                    }
                } else {
                    device.exposureMode = .custom
                    device.setExposureModeCustom(duration: self.shutterSpeed, iso: Float(self.iso), completionHandler: nil)
                }
                device.focusMode = .continuousAutoFocus
                device.unlockForConfiguration()
                
                captureSession.commitConfiguration()
                print("Switched camera position to: \(newPosition == .back ? "Back" : "Front")")
                
                DispatchQueue.main.async {
                    self.cameraPosition = newPosition
                }
                
                // Re-query spec limits for the new active device
                self.getDeviceSpecs()
                
            } catch {
                print("Error toggling camera position: \(error)")
                captureSession.commitConfiguration()
            }
        }
    }
    
    //get min/max iso and shutterspeed of device
    func getDeviceSpecs() {
        
        guard let device = self.device else {
            print("Camera device not available")
            return
        }
        
        DispatchQueue.main.async {
            let minDeviceISO = Double(device.activeFormat.minISO)
            let maxDeviceISO = Double(device.activeFormat.maxISO)
            
            print("Device ISO bounds - Min: \(minDeviceISO), Max: \(maxDeviceISO)")
            self.minISO = minDeviceISO
            self.maxISO = maxDeviceISO
            
            let minDeviceSS = device.activeFormat.maxExposureDuration //slowest
            let maxDeviceSS = device.activeFormat.minExposureDuration //fastet
            
            let minSSRounded = Int(ceil(Float(minDeviceSS.timescale) / 10.0) * 10.0) //round up to nearest 10
            self.minShutterSpeed = max(10, minSSRounded)
            
            let seconds = CMTimeGetSeconds(maxDeviceSS)
            let convertedTimescale = Int(1.0 / seconds)  //convert to 1/x format
            self.maxShutterSpeed = Int(floor(Float(convertedTimescale) / 10.0) * 10.0)  //round down to nearest 10
        }
    }
    
    
    
    //delegate method for processing captured photo
    //delegate method for processing captured photo
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("Error capturing photo: \(error)")
            DispatchQueue.main.async {
                self.isCapturing = false
            }
            return
        }
        
        // Check if the captured photo has RAW data
        guard let photoData = photo.fileDataRepresentation() else {
            print("No photo data available")
            DispatchQueue.main.async {
                self.isCapturing = false
            }
            return
        }
        
        print("Captured RAW image data of size \(photoData.count) bytes")
        
        // Generate low-res thumbnail immediately for instant UI feedback
        generateThumbnail(from: photoData)
        
        // Increment pending count and release the isCapturing lock immediately
        DispatchQueue.main.async {
            self.pendingProcessingCount += 1
            self.isCapturing = false
        }
        
        // Capture metadata before sending to background queue
        let metadata = photo.metadata
        
        // Process the RAW data in the background queue sequentially
        processingQueue.async {
            self.processCapturedPhotoData(photoData, metadata: metadata)
        }
    }
    
    private func processCapturedPhotoData(_ photoData: Data, metadata: [String: Any]) {
        // Run pichromatic pipeline on the raw DNG bytes
        photoData.withUnsafeBytes { (rawBufferPointer: UnsafeRawBufferPointer) in
            guard let baseAddress = rawBufferPointer.baseAddress else {
                DispatchQueue.main.async {
                    self.pendingProcessingCount = max(0, self.pendingProcessingCount - 1)
                }
                return
            }
            let bytesPointer = baseAddress.assumingMemoryBound(to: UInt8.self)
            
            // 1. Decode raw image
            print("Decoding raw image using Rust library...")
            self.triggerCaptureRealizedFeedback()
            guard let rustImage = get_raw_img(bytesPointer, photoData.count) else {
                print("Failed to decode raw image using Rust")
                DispatchQueue.main.async {
                    self.pendingProcessingCount = max(0, self.pendingProcessingCount - 1)
                }
                return
            }
            
            if let metadataPtr = get_image_metadata_c(rustImage) {
                let metadataStr = String(cString: metadataPtr)
                free_string_c(UnsafeMutablePointer(mutating: metadataPtr))
                DispatchQueue.main.async {
                    self.lastPhotoMetadataJson = metadataStr
                }
            }
            
            // 2. Parse config TOML
            let configToml = self.pipelineConfigToml
            print("DEBUG SWIFT: Parsing pipeline config TOML (length \(configToml.count)):\n\(configToml)")
            
            let configData = configToml.data(using: .utf8)!
            configData.withUnsafeBytes { (configBuffer: UnsafeRawBufferPointer) in
                guard let configAddress = configBuffer.baseAddress else { return }
                let configBytes = configAddress.assumingMemoryBound(to: UInt8.self)
                
                guard let pipeline = get_pixel_pipeline_c(configBytes, configData.count) else {
                    print("Failed to parse pipeline config")
                    free_image_c(rustImage)
                    DispatchQueue.main.async {
                        self.pendingProcessingCount = max(0, self.pendingProcessingCount - 1)
                    }
                    return
                }
                
                // 3. Run pipeline
                print("Running pixel pipeline...")
                _ = run_pixel_pipeline_c(rustImage, pipeline)
                
                // 4. Retrieve RGB buffer
                var outWidth: Int = 0
                var outHeight: Int = 0
                var outLen: Int = 0
                print("Retrieving RGB data...")
                if let rgbPtr = get_image_rgb_data_c(rustImage, &outWidth, &outHeight, &outLen) {
                    print("RGB retrieved: \(outWidth)x\(outHeight), size: \(outLen) bytes")
                    
                    // 5. Convert to UIImage with correct EXIF orientation
                    let exifOrientationVal = (metadata[kCGImagePropertyOrientation as String] as? NSNumber)?.int32Value ?? 1
                    var imageOrientation = self.uiImageOrientation(from: exifOrientationVal)
                    if self.cameraPosition == .front && self.mirrorSelfieOutput {
                        imageOrientation = self.adjustOrientationForSelfie(imageOrientation)
                    }
                    print("EXIF orientation: \(exifOrientationVal), mapped to Swift orientation: \(imageOrientation)")
                    
                    if let uiImage = uiImageFromRGBBytes(bytes: rgbPtr, width: outWidth, height: outHeight, orientation: imageOrientation) {
                        print("Successfully created processed UIImage")
                        
                        DispatchQueue.main.async {
                            self.lastCapturedThumbnail = uiImage
                            self.triggerPipelineFinishedFeedback()
                        }
                        
                        // 6. Save processed image to gallery if requested
                        if self.exportFormat == .jpeg || self.exportFormat == .rawAndJpeg {
                            PHPhotoLibrary.requestAuthorization { status in
                                if status == .authorized {
                                    var placeholder: PHObjectPlaceholder?
                                    PHPhotoLibrary.shared().performChanges({
                                        let request = PHAssetChangeRequest.creationRequestForAsset(from: uiImage)
                                        placeholder = request.placeholderForCreatedAsset
                                    }) { success, error in
                                        if success {
                                            print("Processed image saved to gallery successfully!")
                                            if let localId = placeholder?.localIdentifier {
                                                DispatchQueue.main.async {
                                                    self.lastCapturedAssetLocalIdentifier = localId
                                                }
                                            }
                                        } else if let error = error {
                                            print("Error saving processed image to gallery: \(error)")
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        print("Failed to create UIImage from RGB bytes")
                    }
                    
                    // Free the leaked RGB buffer
                    let mutableRgbPtr = UnsafeMutablePointer<UInt8>(mutating: rgbPtr)
                    free_rgb_buffer_c(mutableRgbPtr, outLen)
                } else {
                    print("Failed to retrieve RGB data from processed image")
                }
                
                // Free pipeline
                free_pipeline_c(pipeline)
            }
            
            // Free Rust image
            free_image_c(rustImage)
        }
        
        // Save to photo library if RAW format requested
        if self.exportFormat == .raw || self.exportFormat == .rawAndJpeg {
            PHPhotoLibrary.requestAuthorization { status in
                if status == .authorized {
                    // Save the RAW image to the Photo Library
                    var placeholder: PHObjectPlaceholder?
                    PHPhotoLibrary.shared().performChanges({
                        let creationRequest = PHAssetCreationRequest.forAsset()
                        creationRequest.addResource(with: .photo, data: photoData, options: nil)
                        placeholder = creationRequest.placeholderForCreatedAsset
                    }) { success, error in
                        if success {
                            print("RAW image saved to photo library.")
                            if let localId = placeholder?.localIdentifier {
                                DispatchQueue.main.async {
                                    self.lastCapturedAssetLocalIdentifier = localId
                                }
                            }
                        } else if let error = error {
                            print("Error saving RAW image: \(error)")
                        }
                        
                        // Decrement pending count on final completion
                        DispatchQueue.main.async {
                            self.pendingProcessingCount = max(0, self.pendingProcessingCount - 1)
                        }
                    }
                } else {
                    print("Photo library access denied.")
                    DispatchQueue.main.async {
                        self.pendingProcessingCount = max(0, self.pendingProcessingCount - 1)
                    }
                }
            }
        } else {
            // Decrement pending count on final completion (since no RAW save was needed)
            DispatchQueue.main.async {
                self.pendingProcessingCount = max(0, self.pendingProcessingCount - 1)
            }
        }
    }
    
    private func uiImageFromRGBBytes(bytes: UnsafePointer<UInt8>, width: Int, height: Int, orientation: UIImage.Orientation) -> UIImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.noneSkipLast.rawValue
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        
        // Copy 24-bit RGB (3 bytes) to 32-bit RGBA (4 bytes) context buffer
        if let dest = context.data?.assumingMemoryBound(to: UInt8.self) {
            let pixelCount = width * height
            for i in 0..<pixelCount {
                dest[i * 4]     = bytes[i * 3]     // R
                dest[i * 4 + 1] = bytes[i * 3 + 1] // G
                dest[i * 4 + 2] = bytes[i * 3 + 2] // B
                dest[i * 4 + 3] = 255              // A (Opaque)
            }
        }
        
        guard let cgImage = context.makeImage() else {
            return nil
        }
        
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: orientation)
    }
    
    private func uiImageOrientation(from exifOrientation: Int32) -> UIImage.Orientation {
        switch exifOrientation {
        case 1: return .up
        case 2: return .upMirrored
        case 3: return .down
        case 4: return .downMirrored
        case 5: return .leftMirrored
        case 6: return .right
        case 7: return .rightMirrored
        case 8: return .left
        default: return .up
        }
    }
    
    private func adjustOrientationForSelfie(_ orientation: UIImage.Orientation) -> UIImage.Orientation {
        switch orientation {
        case .up: return .upMirrored
        case .upMirrored: return .up
        case .down: return .downMirrored
        case .downMirrored: return .down
        case .left: return .leftMirrored
        case .leftMirrored: return .left
        case .right: return .rightMirrored
        case .rightMirrored: return .right
        @unknown default: return orientation
        }
    }
    
    
    
    private func generateThumbnail(from rawData: Data) {
        Task.detached { //background thread
            guard let imageSource = CGImageSourceCreateWithData(rawData as CFData, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
                print("Could not create image from RAW data")
                return
            }
            
            // Create UIImage and resize for thumbnail
            let orientation: UIImage.Orientation = (self.cameraPosition == .front && self.mirrorSelfieOutput) ? .rightMirrored : .right
            let fullImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: orientation)
            let thumbnailSize = CGSize(width: 150, height: 150)
            let thumbnail = fullImage.preparingThumbnail(of: thumbnailSize)
            
            await MainActor.run {
                self.lastCapturedThumbnail = thumbnail
            }
        }
    }
        
        
//Save to photos

//        PHPhotoLibrary.requestAuthorization { status in
//            if status == .authorized {
//                // Save the RAW image to the Photo Library
//                PHPhotoLibrary.shared().performChanges({
//                    let creationRequest = PHAssetCreationRequest.forAsset()
//
//                    //add RAW data as resource
//                    creationRequest.addResource(with: .photo, data: photoData, options: nil)
//                }) { success, error in
//                    DispatchQueue.main.async {
//                        if success {
//                            print("RAW image saved to photo library.")
//                        } else if let error = error {
//                            print("Error saving RAW image: \(error)")
//                        }
//                        self.isCapturing = false
//                        //signal to resume ar session once image is saved
//                        self.photoCompletedPublisher.send()
//                    }
//                }
//            } else {
//                print("Photo library access denied.")
//                DispatchQueue.main.async {
//                    self.isCapturing = false
//                }
//            }
//        }
    
}
