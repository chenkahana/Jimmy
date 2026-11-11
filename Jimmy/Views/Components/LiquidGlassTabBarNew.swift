import SwiftUI

/// New Liquid Glass Tab Bar implementation following the plan specifications
struct LiquidGlassTabBarNew: View {
    @Binding var selection: Int
    let tabs: [(icon: String, title: String)]
    
    var body: some View {
        GlassTabBar {
            TabView(selection: $selection) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { index, tab in
                    // Content views would be provided by parent
                    Color.clear
                        .tabItem {
                            VStack {
                                TabIconView(
                                    systemName: tab.icon,
                                    isSelected: selection == index
                                )
                                Text(tab.title)
                                    .font(.caption2)
                            }
                        }
                        .tag(index)
                }
            }
            .tabViewStyle(.automatic)
        }
    }
} 