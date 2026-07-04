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
    @State private var isConfigModalPresented = false
    
    
    var body: some View {
        ZStack {
            // Camera preview
            CameraPreviewView(session: cameraFeedRunning ? viewModel.captureSession : nil) //once camera feed starts pass in session
                .edgesIgnoringSafeArea(.all)
                .onAppear {
                    viewModel.getDeviceSpecs() //get iso and shutterspeed range for device
                }
            
            // Full screen tap-to-dismiss overlay
            if isoWheelActive || ssWheelActive {
                Color.clear
                    .contentShape(Rectangle())
                    .edgesIgnoringSafeArea(.all)
                    .onTapGesture {
                        isoWheelActive = false
                        ssWheelActive = false
                    }
            }
            
            
            VStack {
                Spacer()
                
                //MARK: exposure sliders
                if isoWheelActive {
                    let min = Int(viewModel.minISO)
                    let max = Int(viewModel.maxISO)
                    let isoValues = Array(stride(from: min, through: max, by: 50))
                    
                    ExposureSliderView(tickValues: isoValues, viewModel: viewModel, exposureType: .iso)
                        .padding(.bottom, 10)
                        .padding(.horizontal, 40)
                        .onTapGesture {
                            // Prevent tap propagation
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        ))
                    
                } else if ssWheelActive {
                    
                    let min = viewModel.minShutterSpeed
                    let max = viewModel.maxShutterSpeed
                    let ssValues = Array(stride(from: min, through: max, by: 10))
                    
                    ExposureSliderView(tickValues: ssValues, viewModel: viewModel, exposureType: .shutterSpeed)
                        .padding(.bottom, 10)
                        .padding(.horizontal, 40)
                        .onTapGesture {
                            // Prevent tap propagation
                        }
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        ))
                    
                } else {
                    
                    //MARK: exp settings toolbar
                    HStack(alignment: .center, spacing: 20) {
                        
                        // Flash button
                        Button(action: {
                            flashOn.toggle()
                            viewModel.setupTorch(flashOn)
                        }) {
                            Image(systemName: flashOn ? "bolt.fill" : "bolt.slash.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white)
                        }
                        
                        // Auto/Manual Exposure Mode Toggle Button
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
                        
                        // ISO button
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
                                    .foregroundColor(viewModel.isAutoExposure ? .gray : .white)
                                Text(viewModel.isAutoExposure ? "Auto" : String(Int(viewModel.iso)))
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(viewModel.isAutoExposure ? .gray : .white)
                            }
                        }
                        .disabled(viewModel.isAutoExposure)
                        
                        // Shutter Speed Button
                        Button(action: {
                            if !viewModel.isAutoExposure {
                                ssWheelActive = true
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "stopwatch")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(viewModel.isAutoExposure ? .gray : .white)
                                Text(viewModel.isAutoExposure ? "Auto" : "1/\(Int(viewModel.shutterSpeed.timescale))s")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundColor(viewModel.isAutoExposure ? .gray : .white)
                            }
                        }
                        .disabled(viewModel.isAutoExposure)
                        
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 25)
                            .fill(Color.black.opacity(0.35))
                            .background(
                                RoundedRectangle(cornerRadius: 25)
                                    .fill(.ultraThinMaterial)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 25)
                            .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                    .padding(.bottom, 20)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                }
                
                
                // MARK: bottom Controls
                HStack {
                    
                    // Thumbnail preview
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
                            
                        Text("\(captureCount)")
                            .foregroundColor(.white)
                            .font(.system(size: 16, weight: .medium))
                            .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                    .animation(.spring(response: 0.3), value: viewModel.lastCapturedThumbnail)
                    
                    
                    
                    Spacer()
                    
                    // MARK: Capture button
                    Button(action: {
                        viewModel.capturePhoto(false, false, nil)
                        triggerCameraHapticFeedback()
                        captureCount += 1
                    }) {
                        Image("captureButton")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 115, height: 115)
                    }
                    .accessibilityIdentifier("captureButton")
                    
                    Spacer()
                    
                    // Configuration Button (opens Modal)
                    Button(action: {
                        isConfigModalPresented = true
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.black.opacity(0.6))
                                .frame(width: 60, height: 60)
                                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 4)
                            
                            VStack(spacing: 3) {
                                Image(systemName: "gearshape.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                                Text(viewModel.exportFormat.shortName)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                            }
                        }
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        )
                    }
                        
                    
                }
                .padding(.horizontal, 30)
                .padding(.bottom, 30)
            }
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isoWheelActive)
            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: ssWheelActive)
            
        }
        .onAppear{
            
            //setup camera
            viewModel.setupCamera(false, nil) { result in
                switch result {
                case .success:
                    print("Camera setup complete")
                    cameraFeedRunning = true
                case .failure:
                    print("Error with camera setup")
                }
            }
        }
        .sheet(isPresented: $isConfigModalPresented) {
            ConfigView(viewModel: viewModel)
        }
    }
    
    
    
    // Helper function to trigger haptic feedback
    func triggerCameraHapticFeedback() {
        
        let impactFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)
        impactFeedbackGenerator.prepare()
        impactFeedbackGenerator.impactOccurred()
    }
}



class UICameraPreviewView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
    
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }
}

// Camera preview
struct CameraPreviewView: UIViewRepresentable {
    var session: AVCaptureSession?
    
    func makeUIView(context: Context) -> UICameraPreviewView {
        let view = UICameraPreviewView()
        view.previewLayer.videoGravity = .resizeAspectFill
        if let session = session {
            view.previewLayer.session = session
        }
        return view
    }
    
    func updateUIView(_ uiView: UICameraPreviewView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
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

