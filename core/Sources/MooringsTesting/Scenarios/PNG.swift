import Foundation

// PNG writes a picture as an uncompressed PNG, so a host with no image library can save its shots.
public enum PNG {
    // crcTable holds the CRC-32 of every byte, for the chunk checksums.
    private static let crcTable: [UInt32] = (0..<256).map { n in
        var c = UInt32(n)
        for _ in 0..<8 {
            c = c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1
        }
        return c
    }

    // encode writes width by height pixels given as 4 bytes each, top row first, with the red, green
    // and blue bytes at offsets red, 1 and blue: 0 and 2 for RGBA, 2 and 0 for the BGRA Windows reads.
    public static func encode(width: Int, height: Int, pixels: [UInt8], red: Int = 0, blue: Int = 2) -> Data {
        precondition(pixels.count == width * height * 4, "PNG.encode: \(pixels.count) bytes for \(width)x\(height)")
        var raw = [UInt8]()
        raw.reserveCapacity(height * (width * 3 + 1))
        for row in 0..<height {
            raw.append(0)
            for col in 0..<width {
                let i = (row * width + col) * 4
                raw += [pixels[i + red], pixels[i + 1], pixels[i + blue]]
            }
        }
        var header = Data()
        header.append(be32(UInt32(width)))
        header.append(be32(UInt32(height)))
        header.append(contentsOf: [8, 2, 0, 0, 0])
        var out = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        out.append(chunk("IHDR", header))
        out.append(chunk("IDAT", stored(raw)))
        out.append(chunk("IEND", Data()))
        return out
    }

    // crc32 returns the CRC-32 of bytes, the checksum every chunk carries.
    public static func crc32<S: Sequence>(_ bytes: S) -> UInt32 where S.Element == UInt8 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in bytes {
            c = crcTable[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8)
        }
        return c ^ 0xFFFF_FFFF
    }

    // adler32 returns the Adler-32 of bytes, the checksum that ends a zlib stream.
    public static func adler32(_ bytes: [UInt8]) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for x in bytes {
            a = (a + UInt32(x)) % 65521
            b = (b + a) % 65521
        }
        return b << 16 | a
    }

    // stored wraps bytes in a zlib stream of stored blocks, which need no compressor.
    private static func stored(_ bytes: [UInt8]) -> Data {
        var out = Data([0x78, 0x01])
        var start = 0
        repeat {
            let n = min(65535, bytes.count - start)
            let last: UInt8 = start + n == bytes.count ? 1 : 0
            out.append(last)
            out.append(contentsOf: [UInt8(n & 0xFF), UInt8(n >> 8), UInt8(~n & 0xFF), UInt8((~n >> 8) & 0xFF)])
            out.append(contentsOf: bytes[start..<start + n])
            start += n
        } while start < bytes.count
        out.append(be32(adler32(bytes)))
        return out
    }

    // chunk frames data as a chunk of kind with its length and checksum.
    private static func chunk(_ kind: String, _ data: Data) -> Data {
        let body = Data(kind.utf8) + data
        var out = be32(UInt32(data.count))
        out.append(body)
        out.append(be32(crc32(body)))
        return out
    }

    // be32 writes n big-endian.
    private static func be32(_ n: UInt32) -> Data {
        Data([UInt8(n >> 24), UInt8((n >> 16) & 0xFF), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)])
    }
}
