//
//  ADPCM.swift
//  BluetoothGamepad
//
//  Created by wsjung on 2022/02/28.
//
// 테스트 검증을 위한 참고 데이타 ( 참고용)
// predict = 0, predict_idx = 0
// [raw] Len=80 Data= 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0xFF 0xFF 0x00 0x00
//                    0x00 0x00 0xFF 0xFF 0x00 0x00 0xFF 0xFF 0x00 0x00 0xFF 0xFF 0x00 0x00 0x00 0x00 0x00 0x00 0x01 0x00
//                    0x00 0x00 0x00 0x00 0xFF 0xFF 0xFF 0xFF 0xFF 0xFF 0xFB 0xFF 0x04 0x00 0x1C 0x00 0x2E 0x00 0x39 0x00
//                    0x2A 0x00 0x2E 0x00 0x2D 0x00 0x3D 0x00 0x41 0x00 0x23 0x00 0x28 0x00 0x27 0x00 0x2C 0x00 0x25 0x00
// [enc] Len=20 Data= 0x00 0x00 0x00 0x00 0x91 0x09 0x19 0x19 0x10 0x01 0x90 0x90 0x0B 0x57 0x41 0xA0 0x03 0x1F 0x08 0x08
//
// predict = 38, predict_idx = 12
// [raw] Len=80 Data= 0x1F 0x00 0x14 0x00 0x13 0x00 0x18 0x00 0x16 0x00 0x11 0x00 0x02 0x00 0x05 0x00 0x02 0x00 0xF6 0xFF
//                    0xF3 0xFF 0xF6 0xFF 0xF6 0xFF 0xF2 0xFF 0xF0 0xFF 0xF4 0xFF 0xFA 0xFF 0xFB 0xFF 0x07 0x00 0x0C 0x00
//                    0xFC 0xFF 0xF2 0xFF 0xF3 0xFF 0xE1 0xFF 0xDA 0xFF 0xDB 0xFF 0xD5 0xFF 0xDE 0xFF 0xE2 0xFF 0xE7 0xFF
//                    0xEF 0xFF 0xF4 0xFF 0xF1 0xFF 0xED 0xFF 0xE6 0xFF 0xEC 0xFF 0xEA 0xFF 0xE0 0xFF 0xE1 0xFF 0xF0 0xFF
// [enc] Len=20 Data= 0x9A 0x00 0x89 0xC0 0x9B 0x91 0x0A 0x93 0x40 0x61 0xDA 0x0C 0x90 0x92 0x11 0x32 0x9A 0xB3 0x9F 0x04
//

import Foundation

class ADPCM {
    private var stepIdxTable: [Int] = [
        -1, -1, -1, -1, /* +0 - +3, decrease the step size */
        2, 4, 6, 8,     /* +4 - +7, increase the step size */
        -1, -1, -1, -1, /* -0 - -3, decrease the step size */
        2, 4, 6, 8      /* -4 - -7, increase the step size */
    ]

    private let stepTable: [Int] = [
        7,  8,  9,  10,  11,  12,  13,  14,  16,  17,
        19,  21,  23,  25,  28,  31,  34,  37,  41,  45,
        50,  55,  60,  66,  73,  80,  88,  97,  107, 118,
        130, 143, 157, 173, 190, 209, 230, 253, 279, 307,
        337, 371, 408, 449, 494, 544, 598, 658, 724, 796,
        876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066,
        2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358,
        5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899,
        15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767
    ]

    private var lStepIdx = 0
    private var lPredicted = 0

    func getStepIdx() -> Int {
        return lStepIdx
    }

    func getPedValue() -> Int {
        return lPredicted
    }

    func setPredAndStep(pred: Int, step: Int) {
        lStepIdx = step
        lPredicted = pred
    }

    private func toByteArray<T>(_ value: T) -> [Int8] {
        var value = value
        return withUnsafePointer(to: &value) {
            $0.withMemoryRebound(to: Int8.self, capacity: MemoryLayout<T>.size) {
                Array(UnsafeBufferPointer(start: $0, count: MemoryLayout<T>.size))
            }
        }
    }

    func reset() {
        lPredicted = 0
        lStepIdx = 0
    }

    func encode(input: [Int16]) -> [UInt8] {
        let count = input.count / 2
        var output = [UInt8](repeating: 0, count: count)

        var inputIdx = 0
        var outputIdx = 0

        while ( outputIdx < count ) {
            let lpcm = input[ inputIdx ]
            inputIdx += 1
            let rpcm = input[ inputIdx ]
            inputIdx += 1

            let v = (mic_to_adpcm_split_byte(pcm: lpcm) << 4) & 0xf0
            let x = mic_to_adpcm_split_byte(pcm: rpcm) & 0x0f
            output[outputIdx] = UInt8((v | x))
            outputIdx += 1
        }

        return output
    }

    func mic_to_adpcm_split_byte(pcm: Int16) -> Int {
        var code = 0

        var predict = lPredicted
        var predict_idx = lStepIdx

        let di = Int(pcm)
        var step = stepTable[predict_idx]

        var diff = di - predict

        if diff >= 0 {
            code = 0
        } else {
            diff = -diff
            code = 8
        }

        var diffq = step >> 3

        var j = 4
        while ( j > 0 ){
            if( diff >= step) {
                diff = diff - step
                diffq = diffq + step
                code = code + j
            }
            step = step >> 1
            j = j >> 1
        }

        if(code >= 8) {
            predict = predict - Int(diffq);
        }
        else {
            predict = predict + Int(diffq);
        }

        if (predict > 32767) {
            predict = 32767;
        }
        else if (predict < -32768) {
            predict = -32768;
        }

        lPredicted =  predict

        predict_idx = predict_idx + stepIdxTable[code&15];
        if(predict_idx < 0) {
            predict_idx = 0;
        }
        else if(predict_idx > 88) {
            predict_idx = 88;
        }
        lStepIdx = predict_idx;

        return code
    }

    private func toArray<T>(_ value: T) -> [UInt8] {
        var value = value
        return withUnsafePointer(to: &value) {
            $0.withMemoryRebound(to: UInt8.self, capacity: MemoryLayout<T>.size) {
                Array(UnsafeBufferPointer(start: $0, count: MemoryLayout<T>.size))
            }
        }
    }

    func decode(input: [UInt8]) -> [UInt8] {
        var output = [UInt8]()

        var inputIdx = 0

        while ( inputIdx < input.count ) {
            let data = input[inputIdx]
            inputIdx += 1
            let hi_4bit = (data >> 4) & 0x0f
            let lo_4bit = data & 0x0f

            let lpcm = decode_mic(code: hi_4bit)
            let rpcm = decode_mic(code: lo_4bit)
            let l = toArray(lpcm)
            output.append(contentsOf: l)
            output.append(contentsOf: toArray(rpcm))
        }
        return output
    }

    func decode_mic(code: UInt8) -> Int16 {

        var predsample = lPredicted
        var index = lStepIdx
        let step = stepTable[index]

        var diffq = step >> 3

        if (code & 4) > 0 {
            diffq += step
        }
        if (code & 2) > 0 {
            diffq += step >> 1
        }
        if (code & 1) > 0 {
            diffq += step >> 2
        }

        if (code & 8) > 0 {
            predsample -= diffq
        } else {
            predsample += diffq
        }

        if (predsample > 32767) {
            predsample = 32767
        }
        else if (predsample < -32768) {
            predsample = -32768
        }

        index += stepIdxTable[Int(code)&15]
        if(index < 0) {
            index = 0;
        }
        else if(index > 88) {
            index = 88;
        }
        lPredicted = predsample
        lStepIdx = index
        return Int16(predsample)
    }
}
