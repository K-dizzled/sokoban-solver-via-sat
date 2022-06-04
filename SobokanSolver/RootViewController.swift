//
//  ViewController.swift
//  SobokanSolver
//
//  Created by Андрей on 04.06.2022.
//

import UIKit

class RootViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .orange
        
//        let solver = WaterPouringPuzzleSolver()
//        solver.solveUsingMinisat(for: 8) { positions, oldAmount in
//            print(positions)
//        }
        
        let solve = SolveSokoban(
            size: (6, 7),
            field: ["#######",
                    "#S    #",
                    "#     #",
                    "#C  CX#",
                    "#X    #",
                    "#######"]
        )
    }
}
