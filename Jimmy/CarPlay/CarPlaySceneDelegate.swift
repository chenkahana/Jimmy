import UIKit
import CarPlay
import os

class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private static let logger = Logger(subsystem: "com.chenkahana.Jimmy", category: "CarPlaySceneDelegate")

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didConnect interfaceController: CPInterfaceController,
                                  to window: CPWindow) {
        Self.logger.debug("CarPlay: Scene connecting...")

        // Add safety check and error handling
        guard templateApplicationScene.session.role == .carTemplateApplication else {
            Self.logger.error("CarPlay: Invalid scene role")
            return
        }

        do {
            CarPlayManager.shared.connect(interfaceController: interfaceController, window: window)
            Self.logger.info("CarPlay: Successfully connected")
        } catch {
            Self.logger.error("CarPlay: Failed to connect - \(error)")
        }
    }

    func templateApplicationScene(_ templateApplicationScene: CPTemplateApplicationScene,
                                  didDisconnect interfaceController: CPInterfaceController,
                                  from window: CPWindow) {
        Self.logger.debug("CarPlay: Scene disconnecting...")

        do {
            CarPlayManager.shared.disconnect()
            Self.logger.info("CarPlay: Successfully disconnected")
        } catch {
            Self.logger.error("CarPlay: Failed to disconnect - \(error)")
        }
    }
}
