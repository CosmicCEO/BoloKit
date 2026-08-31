import Darwin

// MARK: - ListNode Structure

public struct ListNode {
    public var prev: UnsafeMutablePointer<ListNode>?
    public var next: UnsafeMutablePointer<ListNode>?
    public var ptr: UnsafeMutableRawPointer?

    public init(prev: UnsafeMutablePointer<ListNode>? = nil, next: UnsafeMutablePointer<ListNode>? = nil, ptr: UnsafeMutableRawPointer? = nil) {
        self.prev = prev
        self.next = next
        self.ptr = ptr
    }
}

// MARK: - List Core Functions

@discardableResult
public func initlist(_ list: UnsafeMutablePointer<ListNode>) -> Int32 {
    list.pointee.prev = nil
    list.pointee.next = nil
    list.pointee.ptr = nil
    return 0
}

@discardableResult
public func addlist(_ list: UnsafeMutablePointer<ListNode>, _ ptr: UnsafeMutableRawPointer?) -> Int32 {
    let node = UnsafeMutablePointer<ListNode>.allocate(capacity: 1)
    node.initialize(to: ListNode(prev: list, next: list.pointee.next, ptr: ptr))
    
    // update links
    if let nextNode = list.pointee.next {
        nextNode.pointee.prev = node
    }
    list.pointee.next = node
    
    return 0
}

public func removelist(_ node: UnsafeMutablePointer<ListNode>, _ releasefunc: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?) -> UnsafeMutablePointer<ListNode>? {
    let nextNode = node.pointee.next
    
    if let prevNode = node.pointee.prev {
        prevNode.pointee.next = nextNode
    }
    if let nextNode = nextNode {
        nextNode.pointee.prev = node.pointee.prev
    }
    
    if let release = releasefunc {
        release(node.pointee.ptr)
    }
    
    node.deinitialize(count: 1)
    node.deallocate()
    
    return nextNode
}

public func clearlist(_ list: UnsafeMutablePointer<ListNode>, _ releasefunc: (@convention(c) (UnsafeMutableRawPointer?) -> Void)?) {
    var node = list.pointee.next
    while let currentNode = node {
        let nextNode = currentNode.pointee.next
        if let release = releasefunc {
            release(currentNode.pointee.ptr)
        }
        currentNode.deinitialize(count: 1)
        currentNode.deallocate()
        node = nextNode
    }
    list.pointee.next = nil
}

public func nextlist(_ node: UnsafeMutablePointer<ListNode>) -> UnsafeMutablePointer<ListNode>? {
    return node.pointee.next
}

public func prevlist(_ node: UnsafeMutablePointer<ListNode>) -> UnsafeMutablePointer<ListNode>? {
    return node.pointee.prev
}

public func ptrlist(_ node: UnsafeMutablePointer<ListNode>) -> UnsafeMutableRawPointer? {
    return node.pointee.ptr
}
