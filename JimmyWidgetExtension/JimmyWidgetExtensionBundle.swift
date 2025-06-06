//
//  JimmyWidgetExtensionBundle.swift
//  JimmyWidgetExtension
//
//  Created by Chen Kahana on 06/06/2025.
//

import WidgetKit
import SwiftUI

@main
struct JimmyWidgetExtensionBundle: WidgetBundle {
    var body: some Widget {
        JimmyWidgetExtension()
        JimmyWidgetExtensionControl()
        JimmyWidgetExtensionLiveActivity()
    }
}
