//
//  JimmyWidgetExtensionLiveActivity.swift
//  JimmyWidgetExtension
//
//  Created by Chen Kahana on 06/06/2025.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct JimmyWidgetExtensionAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct JimmyWidgetExtensionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: JimmyWidgetExtensionAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension JimmyWidgetExtensionAttributes {
    fileprivate static var preview: JimmyWidgetExtensionAttributes {
        JimmyWidgetExtensionAttributes(name: "World")
    }
}

extension JimmyWidgetExtensionAttributes.ContentState {
    fileprivate static var smiley: JimmyWidgetExtensionAttributes.ContentState {
        JimmyWidgetExtensionAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: JimmyWidgetExtensionAttributes.ContentState {
         JimmyWidgetExtensionAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: JimmyWidgetExtensionAttributes.preview) {
   JimmyWidgetExtensionLiveActivity()
} contentStates: {
    JimmyWidgetExtensionAttributes.ContentState.smiley
    JimmyWidgetExtensionAttributes.ContentState.starEyes
}
