//
//  CanvasView.swift
//  DrawTogether
//
//  Created by Brian Plattenburg on 9/26/25.
//

import SwiftUI
import PencilKit
import DittoSwift

struct CanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    @Binding var toolPicker: PKToolPicker?

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.drawing = drawing
        canvasView.delegate = context.coordinator
        canvasView.drawingPolicy = .anyInput // Allows drawing with finger or Apple Pencil
        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        uiView.drawing = drawing
        context.coordinator.toolPicker = toolPicker
        toolPicker?.setVisible(true, forFirstResponder: uiView)
        toolPicker?.addObserver(uiView)
        uiView.becomeFirstResponder() // Make canvas view the first responder to show tool picker
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: CanvasView
        var toolPicker: PKToolPicker?
        var observer: DittoStoreObserver?

        init(_ parent: CanvasView) {
            self.parent = parent
            super.init()
            observer = try? DittoManager.shared?.ditto?.store.registerObserver(query: "SELECT * FROM drawings", handler: updateFromDitto(_:))
        }

        deinit {
            observer?.cancel()
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard let jsonData = try? JSONEncoder().encode(canvasView.drawing),
                let jsonString = String(data: jsonData, encoding: .utf8) else { return }
            print("insert")
            Task {
                try? await DittoManager.shared?.ditto?.store.execute(query: "INSERT INTO drawings documents deserialize_json('\(jsonString)') ON ID CONFLICT DO MERGE")
            }
        }

        func updateFromDitto(_ result: DittoSwift.DittoQueryResult) {
            guard let item = result.items.first,
                  let drawing = try? JSONDecoder().decode(PKDrawing.self, from: item.jsonData()) else { return }
            print("observe")
            parent.drawing = drawing // TODO merge, use PKStrokes for granular updates etc
        }
    }

}
