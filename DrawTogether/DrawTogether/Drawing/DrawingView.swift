//
//  ContentView.swift
//  DrawTogether
//
//  Created by Brian Plattenburg on 9/26/25.
//

import SwiftUI
import PencilKit

struct DrawingView: View {
    let drawingInfo: DrawingInfo

    @State private var drawing = PKDrawing()
    @State private var toolPicker: PKToolPicker? = PKToolPicker()

    var body: some View {
        DrawingCanvasView(drawing: $drawing, toolPicker: $toolPicker, drawingID: drawingInfo.id)
            .id(drawingInfo.id)
            .edgesIgnoringSafeArea(.all)
            .navigationTitle(drawingInfo.name)
            .navigationBarTitleDisplayMode(.inline)
    }
}
