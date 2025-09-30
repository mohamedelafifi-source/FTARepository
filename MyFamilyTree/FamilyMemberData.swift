//
//  FamilyMemberData.swift
//  MyFamilyTree
//
//  Created by Mohamed El Afifi on 9/30/25.
//


import Foundation

/// A single person in the family graph.
struct FamilyMember: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var gender: String?
    var imageName: String?
    var parents: [String]
    var spouses: [String]
    var children: [String]
    var siblings: [String]
    var isImplicit: Bool
    var level: Int
    
    
    init(
        id: UUID = UUID(),
        name: String,
        gender: String? = nil,
        imageName: String? = nil,
        parents: [String] = [],
        spouses: [String] = [],
        children: [String] = [],
        siblings: [String] = [],
        isImplicit: Bool = false,
        level: Int = 0
    ) {
        self.id = id
        self.name = name
        self.gender = gender
        self.imageName = imageName
        self.parents = parents
        self.spouses = spouses
        self.children = children
        self.siblings = siblings
        self.isImplicit = isImplicit
        self.level = level
    }

    // Equality is defined by unique `name`
    static func == (lhs: FamilyMember, rhs: FamilyMember) -> Bool {
        return lhs.name == rhs.name
    }

    // Hashing matches equality (based on `name`)
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
