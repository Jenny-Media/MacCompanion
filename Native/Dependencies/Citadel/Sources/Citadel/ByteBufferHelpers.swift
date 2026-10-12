import NIO
import Foundation

extension ByteBuffer {
    mutating func writeSFTPDate(_ date: Date) {
        writeInteger(UInt32(date.timeIntervalSince1970))
    }
    
    mutating func readSFTPDate() -> Date? {
        guard let date = readInteger(as: UInt32.self) else {
            return nil
        }
        
        return Date(timeIntervalSince1970: TimeInterval(date))
    }
    
    mutating func writeSFTPFileAttributes(_ attributes: SFTPFileAttributes) {
        writeInteger(attributes.flags.rawValue)
        
        if let size = attributes.size {
            writeInteger(size)
        }
        
        if let uidgid = attributes.uidgid {
            writeInteger(uidgid.userId)
            writeInteger(uidgid.groupId)
        }
        
        if let permissions = attributes.permissions {
            writeInteger(permissions)
        }
        
        if let accessModificationTime = attributes.accessModificationTime {
            writeSFTPDate(accessModificationTime.accessTime)
            writeSFTPDate(accessModificationTime.modificationTime)
        }
        
        for (key, value) in attributes.extended {
            writeSSHString(key)
            writeSSHString(value)
        }
    }
    
    mutating func readSFTPFileAttributes() -> SFTPFileAttributes? {
        guard let _flags = readInteger(as: UInt32.self) else {
            return nil
        }
        
        let flags = SFTPFileAttributes.Flags(rawValue: _flags)
        var attributes = SFTPFileAttributes()
        
        if flags.contains(.size) {
            guard let size = readInteger(as: UInt64.self) else {
                return nil
            }
            
            attributes.size = size
        }
        
        if flags.contains(.uidgid) {
            guard
                let uid = readInteger(as: UInt32.self),
                let gid = readInteger(as: UInt32.self)
            else {
                return nil
            }
            
            attributes.uidgid = .init(
                userId: uid,
                groupId: gid
            )
        }
        
        if flags.contains(.permissions) {
            guard let permissions = readInteger(as: UInt32.self) else {
                return nil
            }
            
            attributes.permissions = permissions
        }
        
        if flags.contains(.acmodtime) {
            guard
                let accessTime = readSFTPDate(),
                let modificationTime = readSFTPDate()
            else {
                return nil
            }
            
            attributes.accessModificationTime = .init(
                accessTime: accessTime,
                modificationTime: modificationTime
            )
        }
        
        if flags.contains(.extended) {
            guard let extendedCount = readInteger(as: UInt32.self),
                  extendedCount <= 128, Int(extendedCount) <= readableBytes / 8 else {
                return nil
            }
            // Bound synchronous decoder work before allocating. Each pair
            // needs two SSH-string lengths, even when both strings are empty.
            var extended = [(String, String)]()
            extended.reserveCapacity(Int(extendedCount))
            for _ in 0..<extendedCount {
                guard
                    let type = readSSHString(),
                    let data = readSSHString()
                else {
                    return nil
                }
                
                extended.append((type, data))
            }
            attributes.extended = extended
        }
        
        return attributes
    }
    
    mutating func writeSSHString(_ buffer: inout ByteBuffer) {
        self.writeInteger(UInt32(buffer.readableBytes))
        writeBuffer(&buffer)
    }
    
    mutating func writeSSHString(_ string: String) {
        // Both writes allocate as needed; advancing an index cannot grow storage.
        writeInteger(UInt32(string.utf8.count))
        writeString(string)
    }
    
    mutating func readSSHString() -> String? {
        guard
            let length = getInteger(at: self.readerIndex, as: UInt32.self),
            let string = getString(at: self.readerIndex + 4, length: Int(length))
        else {
            return nil
        }
        
        moveReaderIndex(forwardBy: 4 + Int(length))
        return string
    }
    
    mutating func readSSHBuffer() -> ByteBuffer? {
        guard
            let length = getInteger(at: self.readerIndex, as: UInt32.self),
            let slice = getSlice(at: self.readerIndex + 4, length: Int(length))
        else {
            return nil
        }
        
        moveReaderIndex(forwardBy: 4 + Int(length))
        return slice
    }
}
