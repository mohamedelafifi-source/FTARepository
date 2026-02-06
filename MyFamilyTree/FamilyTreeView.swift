// FamilyTreeView.swift
// MyFamilyTree
//
// Created by Mohamed El Afifi on 9/30/25.
//
// UPDATED with ALL fixes:
// 1. Corrected 'derivedDict' @State bug.
// 2. Added '.id()' modifier to ScrollView.
// 3. Added 'isDrawingSuspended' logic for stable line drawing.
// 4. Replaced '.onTapGesture' with 'Button' to fix "two-click" bug.
// 5. Replaced complex closure in Canvas with simple 'if/else'
//    to fix compiler crash.
// 6. Corrected all typos (mmems, missing braces, etc.)

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

// MARK: - Helper Struct for Spouse Pairs
struct SpousePair: Identifiable {
    let id = UUID()
    let name1: String
    let name2: String
}

// MARK: - Connector Overlay (with Canvas)
struct SpouseConnectorOverlay: View {
    let anchors: [String: Anchor<CGPoint>]
    let pairs: [SpousePair]
    let buttonWidth: CGFloat
    let buttonHeight: CGFloat
    
    // Define how much the line should extend past the button edge
    let extensionAmount: CGFloat = 20
    
    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                var path = Path()
                
                for pair in pairs {
                    guard let memberAnchor = anchors[pair.name1],
                          let spouseAnchor = anchors[pair.name2] else {
                        continue
                    }
                    
                    let memberPoint = proxy[memberAnchor]
                    let spousePoint = proxy[spouseAnchor]
                    let yOffset: CGFloat = buttonHeight / 2 - 5
                    
                    // Simple if/else to prevent compiler crash
                    let initialStartPoint: CGPoint
                    let initialEndPoint: CGPoint
                    
                    if memberPoint.x < spousePoint.x {
                        // Member is on the left
                        initialStartPoint = CGPoint(x: memberPoint.x + buttonWidth / 2, y: memberPoint.y + yOffset)
                        initialEndPoint = CGPoint(x: spousePoint.x - buttonWidth / 2, y: spousePoint.y + yOffset)
                    } else {
                        // Spouse is on the left
                        initialStartPoint = CGPoint(x: spousePoint.x + buttonWidth / 2, y: spousePoint.y + yOffset)
                        initialEndPoint = CGPoint(x: memberPoint.x - buttonWidth / 2, y: memberPoint.y + yOffset)
                    }

                    let shortenedStartPoint = CGPoint(x: initialStartPoint.x - extensionAmount, y: initialStartPoint.y)
                    let shortenedEndPoint = CGPoint(x: initialEndPoint.x + extensionAmount, y: initialEndPoint.y)
                    let controlPoint1 = CGPoint(x: shortenedStartPoint.x + (shortenedEndPoint.x - shortenedStartPoint.x) / 3, y: shortenedStartPoint.y)
                    let controlPoint2 = CGPoint(x: shortenedStartPoint.x + 2 * (shortenedEndPoint.x - shortenedStartPoint.x) / 3, y: shortenedEndPoint.y)
                    
                    path.move(to: shortenedStartPoint)
                    path.addCurve(to: shortenedEndPoint, control1: controlPoint1, control2: controlPoint2)
                }
                
                context.stroke(path, with: .color(Color.black.opacity(0.8)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                
            }
            .allowsHitTesting(false)
        }
    }
}


// MARK: - FamilyTreeView
struct FamilyTreeView: View {
    @ObservedObject var manager = FamilyDataManager.shared
    
    // State variables
    @State private var positionAnchors: [String: Anchor<CGPoint>] = [:]
    @State private var memberButtonSize: CGSize = .zero
    @State private var isDrawingSuspended = true
    
    @State private var showAttachments = false
    @State private var attachmentsMemberName: String = ""
    
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

        let relevant = finalNames.filter { relativeLevels.keys.contains($0) }
        let relevantSet = Set(relevant)

        var spouseGraph: [String: Set<String>] = [:]
        for name in relevant {
            guard let member = dict[name] else { continue }
            let relevantSpouses = member.spouses.filter { relevantSet.contains($0) }
            for spouseName in relevantSpouses {
                spouseGraph[name, default: []].insert(spouseName)
                spouseGraph[spouseName, default: []].insert(name)
            }
        }

        var finalCanonicalLevel: [String: Int] = [:]
        var visited = Set<String>()
        
        for name in relevant {
            guard !visited.contains(name) else { continue }
            
            var component: [String] = []
            var stack: [String] = [name]
            var minLevelInComponent = relativeLevels[name] ?? 0
            
            visited.insert(name)
            
            while let currentName = stack.popLast() {
                component.append(currentName)
                minLevelInComponent = min(minLevelInComponent, relativeLevels[currentName] ?? 0)
                
                for spouse in spouseGraph[currentName, default: []] {
                    if !visited.contains(spouse) {
                        visited.insert(spouse)
                        stack.append(spouse)
                    }
                }
            }
            
            for componentMemberName in component {
                finalCanonicalLevel[componentMemberName] = minLevelInComponent
            }
        }
        
        for name in relevant {
            if finalCanonicalLevel[name] == nil {
                if let level = relativeLevels[name] {
                    finalCanonicalLevel[name] = level
                }
            }
        }

        let minChosen = finalCanonicalLevel.values.min() ?? 0
        let adjust = (minChosen < 0) ? -minChosen : 0

        var canonicalMembers: [FamilyMember] = []
        canonicalMembers.reserveCapacity(finalCanonicalLevel.count)
        
        for (name, rl) in finalCanonicalLevel {
            if var m = dict[name] {
                m.level = rl + adjust
                canonicalMembers.append(m)
            }
        }

        var seenIDs = Set<UUID>()
        let uniqueMembers = canonicalMembers.filter { seenIDs.insert($0.id).inserted }

        let grouped = Dictionary(grouping: uniqueMembers, by: { $0.level })
        var levelGroups: [LevelGroup] = []
        for level in grouped.keys.sorted() {
            if let mems = grouped[level] {
                if mems.isEmpty { continue }
                let focusedInLevel = (mems.count > 1) ? mems.first(where: { $0.id == focusedMember.id }) : nil
                let maybeSorted = manager.sortLevel(mems, focused: focusedInLevel)
                let sortedMems = maybeSorted.isEmpty ? mems : maybeSorted
                
                let spouseAdj = spouseAdjacentOrder(sortedMems, dict: dict, focused: focusedInLevel)
                var seen = Set<UUID>()
                let uniqueSorted = spouseAdj.filter { seen.insert($0.id).inserted }
                levelGroups.append(LevelGroup(level: level, members: uniqueSorted))
            }
        }
        return levelGroups
    }
    
    private func spouseAdjacentOrder(_ members: [FamilyMember], dict: [String: FamilyMember], focused: FamilyMember?) -> [FamilyMember] {
        var byName: [String: FamilyMember] = [:]
        for m in members {
            if byName[m.name] == nil {
                byName[m.name] = m
            }
        }

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

        func degree(_ m: FamilyMember) -> Int { (adj[m.name]?.count ?? 0) }
        let orderedComponents: [[FamilyMember]] = components.map { comp in
            comp.sorted { a, b in
                let da = degree(a), db = degree(b)
                if da != db { return da > db }
                return a.name < b.name
            }
        }

        var focusFirst = orderedComponents
        if let focused = focused {
            if let idx = orderedComponents.firstIndex(where: { comp in comp.contains(where: { $0.id == focused.id }) }) {
                let comp = orderedComponents[idx]
                focusFirst.remove(at: idx)
                focusFirst.insert(comp, at: 0)
            }
        }
        return focusFirst.flatMap { $0 }
    }
    
    func color(for level: Int) -> Color {
        let palette: [Color] = [.blue, .gray, .green, .orange, .purple, .pink, .teal,.yellow]
        return palette[level % palette.count]
    }
    
    var body: some View {
        
        // 'derivedDict' is calculated fresh every time.
        let derivedDict = manager.makeDerivedDictionaryForDisplay(applySiblingInference: true)
        
        // 1. Get the 'grouped' data first.
        let grouped: [LevelGroup] = {
            if derivedDict.isEmpty { return [] }
            if let focus = manager.focusedMemberId {
                return buildConnectedGroups(from: derivedDict, focusId: focus)
            } else {
                return buildAllLevels(from: derivedDict)
            }
        }()

        // 2. Get all visible members and their names.
        let allVisibleMembers = grouped.flatMap { $0.members }
        var seenVisible = Set<UUID>()
        let visibleMembers = allVisibleMembers.filter { seenVisible.insert($0.id).inserted }
        let visibleMemberNames = Set(visibleMembers.map { $0.name })

        // 3. Pre-calculate the pairs array.
        let pairs: [SpousePair] = {
            var pairs: [SpousePair] = []
            var seenPairs = Set<Set<String>>()
            for member in visibleMembers {
                let spousesToDraw = member.spouses.filter { visibleMemberNames.contains($0) }
                for spouseName in spousesToDraw {
                    let pairSet: Set<String> = [member.name, spouseName]
                    if seenPairs.insert(pairSet).inserted {
                        pairs.append(SpousePair(name1: member.name, name2: spouseName))
                    }
                }
            }
            return pairs
        }()
        
        // 4. Check if anchors are ready.
        let allAnchorsCollected = visibleMemberNames.isSubset(of: Set(positionAnchors.keys))

        // 5. Build the view.
        ZStack {
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
                        let currentFocus = manager.focusedMemberId
                        manager.focusedMemberId = nil
                        manager.focusedMemberId = currentFocus
                    }
                    .buttonStyle(.bordered)

                    if manager.focusedMemberId != nil {
                        Button("Show Full Tree") {
                            manager.focusedMemberId = nil
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
                
                if manager.isDirty {
                    Text("You have unsaved changes. Use File > Save")
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
                                        
                                        // --- UPDATED BUTTON FOR FOCUS AND ATTACHMENTS ---
                                        Button(action: {
                                            if manager.focusedMemberId == nil {
                                                manager.focusedMemberId = member.id
                                            } else {
                                                attachmentsMemberName = member.name
                                                DispatchQueue.main.async {
                                                    showAttachments = true
                                                }
                                            }
                                        }) {
                                            Text(member.name)
                                                .padding()
                                                .background(isFocused ? Color.red.opacity(0.5) : color(for: group.level).opacity(0.3))
                                                .cornerRadius(8)
                                                .background(
                                                    GeometryReader { proxy in
                                                        Color.clear
                                                            .onAppear {
                                                                if memberButtonSize == .zero {
                                                                    memberButtonSize = proxy.size
                                                                }
                                                            }
                                                            .anchorPreference(key: MemberPositionKey.self, value: .center) {
                                                                [member.name: $0]
                                                            }
                                                    }
                                                )
                                        }
                                        .buttonStyle(.plain)
                                        // --- END UPDATED BUTTON ---
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.vertical)
                    // Add the ID to force a full reset on focus change
                    .id(manager.focusedMemberId)
                    .onPreferenceChange(MemberPositionKey.self) { value in
                        positionAnchors = value
                        // Once anchors start reporting,
                        // we can allow drawing.
                        isDrawingSuspended = false
                    }
                }
            } // End of VStack
            
            // 6. The overlay logic checks our suspension flag.
            if allAnchorsCollected && memberButtonSize != .zero && !pairs.isEmpty && !isDrawingSuspended {
                SpouseConnectorOverlay(
                    anchors: positionAnchors,
                    pairs: pairs,
                    buttonWidth: memberButtonSize.width,
                    buttonHeight: memberButtonSize.height
                )
            }
            
        } // End of ZStack
        .onAppear {
            isDrawingSuspended = true
        }
        .onChange(of: manager.focusedMemberId) { _ in
            // Suspend drawing and clear *only* the anchors.
            isDrawingSuspended = true
            positionAnchors = [:]
        }
        .onChange(of: manager.members) { _ in
            isDrawingSuspended = true
            positionAnchors = [:]
        }
        .sheet(isPresented: $showAttachments) {
            if let bookmark = UserDefaults.standard.data(forKey: "selectedFolderBookmark") {
                AttachmentsSheet(memberName: attachmentsMemberName, folderBookmark: bookmark) {
                    showAttachments = false
                }
            } else {
                VStack { Text("Select a storage folder first.") }.padding()
            }
        }
    }
}

