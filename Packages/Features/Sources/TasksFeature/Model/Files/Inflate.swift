import Foundation

/// Raw DEFLATE (RFC 1951) in plain Swift, for the Word viewer's ZIP entries. The system's
/// Compression framework is not on every platform the package builds for, and a document is small.
/// `limit` caps the output so a crafted file cannot exhaust memory.
enum Inflate {
    enum Failure: Error { case corrupt, tooLarge }

    static func decompress(_ input: Data, limit: Int) throws -> Data {
        var state = State(input: [UInt8](input), limit: limit)
        try state.run()
        return Data(state.output)
    }

    private struct Huffman {
        var counts = [Int](repeating: 0, count: 16)
        var symbols: [Int]

        static let empty = Huffman(counts: [Int](repeating: 0, count: 16), symbols: [])

        init(counts: [Int], symbols: [Int]) {
            self.counts = counts
            self.symbols = symbols
        }

        init(lengths: ArraySlice<Int>) throws {
            symbols = [Int](repeating: 0, count: lengths.count)
            for length in lengths { counts[length] += 1 }
            counts[0] = 0
            var left = 1
            for length in 1...15 {
                left = left * 2 - counts[length]
                if left < 0 { throw Failure.corrupt }
            }
            var offsets = [Int](repeating: 0, count: 16)
            for length in 1..<15 { offsets[length + 1] = offsets[length] + counts[length] }
            for (symbol, length) in zip(0..., lengths) where length != 0 {
                symbols[offsets[length]] = symbol
                offsets[length] += 1
            }
        }
    }

    private struct State {
        let input: [UInt8]
        let limit: Int
        var output: [UInt8] = []
        var position = 0
        var bitBuffer = 0
        var bitCount = 0

        init(input: [UInt8], limit: Int) {
            self.input = input
            self.limit = limit
        }

        static let lengthBase = [
            3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195,
            227, 258,
        ]
        static let lengthExtra = [
            0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0,
        ]
        static let distanceBase = [
            1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1_025, 1_537, 2_049, 3_073,
            4_097, 6_145, 8_193, 12_289, 16_385, 24_577,
        ]
        static let distanceExtra = [
            0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13,
        ]
        static let codeLengthOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

        mutating func bits(_ count: Int) throws -> Int {
            var value = bitBuffer
            while bitCount < count {
                guard position < input.count else { throw Failure.corrupt }
                value |= Int(input[position]) << bitCount
                position += 1
                bitCount += 8
            }
            bitBuffer = value >> count
            bitCount -= count
            return value & ((1 << count) - 1)
        }

        mutating func run() throws {
            var last = false
            while !last {
                last = try bits(1) == 1
                switch try bits(2) {
                case 0: try stored()
                case 1: try codes(Self.fixed.0, Self.fixed.1)
                case 2:
                    let tables = try dynamicTables()
                    try codes(tables.0, tables.1)
                default: throw Failure.corrupt
                }
            }
        }

        mutating func stored() throws {
            bitBuffer = 0
            bitCount = 0
            guard position + 4 <= input.count else { throw Failure.corrupt }
            let length = Int(input[position]) | Int(input[position + 1]) << 8
            let complement = Int(input[position + 2]) | Int(input[position + 3]) << 8
            position += 4
            guard length == ~complement & 0xFFFF, position + length <= input.count else { throw Failure.corrupt }
            guard output.count + length <= limit else { throw Failure.tooLarge }
            output.append(contentsOf: input[position..<position + length])
            position += length
        }

        mutating func decode(_ table: Huffman) throws -> Int {
            var code = 0
            var first = 0
            var index = 0
            for length in 1...15 {
                code |= try bits(1)
                let count = table.counts[length]
                if code - count < first { return table.symbols[index + (code - first)] }
                index += count
                first = (first + count) << 1
                code <<= 1
            }
            throw Failure.corrupt
        }

        mutating func codes(_ lengths: Huffman, _ distances: Huffman) throws {
            while true {
                let symbol = try decode(lengths)
                if symbol < 256 {
                    guard output.count < limit else { throw Failure.tooLarge }
                    output.append(UInt8(symbol))
                } else if symbol == 256 {
                    return
                } else {
                    let lengthIndex = symbol - 257
                    guard lengthIndex < Self.lengthBase.count else { throw Failure.corrupt }
                    let length = Self.lengthBase[lengthIndex] + (try bits(Self.lengthExtra[lengthIndex]))
                    let distanceIndex = try decode(distances)
                    guard distanceIndex < Self.distanceBase.count else { throw Failure.corrupt }
                    let distance = Self.distanceBase[distanceIndex] + (try bits(Self.distanceExtra[distanceIndex]))
                    guard distance <= output.count else { throw Failure.corrupt }
                    guard output.count + length <= limit else { throw Failure.tooLarge }
                    let start = output.count - distance
                    for offset in 0..<length { output.append(output[start + offset]) }
                }
            }
        }

        mutating func dynamicTables() throws -> (Huffman, Huffman) {
            let literalCount = try bits(5) + 257
            let distanceCount = try bits(5) + 1
            let codeCount = try bits(4) + 4
            guard literalCount <= 286, distanceCount <= 30 else { throw Failure.corrupt }
            var codeLengths = [Int](repeating: 0, count: 19)
            for index in 0..<codeCount { codeLengths[Self.codeLengthOrder[index]] = try bits(3) }
            let codeTable = try Huffman(lengths: codeLengths[...])
            var lengths: [Int] = []
            while lengths.count < literalCount + distanceCount {
                let symbol = try decode(codeTable)
                switch symbol {
                case 0...15:
                    lengths.append(symbol)
                case 16:
                    guard let previous = lengths.last else { throw Failure.corrupt }
                    lengths.append(contentsOf: repeatElement(previous, count: 3 + (try bits(2))))
                case 17:
                    lengths.append(contentsOf: repeatElement(0, count: 3 + (try bits(3))))
                default:
                    lengths.append(contentsOf: repeatElement(0, count: 11 + (try bits(7))))
                }
            }
            guard lengths.count == literalCount + distanceCount, lengths[256] != 0 else { throw Failure.corrupt }
            return (
                try Huffman(lengths: lengths[0..<literalCount]),
                try Huffman(lengths: lengths[literalCount...])
            )
        }

        static let fixed: (Huffman, Huffman) = {
            var lengths = [Int](repeating: 8, count: 288)
            for index in 144..<256 { lengths[index] = 9 }
            for index in 256..<280 { lengths[index] = 7 }
            // Both tables are complete by construction, so building them cannot fail.
            let literal = (try? Huffman(lengths: lengths[...])) ?? Huffman.empty
            let distance = (try? Huffman(lengths: [Int](repeating: 5, count: 30)[...])) ?? Huffman.empty
            return (literal, distance)
        }()
    }
}
