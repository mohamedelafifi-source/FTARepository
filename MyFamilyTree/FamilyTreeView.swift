//
//  FamilyTreeView.swift
//  MyFamilyTree
//
//  Created by Mohamed El Afifi on 9/30/25.
//


import SwiftUI
import Foundation
import PhotosUI

// MARK: - Anchor PreferenceKey
struct MemberPositionKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGPoint>] = [:]
    
    static func reduce(value: inout [String: Anchor<CGPoint>], nextValue: () -> [String: Anchor<CGPoint>]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

// MARK: - Connector Overlay to draw lines between spouses
struct SpouseConnectorOverlay: View {
    let anchors: [String: Anchor<CGPoint>]
    let members: [FamilyMember]
    let buttonWidth: CGFloat
    let buttonHeight: CGFloat
    
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(members, id: \.id) { member in
                    ForEach(member.spouses, id: \.self) { spouseName in
                        if let memberAnchor = anchors[member.name],
                           let spouseAnchor = anchors[spouseName] {
                            
                            let memberPoint = proxy[memberAnchor]
                            let spousePoint = proxy[spouseAnchor]
                            
                            // Adjust the y-coordinate to a point above the bottom of the button
                            let yOffset: CGFloat = buttonHeight / 2 - 5
                            
                            // Calculate the start and end points at the edges of the buttons
                            let startPoint = CGPoint(x: memberPoint.x + buttonWidth / 2, y: memberPoint.y + yOffset)
                            let endPoint = CGPoint(x: spousePoint.x - buttonWidth / 2, y: spousePoint.y + yOffset)
                            
                            // Shorten the horizontal line by 20%
                            let totalDistance = endPoint.x - startPoint.x
                            let shortenedDistance = totalDistance * 0.8 // Now 80% of the original length
                            
                            // Corrected and simplified points for the line
                            let shortenedStartPoint = CGPoint(x: startPoint.x + (totalDistance - shortenedDistance) / 2, y: startPoint.y)
                            let shortenedEndPoint = CGPoint(x: endPoint.x - (totalDistance - shortenedDistance) / 2, y: endPoint.y)
                            
                            // Create a slight curve between the points for a better visual
                            let controlPoint1 = CGPoint(x: shortenedStartPoint.x + (shortenedEndPoint.x - shortenedStartPoint.x) / 3, y: shortenedStartPoint.y)
                            let controlPoint2 = CGPoint(x: shortenedStartPoint.x + 2 * (shortenedEndPoint.x - shortenedStartPoint.x) / 3, y: shortenedEndPoint.y)
                            
                            Path { path in
                                path.move(to: shortenedStartPoint)
                                path.addCurve(to: shortenedEndPoint, control1: controlPoint1, control2: controlPoint2)
                            }
                            .stroke(Color.black.opacity(0.8), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        }
                    }
                }
            }
        }
    }
}


// MARK: - FamilyTreeView
struct FamilyTreeView: View {
    @ObservedObject var manager = FamilyDataManager.shared
    
    @State private var anchorMap: [String: Anchor<CGPoint>] = [:]
    
    // Add a state variable to hold the calculated button size
    @State private var buttonSize: CGSize = .zero
    
    var grouped: [LevelGroup] {
        if let focus = manager.focusedMemberId {
            return manager.getConnectedFamilyOf(memberId: focus)
        } else {
            return manager.getAllLevels()
        }
    }
    
    func color(for level: Int) -> Color {
        let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal]
        return palette[level % palette.count]
    }
    
    var body: some View {
        ZStack {
            VStack {
                if let focusedMemberId = manager.focusedMemberId,
                   let focusedMember = manager.members.first(where: { $0.id == focusedMemberId }) {
                    Text("Focused: \(focusedMember.name)")
                        .font(.headline)
                        .padding(.top)
                        .padding(.bottom, 5)
                }
                
                if manager.focusedMemberId != nil {
                    Button("Show Full Tree") {
                        manager.focusedMemberId = nil
                    }
                    .padding()
                }
                
                ScrollView(.vertical) {
                    VStack(spacing: 40) {
                        ForEach(grouped, id: \.level) { group in
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 20) {
                                    ForEach(group.members, id: \.id) { member in
                                        let isFocused = member.id == manager.focusedMemberId
                                        
                                        Text(member.name)
                                            .padding()
                                            .background(isFocused ? Color.red.opacity(0.5) : color(for: group.level).opacity(0.3))
                                            .cornerRadius(8)
                                            .onTapGesture {
                                                manager.focusedMemberId = member.id
                                            }
                                            .anchorPreference(key: MemberPositionKey.self, value: .center) {
                                                [member.name: $0]
                                            }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.vertical)
                    .onPreferenceChange(MemberPositionKey.self) { value in
                        anchorMap = value
                    }
                }
            }
            
            // Hidden view to measure the button size
            Text("Sample")
                .padding()
                .background(Color.clear)
                .cornerRadius(8)
                .overlay(
                    GeometryReader { proxy in
                        Color.clear.onAppear {
                            buttonSize = proxy.size
                        }
                    }
                )
                .opacity(0) // Hide the view
            
            let visibleNames = grouped.flatMap { $0.members.map { $0.name } }
            let visibleMembers = manager.members.filter { visibleNames.contains($0.name) }
            
            
            if !anchorMap.isEmpty && buttonSize != .zero {
                SpouseConnectorOverlay(
                    anchors: anchorMap,
                    members: visibleMembers,
                    buttonWidth: buttonSize.width,
                    buttonHeight: buttonSize.height
                )
                
                /*.allowsHitTesting(false) is a SwiftUI view modifier that disables hit testing for the view and all of its subviews. In other words, the view will ignore all touch/tap/gesture interactions and let those interactions “pass through” to views underneath it in the z-order.
                 */
                .allowsHitTesting(false)
            }
            
            
        }
    }
}

