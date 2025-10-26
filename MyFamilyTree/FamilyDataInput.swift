//
//  FamilyInout.swift
//  SwiftTreeTwo
//
//  Created by Mohamed El Afifi on 9/15/25.
//

import SwiftUI

struct FamilyDataInputView: View {
    
    @Environment(\.dismiss) private var dismiss
    
    @ObservedObject var manager = FamilyDataManager.shared
    
    // Individual fields
    @State private var name = ""
    @State private var parents = ""
    @State private var spouses = ""
    @State private var children = ""
    @State private var siblings = ""
    // New state for navigation
    @State private var currentMemberIndex: Int = 0
    @State private var showDeleteAlert: Bool = false
    @State private var pendingDeleteName: String? = nil
    @State private var showDuplicateAlert: Bool = false
    @State private var isCreatingNew: Bool = false
    @State private var originalEditingName: String? = nil
    
    var memberNames: [String] {
        manager.membersDictionary.keys.sorted()
    }
    
    
    var body: some View {
        
        let msg5 = " Enter/Edit by member "
        let msg6 = "Update"
        let msg7 = " Delete "
        //let msg8 = " Clear All Family Data"
        //let msg10 = " Are you sure you want to clear all data ?"
        //let msg11 = " Delete all "
        let msg12 = " Next "
        let msg13 = " Previous "
        
        return VStack {
            Form {
                Section(header: Text(msg5)) {
                    TextField("Name", text: $name)
                    TextField("Parents (comma separated)", text: $parents)
                    TextField("Spouses (comma separated)", text: $spouses)
                    TextField("Children (comma separated)", text: $children)
                    TextField("Siblings (comma separated)", text: $siblings)

                    HStack {
                        Spacer()
                        Button(" New ") {
                            clearPersonFields()
                            isCreatingNew = true
                            originalEditingName = nil
                            // Put index out of bounds to prevent displayCurrentMember() from showing old data accidentally
                            currentMemberIndex = 0
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                        //PREVIOUS
                        Button(msg13) {
                            if currentMemberIndex > 0 {
                                currentMemberIndex -= 1
                                displayCurrentMember()
                                isCreatingNew = false
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(currentMemberIndex == 0)
                        Spacer()
                        //NEXT
                        Button(msg12) {
                            if currentMemberIndex < memberNames.count - 1 {
                                currentMemberIndex += 1
                                displayCurrentMember()
                                isCreatingNew = false
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(currentMemberIndex >= memberNames.count - 1)
                        Spacer()
                        //ADD PERSON (now Update)
                        Button(msg6) {
                            let inputName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            let finalName: String
                            if inputName.isEmpty {
                                // Generate a unique placeholder name only when creating new
                                if isCreatingNew {
                                    let base = "New Member"
                                    if !manager.membersDictionary.keys.contains(base) {
                                        finalName = base
                                    } else {
                                        var counter = 2
                                        var candidate = "\(base) \(counter)"
                                        while manager.membersDictionary.keys.contains(candidate) {
                                            counter += 1
                                            candidate = "\(base) \(counter)"
                                        }
                                        finalName = candidate
                                    }
                                } else {
                                    // Editing existing: keep original name if input empty
                                    finalName = originalEditingName ?? inputName
                                }
                            } else {
                                finalName = inputName
                            }

                            let newMember = FamilyMember(
                                name: finalName,
                                gender: nil,
                                imageName: "",
                                parents: parents.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
                                spouses: spouses.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
                                children: children.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
                                siblings: siblings.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
                                isImplicit: false,
                                level: 0
                            )

                            if isCreatingNew {
                                // Always add as new; if name collides, generate a unique suffix
                                var uniqueName = newMember.name
                                if manager.membersDictionary.keys.contains(uniqueName) {
                                    var counter = 2
                                    var candidate = "\(uniqueName) \(counter)"
                                    while manager.membersDictionary.keys.contains(candidate) {
                                        counter += 1
                                        candidate = "\(uniqueName) \(counter)"
                                    }
                                    uniqueName = candidate
                                }
                                var memberToAdd = newMember
                                memberToAdd.name = uniqueName
                                addMember(memberToAdd)
                                // Reflect exactly what was added to avoid any stale data
                                name = memberToAdd.name
                                parents = memberToAdd.parents.joined(separator: ", ")
                                spouses = memberToAdd.spouses.joined(separator: ", ")
                                children = memberToAdd.children.joined(separator: ", ")
                                siblings = memberToAdd.siblings.joined(separator: ", ")
                                isCreatingNew = false
                                originalEditingName = uniqueName
                            } else {
                                // Strict update path: if name changed and conflicts with another, adjust to avoid overwriting
                                if let original = originalEditingName, original != finalName, manager.membersDictionary.keys.contains(finalName) {
                                    // Name taken by someone else; keep original name for this update
                                    var adjusted = newMember
                                    adjusted.name = original
                                    updateMember(adjusted)
                                    originalEditingName = original
                                } else if let original = originalEditingName, original != finalName {
                                    // Rename: remove old key, insert new
                                    manager.membersDictionary.removeValue(forKey: original)
                                    addMember(newMember)
                                    originalEditingName = finalName
                                } else {
                                    // Normal update
                                    updateMember(newMember)
                                    originalEditingName = finalName
                                }
                            }

                            // Navigate to and display the updated/added member
                            if let idx = memberNames.firstIndex(of: originalEditingName ?? finalName) {
                                currentMemberIndex = idx
                            }
                            displayCurrentMember()
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                        //---------------------
                        //DELETE MEMBER
                        //---------------------
                        Button(msg7) {
                            // If there's a current name, ask for confirmation and then remove
                            if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                pendingDeleteName = name
                                showDeleteAlert = true
                            } else {
                                // If no name is present, just clear fields
                                clearPersonFields()
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Spacer()
                    }
                    Text(isCreatingNew ? "Creating new person" : "Editing existing person")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .alert("Are you sure?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let nameToDelete = pendingDeleteName {
                    removeMember(named: nameToDelete)
                    // Reset navigation index safely
                    if currentMemberIndex >= memberNames.count { currentMemberIndex = max(0, memberNames.count - 1) }
                    clearPersonFields()
                }
                pendingDeleteName = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteName = nil
            }
        } message: {
            Text("This will remove the member from the in-memory tree. Save to a tree file to permanently erase the member.")
        }
        .alert("Duplicate name", isPresented: $showDuplicateAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("A member with this name already exists. Please choose a different name or edit the existing member.")
        }
        .padding()
        .onAppear {
            if memberNames.isEmpty {
                currentMemberIndex = 0
                clearPersonFields()
                originalEditingName = nil
                isCreatingNew = true
            } else {
                currentMemberIndex = min(currentMemberIndex, memberNames.count - 1)
                displayCurrentMember()
                isCreatingNew = false
            }
        }
    }
    ////HELPER FUCNTIONS
    ///////===============
    ///////MARK :Clear all data whether bulk or individual
    func clearAllData() {
        manager.membersDictionary.removeAll()
        manager.linkFamilyRelations()
        manager.assignLevels()
        // Reset UI state after clearing in-memory data
        currentMemberIndex = 0
        clearPersonFields()
        originalEditingName = nil
    }
    // MARK: - Add Individual Member
    func addMember(_ member: FamilyMember) {
        manager.membersDictionary[member.name] = member
        manager.linkFamilyRelations()
        manager.assignLevels()
    }
    // MARK: - Update Existing Member
    func updateMember(_ member: FamilyMember) {
        manager.membersDictionary[member.name] = member
        manager.linkFamilyRelations()
        manager.assignLevels()
    }
    // MARK: - Remove Member
    func removeMember(named name: String) {
        manager.membersDictionary.removeValue(forKey: name)
        manager.linkFamilyRelations()
        manager.assignLevels()
        // Adjust navigation state
        if memberNames.isEmpty {
            currentMemberIndex = 0
            clearPersonFields()
            originalEditingName = nil
        } else {
            currentMemberIndex = min(currentMemberIndex, max(0, memberNames.count - 1))
            displayCurrentMember()
        }
    }
                            
    // MARK: - Get Member
    func getMember(named name: String) -> FamilyMember? {
        manager.membersDictionary[name]
    }
    //MARK : Clear one person
    func clearPersonFields() {
        name = ""
        parents = ""
        spouses = ""
        children = ""
        siblings = ""
    }
    
    /////////
    func displayCurrentMember() {
        if isCreatingNew {
            // In New mode, do not populate fields from existing members
            return
        }
        guard !memberNames.isEmpty else {
            clearPersonFields()
            originalEditingName = nil
            return
        }
        if currentMemberIndex >= memberNames.count {
            currentMemberIndex = memberNames.count - 1
        }
        let currentName = memberNames[currentMemberIndex]
        if let member = manager.membersDictionary[currentName] {
            name = member.name
            parents = member.parents.joined(separator: ", ")
            spouses = member.spouses.joined(separator: ", ")
            children = member.children.joined(separator: ", ")
            siblings = member.siblings.joined(separator: ", ")
            originalEditingName = member.name
        } else {
            originalEditingName = nil
        }
        
    }

    // MARK: - Parse Bulk Input
    static func parseBulkInput(_ input: String, manager: FamilyDataManager = .shared) {
        for rawLine in input.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            var name: String = ""
            var parents: [String] = []
            var spouses: [String] = []
            var children: [String] = []
            var siblings: [String] = []

            let components = line.components(separatedBy: ";")
            for component in components {
                let trimmed = component.trimmingCharacters(in: .whitespaces)
                if trimmed.uppercased().hasPrefix("NAME:") {
                    name = trimmed.replacingOccurrences(of: "NAME:", with: "", options: .caseInsensitive).trimmingCharacters(in: .whitespaces)
                } else if trimmed.uppercased().hasPrefix("PARENTS:") {
                    let value = trimmed.replacingOccurrences(of: "PARENTS:", with: "", options: .caseInsensitive)
                    parents = value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                } else if trimmed.uppercased().hasPrefix("SPOUSES:") {
                    let value = trimmed.replacingOccurrences(of: "SPOUSES:", with: "", options: .caseInsensitive)
                    spouses = value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                } else if trimmed.uppercased().hasPrefix("CHILDREN:") {
                    let value = trimmed.replacingOccurrences(of: "CHILDREN:", with: "", options: .caseInsensitive)
                    children = value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                } else if trimmed.uppercased().hasPrefix("SIBLINGS:") {
                    let value = trimmed.replacingOccurrences(of: "SIBLINGS:", with: "", options: .caseInsensitive)
                    siblings = value.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                }
            }

            guard !name.isEmpty else { continue }

            if var existing = manager.membersDictionary[name] {
                // Merge without duplicates
                existing.parents.append(contentsOf: parents.filter { !existing.parents.contains($0) })
                existing.spouses.append(contentsOf: spouses.filter { !existing.spouses.contains($0) })
                existing.children.append(contentsOf: children.filter { !existing.children.contains($0) })
                existing.siblings.append(contentsOf: siblings.filter { !existing.siblings.contains($0) })
                manager.membersDictionary[name] = existing
            } else {
                let member = FamilyMember(
                    name: name,
                    gender: nil,
                    imageName: "",
                    parents: parents,
                    spouses: spouses,
                    children: children,
                    siblings: siblings,
                    isImplicit: false,
                    level: 0
                )
                manager.membersDictionary[name] = member
            }
        }

        // Finalize links and levels
        //==========================
        //This code is in FamilyDataManager
        manager.linkFamilyRelations()
        manager.assignLevels()
    }
}

