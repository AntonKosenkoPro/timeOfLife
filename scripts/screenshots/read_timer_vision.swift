import Vision
import AppKit
import Foundation

// Vision OCR bridge for read_timer.py (macOS only, no device I/O).
//
// Usage: read_timer_vision.swift <png-path>
// Prints a JSON array of {"text","confidence","bbox"} for every recognized
// text line on stdout; bbox is [x, y, w, h] normalized to the image size
// with a TOP-LEFT origin (Vision's bottom-left origin is flipped here so
// the Python caller works in image coordinates). Diagnostics go to stderr;
// any failure exits nonzero with a message, never partial JSON.
func fail(_ message: String) -> Never {
    if let data = ("read_timer_vision: \(message)\n").data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
    exit(2)
}

let args = CommandLine.arguments
guard args.count == 2 else {
    fail("usage: read_timer_vision.swift <png-path>")
}
let path = args[1]
guard let img = NSImage(contentsOfFile: path) else {
    fail("cannot load image at \(path)")
}
var rect = NSRect(x: 0, y: 0, width: 0, height: 0)
guard let cg = img.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
    fail("cannot decode image at \(path)")
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = false
let handler = VNImageRequestHandler(cgImage: cg, options: [:])
do {
    try handler.perform([request])
} catch {
    fail("Vision request failed: \(error)")
}

var out: [[String: Any]] = []
for observation in request.results ?? [] {
    guard let line = observation.topCandidates(1).first else { continue }
    let box = observation.boundingBox
    out.append([
        "text": line.string,
        "confidence": Double(line.confidence),
        "bbox": [
            Double(box.origin.x),
            Double(1.0 - box.origin.y - box.size.height),
            Double(box.size.width),
            Double(box.size.height),
        ],
    ])
}
do {
    let data = try JSONSerialization.data(withJSONObject: out, options: [])
    guard let text = String(data: data, encoding: .utf8) else {
        fail("cannot encode result JSON")
    }
    print(text)
} catch {
    fail("cannot encode result JSON: \(error)")
}
