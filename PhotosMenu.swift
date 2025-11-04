import SwiftUI

struct PhotosMenu: View {
    @ObservedObject var globals = GlobalVariables.shared
    @ObservedObject var dataManager = FamilyDataManager.shared

    @Binding var showGallery: Bool
    @Binding var showFilteredPhotos: Bool
    @Binding var showPhotoImporter: Bool
    @Binding var showNamePrompt: Bool
    @Binding var tempNameInput: String
    @Binding var filteredNamesForPhotos: [String]

    @Binding var alertMessage: String
    @Binding var showAlert: Bool
    @Binding var showSuccess: Bool
    @Binding var successMessage: String

    private func readIndexNames(from indexURL: URL) throws -> Set<String> {
        let data = try Data(contentsOf: indexURL)
        if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            let names = array.compactMap { $0["name"] as? String }
            return Set(names)
        }
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return Set(dict.keys)
        }
        return []
    }

    var body: some View {
        Menu {
            Button("Create Photo Index in Folder") {
                guard let folder = globals.selectedFolderURL else {
                    alertMessage = "Please select a storage folder first."
                    showAlert = true
                    return
                }
                do {
                    let indexURL = folder.appendingPathComponent("photo-index.json")
                    if FileManager.default.fileExists(atPath: indexURL.path) {
                        throw CocoaError(.fileWriteFileExists)
                    }
                    let url = try StorageManager.shared.ensurePhotoIndex(in: folder, fileName: "photo-index.json")
                    globals.selectedJSONURL = url
                    successMessage = "Photo index created at “\(url.lastPathComponent)”."
                    showSuccess = true
                } catch {
                    let nsErr = error as NSError
                    if nsErr.domain == NSCocoaErrorDomain && nsErr.code == NSFileWriteFileExistsError {
                        alertMessage = "A photo index already exists in the selected folder."
                    } else {
                        alertMessage = error.localizedDescription
                    }
                    showAlert = true
                }
            }
            .disabled(globals.selectedFolderURL == nil)
            Divider()
            Button("Import a Photo …") {
                guard globals.selectedFolderURL != nil else {
                    alertMessage = "Select a storage folder first."
                    showAlert = true
                    return
                }
                tempNameInput = ""
                showNamePrompt = true
            }
            .disabled(globals.selectedFolderURL == nil)
            Button("Browse All Photos") {
                if let folder = globals.selectedFolderURL {
                    do {
                        let url = try StorageManager.shared.ensurePhotoIndex(in: folder, fileName: "photo-index.json")
                        globals.selectedJSONURL = url
                    } catch {
                        alertMessage = "Failed to prepare photo index: \(error.localizedDescription)"
                        showAlert = true
                        return
                    }
                    showGallery = true
                } else {
                    alertMessage = "Select a storage folder first."
                    showAlert = true
                }
            }
            .disabled(globals.selectedFolderURL == nil)
            Button("Browse Tree Photos") {
                if dataManager.membersDictionary.isEmpty {
                    alertMessage = "No family data loaded. Please add or parse data first."
                    showAlert = true
                    return
                }
                guard let folder = globals.selectedFolderURL else {
                    alertMessage = "Select a storage folder first (Photos menu)."
                    showAlert = true
                    return
                }
                do {
                    let url = try StorageManager.shared.ensurePhotoIndex(in: folder, fileName: "photo-index.json")
                    globals.selectedJSONURL = url
                } catch {
                    alertMessage = "Failed to prepare photo index: \(error.localizedDescription)"
                    showAlert = true
                    return
                }
                guard let idxURL = globals.selectedJSONURL else {
                    alertMessage = "Select a storage folder and photo index first (Photos menu)."
                    showAlert = true
                    return
                }

                let groups: [LevelGroup]
                if let focus = dataManager.focusedMemberId {
                    groups = dataManager.getConnectedFamilyOf(memberId: focus)
                } else {
                    groups = dataManager.getAllLevels()
                }
                let names = groups.flatMap { $0.members.map { $0.name } }
                filteredNamesForPhotos = Array(Set(names)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                if filteredNamesForPhotos.isEmpty {
                    alertMessage = "No visible names in the current tree."
                    showAlert = true
                    return
                }

                do {
                    print("[PhotosMenu] About to readIndexNames at:", idxURL.path)
                    let indexNames = try readIndexNames(from: idxURL)
                    print("[PhotosMenu] indexNames.count =", indexNames.count)
                    let visible = Set(filteredNamesForPhotos)
                    print("[PhotosMenu] visible.count =", visible.count)
                    let intersection = visible.intersection(indexNames)
                    print("[PhotosMenu] intersection.count =", intersection.count)
                    if indexNames.isEmpty {
                        /* Do not show all the names
                        alertMessage = "No photos found in the photo index for folder \"\(folder.lastPathComponent)\".\nUse Photos → Import a Photo to add photos for your tree members, then try again."
                        */
                        alertMessage = "No photos are found in the photo index"
                        showAlert = true
                        return
                    }
                    if intersection.isEmpty {
                        /* DO not show all the names
                        alertMessage = "None of the visible names are present in the photo index.\nNames: \(filteredNamesForPhotos.joined(separator: ", "))"
                        */
                        alertMessage = "None of the names are present in the photo index"
                        showAlert = true
                        return
                    }
                    print("[PhotosMenu] About to loadPhotoIndex from:", idxURL.path)
                    let allEntries = try StorageManager.shared.loadPhotoIndex(from: idxURL)
                    print("[PhotosMenu] allEntries.count =", allEntries.count)
                    let visibleSet = Set(filteredNamesForPhotos.map { $0.lowercased() })
                    let candidates = allEntries.filter { visibleSet.contains($0.name.lowercased()) }
                    print("[PhotosMenu] candidates.count =", candidates.count)
                    let anyExisting = candidates.contains { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0.fileName).path) }
                    if !anyExisting {
                        alertMessage = "No photos on disk match the names in this tree."
                        showAlert = true
                        return
                    }
                } catch {
                    print("[PhotosMenu] Caught error while reading index:", error)
                    alertMessage = "Line 165 in PhotosMenu Failed to read photo index: \(error.localizedDescription)"
                    showAlert = true
                    return
                }
                // To solve the issue of the first tree photo not shown except when the second photo is added
                DispatchQueue.main.async {
                    showFilteredPhotos = true
                }
            }
            .disabled(globals.selectedFolderURL == nil || dataManager.membersDictionary.isEmpty)
        } label: {
            Text("Photos")
        }
        .font(.footnote)
    }
}
