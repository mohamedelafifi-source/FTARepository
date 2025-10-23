//
//  FamilyView.swift
//  iosApp
//
//  Created by Dennis Vera on 7/19/23.
//  Copyright © 2023 orgName. All rights reserved.
//

import SwiftUI

struct FamilyView: View {
    @ObservedObject var viewModel: FamilyViewModel
    @State private var isRemovingAll = false
    @State private var isReminderSet = false
    @State private var selectedReminder: Reminder? = nil
    
    var body: some View {
        VStack {
            List {
                ForEach(viewModel.familyMembers, id: \.id) { member in
                    Text(member.name)
                }
                .onDelete(perform: viewModel.removeMembers)
            }
            .listStyle(.plain)
            
            Button("Add Family Member") {
                viewModel.addFamilyMember()
            }
            .padding()
            
            Button("Remove All") {
                isRemovingAll = true
            }
            .foregroundColor(.red)
            .padding()
            .alert(isPresented: $isRemovingAll) {
                Alert(
                    title: Text("Delete all"),
                    message: Text("Are you sure you want to clear all data ?"),
                    primaryButton: .destructive(Text("Delete all")) {
                        viewModel.clearAllData()
                    },
                    secondaryButton: .cancel()
                )
            }
        }
        .navigationTitle("Family Members")
    }
}
