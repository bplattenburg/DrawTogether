//
//  CanvasView.swift
//  DrawTogether
//
//  Created by Brian Plattenburg on 9/26/25.
//

import SwiftUI
import PencilKit

struct DrawingCanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    @Binding var toolPicker: PKToolPicker?
    let drawingID: String

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.drawing = drawing
        canvasView.delegate = context.coordinator
        canvasView.drawingPolicy = .anyInput // Allows drawing with finger or Apple Pencil
        context.coordinator.canvasView = canvasView
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if uiView.drawing != drawing {
            uiView.drawing = drawing
        }
        context.coordinator.toolPicker = toolPicker
        toolPicker?.setVisible(true, forFirstResponder: uiView)
        toolPicker?.addObserver(uiView)
        uiView.becomeFirstResponder() // Make canvas view the first responder to show tool picker
    }

    func makeCoordinator() -> DrawingSyncCoordinator {
        DrawingSyncCoordinator(self, drawingID: drawingID)
    }
}
