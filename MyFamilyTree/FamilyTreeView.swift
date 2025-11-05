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

        // Limit to names that have a computed relative level
        let relevant = finalNames.filter { relativeLevels.keys.contains($0) }

        // Canonicalize: choose a single level per person (minimum relative level)
        var chosenLevelForName: [String: Int] = [:]
        for name in relevant {
            if let rl = relativeLevels[name] {
                if let existing = chosenLevelForName[name] {
                    chosenLevelForName[name] = min(existing, rl)
                } else {
                    chosenLevelForName[name] = rl
                }
            }
        }

        // Normalize so that the minimum chosen level becomes 0 (as before)
        let minChosen = chosenLevelForName.values.min() ?? 0
        let adjust = (minChosen < 0) ? -minChosen : 0

        // Create a single instance of each member at its canonical level
        var canonicalMembers: [FamilyMember] = []
        canonicalMembers.reserveCapacity(chosenLevelForName.count)
        for (name, rl) in chosenLevelForName {
            if var m = dict[name] {
                m.level = rl + adjust
                canonicalMembers.append(m)
            }
        }

        // Final defensive de-duplication by id (ensures no duplicates even if name-based paths overlapped)
        var seenIDs = Set<UUID>()
        // Group by level and sort
        let grouped = Dictionary(grouping: canonicalMembers, by: { $0.level })
        var levelGroups: [LevelGroup] = []
        for level in grouped.keys.sorted() {
            if let mems = grouped[level] {
                if mems.isEmpty { continue }
                // Use the focused member only if it exists in this level and there is something to sort around
                let focusedInLevel = (mems.count > 1) ? mems.first(where: { $0.id == focusedMember.id }) : nil

                // Sort defensively; if sort returns empty, fall back to original order
                let maybeSorted = manager.sortLevel(mems, focused: focusedInLevel)
                let sortedMems = maybeSorted.isEmpty ? mems : maybeSorted

                // Group spouses adjacently in focused mode with level-local focus
                let spouseAdj = spouseAdjacentOrder(sortedMems, dict: dict, focused: focusedInLevel)
                var seen = Set<UUID>()
                let uniqueSorted = spouseAdj.filter { seen.insert($0.id).inserted }
                levelGroups.append(LevelGroup(level: level, members: uniqueSorted))
            }
        }
        return levelGroups
    }
    
    // Arrange spouses adjacently within a level (focused view only)
    private func spouseAdjacentOrder(_ members: [FamilyMember], dict: [String: FamilyMember], focused: FamilyMember?) -> [FamilyMember] {
        // Index by name for quick lookup among this level's members
        var byName: [String: FamilyMember] = [:]
        for m in members {
            if byName[m.name] == nil {
                byName[m.name] = m
            }
        }

        // Build spouse adjacency among members present at this level
        var adj: [String: Set<String>] = [:]
        for m in members {
            let inLevelSpouses = m.spouses.filter { byName[$0] != nil }
            if !inLevelSpouses.isEmpty {
                var set = adj[m.name] ?? []
                for s in inLevelSpouses {
                    set.insert(s)
                    var sSet = adj[s] ?? []
                    sSet.insert(m.name)
                    adj[s] = sSet
                }
                adj[m.name] = set
            }
        }

        // Find connected components of the spouse graph
        var visited = Set<String>()
        var components: [[FamilyMember]] = []
        for m in members {
            guard !visited.contains(m.name) else { continue }
            var comp: [FamilyMember] = []
            var stack: [String] = [m.name]
            visited.insert(m.name)
            while let n = stack.popLast() {
                if let mem = byName[n] { comp.append(mem) }
                for nei in (adj[n] ?? []) where !visited.contains(nei) {
                    visited.insert(nei)
                    stack.append(nei)
                }
            }
            components.append(comp)
        }

        // Order within each component: prefer nodes with higher spouse-degree first, then by name for stability
        func degree(_ m: FamilyMember) -> Int { (adj[m.name]?.count ?? 0) }
        let orderedComponents: [[FamilyMember]] = components.map { comp in
            comp.sorted { a, b in
                let da = degree(a), db = degree(b)
                if da != db { return da > db }
                return a.name < b.name
            }
        }

        // Put the component containing the focused member first (if present)
        var focusFirst = orderedComponents
        if let focused = focused {
            if let idx = orderedComponents.firstIndex(where: { comp in comp.contains(where: { $0.id == focused.id }) }) {
                let comp = orderedComponents[idx]
                focusFirst.remove(at: idx)
                focusFirst.insert(comp, at: 0)
            }
        }

        // Flatten
        return focusFirst.flatMap { $0 }
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
                        Text("You have unsaved changes. Use File > Save")
                            //.font(.footnote)
                            .font(.headline)
                            .foregroundStyle(.red)
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
                
                let allVisibleMembers = grouped.flatMap { $0.members }
                var seenVisible = Set<UUID>()
                let visibleMembers = allVisibleMembers.filter { seenVisible.insert($0.id).inserted }
                
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

