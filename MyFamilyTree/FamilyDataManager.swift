//
//  FamilyDataManager.swift
//  MyFamilyTree
//
//  Created by Mohamed El Afifi on 9/30/25.
//


import Foundation
import SwiftUI
import Combine

// MARK: - Supporting Types
// NOTE: This file references `FamilyMember`. This type must be defined elsewhere
// in the project as a Codable, Identifiable model with at least the following:
// - id: UUID
// - name: String
// - parents: [String]
// - children: [String]
// - spouses: [String]
// - siblings: [String]
// - level: Int
// If your definition differs, adjust the code below accordingly.

struct LevelGroup: Identifiable {
    let id = UUID()
    let level: Int
    let members: [FamilyMember]
}

///// MAIN FAMILY DATA MANAGER. DOES ALL THE PROCESSING //////
////=========================================================
@MainActor
class FamilyDataManager: ObservableObject {
    static let shared = FamilyDataManager()

    private let userDefaultsKey = "familyDataMembersDictionary"

    @Published var membersDictionary: [String: FamilyMember] = [:]
    @Published var focusedMemberId: UUID? = nil

    var members: [FamilyMember] {
        Array(membersDictionary.values)
    }

    // MARK: - Export helpers
    func generateExportText() -> String {
        var fileContent = ""
        let sortedMembers = membersDictionary.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        for member in sortedMembers {
            let parentsString = member.parents.joined(separator: ", ")
            let spousesString = member.spouses.joined(separator: ", ")
            let siblingsString = member.siblings.joined(separator: ", ")
            let childrenString = member.children.joined(separator: ", ")
            let line = "NAME:\(member.name); PARENTS:\(parentsString); SPOUSES:\(spousesString); SIBLINGS:\(siblingsString); CHILDREN:\(childrenString)\n"
            fileContent += line
        }
        return fileContent
    }

    // MARK: - Build all levels from roots by traversing down
    func getAllLevels() -> [LevelGroup] {
        var visited = Set<String>()
        var levels: [Int: [FamilyMember]] = [:]

        // The assignLevel function needs to be a nested function
        func assignLevel(_ member: FamilyMember, level: Int) {
            guard !visited.contains(member.name) else { return }
            visited.insert(member.name)
            levels[level, default: []].append(member)

            // Keep spouses at the same level
            for spouseName in member.spouses {
                if let spouse = membersDictionary[spouseName] {
                    assignLevel(spouse, level: level)
                }
            }
            // Children at next level
            for childName in member.children {
                if let child = membersDictionary[childName] {
                    assignLevel(child, level: level + 1)
                }
            }
        }

        // Start from top-level parents (those with no parents)
        let allMembers = Array(membersDictionary.values)
        let topLevel = allMembers.filter { $0.parents.isEmpty }
        for member in topLevel {
            assignLevel(member, level: 0)
        }

        // Convert to sorted LevelGroup array
        return levels.keys.sorted().compactMap { lvl in
            if let membersAtLevel = levels[lvl] {
                return LevelGroup(level: lvl, members: membersAtLevel)
            } else {
                return nil
            }
        }
    }

    // MARK: - Infer Siblings from Shared Parents
    func inferSiblingsFromParents() {
        // 1. Group all members by their parents signature
        let groupedByParents = Dictionary(grouping: membersDictionary.values) { member in
            return member.parents.sorted().joined(separator: "|")
        }

        // 2. Iterate through each group of siblings
        for group in groupedByParents.values {
            // If a group has more than one member, they are siblings
            if group.count > 1 {
                let siblingNames = group.map { $0.name }
                for member in group {
                    if var currentMember = membersDictionary[member.name] {
                        // Update the siblings list for this member
                        let existingSiblings = Set(currentMember.siblings)
                        let newSiblings = Set(siblingNames.filter { $0 != member.name })
                        let allSiblings = existingSiblings.union(newSiblings)
                        currentMember.siblings = Array(allSiblings)
                        membersDictionary[member.name] = currentMember
                    }
                }
            }
        }
    }

    // MARK: - Normalize and link relationships (mutual spouses, parents/children, siblings)
    func linkFamilyRelations() {
        // Work on a local copy to avoid mutating while iterating repeatedly
        var updated = membersDictionary

        func addUnique(_ name: String, to list: inout [String]) {
            if !list.contains(name) { list.append(name) }
        }

        // 1) Ensure mutual spouses
        for (name, member) in membersDictionary {
            for spouseName in member.spouses {
                guard var spouse = updated[spouseName] else { continue }
                addUnique(name, to: &spouse.spouses)
                updated[spouseName] = spouse
            }
        }

        // 2) Ensure parent/child consistency
        for (name, member) in membersDictionary {
            // Parents → child
            for parentName in member.parents {
                guard var parent = updated[parentName] else { continue }
                addUnique(name, to: &parent.children)
                updated[parentName] = parent
            }
            // Children → parent
            for childName in member.children {
                guard var child = updated[childName] else { continue }
                addUnique(name, to: &child.parents)
                updated[childName] = child
            }
        }

        // 3) Ensure mutual siblings (no self)
        for (name, member) in membersDictionary {
            for siblingName in member.siblings where siblingName != name {
                guard var sibling = updated[siblingName] else { continue }
                addUnique(name, to: &sibling.siblings)
                updated[siblingName] = sibling
            }
        }

        // 4) Deduplicate and sort for stability
        for (name, var member) in updated {
            member.parents = Array(Set(member.parents)).sorted()
            member.children = Array(Set(member.children)).sorted()
            member.spouses = Array(Set(member.spouses)).sorted()
            member.siblings = Array(Set(member.siblings.filter { $0 != name })).sorted()
            updated[name] = member
        }

        membersDictionary = updated
    }

    // MARK: - Assign Levels (absolute levels across full tree)
    func assignLevels() {
        // Reset all levels to -1
        for name in membersDictionary.keys {
            membersDictionary[name]?.level = -1
        }

        var assignedCount = 0
        let total = membersDictionary.count

        // Pass 1: Assign levels based on parent-child relationships
        var changedInPass = true
        while changedInPass && assignedCount < total {
            changedInPass = false
            for name in membersDictionary.keys {
                guard var member = membersDictionary[name] else { continue }

                // Case 1: True root (no parents, no level) -> Level 0
                if member.parents.isEmpty && member.level == -1 {
                    member.level = 0
                    membersDictionary[name] = member
                    changedInPass = true
                    assignedCount += 1
                    continue
                }
                // Case 2: Parent has a level -> Child's level is parent.level + 1
                if member.level == -1 {
                    for parentName in member.parents {
                        if let parent = membersDictionary[parentName], parent.level != -1 {
                            member.level = parent.level + 1
                            membersDictionary[name] = member
                            changedInPass = true
                            assignedCount += 1
                            break
                        }
                    }
                }
            }
        }

        // Pass 2: Fill in remaining gaps using spouses and siblings
        changedInPass = true
        while changedInPass {
            changedInPass = false
            for name in membersDictionary.keys {
                guard var member = membersDictionary[name], member.level == -1 else { continue }
                var foundLevel: Int? = nil
                // Check siblings
                for siblingName in member.siblings {
                    if let sibling = membersDictionary[siblingName], sibling.level != -1 {
                        foundLevel = sibling.level
                        break
                    }
                }
                // Check spouses
                if foundLevel == nil {
                    for spouseName in member.spouses {
                        if let spouse = membersDictionary[spouseName], spouse.level != -1 {
                            foundLevel = spouse.level
                            break
                        }
                    }
                }
                if let level = foundLevel {
                    member.level = level
                    membersDictionary[name] = member
                    changedInPass = true
                    assignedCount += 1
                }
            }
        }

        // Optional: Build structured tree data (kept local here, adjust if needed)
        var structuredTreeData: [Int: [[String]]] = [:]
        var groupedByLevel: [Int: [String]] = [:]
        for member in membersDictionary.values {
            if member.level != -1 && member.level != Int.max {
                groupedByLevel[member.level, default: []].append(member.name)
            }
        }
        let sortedLevels = groupedByLevel.keys.sorted()
        for level in sortedLevels {
            guard let memberNamesAtLevel = groupedByLevel[level] else { continue }

            var processedNames: Set<String> = []
            var familyUnits: [[String]] = []
            let sortedMemberNames = memberNamesAtLevel.sorted()

            for name in sortedMemberNames {
                if processedNames.contains(name) { continue }
                var currentUnit: Set<String> = [name]
                var membersToExplore: [String] = [name]
                processedNames.insert(name)
                var explorationIndex = 0
                while explorationIndex < membersToExplore.count {
                    let currentName = membersToExplore[explorationIndex]
                    explorationIndex += 1
                    guard let currentMember = membersDictionary[currentName] else { continue }

                    // Add spouses
                    for spouseName in currentMember.spouses {
                        if let spouse = membersDictionary[spouseName], spouse.level == level, !currentUnit.contains(spouse.name) {
                            currentUnit.insert(spouse.name)
                            membersToExplore.append(spouse.name)
                            processedNames.insert(spouse.name)
                        }
                    }
                    // Add siblings
                    for siblingName in currentMember.siblings {
                        if let sibling = membersDictionary[siblingName], sibling.level == level, !currentUnit.contains(sibling.name) {
                            currentUnit.insert(sibling.name)
                            membersToExplore.append(sibling.name)
                            processedNames.insert(sibling.name)
                        }
                    }
                }
                familyUnits.append(Array(currentUnit).sorted())
            }
            structuredTreeData[level] = familyUnits
        }
        // NOTE: structuredTreeData is computed but not stored; wire it to your UI if needed.
    }

    // MARK: - Persistence
    func saveToUserDefaults() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(Array(membersDictionary.values))
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        } catch {
            print("❌ Failed to save family data: \(error)")
        }
    }
    
    func loadFromUserDefaults(reassignLevels: Bool = true, inferSiblings: Bool = false) {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            // Nothing saved yet
            return
        }
        do {
            let decoder = JSONDecoder()
            let decodedArray = try decoder.decode([FamilyMember].self, from: data)
            // Rebuild dictionary keyed by name
            var newDict: [String: FamilyMember] = [:]
            for member in decodedArray {
                newDict[member.name] = member
            }
            membersDictionary = newDict

            if inferSiblings { inferSiblingsFromParents() }
            if reassignLevels { assignLevels() }
        } catch {
            print("❌ Failed to load family data: \(error)")
        }
    }

    // MARK: - Helper: Sort members at a given level for the FULL tree
    private func sortMembersAtLevel(_ members: [FamilyMember], level: Int) -> [FamilyMember] {
        var sorted: [FamilyMember] = []
        var visited = Set<String>()

        // Sort members by name for consistent processing
        let membersByName = members.sorted { $0.name < $1.name }

        // --- Step 1: Group spouses together ---
        for member in membersByName {
            guard !visited.contains(member.name) else { continue }
            // Find a spouse if one exists at the same level
            if let spouseName = member.spouses.first,
               let spouse = membersDictionary[spouseName],
               spouse.level == level,
               !visited.contains(spouseName) {
                let pair = [member, spouse].sorted { $0.name < $1.name }
                sorted.append(contentsOf: pair)
                visited.insert(member.name)
                visited.insert(spouse.name)
            }
        }

        // --- Step 2: Group remaining unmarried siblings ---
        let remaining = membersByName.filter { !visited.contains($0.name) }

        // Group the remaining members by their parents to identify siblings
        let siblingGroups = Dictionary(grouping: remaining) { member in
            let sortedParents = member.parents.sorted()
            return sortedParents.joined(separator: "-")
        }
        for group in siblingGroups.values {
            let sortedGroup = group.sorted { $0.name < $1.name }
            sorted.append(contentsOf: sortedGroup)
        }
        return sorted
    }

    // MARK: - Compute Relative Levels (BFS over relationships)
    func computeRelativeLevels(from startName: String, using members: [String: FamilyMember]) -> [String: Int] {
        var levels: [String: Int] = [startName: 0]
        var queue: [(name: String, level: Int)] = [(startName, 0)]
        var visited = Set<String>()
        while !queue.isEmpty {
            let (currentName, currentLevel) = queue.removeFirst()
            visited.insert(currentName)
            guard let member = members[currentName] else { continue }

            // Parents = level - 1
            for parent in member.parents where !visited.contains(parent) {
                if levels[parent] == nil { levels[parent] = currentLevel - 1 }
                queue.append((parent, currentLevel - 1))
            }
            // Children = level + 1
            for child in member.children where !visited.contains(child) {
                if levels[child] == nil { levels[child] = currentLevel + 1 }
                queue.append((child, currentLevel + 1))
            }
            // Siblings = same level
            for sibling in member.siblings where !visited.contains(sibling) {
                if levels[sibling] == nil { levels[sibling] = currentLevel }
                queue.append((sibling, currentLevel))
            }
            // Spouses = same level
            for spouse in member.spouses where !visited.contains(spouse) {
                if levels[spouse] == nil { levels[spouse] = currentLevel }
                queue.append((spouse, currentLevel))
            }
        }
        return levels
    }

    // MARK: - Connected Subtree around a focused member
    func getConnectedFamilyOf(memberId: UUID) -> [LevelGroup] {
        guard let focusedMember = membersDictionary.first(where: { $0.value.id == memberId })?.value else {
            print("❌ ERROR: Focused member with ID \(memberId) not found.")
            return []
        }

        // --- Stage 1: Collect all relevant members ---
        var finalMemberNames = Set<String>()

        // Rule 1 & 2: Add focused member, spouses, and siblings
        finalMemberNames.insert(focusedMember.name)
        for spouseName in focusedMember.spouses { finalMemberNames.insert(spouseName) }
        for siblingName in focusedMember.siblings { finalMemberNames.insert(siblingName) }

        // Traversal for ancestors (limited depth)
        var currentAncestorNames = focusedMember.parents
        var visitedAncestors = Set(currentAncestorNames)
        var ancestorDepth = 0
        let maxAncestorTraversalDepth = 2

        while !currentAncestorNames.isEmpty && ancestorDepth < maxAncestorTraversalDepth {
            var nextAncestorNames: [String] = []
            for ancestorName in currentAncestorNames {
                finalMemberNames.insert(ancestorName)
                if let ancestor = membersDictionary[ancestorName] {
                    for spouseName in ancestor.spouses { finalMemberNames.insert(spouseName) }
                    for parentName in ancestor.parents where visitedAncestors.insert(parentName).inserted {
                        nextAncestorNames.append(parentName)
                    }
                }
            }
            currentAncestorNames = nextAncestorNames
            ancestorDepth += 1
        }

        // Traversal for descendants (all depths)
        var visitedDescendants = Set<String>()
        func collectAllDescendants(of name: String) {
            guard let member = membersDictionary[name] else { return }
            for childName in member.children where visitedDescendants.insert(childName).inserted {
                finalMemberNames.insert(childName)
                if let child = membersDictionary[childName] {
                    for spouseName in child.spouses { finalMemberNames.insert(spouseName) }
                }
                collectAllDescendants(of: childName)
            }
        }
        collectAllDescendants(of: focusedMember.name)

        // --- Stage 2: Compute relative levels ---
        let relativeLevels = computeRelativeLevels(from: focusedMember.name, using: membersDictionary)

        // --- Stage 3: Build final display members and groups ---
        var finalDisplayMembers = [FamilyMember]()
        let relevantNames = finalMemberNames.filter { relativeLevels.keys.contains($0) }
        let minLevel = relevantNames.compactMap { relativeLevels[$0] }.min() ?? 0
        let levelAdjustment = (minLevel < 0) ? -minLevel : 0

        for name in relevantNames {
            if let member = membersDictionary[name], let relativeLevel = relativeLevels[name] {
                var memberToAdd = member
                memberToAdd.level = relativeLevel + levelAdjustment
                finalDisplayMembers.append(memberToAdd)
            }
        }

        let grouped = Dictionary(grouping: finalDisplayMembers, by: { $0.level })
        var levelGroups: [LevelGroup] = []
        let sortedLevels = grouped.keys.sorted()

        for level in sortedLevels {
            if let members = grouped[level] {
                let sortedMembers = sortLevel(members, focused: focusedMember)
                levelGroups.append(LevelGroup(level: level, members: sortedMembers))
            }
        }
        return levelGroups
    }

    // MARK: - Sorting members at a level around a focus
    // This sorts so that:
    // 1) Focused member (if present) and their spouses come first.
    // 2) Remaining couples (members with spouses) grouped together.
    // 3) Remaining individuals grouped by sibling groups (shared parents), then by name.
    func sortLevel(_ members: [FamilyMember], focused: FamilyMember? = nil) -> [FamilyMember] {
        var sorted: [FamilyMember] = []
        var remainingMembers = members

        // --- Step 1: Focused member and their spouses first ---
        if let focusedMember = focused, let index = remainingMembers.firstIndex(where: { $0.name == focusedMember.name }) {
            let member = remainingMembers.remove(at: index)
            sorted.append(member)
            for spouseName in member.spouses {
                if let spouseIndex = remainingMembers.firstIndex(where: { $0.name == spouseName }) {
                    sorted.append(remainingMembers.remove(at: spouseIndex))
                }
            }
        }

        // --- Step 2: Remaining couples ---
        var otherCouples: [FamilyMember] = []
        var visitedInStep2 = Set<String>()
        let marriedMembers = remainingMembers.filter { !$0.spouses.isEmpty }.sorted { $0.name < $1.name }
        for member in marriedMembers {
            guard !visitedInStep2.contains(member.name) else { continue }
            otherCouples.append(member)
            visitedInStep2.insert(member.name)
            for spouseName in member.spouses {
                if let spouse = remainingMembers.first(where: { $0.name == spouseName }) {
                    otherCouples.append(spouse)
                    visitedInStep2.insert(spouse.name)
                }
            }
        }
        sorted.append(contentsOf: otherCouples)
        remainingMembers.removeAll(where: { visitedInStep2.contains($0.name) })

        // --- Step 3: Remaining unmarried individuals grouped by sibling groups ---
        let siblingGroups = Dictionary(grouping: remainingMembers) { member in
            member.parents.sorted().joined(separator: "-")
        }
        let sortedSiblingKeys = siblingGroups.keys.sorted()
        for key in sortedSiblingKeys {
            if let group = siblingGroups[key]?.sorted(by: { $0.name < $1.name }) {
                sorted.append(contentsOf: group)
            }
        }
        return sorted
    }
}

