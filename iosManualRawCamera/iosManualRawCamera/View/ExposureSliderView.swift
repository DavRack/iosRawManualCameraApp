//
//  ExposureSliderView.swift
//  iosManualRawCamera
//
//  Created by Jonathan Thomas on 2025-10-14.
//

import SwiftUI
import AVFoundation

struct ExposureSliderView: View {
    
    //accepts tick values array, camera view model and epxosure type
    let tickValues: [Int]
    let viewModel: CameraViewModel
    let exposureType: ExposureType
    
    @State private var currentTickIndex: Int
    @State private var tickOffset: CGFloat = 0
    @State private var lastDragTranslation: CGFloat = 0
    
    //fixed tick spacing
    private let tickSpacing: CGFloat = 15
    private let phantomTickCount: Int = 10 //un-selectable ticks at edges
    
    init(tickValues: [Int], viewModel: CameraViewModel, exposureType: ExposureType) {
        self.tickValues = tickValues
        self.viewModel = viewModel
        self.exposureType = exposureType
        
        var initialIndex: Int
        if exposureType == .iso {
            initialIndex = tickValues.firstIndex(of: Int(viewModel.iso))!
        } else {
            initialIndex = tickValues.firstIndex(of: Int(viewModel.shutterSpeed.timescale))!
        }
        
        self._currentTickIndex = State(initialValue: initialIndex)
    }
    
    // Computed properties
    private var tickCount: Int {
        return tickValues.count
    }
    
    private var totalTickCount: Int {
        return tickCount + (phantomTickCount * 2)
    }
    
    private var currentValue: Int {
        guard currentTickIndex >= 0 && currentTickIndex < tickValues.count else {
            return 0
        }
        return tickValues[currentTickIndex]
    }
    
    // Calculate which ticks are actually visible
    private func visibleTickRange(for sliderWidth: CGFloat) -> Range<Int> {
        let ticksPerSide = Int(ceil(sliderWidth / (2 * tickSpacing))) + 2 //buffer
        let start = currentTickIndex - ticksPerSide - phantomTickCount
        let end = currentTickIndex + ticksPerSide + phantomTickCount + 1
        return start..<end
    }
    
    var body: some View {
        GeometryReader { geometry in
            let sliderWidth = geometry.size.width
            let sliderHeight: CGFloat = 90
            let centerX = sliderWidth / 2
            let visibleRange = visibleTickRange(for: sliderWidth)
            
            ZStack {
                // Background container
                RoundedRectangle(cornerRadius: 100)
                    .fill(Color.black.opacity(0.5))
                    .background(
                        RoundedRectangle(cornerRadius: 100)
                            .fill(.ultraThinMaterial)
                    )
                    .frame(width: sliderWidth, height: sliderHeight)
                    .shadow(color: .black.opacity(0.3), radius: 3.9, x: 0, y: 9)
                    .overlay(
                        RoundedRectangle(cornerRadius: 100)
                            .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let dragDistance = value.translation.width - lastDragTranslation
                                
                                // Calculate how many ticks we've moved based on fixed spacing
                                let ticksMoved = Int(round(dragDistance / tickSpacing))
                                
                                if ticksMoved != 0 {
                                    let newTickIndex = currentTickIndex - ticksMoved
                                    
                                    // Clamp to valid range (only real ticks, not phantom ones)
                                    currentTickIndex = max(0, min(tickCount - 1, newTickIndex))
                                    
                                    // Haptic feedback
                                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                    impactFeedback.impactOccurred()
                                    
                                    // Update the last drag translation to prevent accumulation
                                    lastDragTranslation = value.translation.width
                                }
                            }
                            .onEnded { _ in
                                lastDragTranslation = 0
                                
                                //update camera settings
                                if exposureType == .iso {
                                    viewModel.iso = Double(currentValue)
                                } else {
                                    viewModel.shutterSpeed = CMTime(value: 1, timescale: Int32(currentValue))
                                }
                            }
                    )
                
                
                VStack(spacing: 4) {
                    
                    // Fixed center indicator
                    Text(exposureType == .iso ? "\(currentValue)" : "1/\(currentValue)")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Triangle()
                        .fill(Color(red: 0.49, green: 0.53, blue: 1))
                        .frame(width: 8, height: 6)
                        .offset(y: -2)
                        .padding(.bottom, 4)
                    
                    // Moving tick marks container - only render visible ticks
                    ZStack(alignment: .bottom) {
                        // Only generate visible ticks
                        ForEach(max(visibleRange.lowerBound, -phantomTickCount)..<min(visibleRange.upperBound, tickCount + phantomTickCount), id: \.self) { index in
                            let adjustedIndex = index + phantomTickCount // Offset for phantom calculation
                            let tickX = CGFloat(index - currentTickIndex) * tickSpacing + centerX
                            
                            TickMark(
                                index: adjustedIndex,
                                tickX: tickX,
                                centerX: centerX,
                                sliderWidth: sliderWidth,
                                isPhantom: index < 0 || index >= tickCount
                            )
                            .offset(x: tickX - centerX, y: 0)
                        }
                    }
                    .frame(width: sliderWidth, height: 30)
                    .padding(.bottom, 10)
                    .clipShape(RoundedRectangle(cornerRadius: 100))
                    .allowsHitTesting(false)
                    .animation(.easeOut(duration: 0.2), value: currentTickIndex)
                }
                .allowsHitTesting(false)
            }
        }
        .frame(height: 100)
    }
}

struct TickMark: View {
    let index: Int
    let tickX: CGFloat
    let centerX: CGFloat
    let sliderWidth: CGFloat
    let isPhantom: Bool
    
    private var tickOpacity: Double {
        // Calculate opacity based on distance from center of the view
        let distanceFromCenter = abs(tickX - centerX)
        let maxDistance = sliderWidth / 2
        let normalizedDistance = min(distanceFromCenter / maxDistance, 1.0)
        
        //base opacity calculation
        let baseOpacity = pow(0.005, pow(normalizedDistance, 5))
        
        //phantom ticks greyed out
        return isPhantom ? baseOpacity * 0.05 : baseOpacity
    }
    
    private var tickHeight: CGFloat {
        if index % 5 == 0 {
            return 30 // tall tick
        } else {
            return 20 // short tick
        }
    }
    
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(tickOpacity))
            .frame(width: 2, height: tickHeight)
            .animation(.easeInOut(duration: 0.2), value: tickOpacity)
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

enum ExposureType {
    case iso
    case shutterSpeed
}
