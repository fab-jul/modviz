//
//  Buffer.swift
//  modviz
//
//  Created by Fabian Mentzer on 19.01.2025.
//

/*
 
 
 
 */


private class Node<T> {
    var value: T
    var next: Node<T>?
    
    init(value: T) {
        self.value = value
        self.next = nil
    }
}


struct ShiftingBuffer<T> {
    private var start: Node<T>
    private var end: Node<T>
    private let defaultValue: T
    let size: Int

    init(size: Int, defaultValue: T) {
        self.size = size
        self.defaultValue = defaultValue
        self.start = Node<T>(value: defaultValue)
        var end = self.start
        for _ in 1..<size {
            let newEnd = Node<T>(value: defaultValue)
            end.next = newEnd
            end = newEnd
        }
        self.end = end
    }
    
    mutating func append(_ element: T) {
        guard let newStart = self.start.next else { fatalError() }
        self.start = newStart
        self.end.next = Node<T>(value: element)
        self.end = self.end.next!
    }
    
    func get() -> [T] {
        var output = [T](repeating: self.defaultValue, count: self.size)
        var current: Node<T>? = self.start
        var i = 0
        while let currentNode = current {
            output[i] = currentNode.value
            current = currentNode.next
            i += 1
        }
        assert(i == self.size, "Buffer size mismatch")
        return output
    }
}
