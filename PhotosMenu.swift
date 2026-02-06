//
//  PhotosMenu.swift
//  MyFamilyTree
//
//  Updated to include Browse All Attachments
//

import SwiftUI

struct PhotosMenu: View {
    @Binding var showGallery: Bool
    @Binding var showFilteredPhotos: Bool
    @Binding var showAllAttachments: Bool  // ← ADDED
    @Binding var showPhotoImporter: Bool
    @Binding var showNamePrompt: Bool
    @Binding var tempNameInput: String
    @Binding var filteredNamesForPhotos: [String]
    @Binding var alertMessage: String
    @Binding var showAlert: Bool
    @Binding var showSuccess: Bool
    @Binding var successMessage: String
    @Binding var showResetConfirm: Bool
    
    var body: some View {
        Group {
            Button {
                showGallery = true
            } label: {
                Label("Browse All Photos", systemImage: "photo.on.rectangle.angled")
            }
            
            Button {
                showAllAttachments = true
            } label: {
                Label("Browse All Attachments", systemImage: "paperclip")
            }
            
            Button {
                showNamePrompt = true
            } label: {
                Label("Add Photo", systemImage: "photo.badge.plus")
            }
            
            Divider()
            
            Button {
                showFilteredPhotos = true
                filteredNamesForPhotos = Array(FamilyDataManager.shared.membersDictionary.keys)
            } label: {
                Label("Browse Tree Photos", systemImage: "person.crop.square.filled.and.at.rectangle")
            }
            .disabled(FamilyDataManager.shared.membersDictionary.isEmpty)
            
            Divider()
            
            Button(role: .destructive) {
                showResetConfirm = true
            } label: {
                Label("Reset Photo Index", systemImage: "trash")
            }
        }
    }
}

