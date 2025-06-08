import UIKit
import CarPlay

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController,
                                  to window: CPWindow) {
        print("CarPlay: Scene connecting...")
        
        // Add safety check and error handling
        guard templateApplicationScene.session.role == .carTemplateApplication else {
            print("CarPlay: Invalid scene role")
            return
        }
        
        do {
            CarPlayManager.shared.connect(interfaceController: interfaceController, window: window)
            print("CarPlay: Successfully connected")
        } catch {
            print("CarPlay: Failed to connect - \(error)")
        }
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnect interfaceController: CPInterfaceController,
                                  from window: CPWindow) {
        print("CarPlay: Scene disconnecting...")
        
        do {
            CarPlayManager.shared.disconnect()
            print("CarPlay: Successfully disconnected")
        } catch {
            print("CarPlay: Failed to disconnect - \(error)")
        }
    }
}
