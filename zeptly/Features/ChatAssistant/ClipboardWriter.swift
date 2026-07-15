//
//  ClipboardWriter.swift
//  zeptly
//

import UIKit

enum ClipboardWriter {
    static func copy(_ text: String) {
        UIPasteboard.general.string = text
    }
}
