//
//  ChooseAction.swift
//  Cooked
//
//  Created by Keira on 19/08/26.
//

import SwiftUI
import SpriteKit

struct ChooseAction: View {
    let station: StationID              // .bowl1 atau .bowl2, bukan .bowl
    @ObservedObject var inventory: PlayerInventory
    let state: GameState                 // buat isUnlocked
    var onChoose: (CookAction) -> Void   // panggil ini kalau ditekan & valid
    
    private var whiskingAction: CookAction? {
        Recipe.actions.first{$0.motion == .whisk}
    }
    
    private var canWhisk: Bool{
        guard let action = whiskingAction, state.isUnlocked(action) else { return false }
        let needed = GatingBridge.requiredUtensil(for: action)
        return inventory.utensil?.id == needed?.rawValue
    }
    
    var body: some View {
        
        HStack{
            Button(action: {
                if let action = whiskingAction { onChoose(action) }
            }) {
                ZStack{
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.red)
                        .stroke(Color.blue, lineWidth: 4)
                    Text("Whisking")
                        .tint(Color.white)
                    
                }
            }
            .frame(width: 450, height: 100)
        }
    }
    
}

//#Preview {
//    ChooseAction()
//}

