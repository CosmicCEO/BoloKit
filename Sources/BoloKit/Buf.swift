import Darwin

// MARK: - Buf Structure

public struct Buf {
    public var ptr: UnsafeMutableRawPointer?
    public var nbytes: Int
    public var size: Int

    public init(ptr: UnsafeMutableRawPointer? = nil, nbytes: Int = 0, size: Int = 0) {
        self.ptr = ptr
        self.nbytes = nbytes
        self.size = size
    }
}

// MARK: - Constants

private let BUFBLOCKSIZE = 16

// MARK: - Buf Core Functions

@discardableResult
public func initbuf(_ buf: UnsafeMutablePointer<Buf>) -> Int32 {
    guard let allocated = malloc(BUFBLOCKSIZE) else {
        return -1
    }
    buf.pointee.ptr = allocated
    buf.pointee.nbytes = 0
    buf.pointee.size = BUFBLOCKSIZE
    return 0
}

public func freebuf(_ buf: UnsafeMutablePointer<Buf>) {
    if let pointer = buf.pointee.ptr {
        free(pointer)
        buf.pointee.ptr = nil
    }
}

private func resizebuf(_ buf: UnsafeMutablePointer<Buf>, _ nbytes: Int) -> Int32 {
    guard let pointer = buf.pointee.ptr else {
        return -1
    }
    let desiredSize = ((nbytes + ((BUFBLOCKSIZE * 2) - 1)) / BUFBLOCKSIZE) * BUFBLOCKSIZE
    if desiredSize != buf.pointee.size {
        guard let reallocated = realloc(pointer, desiredSize) else {
            return -1
        }
        buf.pointee.ptr = reallocated
        buf.pointee.size = desiredSize
    }
    return 0
}

@discardableResult
public func writebuf(_ buf: UnsafeMutablePointer<Buf>, _ data: UnsafeRawPointer, _ nbytes: Int) -> Int {
    if resizebuf(buf, buf.pointee.nbytes + nbytes) != 0 {
        return -1
    }
    if let dest = buf.pointee.ptr {
        memmove(dest + buf.pointee.nbytes, data, nbytes)
        buf.pointee.nbytes += nbytes
    }
    return nbytes
}

@discardableResult
public func readbuf(_ buf: UnsafeMutablePointer<Buf>, _ data: UnsafeMutableRawPointer?, _ nbytes: Int) -> Int {
    guard let dest = buf.pointee.ptr else {
        return -1
    }
    if let target = data {
        memmove(target, dest, nbytes)
    }
    
    let remainingBytes = buf.pointee.nbytes - nbytes
    memmove(dest, dest + nbytes, remainingBytes)
    buf.pointee.nbytes = remainingBytes
    
    if resizebuf(buf, remainingBytes) != 0 {
        return -1
    }
    return remainingBytes
}

// MARK: - POSIX Network & Polling Functions

@discardableResult
public func sendbuf(_ buf: UnsafeMutablePointer<Buf>, _ d: Int32) -> Int {
    guard let pointer = buf.pointee.ptr else { return -1 }
    let nbytes = send(d, pointer, buf.pointee.nbytes, 0)
    if nbytes == -1 {
        if errno != EAGAIN {
            return -1
        }
        return 0
    } else {
        if readbuf(buf, nil, nbytes) == -1 {
            return -1
        }
    }
    return nbytes
}

@discardableResult
public func recvbuf(_ buf: UnsafeMutablePointer<Buf>, _ d: Int32) -> Int {
    var totalnbytes = 0
    while true {
        if resizebuf(buf, buf.pointee.nbytes) != 0 {
            return -1
        }
        guard let pointer = buf.pointee.ptr else { return -1 }
        let availableCapacity = buf.pointee.size - buf.pointee.nbytes
        let nbytes = recv(d, pointer + buf.pointee.nbytes, availableCapacity, MSG_DONTWAIT)
        if nbytes == -1 {
            if errno != EAGAIN {
                return -1
            }
            break
        }
        buf.pointee.nbytes += nbytes
        totalnbytes += nbytes
        if buf.pointee.nbytes < buf.pointee.size {
            break
        }
    }
    return totalnbytes
}

public func selectreadwrite(_ readsock: Int32, _ writesock: Int32) -> Int32 {
    var fds = [
        pollfd(fd: readsock, events: Int16(POLLIN), revents: 0),
        pollfd(fd: writesock, events: Int16(POLLOUT), revents: 0)
    ]
    while true {
        let ret = poll(&fds, 2, -1)
        if ret == -1 {
            if errno != EINTR {
                return -1
            }
        } else {
            break
        }
    }
    if (fds[0].revents & Int16(POLLIN)) != 0 {
        return 1
    } else if (fds[1].revents & Int16(POLLOUT)) != 0 {
        return 0
    }
    return -1
}

public func selectreadread(_ readsock1: Int32, _ readsock2: Int32) -> Int32 {
    var fds = [
        pollfd(fd: readsock1, events: Int16(POLLIN), revents: 0),
        pollfd(fd: readsock2, events: Int16(POLLIN), revents: 0)
    ]
    while true {
        let ret = poll(&fds, 2, -1)
        if ret == -1 {
            if errno != EINTR {
                return -1
            }
        } else {
            break
        }
    }
    if (fds[0].revents & Int16(POLLIN)) != 0 {
        return 1
    } else if (fds[1].revents & Int16(POLLIN)) != 0 {
        return 0
    }
    return -1
}

@discardableResult
public func cntlsend(_ cntlsock: Int32, _ sock: Int32, _ buf: UnsafeMutablePointer<Buf>) -> Int32 {
    var ret: Int32 = 0
    while true {
        ret = selectreadwrite(cntlsock, sock)
        if ret == -1 {
            return -1
        } else if ret == 1 {
            break
        } else if ret == 0 {
            if sendbuf(buf, sock) == -1 {
                return -1
            }
            if buf.pointee.nbytes == 0 {
                break
            }
        }
    }
    return ret
}

@discardableResult
public func cntlrecv(_ cntlsock: Int32, _ sock: Int32, _ buf: UnsafeMutablePointer<Buf>, _ nbytes: Int) -> Int32 {
    var ret: Int32 = 0
    while buf.pointee.nbytes < nbytes {
        ret = selectreadread(cntlsock, sock)
        if ret == -1 {
            return -1
        } else if ret == 1 {
            ret = 1
            break
        } else if ret == 0 {
            let r = recvbuf(buf, sock)
            if r == -1 {
                return -1
            } else if r == 0 {
                errno = EPIPE
                return -1
            }
        }
    }
    return ret
}
