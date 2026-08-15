//
//  HoldScreen.swift
//  Cooked
//
//  Created by Keira on 15/08/26.
//
//  A plain hold-to-work station.
//
//  Used for actions that do not have their own motion yet: preheat, bake,
//  assemble, decorate, serve, macerate. Swap them over one at a time as
//  each real screen gets built.
//

import SpriteKit


class HoldOverlay: StationOverlay {

    var isTouching = false

    override func setUpStation() {
        amountNeeded = 3.0          // seconds of holding
        hintWhenIdle = "Hold to work"
        hintWhenWorking = "Working"
        prop.size = CGSize(width: 80, height: 8)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isFinished { return }
        isTouching = true
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        isTouching = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        isTouching = false
    }

    override func readInput(secondsSinceLastFrame: Double) {
        isWorking = isTouching

        if isWorking {
            amountDone = amountDone + secondsSinceLastFrame
        }
    }

    override func animateProp(secondsSinceLastFrame: Double) {
        // A gentle pulse so the screen is not completely static.
        if isWorking {
            let howFull = amountDone / amountNeeded
            prop.xScale = CGFloat(1 + howFull * 0.3)
        }
    }
}

class HoldScreen: SKScene {
    
    var overlay: HoldOverlay!
    var timeOfLastFrame = 0.0
    
    override func didMove(to view: SKView) {
        backgroundColor = SKColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1)
        showWhiskScreen()
    }
    
    func showWhiskScreen() {
        overlay?.removeFromParent()
        
        let newOverlay = HoldOverlay(screenSize: size, actionName: "Hold action (action that isn't coded)")
        
        // When it finishes, wait a moment and show it again so you can retry.
        newOverlay.whenFinished = {
            let wait = SKAction.wait(forDuration: 0.6)
            let again = SKAction.run {
                self.showWhiskScreen()
            }
            self.run(SKAction.sequence([wait, again]))
        }
        
        addChild(newOverlay)
        overlay = newOverlay
    }
    
    override func update(_ currentTime: TimeInterval) {
        if timeOfLastFrame == 0 {
            timeOfLastFrame = currentTime
        }
        
        var gap = currentTime - timeOfLastFrame
        if gap > 0.1 {
            gap = 0.1
        }
        timeOfLastFrame = currentTime
        
        overlay?.update(secondsSinceLastFrame: gap)
    }
}



#if DEBUG
import SwiftUI

#Preview("Melting") {
    GeometryReader { geometry in
        SpriteView(scene: {
            let scene = HoldScreen(size: geometry.size)
            scene.scaleMode = .resizeFill
            return scene
        }())
        .ignoresSafeArea()
    }
}
#endif
