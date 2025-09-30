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
    
    var memberNames: [String] {
        manager.membersDictionary.keys.sorted()
    }
    
    
    var body: some View {
        let msg5 = " Enter individual member "
        let msg6 = "Add person"
        let msg7 = " Clear Present Fields"
        let msg8 = " Clear All Family Data"
        let msg10 = " Are you sure you want to clear all data ?"
        let msg11 = " Delete all "
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
                        //PREVIOUS
                        Button(msg13) {
                            if currentMemberIndex > 0 {
                                currentMemberIndex -= 1
                                displayCurrentMember()
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
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(currentMemberIndex >= memberNames.count - 1)
                        Spacer()
                        //ADD PERSON
                        Button(msg6) {
                            let newMember = FamilyMember(
                                name: name,
                                gender: nil,
                                imageName: "",
                                parents: parents.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
                                spouses: spouses.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
                                children: children.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
                                siblings: siblings.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
                                isImplicit: false,
                                level: 0
                            )
                            addMember(newMember)
                            clearPersonFields()
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                        //CLEAR PRESENT FIELDS
                        Button(msg7) {
                            clearPersonFields()
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.orange)
                        Spacer()
                    }
                }
            }
        }
        .padding()
        .onAppear {
            if !memberNames.isEmpty {
                displayCurrentMember()
            }
        }
    }
    ////HELPER FUCNTIONS
    ///////===============
    ///////MARK :Clear all data whether bulk or individual
    func clearAllData() {
        manager.membersDictionary.removeAll()
        // Reset UI state after clearing in-memory data
        currentMemberIndex = 0
        clearPersonFields()
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
    }
                            
    // MARK: - Get Member
    func getMember(named name: String) -> FamilyMember? {
        manager.membersDictionary[name]
    }
    //MARK : Clear one person - new comment
    func clearPersonFields() {
        name = ""
        parents = ""
        spouses = ""
        children = ""
        siblings = ""
    }
    
    /////////
    func displayCurrentMember() {
        guard !memberNames.isEmpty else {
            clearPersonFields()
            return
        }
        if currentMemberIndex >= memberNames.count {
            currentMemberIndex = memberNames.count - 1
        }
        let currentName = memberNames[currentMemberIndex]
        if let member = manager.membersDictionary[currentName] {
            name = member.name
            parents = member.parents.joined(separator: ",")
            spouses = member.spouses.joined(separator: ",")
            children = member.children.joined(separator: ",")
            siblings = member.siblings.joined(separator: ",")
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


