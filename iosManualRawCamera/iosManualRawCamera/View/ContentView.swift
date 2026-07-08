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
                            .foregroundColor(showGrid ? Color(hex: "C0392B") : .white)
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
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color(hex: "1C1B1B"), Color(hex: "131313")]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    VStack {
                        Spacer()
                        Rectangle()
                            .fill(Color.black)
                            .frame(height: 1)
                        Rectangle()
                            .fill(Color.white.opacity(0.05))
                            .frame(height: 1)
                    }
                )
                
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
                            HStack(spacing: 3) {
                                if viewModel.isFocusLocked {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 8))
                                        .foregroundColor(Color(hex: "C0392B"))
                                }
                                Text(focusMode.rawValue)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor((focusMode == .auto && !viewModel.isFocusLocked) ? .white : Color(hex: "C0392B"))
                            }
                            .frame(width: 48, height: 36)
                        }
                        .buttonStyle(TactileButtonStyle(isSelected: focusMode == .point || viewModel.isFocusLocked))
                        .padding(.leading, 16)
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.5)
                                .onEnded { _ in
                                    viewModel.toggleFocusLock()
                                    triggerCameraHapticFeedback()
                                }
                        )
                        
                        Spacer()
                        
                        // Center: Lens Switcher (0.5x, 1x, Tele)
                        if viewModel.cameraPosition == .back && viewModel.availableLenses.count > 1 {
                            HStack(spacing: 8) {
                                ForEach(viewModel.availableLenses) { lens in
                                    Button(action: {
                                        viewModel.selectedLens = lens
                                        initializeFocusSquare()
                                        triggerCameraHapticFeedback()
                                    }) {
                                        Text(lens.displayName)
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            .foregroundColor(viewModel.selectedLens?.id == lens.id ? Color(hex: "C0392B") : .white)
                                            .frame(width: 50, height: 36)
                                    }
                                    .buttonStyle(TactileButtonStyle(isSelected: viewModel.selectedLens?.id == lens.id))
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
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(meteringMode == .auto ? .white : Color(hex: "C0392B"))
                                .frame(width: 48, height: 36)
                        }
                        .buttonStyle(TactileButtonStyle(isSelected: meteringMode != .auto))
                        .padding(.trailing, 16)
                    }
                    
                    // 2. Exposure settings / Sliders
                    if viewModel.isAutoExposure {
                        HStack(alignment: .center, spacing: 12) {
                            Button(action: {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    viewModel.isAutoExposure.toggle()
                                }
                                triggerCameraHapticFeedback()
                            }) {
                                HStack(spacing: 6) {
                                    ZStack(alignment: viewModel.isAutoExposure ? .top : .bottom) {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color(hex: "0E0E0E"))
                                            .frame(width: 14, height: 26)
                                            .innerShadow(shape: RoundedRectangle(cornerRadius: 6), color: .black, radius: 1, offsetX: 0.5, offsetY: 0.5)
                                        
                                        Circle()
                                            .fill(Color(hex: "C0392B"))
                                            .frame(width: 10, height: 10)
                                            .padding(.vertical, 2)
                                            .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 1)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 1) {
                                        HStack(spacing: 2) {
                                            if viewModel.isExposureLocked {
                                                Image(systemName: "lock.fill")
                                                    .font(.system(size: 7))
                                                    .foregroundColor(Color(hex: "C0392B"))
                                            }
                                            Text("AUTO")
                                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                                .foregroundColor(viewModel.isAutoExposure ? .white : Color(hex: "4E4E4E"))
                                        }
                                        
                                        Text("MANUAL")
                                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                                            .foregroundColor(!viewModel.isAutoExposure ? .white : Color(hex: "4E4E4E"))
                                    }
                                }
                                .frame(width: 76, height: 32)
                                .padding(.horizontal, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(hex: "1C1B1B"))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                                        )
                                )
                            }
                            .simultaneousGesture(
                                LongPressGesture(minimumDuration: 0.5)
                                    .onEnded { _ in
                                        viewModel.toggleExposureLock()
                                        triggerCameraHapticFeedback()
                                    }
                            )
                            
                            HStack(spacing: 10) {
                                Image(systemName: "plusminus.circle")
                                    .foregroundColor(.white)
                                    .font(.system(size: 15))
                                
                                // Custom recessed slider track matching the toggle style
                                GeometryReader { geometry in
                                    let width = geometry.size.width
                                    let range: ClosedRange<Double> = -3.0...3.0
                                    let step: Double = 0.3
                                    let fraction = (viewModel.exposureCompensation - range.lowerBound) / (range.upperBound - range.lowerBound)
                                    let knobX = fraction * (width - 12)
                                    
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color(hex: "0E0E0E"))
                                            .frame(height: 12)
                                            .innerShadow(shape: RoundedRectangle(cornerRadius: 6), color: .black, radius: 1, offsetX: 0.5, offsetY: 0.5)
                                        
                                        Circle()
                                            .fill(Color(hex: "C0392B"))
                                            .frame(width: 12, height: 12)
                                            .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 1)
                                            .offset(x: knobX)
                                    }
                                    .contentShape(Rectangle())
                                    .gesture(
                                        DragGesture(minimumDistance: 0)
                                            .onChanged { value in
                                                let locX = value.location.x
                                                let percentage = max(0.0, min(1.0, locX / width))
                                                let rawVal = range.lowerBound + percentage * (range.upperBound - range.lowerBound)
                                                let snappedVal = round(rawVal / step) * step
                                                let clampedVal = max(range.lowerBound, min(range.upperBound, snappedVal))
                                                if viewModel.exposureCompensation != clampedVal {
                                                    viewModel.exposureCompensation = clampedVal
                                                    triggerCameraHapticFeedback()
                                                }
                                            }
                                    )
                                }
                                .frame(height: 12)
                                
                                Text(String(format: "%+.1f", viewModel.exposureCompensation))
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)
                                    .frame(width: 38, alignment: .trailing)
                            }
                            .contentShape(Rectangle())
                            .highPriorityGesture(
                                TapGesture(count: 2)
                                    .onEnded {
                                        viewModel.exposureCompensation = 0.0
                                        triggerCameraHapticFeedback()
                                    }
                            )
                        }
                        .frame(height: 44)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .transition(.opacity)
                    } else {
                        // Manual Mode with 2 side-by-side compact wheel sliders on a single row
                        HStack(alignment: .center, spacing: 12) {
                            Button(action: {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                    viewModel.isAutoExposure.toggle()
                                }
                                triggerCameraHapticFeedback()
                            }) {
                                HStack(spacing: 6) {
                                    ZStack(alignment: viewModel.isAutoExposure ? .top : .bottom) {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color(hex: "0E0E0E"))
                                            .frame(width: 14, height: 26)
                                            .innerShadow(shape: RoundedRectangle(cornerRadius: 6), color: .black, radius: 1, offsetX: 0.5, offsetY: 0.5)
                                        
                                        Circle()
                                            .fill(Color(hex: "C0392B"))
                                            .frame(width: 10, height: 10)
                                            .padding(.vertical, 2)
                                            .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 1)
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 1) {
                                        HStack(spacing: 2) {
                                            if viewModel.isExposureLocked {
                                                Image(systemName: "lock.fill")
                                                    .font(.system(size: 7))
                                                    .foregroundColor(Color(hex: "C0392B"))
                                            }
                                            Text("AUTO")
                                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                                .foregroundColor(viewModel.isAutoExposure ? .white : Color(hex: "4E4E4E"))
                                        }
                                        
                                        Text("MANUAL")
                                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                                            .foregroundColor(!viewModel.isAutoExposure ? .white : Color(hex: "4E4E4E"))
                                    }
                                }
                                .frame(width: 76, height: 32)
                                .padding(.horizontal, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(hex: "1C1B1B"))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.white.opacity(0.05), lineWidth: 0.5)
                                        )
                                )
                            }
                            .simultaneousGesture(
                                LongPressGesture(minimumDuration: 0.5)
                                    .onEnded { _ in
                                        viewModel.toggleExposureLock()
                                        triggerCameraHapticFeedback()
                                    }
                            )
                            
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
                            
                            ExposureSliderView(tickValues: isoValues, viewModel: viewModel, exposureType: .iso)
                            ExposureSliderView(tickValues: ssValues, viewModel: viewModel, exposureType: .shutterSpeed)
                        }
                        .frame(height: 44)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .transition(.opacity)
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
                            ZStack {
                                // Outer bezel ring (Metallic look)
                                Circle()
                                    .fill(LinearGradient(
                                        gradient: Gradient(colors: [Color(hex: "4E4E4E"), Color(hex: "2A2A2A"), Color(hex: "1A1A1A")]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                                    .frame(width: 84, height: 84)
                                    .shadow(color: .black.opacity(0.6), radius: 4, x: 0, y: 3)
                                    
                                // Inner recessed rim
                                Circle()
                                    .fill(Color(hex: "0E0E0E"))
                                    .frame(width: 72, height: 72)
                                    .innerShadow(shape: Circle(), color: .black, radius: 2, offsetX: 1, offsetY: 1)
                                    
                                // Inner crimson button core (tactile dome)
                                Circle()
                                    .fill(LinearGradient(
                                        gradient: Gradient(colors: [Color(hex: "C0392B"), Color(hex: "A93226"), Color(hex: "78281F")]),
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                                    .frame(width: 62, height: 62)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                                    )
                                    .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1.5)
                            }
                            .scaleEffect(viewModel.isCapturing ? 0.92 : 1.0)
                            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: viewModel.isCapturing)
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
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color(hex: "1A1A1A"), Color(hex: "0E0E0E")]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    VStack {
                        Rectangle()
                            .fill(Color.black)
                            .frame(height: 1)
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 1)
                        Spacer()
                    }
                )
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.isAutoExposure)
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
                    .stroke(Color(hex: "C0392B"), lineWidth: 1.5)
            case .square:
                Rectangle()
                    .stroke(Color(hex: "C0392B"), lineWidth: 1.5)
            case .squircle:
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(hex: "C0392B"), lineWidth: 1.5)
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
    @State private var isMetadataExpanded = false
    
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
                
                Section(header: Text("Last Captured Photo Metadata")) {
                    if let metadata = viewModel.lastPhotoMetadataJson {
                        Button(action: {
                            isMetadataExpanded.toggle()
                        }) {
                            HStack {
                                Image(systemName: "info.circle")
                                Text(isMetadataExpanded ? "Hide Metadata" : "Deploy Metadata")
                            }
                        }
                        
                        if isMetadataExpanded {
                            ScrollView {
                                Text(metadata)
                                    .font(.system(.caption2, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxHeight: 250)
                        }
                    } else {
                        Text("No metadata available. Take a photo first.")
                            .foregroundColor(.gray)
                    }
                }
                
                Section {
                    DisclosureGroup("Pichromatic pipeline", isExpanded: $isPipelineConfigExpanded) {
                        VStack(alignment: .leading, spacing: 8) {
                            TextEditor(text: $viewModel.pipelineConfigToml)
                                .font(.system(.body, design: .monospaced))
                                .frame(minHeight: 300)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.none)
                                .onChange(of: viewModel.pipelineConfigToml) { newValue in
                                    print("DEBUG SWIFT: pipelineConfigToml changed to \(newValue.count) chars")
                                }
                            
                            Button(action: {
                                viewModel.resetPipelineConfigToDefault()
                            }) {
                                HStack {
                                    Image(systemName: "arrow.counterclockwise")
                                    Text("Reset to Default")
                                }
                                .font(.subheadline)
                                .foregroundColor(.red)
                            }
                            .padding(.top, 4)
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


// MARK: - Skeuomorphic Design Extensions

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

extension View {
    func innerShadow<S: Shape>(shape: S, color: Color = .black.opacity(0.8), radius: CGFloat = 2, offsetX: CGFloat = 1, offsetY: CGFloat = 1) -> some View {
        self.overlay(
            shape
                .stroke(color, lineWidth: radius)
                .shadow(color: color, radius: radius, x: offsetX, y: offsetY)
                .clipShape(shape)
        )
    }
}

struct TactileButtonStyle: ButtonStyle {
    var isSelected: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Group {
                    if isSelected {
                        // Sunken (Recessed) state
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(hex: "0E0E0E"))
                            .innerShadow(shape: RoundedRectangle(cornerRadius: 6), color: .black, radius: 2, offsetX: 1, offsetY: 1)
                    } else {
                        // Raised state
                        RoundedRectangle(cornerRadius: 6)
                            .fill(LinearGradient(
                                gradient: Gradient(colors: [Color(hex: "2A2A2A"), Color(hex: "1C1B1B")]),
                                startPoint: .top,
                                endPoint: .bottom
                            ))
                            .shadow(color: Color.black.opacity(0.5), radius: 2, x: 0, y: 1.5)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                            )
                    }
                }
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.15), value: configuration.isPressed)
    }
}
