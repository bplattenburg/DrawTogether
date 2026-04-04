//
//  ContentView.swift
//  DrawTogether
//
//  Created by Brian Plattenburg on 9/26/25.
//

import SwiftUI
import PencilKit

struct DrawingView: View {
    let drawingID: String

    @State private var drawing = PKDrawing()
    @State private var toolPicker: PKToolPicker? = PKToolPicker()

    var body: some View {
        DrawingCanvasView(drawing: $drawing, toolPicker: $toolPicker, drawingID: drawingID)
            .id(drawingID)
            .edgesIgnoringSafeArea(.all)
    }
}
