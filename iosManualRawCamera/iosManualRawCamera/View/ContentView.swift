//
//  ContentView.swift
//  iosManualRawCamera
//
//  Created by Jonathan Thomas on 2025-10-14.
//

import SwiftUI
import AVFoundation

//Main capture view
struct ContentView: View {
    
    
    @StateObject private var viewModel = CameraViewModel()

    
    @State private var cameraFeedRunning = false
    @State private var captureCount = 0
    @State private var flashOn = false
    @State private var isoWheelActive = false
    @State private var ssWheelActive = false
    enum FocusModeState: String {
        case auto = "AF-A"
        case point = "AF-S"
    }
    
    enum MeteringMode: String {
        case auto = "AUTO"
        case center = "CENTER"
        case spot = "SPOT"
    }
    
    @State private var isConfigModalPresented = false
    @State private var showGrid = UserDefaults.standard.bool(forKey: "showGrid")
    @State private var focusSquarePosition: CGPoint? = nil
    @State private var focusMode: FocusModeState = .auto
    @State private var meteringMode: MeteringMode = .auto
    
    
    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea() // Solid black background behind bars
            

            
            // Full screen tap-to-dismiss overlay
            if isoWheelActive || ssWheelActive {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        isoWheelActive = false
                        ssWheelActive = false
                    }
            }
            
            VStack(spacing: 0) {
                // Top Bar - Flash, Config and Grid icons, sized just big enough for them
                HStack(spacing: 20) {
                    Button(action: {
                        isConfigModalPresented = true
                    }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.white)
                    }
                    
                    Button(action: {
                        showGrid.toggle()
                        UserDefaults.standard.set(showGrid, forKey: "showGrid")
                        triggerCameraHapticFeedback()
                    }) {
                        Image(systemName: showGrid ? "grid" : "grid.circle")
                            .font(.system(size: 22))
                            .foregroundColor(showGrid ? .yellow : .white)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        flashOn.toggle()
                        viewModel.setupTorch(flashOn)
                    }) {
                        Image(systemName: flashOn ? "bolt.fill" : "bolt.slash.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal, 24)
                .frame(height: 44)
                .background(Color.black)
                
                ZStack {
                    // Camera preview placed directly in layout hierarchy, preventing touch interception
                    CameraPreviewView(session: cameraFeedRunning ? viewModel.captureSession : nil) { layerPoint, devicePoint in
                        self.focusSquarePosition = layerPoint
                        
                        // Save points in viewModel for dynamic mode toggling
                        viewModel.deviceFocusPoint = devicePoint
                        viewModel.deviceExposurePoint = devicePoint
                        
                        let wasAuto = (focusMode == .auto)
                        let isSpot = (meteringMode == .spot)
                        let isExposureMetered = viewModel.isAutoExposure
                        
                        if wasAuto && !isSpot {
                            // Tapping in AF-A when spot is not active shifts focus selector to AF-S
                            self.focusMode = .point
                        }
                        
                        let isFocusPoint = (focusMode == .point || (wasAuto && !isSpot))
                        let isExposurePoint = (isSpot && isExposureMetered)
                        
                        viewModel.updateFocusAndExposure(
                            focusPoint: isFocusPoint ? devicePoint : nil,
                            exposurePoint: isExposurePoint ? devicePoint : nil,
                            isFocusPoint: isFocusPoint,
                            isExposurePoint: isExposurePoint
                        )
                    }
                    .allowsHitTesting(!(isoWheelActive || ssWheelActive))
                    
                    if showGrid {
                        GridView()
                            .allowsHitTesting(false)
                    }
                    
                    // Translucent Center Weight Circle (same color/opacity as thirds grid)
                    if meteringMode == .center {
                        Circle()
                            .stroke(Color.white.opacity(0.4), lineWidth: 1.5)
                            .frame(width: 90, height: 90)
                    }
                    
                    // Visual Focus/Exposure Indicator (aligned inside 3:4 preview bounds)
                    if let focusPosition = focusSquarePosition {
                        let isFocusActive = (focusMode == .point)
                        let isSpotActive = (meteringMode == .spot && viewModel.isAutoExposure)
                        let showIndicator = isFocusActive || isSpotActive
                        
                        let style: FocusIndicatorView.IndicatorStyle = {
                            if isFocusActive && isSpotActive {
                                return .squircle
                            } else if isSpotActive {
                                return .circle
                            } else {
                                return .square
                            }
                        }()
                        
                        if showIndicator {
                            FocusIndicatorView(style: style)
                                .position(focusPosition)
                                .id("\(focusPosition.x)-\(focusPosition.y)-\(style)")
                        }
                    }
                }
                .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.width * 4 / 3)
                
                // Bottom Space - Lens switcher, exposure settings, and controls
                VStack(spacing: 16) {
                    // 1. Bottom Control Row (Focus selector, Lenses, and future placeholder)
                    if !isoWheelActive && !ssWheelActive {
                        HStack {
                            // Left: Focus Mode Selector
                            Button(action: {
                                triggerCameraHapticFeedback()
                                if focusMode == .point {
                                    focusMode = .auto
                                    // Reset both focus and exposure back to center/defaults
                                    viewModel.updateFocusAndExposure(
                                        focusPoint: nil,
                                        exposurePoint: (meteringMode == .spot) ? CGPoint(x: 0.5, y: 0.5) : nil,
                                        isFocusPoint: false,
                                        isExposurePoint: (meteringMode == .spot && viewModel.isAutoExposure)
                                    )
                                    initializeFocusSquare()
                                } else {
                                    focusMode = .point
                                    // Center point coordinates in screen and device space
                                    let screenWidth = UIScreen.main.bounds.width
                                    focusSquarePosition = CGPoint(x: screenWidth / 2.0, y: (screenWidth * 4.0 / 3.0) / 2.0)
                                    
                                    let devicePoint = CGPoint(x: 0.5, y: 0.5)
                                    viewModel.deviceFocusPoint = devicePoint
                                    if meteringMode == .spot {
                                        viewModel.deviceExposurePoint = devicePoint
                                    }
                                    
                                    viewModel.updateFocusAndExposure(
                                        focusPoint: devicePoint,
                                        exposurePoint: (meteringMode == .spot && viewModel.isAutoExposure) ? devicePoint : nil,
                                        isFocusPoint: true,
                                        isExposurePoint: (meteringMode == .spot && viewModel.isAutoExposure)
                                    )
                                }
                            }) {
                                Text(focusMode.rawValue)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(focusMode == .auto ? .white : .yellow)
                                    .frame(width: 48, height: 36)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(focusMode == .auto ? Color.white.opacity(0.3) : Color.yellow, lineWidth: 1.0)
                                    )
                            }
                            .padding(.leading, 16)
                            
                            Spacer()
                            
                            // Center: Lens Switcher (0.5x, 1x, Tele)
                            if viewModel.cameraPosition == .back && viewModel.availableLenses.count > 1 {
                                HStack(spacing: 12) {
                                    ForEach(viewModel.availableLenses) { lens in
                                        Button(action: {
                                            viewModel.selectedLens = lens
                                            initializeFocusSquare()
                                            triggerCameraHapticFeedback()
                                        }) {
                                            Text(lens.displayName)
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(viewModel.selectedLens?.id == lens.id ? .black : .white)
                                                .frame(width: 50, height: 36)
                                                .background(
                                                    RoundedRectangle(cornerRadius: 6)
                                                        .fill(viewModel.selectedLens?.id == lens.id ? Color.yellow : Color.white.opacity(0.15))
                                                )
                                        }
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            // Right: Metering Mode Selector (AUTO, CENTER, SPOT)
                            Button(action: {
                                triggerCameraHapticFeedback()
                                switch meteringMode {
                                case .auto:
                                    // AUTO -> SPOT
                                    meteringMode = .spot
                                    let spotPoint = focusSquarePosition != nil ? viewModel.deviceExposurePoint : CGPoint(x: 0.5, y: 0.5)
                                    viewModel.updateFocusAndExposure(
                                        focusPoint: (focusMode == .point) ? viewModel.deviceFocusPoint : nil,
                                        exposurePoint: spotPoint,
                                        isFocusPoint: (focusMode == .point),
                                        isExposurePoint: viewModel.isAutoExposure
                                    )
                                case .spot:
                                    // SPOT -> CENTER
                                    meteringMode = .center
                                    viewModel.updateFocusAndExposure(
                                        focusPoint: (focusMode == .point) ? viewModel.deviceFocusPoint : nil,
                                        exposurePoint: CGPoint(x: 0.5, y: 0.5),
                                        isFocusPoint: (focusMode == .point),
                                        isExposurePoint: true
                                    )
                                case .center:
                                    // CENTER -> AUTO
                                    meteringMode = .auto
                                    viewModel.updateFocusAndExposure(
                                        focusPoint: (focusMode == .point) ? viewModel.deviceFocusPoint : nil,
                                        exposurePoint: nil,
                                        isFocusPoint: (focusMode == .point),
                                        isExposurePoint: false
                                    )
                                }
                            }) {
                                Text(meteringMode.rawValue)
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(meteringMode == .auto ? .white : .yellow)
                                    .frame(width: 48, height: 36)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(meteringMode == .auto ? Color.white.opacity(0.3) : Color.yellow, lineWidth: 1.0)
                                    )
                            }
                            .padding(.trailing, 16)
                        }
                        .transition(.opacity)
                    }
                    
                    // 2. Exposure settings / Sliders
                    if isoWheelActive {
                        let isoValues: [Int] = {
                            let min = Int(viewModel.minISO)
                            let max = Int(viewModel.maxISO)
                            let standardISOs = [25, 32, 40, 50, 64, 80, 100, 125, 160, 200, 250, 320, 400, 500, 640, 800, 1000, 1250, 1600, 2000, 2500, 3200, 4000, 5000, 6400, 8000, 10000, 12800, 25600]
                            var filtered = standardISOs.filter { $0 >= min && $0 <= max }
                            if !filtered.contains(min) { filtered.append(min) }
                            if !filtered.contains(max) { filtered.append(max) }
                            let current = Int(viewModel.iso)
                            if !filtered.contains(current) { filtered.append(current) }
                            return filtered.sorted()
                        }()
                        
                        ExposureSliderView(tickValues: isoValues, viewModel: viewModel, exposureType: .iso)
                            .padding(.bottom, 10)
                            .padding(.horizontal, 40)
                            .onTapGesture {}
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: .bottom).combined(with: .opacity)
                            ))
                        
                    } else if ssWheelActive {
                        let ssValues: [Int] = {
                            let min = viewModel.minShutterSpeed
                            let max = viewModel.maxShutterSpeed
                            let standardSS = [
                                1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 20, 22, 25, 28, 30, 35, 40, 45, 50, 55, 60, 70, 80, 90, 100,
                                125, 160, 200, 250, 320, 400, 500, 640, 800, 1000, 1250, 1600, 2000, 2500, 3200, 4000, 5000, 6400, 8000, 10000, 12000
                            ]
                            var filtered = standardSS.filter { $0 >= min && $0 <= max }
                            if !filtered.contains(min) { filtered.append(min) }
                            if !filtered.contains(max) { filtered.append(max) }
                            let current = Int(viewModel.shutterSpeed.timescale)
                            if !filtered.contains(current) { filtered.append(current) }
                            return filtered.sorted()
                        }()
                        
                        ExposureSliderView(tickValues: ssValues, viewModel: viewModel, exposureType: .shutterSpeed)
                            .padding(.bottom, 10)
                            .padding(.horizontal, 40)
                            .onTapGesture {}
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: .bottom).combined(with: .opacity)
                            ))
                        
                    } else {
                        // Exposure settings toolbar (excluding Config/Flash)
                        HStack(alignment: .center, spacing: 20) {
                            Button(action: {
                                viewModel.isAutoExposure.toggle()
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: viewModel.isAutoExposure ? "a.circle.fill" : "m.circle.fill")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundColor(viewModel.isAutoExposure ? .yellow : .white)
                                    Text(viewModel.isAutoExposure ? "Auto" : "Manual")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                            
                            Spacer()
                            
                            if viewModel.isAutoExposure {
                                HStack(spacing: 8) {
                                    Image(systemName: "plusminus.circle")
                                        .foregroundColor(.white)
                                        .font(.system(size: 16))
                                    Slider(value: $viewModel.exposureCompensation, in: -3.0...3.0, step: 0.3)
                                        .accentColor(.yellow)
                                    Text(String(format: "%+.1f", viewModel.exposureCompensation))
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white)
                                        .frame(width: 35, alignment: .trailing)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    viewModel.exposureCompensation = 0.0
                                    triggerCameraHapticFeedback()
                                }
                                .frame(maxWidth: 180)
                            } else {
                                Button(action: {
                                    if !viewModel.isAutoExposure {
                                        isoWheelActive = true
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image("isoIcon")
                                            .renderingMode(.template)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(height: 22)
                                            .foregroundColor(.white)
                                        Text(String(Int(viewModel.iso)))
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(.white)
                                    }
                                }
                                
                                Button(action: {
                                    if !viewModel.isAutoExposure {
                                        ssWheelActive = true
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "stopwatch")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.white)
                                        Text("1/\(Int(viewModel.shutterSpeed.timescale))s")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundColor(.white)
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        ))
                    }
                    
                    // 3. Shutter and bottom options
                    HStack {
                        // Gallery Button (Thumbnail preview)
                        Button(action: {
                            viewModel.openLastPhotoInSystemGallery()
                            #if !targetEnvironment(simulator)
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.prepare()
                            generator.impactOccurred()
                            #endif
                        }) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.black.opacity(0.6))
                                    .frame(width: 60, height: 60)
                                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 4)
                                
                                if let thumbnail = viewModel.lastCapturedThumbnail {
                                    Image(uiImage: thumbnail)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 60, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .transition(.asymmetric(
                                            insertion: .opacity.combined(with: .scale(scale: 1.1)),
                                            removal: .identity
                                        ))
                                        .id(UUID())
                                }
                                    
                                if viewModel.pendingProcessingCount > 0 {
                                    Color.black.opacity(0.4)
                                        .frame(width: 60, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                    
                                    ZStack {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(1.6)
                                        
                                        Text("\(viewModel.pendingProcessingCount)")
                                            .foregroundColor(.white)
                                            .font(.system(size: 12, weight: .bold))
                                    }
                                } else {
                                    Text("\(captureCount)")
                                        .foregroundColor(.white)
                                        .font(.system(size: 16, weight: .medium))
                                        .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                                }
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .animation(.spring(response: 0.3), value: viewModel.lastCapturedThumbnail)
                        
                        Spacer()
                        
                        // Capture button
                        Button(action: {
                            viewModel.capturePhoto(false, false, nil)
                            captureCount += 1
                        }) {
                            Image("captureButton")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 90, height: 90)
                        }
                        .accessibilityIdentifier("captureButton")
                        
                        Spacer()
                        
                        // Rotate Camera Button
                        Button(action: {
                            viewModel.toggleCameraPosition()
                            initializeFocusSquare()
                            triggerCameraHapticFeedback()
                        }) {
                            ZStack {
                                Circle()
                                    .fill(Color.black.opacity(0.6))
                                    .frame(width: 60, height: 60)
                                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 4)
                                
                                Image(systemName: "arrow.triangle.2.circlepath.camera")
                                    .font(.system(size: 22))
                                    .foregroundColor(.white)
                            }
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal, 30)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .background(Color.black)
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isoWheelActive)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: ssWheelActive)
        }
        .onAppear {
            viewModel.setupCamera(false, nil) { result in
                switch result {
                case .success:
                    print("Camera setup complete")
                    cameraFeedRunning = true
                case .failure:
                    print("Error with camera setup")
                }
            }
            viewModel.getDeviceSpecs()
            initializeFocusSquare()
        }
        .sheet(isPresented: $isConfigModalPresented) {
            ConfigView(viewModel: viewModel)
        }
    }
    
    func safeAreaInsets() -> UIEdgeInsets {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            return window.safeAreaInsets
        }
        return .zero
    }
    
    // Helper function to trigger haptic feedback
    func triggerCameraHapticFeedback() {
        #if !targetEnvironment(simulator)
        let impactFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)
        impactFeedbackGenerator.prepare()
        impactFeedbackGenerator.impactOccurred()
        #endif
    }
    
    private func initializeFocusSquare() {
        let screenWidth = UIScreen.main.bounds.width
        focusSquarePosition = CGPoint(x: screenWidth / 2.0, y: (screenWidth * 4.0 / 3.0) / 2.0)
        focusMode = .auto
        meteringMode = .auto
    }
}



class UICameraPreviewView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
    
    var onTap: ((CGPoint, CGPoint) -> Void)?
    
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupTapGesture()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTapGesture()
    }
    
    private func setupTapGesture() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        self.addGestureRecognizer(tapGesture)
    }
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let pointInLayer = gesture.location(in: self)
        if bounds.contains(pointInLayer) {
            let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: pointInLayer)
            onTap?(pointInLayer, devicePoint)
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }
}

// Camera preview
struct CameraPreviewView: UIViewRepresentable {
    var session: AVCaptureSession?
    var onTap: ((CGPoint, CGPoint) -> Void)
    
    func makeUIView(context: Context) -> UICameraPreviewView {
        let view = UICameraPreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        if let session = session {
            view.previewLayer.session = session
        }
        view.onTap = onTap
        return view
    }
    
    func updateUIView(_ uiView: UICameraPreviewView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
        uiView.onTap = onTap
    }
}

struct FocusIndicatorView: View {
    enum IndicatorStyle {
        case square
        case circle
        case squircle
    }
    
    let style: IndicatorStyle
    @State private var scale: CGFloat = 1.4
    @State private var opacity: Double = 0.0
    
    var body: some View {
        Group {
            switch style {
            case .circle:
                Circle()
                    .stroke(Color.yellow, lineWidth: 1.5)
            case .square:
                Rectangle()
                    .stroke(Color.yellow, lineWidth: 1.5)
            case .squircle:
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.yellow, lineWidth: 1.5)
            }
        }
        .frame(width: 70, height: 70)
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.2)) {
                scale = 1.0
                opacity = 1.0
            }
        }
    }
}

struct ConfigView: View {
    @ObservedObject var viewModel: CameraViewModel
    @Environment(\.dismiss) var dismiss
    @State private var isPipelineConfigExpanded = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Export Configuration")) {
                    Picker("Format", selection: $viewModel.exportFormat) {
                        ForEach(ExportFormat.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                Section(header: Text("Selfie Camera")) {
                    Toggle("Mirror Selfie Output", isOn: $viewModel.mirrorSelfieOutput)
                }
                
                Section {
                    DisclosureGroup("Pichromatic pipeline", isExpanded: $isPipelineConfigExpanded) {
                        TextEditor(text: $viewModel.pipelineConfigToml)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 300)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.none)
                            .onChange(of: viewModel.pipelineConfigToml) { newValue in
                                print("DEBUG SWIFT: pipelineConfigToml changed to \(newValue.count) chars")
                            }
                    }
                }
            }
            .navigationTitle("Configuration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}


struct GridView: View {
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            
            ZStack {
                // Vertical lines
                Path { path in
                    path.move(to: CGPoint(x: w / 3, y: 0))
                    path.addLine(to: CGPoint(x: w / 3, y: h))
                    
                    path.move(to: CGPoint(x: 2 * w / 3, y: 0))
                    path.addLine(to: CGPoint(x: 2 * w / 3, y: h))
                }
                .stroke(Color.white.opacity(0.4), lineWidth: 1)
                
                // Horizontal lines
                Path { path in
                    path.move(to: CGPoint(x: 0, y: h / 3))
                    path.addLine(to: CGPoint(x: w, y: h / 3))
                    
                    path.move(to: CGPoint(x: 0, y: 2 * h / 3))
                    path.addLine(to: CGPoint(x: w, y: 2 * h / 3))
                }
                .stroke(Color.white.opacity(0.4), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
    }
}



