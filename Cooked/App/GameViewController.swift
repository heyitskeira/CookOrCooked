//
//  Untitled.swift
//  Cooked
//
//  Created by Keira on 10/08/26.
//

import UIKit
import SpriteKit

final class GameViewController: UIViewController {

    override func loadView() {
        view = SKView(frame: UIScreen.main.bounds)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let skView = view as? SKView else { return }
        skView.ignoresSiblingOrder = true
        skView.showsFPS = false
        skView.showsNodeCount = false
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let skView = view as? SKView, skView.scene == nil else { return }
        let scene = KitchenScene(size: skView.bounds.size)
        scene.scaleMode = .resizeFill
        skView.presentScene(scene)
    }

    override var prefersStatusBarHidden: Bool { true }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .landscape
    }
}
