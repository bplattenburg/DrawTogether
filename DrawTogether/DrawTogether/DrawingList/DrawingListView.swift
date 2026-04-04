//
//  DrawingPickerView.swift
//  DrawTogether
//
//  Created by Brian Plattenburg on 3/30/26.
//

import SwiftUI

struct DrawingListView: View {
    @StateObject private var drawingList = DrawingListProvider()
    @State private var newDrawingName = ""
    @State private var selectedDrawing: DrawingInfo?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(drawingList.drawings) { drawing in
                        Button {
                            selectedDrawing = drawing
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
            .navigationDestination(item: $selectedDrawing) { drawing in
                DrawingView(drawingInfo: drawing)
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
                selectedDrawing = DrawingInfo(id: id, name: name)
            } catch {
                NSLog("Failed to create drawing: %@", "\(error)")
            }
        }
    }
}
