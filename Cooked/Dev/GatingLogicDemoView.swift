//
//  GatingLogicDemoView.swift
//  Cooked
//
//  Throwaway self-test for the gating rules. Runs scenarios and shows PASS/FAIL
//  so the logic can be eyeballed in the Xcode canvas. Not part of the game.
//

import SwiftUI

private struct Check {
    let name: String
    let passed: Bool
}

private enum GatingTests {

    static func run() -> [Check] {
        var checks: [Check] = []
        func expect(_ name: String, _ condition: Bool) {
            checks.append(Check(name: name, passed: condition))
        }

        // 1) Chop needs strawberries + knife.
        do {
            let board = Station(type: .cuttingBoard)
            GatingEngine.deposit(FoodItem(id: .strawberries), into: board)
            expect("Chop not ready without a knife",
                   GatingEngine.availableAction(at: board, holdingUtensil: nil) == nil)
            expect("Chop ready with a knife",
                   GatingEngine.availableAction(at: board, holdingUtensil: .knife)?.id == "chop")
            let outcome = GatingEngine.perform(at: board, holdingUtensil: .knife)
            expect("Chop produces chopped strawberries",
                   outcome == .produced(FoodItem(id: .choppedStrawberries)))
            expect("Board is blocked by the result",
                   board.isBlocked)
            expect("Taking the result frees the board",
                   GatingEngine.takeOutput(from: board)?.id == .choppedStrawberries && !board.isBlocked)
        }

        // 2) Rotten ingredients: refused at a cooking station, trashed at the bin
        //    through the same deposit → perform path as every other station.
        do {
            let board = Station(type: .cuttingBoard)
            let bin = Station(type: .garbage)
            let rotten = FoodItem(id: .strawberries, isRotten: true)
            expect("Cooking station refuses rotten",
                   GatingEngine.canDeposit(rotten, into: board) == false)
            expect("Garbage bin accepts rotten",
                   GatingEngine.canDeposit(rotten, into: bin) == true)
            expect("Garbage bin refuses a fresh item",
                   GatingEngine.canDeposit(FoodItem(id: .sugar), into: bin) == false)
            GatingEngine.deposit(rotten, into: bin)
            expect("Throwing out the rotten item is trashed",
                   GatingEngine.perform(at: bin, holdingUtensil: nil) == .trashed)
        }

        // 3) Make dough needs ALL five + mixer.
        do {
            let bowl = Station(type: .bowl)
            [.siftedFlour, .meltedButter, .crackedEgg, .sugar].forEach {
                GatingEngine.deposit(FoodItem(id: $0), into: bowl)
            }
            expect("Dough not ready with only 4 of 5",
                   GatingEngine.availableAction(at: bowl, holdingUtensil: .mixer) == nil)
            GatingEngine.deposit(FoodItem(id: .cream), into: bowl)
            expect("Dough not ready with 5 but wrong utensil",
                   GatingEngine.availableAction(at: bowl, holdingUtensil: .whisk) == nil)
            expect("Dough ready with 5 + mixer",
                   GatingEngine.availableAction(at: bowl, holdingUtensil: .mixer)?.id == "dough")
        }

        // 4) Bake needs a pre-heated oven.
        do {
            let oven = Station(type: .oven)
            GatingEngine.deposit(FoodItem(id: .rawDough), into: oven)
            expect("Bake blocked while oven is cold",
                   GatingEngine.availableAction(at: oven, holdingUtensil: nil) == nil)
            // Pre-heat is its own action on an empty oven.
            let empty = Station(type: .oven)
            expect("Pre-heat ready on empty oven",
                   GatingEngine.availableAction(at: empty, holdingUtensil: nil)?.id == "preheat")
            oven._setHot(true)   // simulate the oven having been pre-heated
            expect("Bake ready once oven is hot",
                   GatingEngine.availableAction(at: oven, holdingUtensil: nil)?.id == "bake")
        }

        // 5) Serve wins.
        do {
            let table = Station(type: .table)
            GatingEngine.deposit(FoodItem(id: .finishedCake), into: table)
            expect("Serving the finished cake wins",
                   GatingEngine.perform(at: table, holdingUtensil: nil) == .served)
        }

        // 6) The two bowls are independent.
        do {
            let bowls = [Station(type: .bowl, index: 0), Station(type: .bowl, index: 1)]
            expect("The two bowls have distinct ids", bowls[0].id != bowls[1].id)
            GatingEngine.deposit(FoodItem(id: .flour), into: bowls[0])
            expect("Depositing in bowl 0 leaves bowl 1 empty",
                   bowls[0].deposited.count == 1 && bowls[1].deposited.isEmpty)
        }

        return checks
    }
}

struct GatingLogicDemoView: View {
    private let checks = GatingTests.run()

    private var passedCount: Int { checks.filter { $0.passed }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gating self-test")
                .font(.system(size: 26, weight: .heavy, design: .rounded))
            Text("\(passedCount)/\(checks.count) passed")
                .font(.headline)
                .foregroundStyle(passedCount == checks.count ? .green : .red)

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(checks.indices, id: \.self) { i in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: checks[i].passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(checks[i].passed ? .green : .red)
                            Text(checks[i].name)
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                            Spacer()
                        }
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(white: 0.97).ignoresSafeArea())
    }
}

#Preview {
    GatingLogicDemoView()
}
