//
//  ContentView.swift
//  DrawTogether
//
//  Created by Brian Plattenburg on 9/26/25.
//

import SwiftUI
import PencilKit

struct ContentView: View {
    @State private var drawing = PKDrawing()
    @State private var toolPicker: PKToolPicker? = PKToolPicker()

    var body: some View {
        VStack {
            CanvasView(drawing: $drawing, toolPicker: $toolPicker)
                .edgesIgnoringSafeArea(.all) // Extend canvas to fill screen
        }
    }
}

#Preview {
    ContentView()
}
