//
//  PhotosMenu.swift
//  MyFamilyTree
//
//  Updated to include Browse All Attachments
//
//  Note: Non-attachment menu options are commented out as per request.
//

import SwiftUI

struct PhotosMenu: View {
    // Keep only the bindings we still use actively
    @Binding var showAllAttachments: Bool  // Active binding for Attachments Browser

    // Commented-out bindings preserved for reference and future use
    // @Binding var showGallery: Bool
    // @Binding var showFilteredPhotos: Bool
    // @Binding var showPhotoImporter: Bool
    // @Binding var showNamePrompt: Bool
    // @Binding var tempNameInput: String
    // @Binding var filteredNamesForPhotos: [String]
    // @Binding var alertMessage: String
    // @Binding var showAlert: Bool
    // @Binding var showSuccess: Bool
    // @Binding var successMessage: String
    // @Binding var showResetConfirm: Bool

    var body: some View {
        Group {
            // The only active menu item we keep
            Button {
                showAllAttachments = true
            } label: {
                Label("Browse All Attachments", systemImage: "paperclip")
            }

            // --- The following options are intentionally disabled/commented out ---
            // Button {
            //     showGallery = true
            // } label: {
            //     Label("Browse All Photos", systemImage: "photo.on.rectangle.angled")
            // }
            //
            // Button {
            //     showNamePrompt = true
            // } label: {
            //     Label("Add Photo", systemImage: "photo.badge.plus")
            // }
            //
            // Divider()
            //
            // Button {
            //     showFilteredPhotos = true
            //     // filteredNamesForPhotos = Array(FamilyDataManager.shared.membersDictionary.keys)
            // } label: {
            //     Label("Browse Tree Photos", systemImage: "person.crop.square.filled.and.at.rectangle")
            // }
            // .disabled(FamilyDataManager.shared.membersDictionary.isEmpty)
            //
            // Divider()
            //
            // Button(role: .destructive) {
            //     showResetConfirm = true
            // } label: {
            //     Label("Reset Photo Index", systemImage: "trash")
            // }
        }
    }
}
