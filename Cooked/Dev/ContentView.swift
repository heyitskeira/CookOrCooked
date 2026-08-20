//
//  ContentView.swift
//  Cooked
//
//  Created by Keira on 10/08/26.
//

import SwiftUI
import SpriteKit
 
// A simple menu so you can open any screen on your phone and try it.
// Tap a button to open that screen, tap Back to return to the menu.
 
struct ContentView: View {
 
    // Holds whichever scene is currently open.
    // When this is nil, the menu is showing instead.
    @State private var activeScene: SKScene?
 
    // The name of the open screen, shown next to the Back button.
    @State private var activeName = ""

    // Storage pantry overlay + the shared inventory it fills (Kitchen map only).
    @State private var showStorage = false
    @State private var showDrawer = false
    @StateObject private var inventory = PlayerInventory()
    @StateObject private var pantry = StoragePantry()
    @StateObject private var drawerBox = DrawerBox()

    var body: some View {
        GeometryReader { geometry in
 
            if let scene = activeScene {
                // A screen is open, so show it with a Back button on top.
                ZStack(alignment: .topLeading) {
 
                    SpriteView(scene: scene)
                        .ignoresSafeArea()
 
                    HStack(spacing: 10) {
                        Button("Back") {
                            activeScene = nil
                            showStorage = false
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.white.opacity(0.15))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())

                        Text(activeName)
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.leading, 20)
                    .padding(.top, 16)

                    // Inventory indicator over the kitchen map.
                    if activeName == "Kitchen map" {
                        VStack {
                            Spacer()
                            InventoryBar(inventory: inventory)
                                .padding(.bottom, 20)
                        }
                    }

                    // Storage pantry, opened from the storage station.
                    if showStorage {
                        StorageView(inventory: inventory, pantry: pantry, onClose: {
                            withAnimation(.easeInOut(duration: 0.2)) { showStorage = false }
                        })
                        .transition(.opacity)
                    }

                    // Drawer shelves, opened from the drawer station.
                    if showDrawer {
                        DrawerView(inventory: inventory, box: drawerBox, onClose: {
                            withAnimation(.easeInOut(duration: 0.2)) { showDrawer = false }
                        })
                        .transition(.opacity)
                    }
                }

            } else {
                // No screen open, so show the menu.
                menu(size: geometry.size)
            }
        }
    }
 
    // ---------------------------------------------------------------
    // THE MENU
    // ---------------------------------------------------------------
 
    private func menu(size: CGSize) -> some View {
        ZStack {
            Color(red: 0.11, green: 0.11, blue: 0.13)
                .ignoresSafeArea()
            
            ScrollView() {
                VStack(spacing: 16) {
     
                    Text("Cook or Cooked")
                        .font(.title.weight(.semibold))
                        .foregroundStyle(.white)
     
                    Text("Pick a screen to test")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.bottom, 12)
     
                    menuButton(title: "Whisking") {
                        activeName = "Whisking"
                        activeScene = makeScene(WhiskPreviewScene(size: size))
                    }
     
                    menuButton(title: "Chopping") {
                        activeName = "Chopping"
                        activeScene = makeScene(ChopPreviewScene(size: size))
                    }
     
                    menuButton(title: "Sifting") {
                        activeName = "Sifting"
                        activeScene = makeScene(SiftPreviewScene(size: size))
                    }
                    
                    menuButton(title: "Melting") {
                        activeName = "Melting"
                        activeScene = makeScene(MeltPreviewScene(size: size))
                    }
                    
                    menuButton(title: "Blow Melt") {
                        activeName = "Butter Melt"
                        activeScene = makeScene(BlowmeltingScreen(size: size))
                    }
                    
                    menuButton(title: "Break Egg") {
                        activeName = "Break Egg"
                        activeScene = makeScene(EggScreen(size: size))
                    }
                    
                    menuButton(title: "Mix prep") {
                        activeName = "Mixing"
                        activeScene = makeScene(MixingScreen(size: size))
                    }
                    
                    menuButton(title: "Decorate Cake") {
                        activeName = "Decorating"
                        activeScene = makeScene(DecorateScreen(size: size))
                    }
     
                    // Delete this button if KitchenScene is not in your project yet.
                    menuButton(title: "Kitchen map") {
                        activeName = "Kitchen map"
                        let scene = KitchenScene(size: size)
                        scene.scaleMode = .resizeFill
                        scene.inventory = inventory
                        scene.onOpenStorage = {
                            withAnimation(.easeInOut(duration: 0.2)) { showStorage = true }
                        }
                        scene.onOpenDrawer = {
                            withAnimation(.easeInOut(duration: 0.2)) { showDrawer = true }
                        }
                        activeScene = scene
                    }
                }
            }
        }
    }
 
    // One button in the menu. The action runs when it is tapped.
    private func menuButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.medium))
                .frame(maxWidth: 240)
                .padding(.vertical, 14)
                .background(.white.opacity(0.12))
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
 
    // ---------------------------------------------------------------
    // HELPER
    // ---------------------------------------------------------------
 
    // Every scene needs the same setup, so this does it in one place.
    private func makeScene(_ scene: SKScene) -> SKScene {
        scene.scaleMode = .resizeFill
        return scene
    }
}
 
#Preview {
    ContentView()
}
