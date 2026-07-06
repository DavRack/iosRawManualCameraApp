//
//  ExposureSliderView.swift
//  iosManualRawCamera
//
//  Created by Jonathan Thomas on 2025-10-14.
//

import SwiftUI
import AVFoundation

struct ExposureSliderView: View {
    let tickValues: [Int]
    let viewModel: CameraViewModel
    let exposureType: ExposureType
    
    // Smooth horizontal 1:1 scrolling state
    @State private var scrollPosition: Double
    @State private var isDragging: Bool = false
    @State private var dragStartPosition: Double = 0
    
    // Horizontal item spacing
    private let tickSpacing: CGFloat = 34
    
    init(tickValues: [Int], viewModel: CameraViewModel, exposureType: ExposureType) {
        self.tickValues = tickValues
        self.viewModel = viewModel
        self.exposureType = exposureType
        
        let initialValue: Int
        if exposureType == .iso {
            initialValue = Int(viewModel.iso)
        } else {
            initialValue = Int(viewModel.shutterSpeed.timescale)
        }
        let initialIndex = tickValues.firstIndex(of: initialValue) ?? 0
        self._scrollPosition = State(initialValue: Double(initialIndex))
    }
    
    private var tickCount: Int {
        tickValues.count
    }
    
    private func valueString(for index: Int) -> String {
        guard index >= 0 && index < tickValues.count else { return "" }
        let val = tickValues[index]
        if exposureType == .iso {
            return "\(val)"
        } else {
            return "1/\(val)"
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            let sliderWidth = geometry.size.width
            let sliderHeight = geometry.size.height
            let centerX = sliderWidth / 2
            
            ZStack {
                // Cylindrical Recessed Background
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(
                        gradient: Gradient(colors: [Color(hex: "121212"), Color(hex: "080808")]),
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                    .innerShadow(shape: RoundedRectangle(cornerRadius: 6), color: .black, radius: 2, offsetX: 1, offsetY: 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if !isDragging {
                                    isDragging = true
                                    dragStartPosition = scrollPosition
                                }
                                
                                // Horizontal translation maps to index updates
                                let deltaTicks = Double(value.translation.width / tickSpacing)
                                let newPosition = dragStartPosition - deltaTicks
                                let clampedPosition = max(0.0, min(Double(tickCount - 1), newPosition))
                                
                                scrollPosition = clampedPosition
                                
                                // Update ViewModel on integer step changes
                                let index = Int(round(clampedPosition))
                                if exposureType == .iso {
                                    let targetIso = Double(tickValues[index])
                                    if viewModel.iso != targetIso {
                                        viewModel.iso = targetIso
                                        triggerHaptic()
                                    }
                                } else {
                                    let targetSS = Int32(tickValues[index])
                                    if viewModel.shutterSpeed.timescale != targetSS {
                                        viewModel.shutterSpeed = CMTime(value: 1, timescale: targetSS)
                                        triggerHaptic()
                                    }
                                }
                            }
                            .onEnded { _ in
                                isDragging = false
                                let snappedIndex = Int(round(scrollPosition))
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                                    scrollPosition = Double(snappedIndex)
                                }
                            }
                    )
                
                // Vertical Selection Frame Highlights (Clock app style slot, but vertical)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.04))
                    .frame(width: 44, height: 26)
                    .allowsHitTesting(false)
                
                // Horizontal Scrolling Cylindrical 3D Picker Elements
                ZStack {
                    let visibleBuffer = Int(ceil(sliderWidth / (2 * tickSpacing))) + 1
                    let centerInt = Int(round(scrollPosition))
                    let rangeStart = max(0, centerInt - visibleBuffer)
                    let rangeEnd = min(tickCount - 1, centerInt + visibleBuffer)
                    
                    ForEach(rangeStart...rangeEnd, id: \.self) { index in
                        let tickX = CGFloat(Double(index) - scrollPosition) * tickSpacing + centerX
                        let distanceFromCenter = tickX - centerX
                        let maxDistance = sliderWidth / 2
                        let ratio = distanceFromCenter / maxDistance
                        let clampedRatio = max(-1.0, min(1.0, Double(ratio)))
                        
                        // 3D Perspective Rotation around vertical Y-axis
                        let angle = Angle(degrees: clampedRatio * 60)
                        let scale = 1.0 - abs(clampedRatio) * 0.15
                        let opacity = index == Int(round(scrollPosition)) ? 1.0 : (1.0 - abs(clampedRatio) * 0.7)
                        
                        Text(valueString(for: index))
                            .font(.system(size: index == Int(round(scrollPosition)) ? 13 : 11, weight: .bold, design: .monospaced))
                            .foregroundColor(index == Int(round(scrollPosition)) ? Color(hex: "C0392B") : .white)
                            .opacity(opacity)
                            .scaleEffect(scale)
                            .rotation3DEffect(angle, axis: (x: 0.0, y: 1.0, z: 0.0), anchor: .center, perspective: 0.5)
                            .offset(x: tickX - centerX, y: 3)
                    }
                }
                .frame(width: sliderWidth)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .allowsHitTesting(false)
                
                // Tiny Corner Label Indicator
                VStack {
                    HStack {
                        Text(exposureType == .iso ? "ISO" : "SHUTTER")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "C5C7C1"))
                            .padding(.leading, 6)
                            .padding(.top, 4)
                        Spacer()
                    }
                    Spacer()
                }
                .allowsHitTesting(false)
            }
        }
        .frame(height: 44)
        .onChange(of: viewModel.iso) { newIso in
            if !isDragging && exposureType == .iso {
                if let idx = tickValues.firstIndex(of: Int(newIso)) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        scrollPosition = Double(idx)
                    }
                }
            }
        }
        .onChange(of: viewModel.shutterSpeed) { newSS in
            if !isDragging && exposureType == .shutterSpeed {
                if let idx = tickValues.firstIndex(of: Int(newSS.timescale)) {
                    withAnimation(.easeOut(duration: 0.15)) {
                        scrollPosition = Double(idx)
                    }
                }
            }
        }
    }
    
    private func triggerHaptic() {
        #if !targetEnvironment(simulator)
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        #endif
    }
}

enum ExposureType {
    case iso
    case shutterSpeed
}
