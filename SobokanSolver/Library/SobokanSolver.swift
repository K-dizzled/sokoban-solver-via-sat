//
//  SobokanSolver.swift
//  SobokanSolver
//
//  Created by Андрей on 04.06.2022.
//

import Foundation
import MiniSat
import Algorithms

extension Dictionary where Value : Equatable {
    func allKeysForValue(val : Value) -> [Key] {
        return self.filter { $1 == val }.map { $0.0 }
    }
}

extension String {
    func chopPrefix(_ count: Int = 1) -> String {
        if count >= 0 && count <= self.count {
            let indexStartOfText = self.index(self.startIndex, offsetBy: count)
            return String(self[indexStartOfText...])
        }
        return ""
    }
    
    func chopSuffix(_ count: Int = 1) -> String {
        if count >= 0 && count <= self.count {
            let indexEndOfText = self.index(self.endIndex, offsetBy: -count)
            return String(self[..<indexEndOfText])
        }
        return ""
    }
}

extension StringProtocol where Self: RangeReplaceableCollection {
    subscript(offset: Int) -> Element {
        get {
            return self[index(startIndex, offsetBy: offset)]
        }
        
        set {
            let start = index(startIndex, offsetBy: offset)
            replaceSubrange(start..<index(after: start), with: [newValue])
        }
    }
}

extension Array where Element == String {
    func bottom(of position: (i: Int, j: Int)) -> Character? {
        if position.i + 1 < self.count {
            return (self[position.i + 1])[position.j]
        } else {
            return nil
        }
    }
    
    func top(of position: (i: Int, j: Int)) -> Character? {
        if position.i - 1 >= 0 {
            return self[position.i - 1][position.j]
        } else {
            return nil
        }
    }
    
    func right(of position: (i: Int, j: Int)) -> Character? {
        if position.j + 1 < self[0].count {
            return self[position.i][position.j + 1]
        } else {
            return nil
        }
    }
    
    func left(of position: (i: Int, j: Int)) -> Character? {
        if position.j - 1 >= 0 {
            return self[position.i][position.j - 1]
        } else {
            return nil
        }
    }
}

class SolveSokoban {
    
    private enum SolverErrors : Error {
        case incorrectMapError
    }
    
    var field: [String]
    let size: (height: Int, width: Int)
    
    var mapDict: Dictionary<Int, [String]> = [:]
    var neighbours: [String] = []
    var validTiles: [Int] = []
    var mapVariables: Dictionary<String, Int32> = [:]
    var minisat: MiniSat
    var actionsCodes: [Int32] = []
    let maxSteps: Int
    
    var nCrates = 0
    var tileCounter = 0

    var xCounter = 0
    var sCounter = 0
    
    init(
        size: (height: Int, width: Int),
        field: [String],
        maxSteps: Int = 30
    ) {
        self.size = size
        self.field = field
        self.minisat = MiniSat()
        self.maxSteps = maxSteps
        
        do {
            try parseInput()
            if lookupSolution() {
                for e in actionsCodes {
                    if minisat.value(of: e) == .positive {
                        print(mapVariables.allKeysForValue(val: e))
                    }
                }
            } else {
                print("Решений не найдено")
            }
            
            
        } catch {
            print(error)
        }
    }
    
    private func safeGet(_ name: String) -> Int32 {
        if name.first == "-" {
            let absName = name.chopPrefix(1)
            if let val = mapVariables[absName] {
                return -val
            } else {
                let v = minisat.new()
                mapVariables[absName] = v
                
                if absName.contains("move") || absName.contains("push") {
                    actionsCodes.append(v)
                }
                
                return -v
            }
        } else {
            if let val = mapVariables[name] {
                return val
            } else {
                let v = minisat.new()
                mapVariables[name] = v
                
                if name.contains("move") || name.contains("push") {
                    actionsCodes.append(v)
                }
                
                return v
            }
        }
    }
    
    private func lookupSolution() -> Bool {
        var sat = false
        var steps = 1

        while !sat && steps < maxSteps {
            if sat { return true } else {
                debugPrint("step \(steps), unsat yet")
            }

            sat = searchSolution(for: steps)
            steps += 1
        }

        return sat
    }
    
    private func parseFormula(_ formula: String) {
        let lines = formula.split(separator: "\n")
        for line in lines {
            let literals = line.components(separatedBy: " v ")
            let clause : [Int32] = literals.map { safeGet($0) }
            
            //print(clause)
            minisat.add(clause: clause)
        }
    }
    
    func searchSolution(for steps: Int) -> Bool {
        let goalAmountOfIterations = steps + 1
        minisat = MiniSat()
        mapVariables = [:]
        actionsCodes = []
    
        // Add all the available movememts
        for neigh in neighbours {
            minisat.add(clause: [safeGet(neigh)])
        }
        
        // Add initial state
        for tile in mapDict.keys {
            if mapDict[tile]?.first != "#" && mapDict[tile]?.first != " " {
                for item in mapDict[tile] ?? [] {
                    if item.contains("C") || item.contains("S") {
                        minisat.add(clause: [safeGet(item)])
                    }
                }
            }
        }
        
        // Add goal state
        var formula: String = ""
        for tile in mapDict.keys {
            if mapDict[tile]?.first != "#" && mapDict[tile]?.first != " " {
                for item in mapDict[tile] ?? [] {
                    if item.contains("X") {
                        for ci in 0..<nCrates {
                            if ci != (nCrates - 1) {
                                let clause = item.replacingOccurrences(of: "X", with: "C\(ci)")
                                                 .replacingOccurrences(of: ")", with: ",\(goalAmountOfIterations - 1)) v ")
                                
                                formula += clause
                            } else {
                                let clause = item.replacingOccurrences(of: "X", with: "C\(ci)")
                                                 .replacingOccurrences(of: ")", with: ",\(goalAmountOfIterations - 1))\n")
                                
                                formula += clause
                            }
                        }
                    }
                }
            }
        }
        parseFormula(formula)
        
        
        // Add move semantics
        formula = ""
        var actions: Dictionary<Int, [String]> = [:]
        for i in 0..<goalAmountOfIterations {
            if i != 0 {
                actions[i] = []
                // Rules:
                // move(x,y,{i}) -> next(x,y)
                // move(x,y,{i}) -> at(S,x,{i-1})
                // move(x,y,{i}) -> -at(C,y,{i-1})
                // move(x,y,{i}) -> at(S,y,{i})
                // move(x,y,{i}) -> -at(S,x,{i})
                
                for x in 0..<tileCounter {
                    for y in 0..<tileCounter {
                        if x != y && neighbours.contains("next(\(x),\(y))") {
                            formula += "-move(\(x),\(y),\(i)) v next(\(x),\(y))\n"
                            formula += "-move(\(x),\(y),\(i)) v at(S,\(x),\(i-1))\n"

                            for ci in 0..<nCrates {
                                formula += "-move(\(x),\(y),\(i)) v -at(C\(ci),\(y),\(i - 1))\n"
                            }
                                
                            formula += "-move(\(x),\(y),\(i)) v at(S,\(y),\(i))\n"
                            formula += "-move(\(x),\(y),\(i)) v -at(S,\(x),\(i))\n"

                            actions[i]?.append("move(\(x),\(y),\(i))")
                        }
                    }
                }
            }
        }
        parseFormula(formula)
        
        formula = ""
        for i in 0..<goalAmountOfIterations {
            if i != 0 {
                for y in 0..<tileCounter {
                    for z in 0..<tileCounter {
                        if y != z && neighbours.contains("next(\(y),\(z))") && neighbours.contains("next(\(z),\(y))") && validTiles.contains(y + (y - z)) {
                            for ci in 0..<nCrates {
                                formula += "-push(C\(ci),\(y),\(z),\(i)) v at(S,\(y+(y-z)),\(i-1))\n"
                                formula += "-push(C\(ci),\(y),\(z),\(i)) v next(\(y),\(z))\n"
                                formula += "-push(C\(ci),\(y),\(z),\(i)) v next(\(y+(y-z)),\(y))\n"
                                formula += "-push(C\(ci),\(y),\(z),\(i)) v at(C\(ci),\(y),\(i-1))\n"

                                for cj in 0..<nCrates {
                                    if ci != cj {
                                        formula += "-push(C\(ci),\(y),\(z),\(i)) v -at(C\(cj),\(z),\(i-1))\n"
                                    }
                                }
                                    
                                formula += "-push(C\(ci),\(y),\(z),\(i)) v at(S,\(y),\(i))\n"
                                formula += "-push(C\(ci),\(y),\(z),\(i)) v at(C\(ci),\(z),\(i))\n"
                                formula += "-push(C\(ci),\(y),\(z),\(i)) v -at(C\(ci),\(y),\(i))\n"
                                formula += "-push(C\(ci),\(y),\(z),\(i)) v -at(S,\(y+(y-z)),\(i))\n"

                                actions[i]?.append("push(C\(ci),\(y),\(z),\(i))")
                            }
                        }
                    }
                }
            }
        }
        parseFormula(formula)
        
        // At least anything happens on each turn
        for i in 0..<goalAmountOfIterations {
            if i != 0 {
                let clause = actions[i]?.map { safeGet($0) } ?? []
        
                minisat.add(clause: clause)
            }
        }

        // Two things do not happen at the same time
        for i in 0..<goalAmountOfIterations {
            if i != 0 {
                for a in actions[i] ?? [] {
                    for b in actions[i] ?? [] {
                        if a != b {
                            minisat.add(clause: [-safeGet(a), -safeGet(b)])
                        }
                    }
                }
            }
        }
        
        // If sokoban moved, crates stay
        // If one crate moves, other crates stay
        for i in 0..<goalAmountOfIterations {
            if i != 0 {
                for x in 0..<tileCounter {
                    for a in 0..<tileCounter {
                        for b in 0..<tileCounter {
                            if a != b && a != x && b != x && (actions[i] ?? []).contains("move(\(a),\(b),\(i))") && validTiles.contains(x) {
                                for ci in 0..<nCrates {
                                    let formula = "-at(C\(ci),\(x),\(i-1)) v -move(\(a),\(b),\(i)) v at(C\(ci),\(x),\(i))\n"
                                    
                                    parseFormula(formula)
                                }
                            }
                        }
                    }
                }
                for x in 0..<tileCounter {
                    for a in  0..<tileCounter {
                        for b in 0..<tileCounter {
                            for ci in 0..<nCrates {
                                for cj in 0..<nCrates {
                                    if a != b && a != x && b != x && (actions[i] ?? []).contains("push(C\(ci),\(a),\(b),\(i))") && validTiles.contains(x) && cj != ci {
                                        let formula = "-at(C\(ci),\(x),\(i-1)) v -push(C\(cj),\(a),\(b),\(i)) v at(C\(ci),\(x),\(i))\n"
                                        
                                        parseFormula(formula)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        
        formula = ""
        for i in 0..<goalAmountOfIterations {
            if i != 0 {
                for x in 0..<tileCounter {
                    for y in 0..<tileCounter {
                        if x != y && validTiles.contains(x) && validTiles.contains(y) {
                            formula += "-at(S,\(x),\(i-1)) v -at(S,\(y),\(i-1))\n"
                            formula += "-at(S,\(x),\(i)) v -at(S,\(y),\(i))\n"
                            
                            for ci in 0..<nCrates {
                                formula += "-at(C\(ci),\(x),\(i-1)) v -at(C\(ci),\(y),\(i-1))\n"
                                formula += "-at(C\(ci),\(x),\(i)) v -at(C\(ci),\(y),\(i))\n"
                            }
                        }
                    }
                }
            }
        }
        
        parseFormula(formula)
        
        let result = minisat.solve()
        switch result {
        case .satisfiable:
            return true
        case .unsatisfiable:
            return false
        }
    }
    
    func parseInput() throws {
        for line in field {
            for c in line {
                if c == "#" {
                    mapDict[tileCounter] = ["#"]
                } else if c == " " {
                    mapDict[tileCounter] = [" "]
                    validTiles.append(tileCounter)
                } else if c == "S" {
                    mapDict[tileCounter] = ["at(S,\(tileCounter),0)"]
                    validTiles.append(tileCounter)
                    sCounter += 1
                } else if c == "s" {
                    mapDict[tileCounter] = ["at(X,\(tileCounter))", "at(S,\(tileCounter),0)"]
                    validTiles.append(tileCounter)
                    xCounter += 1
                    sCounter += 1
                } else if c == "X" {
                    mapDict[tileCounter] = ["at(X,\(tileCounter))"]
                    validTiles.append(tileCounter)
                    xCounter += 1
                } else if c == "C" {
                    mapDict[tileCounter] = ["at(C\(nCrates),\(tileCounter),0)"]
                    validTiles.append(tileCounter)
                    nCrates += 1
                } else if c == "c" {
                    mapDict[tileCounter] = ["at(X,\(tileCounter))", "at(C\(nCrates),\(tileCounter),0)"]
                    validTiles.append(tileCounter)
                    xCounter += 1
                    nCrates += 1
                } else if c == "\n" {
                    continue
                }

                tileCounter += 1
            }
        }
        
        for tile in mapDict.keys {
            if mapDict[tile]?.first != "#" {
                if mapDict[tile + 1]?.first != "#" {
                    neighbours.append("next(\(tile),\(tile + 1))")
                }
                
                if mapDict[tile - 1]?.first != "#" {
                    neighbours.append("next(\(tile),\(tile - 1))")
                }
                
                if mapDict[tile + size.width]?.first != "#" {
                    neighbours.append("next(\(tile),\(tile + size.width))")
                }
                
                if mapDict[tile - size.width]?.first != "#" {
                    neighbours.append("next(\(tile),\(tile - size.width))")
                }
            }
        }
        
        if sCounter != 1 || xCounter != nCrates {
            throw SolverErrors.incorrectMapError
        }
    }
}
