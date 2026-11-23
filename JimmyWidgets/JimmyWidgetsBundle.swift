import SwiftUI
import WidgetKit

@main
struct JimmyWidgetsBundle: WidgetBundle {
    var body: some Widget {
        PlayPauseControl()
        NowPlayingWidget()
    }
}
