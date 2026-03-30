//
//  ContentView.swift
//  DrawTogether
//
//  Created by Brian Plattenburg on 9/26/25.
//

import SwiftUI
import PencilKit

struct ContentView: View {
    let drawingID: String

    @State private var drawing = PKDrawing()
    @State private var toolPicker: PKToolPicker? = PKToolPicker()

    var body: some View {
        CanvasView(drawing: $drawing, toolPicker: $toolPicker, drawingID: drawingID)
            .edgesIgnoringSafeArea(.all)
    }
}
