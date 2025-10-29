//
//  FamilyTreeView.swift
//  MyFamilyTree
//
//  Created by Mohamed El Afifi on 9/30/25.
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
    
    // Define how much the line should extend past the button edge
    // I increased the extension from 10 to 20
    let extensionAmount: CGFloat = 20
    
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(members, id: \.id) { member in
                    // Ensure we only draw the line once per spouse pair
                    let sortedSpouses = member.spouses.filter { $0 > member.name }
                    
                    ForEach(sortedSpouses, id: \.self) { spouseName in
                        if let memberAnchor = anchors[member.name],
                           let spouseAnchor = anchors[spouseName] {
                            
                            let memberPoint = proxy[memberAnchor]
                            let spousePoint = proxy[spouseAnchor]
                            
                            // Anchor is .center, so we move down half the height minus a small offset
                            let yOffset: CGFloat = buttonHeight / 2 - 5
                            
                            // Calculate the initial start and end points at the edges of the buttons (always left-to-right)
                            let (initialStartPoint, initialEndPoint) = {
                                if memberPoint.x < spousePoint.x {
                                    // Member is on the left
                                    let start = CGPoint(x: memberPoint.x + buttonWidth / 2, y: memberPoint.y + yOffset)
                                    let end = CGPoint(x: spousePoint.x - buttonWidth / 2, y: spousePoint.y + yOffset)
                                    return (start, end)
                                } else {
                                    // Spouse is on the left
                                    let start = CGPoint(x: spousePoint.x + buttonWidth / 2, y: spousePoint.y + yOffset)
                                    let end = CGPoint(x: memberPoint.x - buttonWidth / 2, y: memberPoint.y + yOffset)
                                    return (start, end)
                                }
                            }()
                            
                            // **FIX:** Extend the line on both the start and end sides
                            let shortenedStartPoint = CGPoint(x: initialStartPoint.x - extensionAmount, y: initialStartPoint.y)
                            let shortenedEndPoint = CGPoint(x: initialEndPoint.x + extensionAmount, y: initialEndPoint.y)
                            
                            // Create a slight curve (optional, but maintained for visual style)
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
    
    // State variables
    @State private var positionAnchors: [String: Anchor<CGPoint>] = [:]
    @State private var memberButtonSize: CGSize = .zero
    @State private var derivedDict: [String: FamilyMember] = [:]
    
    // NEW STATE: To force a final view update after collecting preferences.
    @State private var shouldShowOverlay = false
    
    private func buildAllLevels(from dict: [String: FamilyMember]) -> [LevelGroup] {
        var visited = Set<String>()
        var levels: [Int: [FamilyMember]] = [:]
        func assignLevel(_ member: FamilyMember, level: Int) {
            guard !visited.contains(member.name) else { return }
            visited.insert(member.name)
            levels[level, default: []].append(member)
            for spouseName in member.spouses { if let spouse = dict[spouseName] { assignLevel(spouse, level: level) } }
            for childName in member.children { if let child = dict[childName] { assignLevel(child, level: level + 1) } }
        }
        let allMembers = Array(dict.values)
        let topLevel = allMembers.filter { $0.parents.isEmpty }
        for member in topLevel { assignLevel(member, level: 0) }
        return levels.keys.sorted().compactMap { lvl in
            if let membersAtLevel = levels[lvl] { return LevelGroup(level: lvl, members: membersAtLevel) } else { return nil }
        }
    }
    
    private func buildConnectedGroups(from dict: [String: FamilyMember], focusId: UUID) -> [LevelGroup] {
        guard let focusedMember = dict.first(where: { $0.value.id == focusId })?.value else { return [] }
        var finalNames = Set<String>()
        finalNames.insert(focusedMember.name)
        for spouse in focusedMember.spouses { finalNames.insert(spouse) }
        for sib in focusedMember.siblings { finalNames.insert(sib) }
        var currentAncestors = focusedMember.parents
        var visitedAnc = Set(currentAncestors)
        var depth = 0
        let maxDepth = 2
        while !currentAncestors.isEmpty && depth < maxDepth {
            var next: [String] = []
            for anc in currentAncestors {
                finalNames.insert(anc)
                if let a = dict[anc] {
                    for s in a.spouses { finalNames.insert(s) }
                    for p in a.parents where visitedAnc.insert(p).inserted { next.append(p) }
                }
            }
            currentAncestors = next
            depth += 1
        }
        var visitedDesc = Set<String>()
        func collectDesc(of name: String) {
            guard let m = dict[name] else { return }
            for child in m.children where visitedDesc.insert(child).inserted {
                finalNames.insert(child)
                if let c = dict[child] { for s in c.spouses { finalNames.insert(s) } }
                collectDesc(of: child)
            }
        }
        collectDesc(of: focusedMember.name)
        let relativeLevels = manager.computeRelativeLevels(from: focusedMember.name, using: dict)
        var finalMembers: [FamilyMember] = []
        let relevant = finalNames.filter { relativeLevels.keys.contains($0) }
        let minLevel = relevant.compactMap { relativeLevels[$0] }.min() ?? 0
        let adjust = (minLevel < 0) ? -minLevel : 0
        for name in relevant { if let m = dict[name], let rl = relativeLevels[name] { var mm = m; mm.level = rl + adjust; finalMembers.append(mm) } }
        let grouped = Dictionary(grouping: finalMembers, by: { $0.level })
        var levelGroups: [LevelGroup] = []
        for level in grouped.keys.sorted() { if let mems = grouped[level] { let sortedMems = manager.sortLevel(mems, focused: focusedMember); levelGroups.append(LevelGroup(level: level, members: sortedMems)) } }
        return levelGroups
    }
    
    func color(for level: Int) -> Color {
        let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal]
        return palette[level % palette.count]
    }
    
    var grouped: [LevelGroup] {
        if derivedDict.isEmpty { return [] }
        if let focus = manager.focusedMemberId {
            return buildConnectedGroups(from: derivedDict, focusId: focus)
        } else {
            return buildAllLevels(from: derivedDict)
        }
    }
    
    var body: some View {
        ZStack {
            // Conditional rendering based on shouldShowOverlay
            if shouldShowOverlay || positionAnchors.isEmpty {
                VStack {
                    if let focusedMemberId = manager.focusedMemberId,
                        let focusedMember = manager.members.first(where: { $0.id == focusedMemberId }) {
                        Text("Focused: \(focusedMember.name)")
                            .font(.headline)
                            .padding(.top)
                            .padding(.bottom, 5)
                    }
                    
                    HStack {
                        Button("Refresh Tree") {
                            derivedDict = manager.makeDerivedDictionaryForDisplay(applySiblingInference: true)
                        }
                        .buttonStyle(.bordered)

                        if manager.focusedMemberId != nil {
                            Button("Show Full Tree") {
                                manager.focusedMemberId = nil
                                derivedDict = manager.makeDerivedDictionaryForDisplay(applySiblingInference: true)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                    
                    if manager.isDirty {
                        Text("You have unsaved changes. Use File > Save to persist your authored data.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .padding(.horizontal)
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
                                                .background(
                                                    // Robust size and position collection
                                                    GeometryReader { proxy in
                                                        Color.clear
                                                            .onAppear {
                                                                // Only measure the size once
                                                                if memberButtonSize == .zero {
                                                                    memberButtonSize = proxy.size
                                                                }
                                                            }
                                                            .anchorPreference(key: MemberPositionKey.self, value: .center) {
                                                                [member.name: $0]
                                                            }
                                                    }
                                                )
                                                .onTapGesture {
                                                    manager.focusedMemberId = member.id
                                                }
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                        .padding(.vertical)
                        // Explicitly trigger a re-render after anchors are collected
                        .onPreferenceChange(MemberPositionKey.self) { value in
                            positionAnchors = value
                            
                            // This ensures the view re-renders with the collected anchors on the next frame
                            DispatchQueue.main.async {
                                shouldShowOverlay = true
                            }
                        }
                    }
                }
                
                let visibleNames = grouped.flatMap { $0.members.map { $0.name } }
                let visibleMembers = derivedDict.values.filter { visibleNames.contains($0.name) }
                
                // Render the overlay only when size and positions are ready and the trigger has fired
                if shouldShowOverlay && !positionAnchors.isEmpty && memberButtonSize != .zero {
                    SpouseConnectorOverlay(
                        anchors: positionAnchors,
                        members: visibleMembers,
                        buttonWidth: memberButtonSize.width,
                        buttonHeight: memberButtonSize.height
                    )
                    .allowsHitTesting(false)
                }
            }
        }
        .onAppear {
            derivedDict = manager.makeDerivedDictionaryForDisplay(applySiblingInference: true)
        }
        .onChange(of: manager.focusedMemberId) { _ in
            // Reset state to force a clean re-measurement cycle and hide the overlay initially
            memberButtonSize = .zero
            positionAnchors = [:]
            shouldShowOverlay = false // Hide the overlay until new anchors are ready
            derivedDict = manager.makeDerivedDictionaryForDisplay(applySiblingInference: true)
        }
    }
}
