//
//  DrawingPickerView.swift
//  DrawTogether
//
//  Created by Brian Plattenburg on 3/30/26.
//

import SwiftUI

struct DrawingPickerView: View {
    @StateObject private var drawingList = DrawingListProvider()
    @State private var newDrawingName = ""
    @State private var selectedDrawingID: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(drawingList.drawings) { drawing in
                        Button {
                            selectedDrawingID = drawing.id
                        } label: {
                            Text(drawing.name)
                        }
                    }
                } header: {
                    if !drawingList.drawings.isEmpty {
                        Text("Drawings")
                    }
                }

                Section {
                    HStack {
                        TextField("Drawing name", text: $newDrawingName)
                            .textFieldStyle(.roundedBorder)
                        Button("Create") {
                            createDrawing()
                        }
                        .disabled(newDrawingName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            .navigationTitle("DrawTogether")
            .navigationDestination(item: $selectedDrawingID) { drawingID in
                ContentView(drawingID: drawingID)
            }
        }
    }

    private func createDrawing() {
        let name = newDrawingName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        newDrawingName = ""
        Task {
            do {
                let id = try await drawingList.createDrawing(name: name)
                selectedDrawingID = id
            } catch {
                NSLog("Failed to create drawing: %@", "\(error)")
            }
        }
    }
}
