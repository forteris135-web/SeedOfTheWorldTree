// 임시 음악 합성기. 기획자의 주제곡이 오기 전까지 쓰는 자리 채움 곡들을 코드로 작곡·합성한다.
// 사용: swift tools/gen_music.swift   → audio/_temp_music/*.wav (22050Hz, 모노, 16비트)
// 2026-10-19: 기획자의 정식 곡 18곡이 audio/music/ 에 들어왔다. 이 합성기는 기록으로만 남기고, 정식 곡을 덮어쓰지 않게
// 결과는 audio/_temp_music/ 에 쓴다 (게임은 이 폴더를 쓰지 않는다).
// 주제곡: C단조, 느린 4/4, A(8마디) + B(12마디, 마지막은 G7에 걸침). 엔딩 버전은 C장조로 끝난다.
import Foundation

let RATE = 22050.0
let OUT = "audio/_temp_music/"

enum Inst { case piano, pad, bass, bell, strings, kick, snare, pluck, drone }

struct Note { var midi: Int; var start: Double; var len: Double; var vel: Double; var inst: Inst }

func freq(_ m: Int) -> Double { 440.0 * pow(2.0, Double(m - 69) / 12.0) }

// 음 이름 → 미디 번호. "C4" = 60
func n(_ name: String) -> Int {
    let table: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
    var chars = Array(name)
    var v = table[chars.removeFirst()]!
    if chars.first == "#" { v += 1; chars.removeFirst() }
    if chars.first == "b" { v -= 1; chars.removeFirst() }
    let oct = Int(String(chars))!
    return 12 * (oct + 1) + v
}

final class Track {
    var notes: [Note] = []
    var bpm: Double
    /// 한 마디의 박 수 (4/4 = 4, 왈츠 3/4 = 3). 확장판 수액의 호수 곡들이 3 을 쓴다. 기본 4 라 기존 곡은 바이트 그대로다.
    var beatsPerBar: Double
    init(bpm: Double, beatsPerBar: Double = 4) { self.bpm = bpm; self.beatsPerBar = beatsPerBar }
    func add(_ name: String, _ bar: Double, _ beat: Double, _ len: Double, _ vel: Double = 0.8, _ inst: Inst = .piano) {
        notes.append(Note(midi: n(name), start: (bar - 1) * beatsPerBar + (beat - 1), len: len, vel: vel, inst: inst))
    }
    func chord(_ names: [String], _ bar: Double, _ beat: Double, _ len: Double, _ vel: Double = 0.5, _ inst: Inst = .pad) {
        for nm in names { add(nm, bar, beat, len, vel, inst) }
    }
    func midiNote(_ m: Int, _ startBeat: Double, _ len: Double, _ vel: Double, _ inst: Inst) {
        notes.append(Note(midi: m, start: startBeat, len: len, vel: vel, inst: inst))
    }
    var lengthBeats: Double { notes.map { $0.start + $0.len }.max() ?? 0 }
}

// ---- 악기 (t: 음 시작부터의 초, dur: 누르고 있는 길이) ----
func env(_ t: Double, _ dur: Double, attack: Double, release: Double, decay: Double) -> Double {
    let a = min(t / attack, 1.0)
    let d = exp(-decay * t)
    let r = t > dur ? exp(-(t - dur) / release) : 1.0
    return a * d * r
}

func render(_ note: Note, bpm: Double, into buf: inout [Double]) {
    let spb = 60.0 / bpm
    let f = freq(note.midi)
    let start = note.start * spb
    let dur = note.len * spb
    var tail = 2.0
    switch note.inst {
    case .piano: tail = 2.5
    case .pad, .strings, .drone: tail = 1.8
    case .bass: tail = 1.2
    case .bell: tail = 3.0
    case .kick, .snare: tail = 0.4
    case .pluck: tail = 0.8
    }
    let total = dur + tail
    let i0 = Int(start * RATE)
    let count = Int(total * RATE)
    var rng = UInt32(note.midi * 7919 + Int(note.start * 100))
    func noise() -> Double { rng = rng &* 1664525 &+ 1013904223; return Double(rng) / Double(UInt32.max) * 2 - 1 }
    var lp = 0.0
    for k in 0..<count {
        let i = i0 + k
        if i >= buf.count { break }
        let t = Double(k) / RATE
        var v = 0.0
        switch note.inst {
        case .piano:
            let e = env(t, dur, attack: 0.004, release: 0.25, decay: 0.9 + f / 900.0)
            for h in 1...6 {
                let hd = Double(h)
                v += sin(2 * .pi * f * hd * t) * pow(hd, -1.2) * exp(-0.35 * hd * t)
            }
            v += 0.25 * sin(2 * .pi * f * 1.003 * t) * exp(-0.6 * t)
            v *= e * 0.5
        case .pluck:
            let e = env(t, dur, attack: 0.002, release: 0.1, decay: 3.0 + f / 400.0)
            for h in 1...4 { v += sin(2 * .pi * f * Double(h) * t) * pow(Double(h), -1.0) }
            v *= e * 0.5
        case .pad:
            let e = env(t, dur, attack: 1.4, release: 1.6, decay: 0.03)
            let vib = 1.0 + 0.003 * sin(2 * .pi * 4.5 * t)
            for h in 1...4 { v += sin(2 * .pi * f * vib * Double(h) * t) * pow(Double(h), -1.6) }
            v += 0.5 * sin(2 * .pi * f * 0.998 * t)
            v *= e * 0.28
        case .strings:
            let e = env(t, dur, attack: 0.12, release: 0.4, decay: 0.0)
            let vib = 1.0 + 0.004 * sin(2 * .pi * 5.5 * t + Double(note.midi))
            for h in 1...9 { v += sin(2 * .pi * f * vib * Double(h) * t) * (1.0 / Double(h)) * exp(-0.18 * Double(h)) }
            v *= e * 0.32
        case .drone:
            let e = env(t, dur, attack: 2.5, release: 3.0, decay: 0.0)
            v = sin(2 * .pi * f * t) + 0.4 * sin(2 * .pi * f * 2.01 * t) + 0.2 * sin(2 * .pi * f * 0.5 * t)
            v *= e * 0.35 * (0.85 + 0.15 * sin(2 * .pi * 0.15 * t))
        case .bass:
            let e = env(t, dur, attack: 0.01, release: 0.3, decay: 0.5)
            v = (sin(2 * .pi * f * t) + 0.35 * sin(2 * .pi * f * 2 * t) + 0.1 * sin(2 * .pi * f * 3 * t)) * e * 0.6
        case .bell:
            let e = exp(-1.4 * t)
            v = (sin(2 * .pi * f * t) + 0.5 * sin(2 * .pi * f * 2.76 * t) * exp(-3 * t) + 0.25 * sin(2 * .pi * f * 5.4 * t) * exp(-5 * t)) * e * 0.45
        case .kick:
            let fk = 40.0 + 110.0 * exp(-18 * t)
            v = sin(2 * .pi * fk * t) * exp(-9 * t) * 1.1
        case .snare:
            lp += (noise() - lp) * 0.35
            v = (lp * 0.9 + 0.2 * sin(2 * .pi * 190 * t)) * exp(-14 * t) * 0.8
        }
        buf[i] += v * note.vel
    }
}

func reverb(_ x: [Double], mix: Double, size: Double) -> [Double] {
    var out = x
    let delays = [0.0297, 0.0371, 0.0411, 0.0437].map { Int($0 * size * RATE) }
    var combs = [[Double]](repeating: [], count: 4)
    for d in 0..<4 {
        var buf = [Double](repeating: 0, count: delays[d])
        var idx = 0
        var y = [Double](repeating: 0, count: x.count)
        for i in 0..<x.count {
            let delayed = buf[idx]
            let v = x[i] + delayed * 0.72
            buf[idx] = v
            idx = (idx + 1) % delays[d]
            y[i] = delayed
        }
        combs[d] = y
    }
    // 올패스 하나
    let ad = Int(0.005 * RATE)
    var abuf = [Double](repeating: 0, count: ad)
    var aidx = 0
    for i in 0..<x.count {
        let s = (combs[0][i] + combs[1][i] + combs[2][i] + combs[3][i]) * 0.25
        let d = abuf[aidx]
        let v = s + d * 0.5
        abuf[aidx] = v
        aidx = (aidx + 1) % ad
        out[i] = x[i] * (1 - mix) + (d - 0.5 * v) * mix * 1.6
    }
    return out
}

func writeWav(_ samples: [Double], _ name: String) {
    var peak = 0.001
    for s in samples { peak = max(peak, abs(s)) }
    let gain = 0.89 / peak
    var data = Data()
    let count = samples.count
    func u32(_ v: UInt32) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 4)) }
    func u16(_ v: UInt16) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 2)) }
    data.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + count * 2)); data.append("WAVE".data(using: .ascii)!)
    data.append("fmt ".data(using: .ascii)!); u32(16); u16(1); u16(1); u32(UInt32(RATE)); u32(UInt32(RATE) * 2); u16(2); u16(16)
    data.append("data".data(using: .ascii)!); u32(UInt32(count * 2))
    var pcm = [Int16](repeating: 0, count: count)
    for i in 0..<count { pcm[i] = Int16(max(-1.0, min(1.0, samples[i] * gain)) * 32767.0) }
    pcm.withUnsafeBufferPointer { data.append(Data(buffer: $0)) }
    try? FileManager.default.createDirectory(atPath: OUT, withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: OUT + ".gdignore", contents: Data())   // Godot 이 가져오지 않게
    try! data.write(to: URL(fileURLWithPath: OUT + name + ".wav"))
    print("\(name).wav  \(String(format: "%.1f", Double(count) / RATE))초")
}

/// 트랙을 렌더링. loopBeats 가 있으면 그 길이에서 자르고 꼬리를 앞머리에 섞어 끊김 없이 반복되게 한다.
/// 인자로 곡 이름을 주면(예: swift tools/gen_music.swift ambient_flooded_mine boss_iron_pump) 그 곡만 만든다. 없으면 전부.
/// **이미 있는 파일은 건너뛴다** (기획자의 진짜 곡을 같은 이름으로 넣어 두었을 수 있다). 덮어쓰려면 --force.
let FORCE = CommandLine.arguments.contains("--force")
let ONLY = Set(CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("--") })

func bounce(_ tr: Track, _ name: String, loopBeats: Double? = nil, tailSec: Double = 4.0, mix: Double = 0.28, size: Double = 1.0) {
    if !ONLY.isEmpty && !ONLY.contains(name) { return }
    if !FORCE && FileManager.default.fileExists(atPath: OUT + name + ".wav") {
        print("\(name).wav 이미 있음 — 건너뜀 (덮어쓰려면 --force)")
        return
    }
    let spb = 60.0 / tr.bpm
    let total = (loopBeats ?? tr.lengthBeats) * spb + tailSec
    var buf = [Double](repeating: 0, count: Int(total * RATE) + 1)
    for note in tr.notes { render(note, bpm: tr.bpm, into: &buf) }
    var wet = reverb(buf, mix: mix, size: size)
    if let lb = loopBeats {
        let loopLen = Int(lb * spb * RATE)
        // 꼬리를 앞에 겹쳐 반복 이음새를 지운다
        for i in loopLen..<wet.count { let j = i - loopLen; if j < wet.count { wet[j] += wet[i] } }
        wet = Array(wet[0..<loopLen])
    }
    writeWav(wet, name)
}

// =====================================================================
// 주제곡 (C단조). 62 bpm, 4/4.
// =====================================================================
func themeA(_ t: Track, bar b: Double, vel: Double = 0.75) {
    // 선율 (A: 공간을 여는 단음)
    t.add("G4", b, 1, 2, vel); t.add("Eb4", b, 3, 1, vel); t.add("D4", b, 4, 1, vel)
    t.add("C4", b+1, 1, 4, vel)
    t.add("Ab4", b+2, 1, 2, vel); t.add("G4", b+2, 3, 1, vel); t.add("F4", b+2, 4, 1, vel)
    t.add("Eb4", b+3, 1, 3, vel); t.add("D4", b+3, 4, 1, vel)
    t.add("G4", b+4, 1, 2, vel); t.add("Bb4", b+4, 3, 1, vel); t.add("C5", b+4, 4, 1, vel)
    t.add("Bb4", b+5, 1, 2, vel); t.add("G4", b+5, 3, 2, vel)
    t.add("F4", b+6, 1, 1, vel); t.add("Eb4", b+6, 2, 1, vel); t.add("D4", b+6, 3, 1, vel); t.add("Eb4", b+6, 4, 1, vel)
    t.add("C4", b+7, 1, 4, vel)
    // 아주 낮은 울림
    t.add("C2", b, 1, 8, 0.35, .bass); t.add("C2", b+4, 1, 8, 0.3, .bass)
}

let bChords: [(String, [String], [String])] = [   // (베이스, 화음, 선율 한 마디)
    ("C2", ["C3","Eb3","G3"], ["Eb5:1:2","D5:3:1","C5:4:1"]),
    ("Ab1", ["Ab2","C3","Eb3"], ["C5:1:2","Bb4:3:2"]),
    ("F2", ["F3","Ab3","C4"], ["Ab4:1:2","G4:3:1","F4:4:1"]),
    ("G1", ["G2","B2","D3"], ["G4:1:3"]),
    ("C2", ["C3","Eb3","G3"], ["G5:1:2","F5:3:1","Eb5:4:1"]),
    ("Eb2", ["Eb3","G3","Bb3"], ["Eb5:1:1","D5:2:1","Eb5:3:1","G5:4:1"]),
    ("Ab1", ["Ab2","C3","Eb3"], ["Ab5:1:2","G5:3:1","F5:4:1"]),
    ("Bb1", ["Bb2","D3","F3"], ["F5:1:2","D5:3:2"]),
    ("C2", ["C3","Eb3","G3"], ["Eb5:1:2","C5:3:1","D5:4:1"]),
    ("F2", ["F3","Ab3","C4"], ["C5:1:2","Ab4:3:2"]),
    ("Ab1", ["Ab2","C3","Eb3"], ["Ab4:1:1","Bb4:2:1","C5:3:2"]),
    ("G1", ["G2","B2","D3","F3"], ["D5:1:1","B4:2:3"]),
]

func themeB(_ t: Track, bar b: Double, bars: Int, vel: Double = 0.8, padInst: Inst = .pad) {
    for (k, c) in bChords.prefix(bars).enumerated() {
        let bar = b + Double(k)
        t.add(c.0, bar, 1, 4, 0.5, .bass)
        t.chord(c.1, bar, 1, 4, 0.28 + 0.02 * Double(k), padInst)
        for m in c.2 {
            let p = m.split(separator: ":")
            t.add(String(p[0]), bar, Double(p[1])!, Double(p[2])!, vel)
            // 선율의 3도 아래 희미한 화성 (후반부)
            if k >= 4 { t.add(String(p[0]), bar, Double(p[1])!, Double(p[2])!, vel * 0.25, .pluck) }
        }
        // 분산화음 (왼손)
        for (i, nm) in c.1.enumerated() where i < 3 { t.add(nm, bar, 1.5 + Double(i), 0.8, 0.22, .piano) }
    }
}

// A만 (첫 회상)
do {
    let t = Track(bpm: 62)
    themeA(t, bar: 1)
    bounce(t, "theme_a", loopBeats: 32, mix: 0.35, size: 1.3)
}
// A + B 일부 (둘째 회상) : B 6마디까지, Eb 화음 위에서 멈춘다
do {
    let t = Track(bpm: 62)
    themeA(t, bar: 1)
    themeB(t, bar: 9, bars: 6)
    bounce(t, "theme_ab", loopBeats: 56, mix: 0.35, size: 1.3)
}
// 전체 (마지막 회상, 타이틀) : A + B, G7 에 걸쳐 반복
do {
    let t = Track(bpm: 62)
    themeA(t, bar: 1)
    themeB(t, bar: 9, bars: 12)
    bounce(t, "theme_full", loopBeats: 80, mix: 0.35, size: 1.3)
}
// 엔딩 버전: 전체 뒤 C장조로 끝맺음 (반복 없음)
do {
    let t = Track(bpm: 58)
    themeA(t, bar: 1)
    themeB(t, bar: 9, bars: 12)
    // 21~24: 해결. E♮ 이 들어온다
    t.add("C2", 21, 1, 16, 0.5, .bass)
    t.chord(["C3","E3","G3","C4"], 21, 1, 16, 0.3)
    t.add("C5", 21, 1, 4, 0.8)
    t.add("E5", 22, 1, 1, 0.5, .bell); t.add("G5", 22, 2, 1, 0.5, .bell); t.add("C6", 22, 3, 2, 0.6, .bell)
    t.add("E5", 23, 1, 4, 0.7); t.add("G5", 23, 1, 4, 0.5)
    t.add("C6", 24, 1, 4, 0.5, .bell); t.add("E6", 24, 3, 2, 0.35, .bell)
    bounce(t, "theme_ending", tailSec: 7.0, mix: 0.4, size: 1.5)
}
// 최종 보스 2페이즈: 격렬한 편곡 (150 bpm, 몰아치는 왼손, 현악, 북)
do {
    let t = Track(bpm: 150)
    // 선율은 두 배 빠르게 (같은 마디 수지만 bpm 이 빠름) — A 와 B 를 현악으로
    func fastA(_ b: Double) {
        let v = 0.9
        let notes: [(String, Double, Double, Double)] = [("G5",1,1,2),("Eb5",1,3,1),("D5",1,4,1),("C5",2,1,4),("Ab5",3,1,2),("G5",3,3,1),("F5",3,4,1),("Eb5",4,1,3),("D5",4,4,1),("G5",5,1,2),("Bb5",5,3,1),("C6",5,4,1),("Bb5",6,1,2),("G5",6,3,2),("F5",7,1,1),("Eb5",7,2,1),("D5",7,3,1),("Eb5",7,4,1),("C5",8,1,4)]
        for (nm, bar, beat, len) in notes { t.add(nm, b + bar - 1, beat, len, v, .strings); t.add(nm, b + bar - 1, beat, len, v * 0.6, .piano) }
    }
    let bassLine: [(String, String)] = [("C2","C3"),("C2","C3"),("Ab1","Ab2"),("Ab1","Ab2"),("F2","F3"),("F2","F3"),("G1","G2"),("G1","G2")]
    func ostinato(_ b: Double, bars: Int, roots: [String]) {
        for k in 0..<bars {
            let bar = b + Double(k)
            let r = roots[k % roots.count]
            let m = n(r)
            for e in 0..<8 {   // 8분음표 왼손
                let mm = (e % 4 == 2) ? m + 7 : ((e % 4 == 3) ? m + 12 : m)
                t.midiNote(mm, (bar - 1) * 4 + Double(e) * 0.5, 0.45, 0.55, .bass)
            }
            t.midiNote(36, (bar - 1) * 4 + 0, 0.5, 0.9, .kick); t.midiNote(36, (bar - 1) * 4 + 2, 0.5, 0.8, .kick)
            t.midiNote(38, (bar - 1) * 4 + 1, 0.5, 0.6, .snare); t.midiNote(38, (bar - 1) * 4 + 3, 0.5, 0.6, .snare)
            t.midiNote(38, (bar - 1) * 4 + 3.5, 0.25, 0.35, .snare)
        }
    }
    ostinato(1, bars: 8, roots: ["C2","C2","Ab1","Ab1","F2","F2","G1","G1"])
    fastA(1)
    t.chord(["C4","Eb4","G4"], 1, 1, 8, 0.35, .strings); t.chord(["Ab3","C4","Eb4"], 3, 1, 8, 0.35, .strings)
    t.chord(["F3","Ab3","C4"], 5, 1, 8, 0.35, .strings); t.chord(["G3","B3","D4"], 7, 1, 8, 0.4, .strings)
    // B 를 더 격하게
    var roots: [String] = []
    for c in bChords { roots.append(c.0) }
    ostinato(9, bars: 12, roots: roots)
    for (k, c) in bChords.enumerated() {
        let bar = 9 + Double(k)
        t.chord(c.1.map { $0 }, bar, 1, 4, 0.4, .strings)
        for m in c.2 {
            let p = m.split(separator: ":")
            let nm = String(p[0])
            t.add(nm, bar, Double(p[1])!, Double(p[2])!, 0.95, .strings)
            t.midiNote(n(nm) + 12, (bar - 1) * 4 + Double(p[1])! - 1, Double(p[2])!, 0.5, .piano)
        }
    }
    bounce(t, "theme_battle", loopBeats: 80, tailSec: 3.0, mix: 0.22, size: 0.9)
}

// =====================================================================
// 지역 배경음악 (반복, 큰 절정 없이)
// =====================================================================
// 수관: 바람과 빛. C단조 패드 + 드문드문 높은 피아노
do {
    let t = Track(bpm: 60)
    let prog = [["C3","G3","Eb4"],["Ab2","Eb3","C4"],["F2","C3","Ab3"],["G2","D3","Bb3"]]
    for k in 0..<4 { t.chord(prog[k], 1 + Double(k * 4), 1, 16, 0.3) }
    let sparkle: [(String, Double, Double)] = [("G5",2,1),("Eb5",3,3),("C6",5,2),("Bb5",7,1),("G5",8,4),("Ab5",10,2),("F5",11,3),("Eb5",13,1),("D5",14,2),("G5",15,4)]
    for (nm, bar, beat) in sparkle { t.add(nm, bar, beat, 2, 0.4, .bell) }
    t.add("C2", 1, 1, 64, 0.25, .drone)
    bounce(t, "ambient_canopy", loopBeats: 64, mix: 0.45, size: 1.6)
}
// 마을: 따뜻하지만 아련한. Eb장조(나란한조) 피아노 아르페지오
do {
    let t = Track(bpm: 72)
    let prog = [["Eb3","G3","Bb3"],["C3","Eb3","G3"],["Ab2","C3","Eb3"],["Bb2","D3","F3"]]
    for rep in 0..<2 {
        for k in 0..<4 {
            let bar = 1 + Double(rep * 16 + k * 4)
            t.chord(prog[k], bar, 1, 16, 0.22)
            t.add(prog[k][0].replacingOccurrences(of: "3", with: "2"), bar, 1, 16, 0.35, .bass)
            for b2 in 0..<4 {
                for (i, nm) in prog[k].enumerated() { t.add(nm, bar + Double(b2), 1 + Double(i), 1.2, 0.3, .piano) }
                t.add(prog[k][1].replacingOccurrences(of: "3", with: "4"), bar + Double(b2), 4, 1.2, 0.22, .piano)
            }
        }
    }
    let mel: [(String, Double, Double, Double)] = [("Bb4",2,1,2),("G4",2,3,2),("Eb5",6,1,3),("D5",6,4,1),("C5",10,1,2),("Ab4",10,3,2),("Bb4",14,1,4),("G4",18,1,2),("Bb4",18,3,2),("C5",22,1,2),("Eb5",22,3,2),("D5",26,1,3),("Bb4",26,4,1),("Eb5",30,1,4)]
    for (nm, bar, beat, len) in mel { t.add(nm, bar, beat, len, 0.45, .bell) }
    bounce(t, "ambient_village", loopBeats: 128, mix: 0.38, size: 1.3)
}
// 채굴장: 무겁고 기계적. 낮은 드론, 규칙적인 맥동, 가끔 불협
do {
    let t = Track(bpm: 66)
    t.add("C1", 1, 1, 64, 0.5, .drone); t.add("G1", 1, 1, 64, 0.25, .drone)
    for bar in 1...16 {
        t.midiNote(36, Double(bar - 1) * 4, 0.5, 0.5, .kick)
        t.midiNote(36, Double(bar - 1) * 4 + 2.5, 0.5, 0.3, .kick)
        if bar % 4 == 0 { t.midiNote(38, Double(bar - 1) * 4 + 3, 0.5, 0.3, .snare) }
    }
    let dis: [(String, Double, Double)] = [("Db3",3,1),("C3",3,3),("G2",7,1),("Ab2",7,3),("Db3",11,1),("C3",12,1),("F#2",15,1)]
    for (nm, bar, beat) in dis { t.add(nm, bar, beat, 3, 0.35, .strings) }
    t.chord(["C3","G3"], 1, 1, 32, 0.2, .strings); t.chord(["Ab2","Eb3"], 9, 1, 32, 0.2, .strings)
    bounce(t, "ambient_mine", loopBeats: 64, mix: 0.3, size: 1.1)
}
// 심연: 깊고 낮은. 아주 느린 종소리, 단2도의 긴장
do {
    let t = Track(bpm: 50)
    t.add("C1", 1, 1, 64, 0.45, .drone); t.add("Ab1", 1, 1, 32, 0.2, .drone); t.add("G1", 9, 1, 32, 0.2, .drone)
    let bells: [(String, Double, Double)] = [("C4",1,1),("Ab3",3,3),("G3",5,1),("Eb4",8,1),("D4",9,3),("C4",12,1),("B3",14,1),("C4",16,3)]
    for (nm, bar, beat) in bells { t.add(nm, bar, beat, 4, 0.35, .bell) }
    t.chord(["C3","Eb3"], 1, 1, 64, 0.15); t.chord(["Ab2","G3"], 5, 1, 24, 0.12)
    bounce(t, "ambient_abyss", loopBeats: 64, mix: 0.5, size: 1.8)
}

// =====================================================================
// 보스곡 (격렬하지만 처절하게)
// =====================================================================
// 잿빛 잎새의 새: 높은 음역의 날카로운 현악, 빠른 분산화음
do {
    let t = Track(bpm: 140)
    let prog = [["C","Eb","G"],["Ab","C","Eb"],["F","Ab","C"],["G","B","D"]]
    for rep in 0..<2 {
        for k in 0..<4 {
            let bar = 1 + Double(rep * 8 + k * 2)
            let root = n(prog[k][0] + "5"); let third = n(prog[k][1] + "5"); let fifth = n(prog[k][2] + "5")
            let arp = [root, third, fifth, root + 12, fifth, third, root, third]
            for b2 in 0..<2 { for e in 0..<8 { t.midiNote(arp[e] + (b2 == 1 ? 0 : 0), (bar - 1 + Double(b2)) * 4 + Double(e) * 0.5, 0.5, 0.5, .strings) } }
            t.midiNote(root - 36, (bar - 1) * 4, 8, 0.5, .bass)
            t.midiNote(root - 12, (bar - 1) * 4, 8, 0.3, .strings)
            for e in 0..<16 { if e % 2 == 0 { t.midiNote(36, (bar - 1) * 4 + Double(e) * 0.5, 0.3, e % 4 == 0 ? 0.8 : 0.4, .kick) } else if e % 4 == 3 { t.midiNote(38, (bar - 1) * 4 + Double(e) * 0.5, 0.3, 0.5, .snare) } }
        }
    }
    let mel: [(String, Double, Double, Double)] = [("G6",3,1,1.5),("F6",3,2.5,0.5),("Eb6",3,3,2),("D6",5,1,1),("Eb6",5,2,1),("C6",5,3,2),("Ab6",7,1,2),("G6",7,3,1),("F6",7,4,1),("D6",8,1,4),("G6",11,1,1),("Bb6",11,2,1),("C7",11,3,2),("Bb6",13,1,2),("G6",13,3,2),("F6",15,1,1),("Eb6",15,2,1),("D6",15,3,2)]
    for (nm, bar, beat, len) in mel { t.add(nm, bar, beat, len, 0.8, .strings) }
    bounce(t, "boss_bird", loopBeats: 64, tailSec: 2.5, mix: 0.25, size: 1.0)
}
// 등불 기사: 장중하고 무너져 가는 행진
do {
    let t = Track(bpm: 96)
    let prog = [["C2","C3","G3","Eb4"],["Ab1","Ab2","Eb3","C4"],["F1","F2","C3","Ab3"],["G1","G2","D3","B3"],["C2","C3","G3","Eb4"],["Bb1","Bb2","F3","D4"],["Ab1","Ab2","Eb3","C4"],["G1","G2","D3","B3"]]
    for (k, c) in prog.enumerated() {
        let bar = 1 + Double(k * 2)
        t.add(c[0], bar, 1, 8, 0.6, .bass)
        t.chord(Array(c[1...]), bar, 1, 8, 0.4, .strings)
        for b2 in 0..<2 {
            let base = (bar - 1 + Double(b2)) * 4
            t.midiNote(36, base, 0.5, 0.9, .kick); t.midiNote(38, base + 1, 0.5, 0.5, .snare)
            t.midiNote(36, base + 2, 0.5, 0.7, .kick); t.midiNote(38, base + 3, 0.5, 0.6, .snare); t.midiNote(38, base + 3.5, 0.25, 0.35, .snare)
            // 행진 리듬의 피아노 화음
            t.chord(Array(c[1...]), bar + Double(b2), 1, 0.6, 0.35, .piano); t.chord(Array(c[1...]), bar + Double(b2), 3, 0.6, 0.3, .piano)
        }
    }
    let mel: [(String, Double, Double, Double)] = [("G4",1,1,3),("Ab4",1,4,1),("G4",2,1,2),("Eb4",2,3,2),("C5",3,1,3),("Bb4",3,4,1),("Ab4",4,1,4),("F4",5,1,2),("Ab4",5,3,2),("C5",6,1,2),("Eb5",6,3,2),("D5",7,1,3),("B4",7,4,1),("G4",8,1,4),("G5",9,1,2),("F5",9,3,1),("Eb5",9,4,1),("D5",10,1,4),("F5",11,1,2),("D5",11,3,2),("Bb4",12,1,4),("Ab4",13,1,2),("C5",13,3,2),("Eb5",14,1,4),("D5",15,1,2),("B4",15,3,2),("G4",16,1,4)]
    for (nm, bar, beat, len) in mel { t.add(nm, bar, beat, len, 0.85, .strings) }
    bounce(t, "boss_knight", loopBeats: 64, tailSec: 2.5, mix: 0.3, size: 1.2)
}
// 뿌리지기 1페이즈: 느리고 낮게 시작해 점점 격해지는 곡
do {
    let t = Track(bpm: 112)
    t.add("C1", 1, 1, 64, 0.35, .drone)
    let prog = [["C2","G3","Eb4","Bb4"],["Ab1","Eb3","C4","G4"],["Db2","Ab3","F4","Db5"],["G1","D3","B3","F4"]]
    for rep in 0..<2 {
        for k in 0..<4 {
            let bar = 1 + Double(rep * 8 + k * 2)
            let c = prog[k]
            t.add(c[0], bar, 1, 8, 0.6, .bass)
            t.chord(Array(c[1...]), bar, 1, 8, 0.3 + 0.12 * Double(rep), .strings)
            let dens = rep == 0 ? 2 : 4
            for b2 in 0..<2 {
                let base = (bar - 1 + Double(b2)) * 4
                for e in stride(from: 0, to: 8, by: 8 / dens) { t.midiNote(36, base + Double(e) * 0.5, 0.4, e == 0 ? 0.9 : 0.5, .kick) }
                if rep == 1 { t.midiNote(38, base + 2, 0.4, 0.5, .snare); t.midiNote(38, base + 3.5, 0.2, 0.35, .snare) }
                if rep == 1 { for e in 0..<8 { t.midiNote(n(c[0]) + 12 + (e % 2 == 0 ? 0 : 7), base + Double(e) * 0.5, 0.45, 0.4, .bass) } }
            }
        }
    }
    let mel: [(String, Double, Double, Double)] = [("Eb4",3,1,2),("D4",3,3,2),("C4",4,1,4),("Ab4",7,1,2),("G4",7,3,2),("F4",8,1,4),("Eb5",11,1,1),("D5",11,2,1),("C5",11,3,2),("Bb4",12,1,2),("G4",12,3,2),("Ab4",13,1,1),("Bb4",13,2,1),("C5",13,3,2),("Db5",14,1,2),("C5",14,3,2),("B4",15,1,3),("D5",15,4,1),("G4",16,1,4)]
    for (nm, bar, beat, len) in mel { t.add(nm, bar, beat, len, 0.8, .strings); t.add(nm, bar, beat, len, 0.4, .bell) }
    bounce(t, "boss_root", loopBeats: 64, tailSec: 2.5, mix: 0.35, size: 1.4)
}
// =====================================================================
// 확장판 · 수액의 호수 (3/4 왈츠). EXPANSION.md 10장의 Suno 프롬프트를 흉내 낸 임시곡.
// 기획자의 진짜 곡(field_sap_lake.mp3 / boss_sap_queen.mp3)이 오면 같은 이름의 wav 로 바꿔 끼운다.
// ==============================================================// 수액의 호수 필드: 쓸쓸한 왈츠, 부드러운 피아노·하프(pluck), 흐르는 패드. Eb장조에 단조 그림자. 72bpm, 24마디 반복 (60초).
do {
    let t = Track(bpm: 72, beatsPerBar: 3)
    // (베이스, 화음, 하프 분산화음 6개(8분음표))
    let prog: [(String, [String], [String])] = [
        ("Eb2", ["Eb3","G3","Bb3"], ["Eb3","Bb3","G4","Bb4","G4","Bb3"]),
        ("C2",  ["C3","Eb3","G3"],  ["C3","G3","Eb4","G4","Eb4","G3"]),
        ("Ab2", ["Ab2","C3","Eb3"], ["Ab2","Eb3","C4","Eb4","C4","Eb3"]),
        ("Bb2", ["Bb2","D3","F3"],  ["Bb2","F3","D4","F4","D4","F3"]),
        ("Eb2", ["Eb3","G3","Bb3"], ["Eb3","Bb3","G4","Bb4","G4","Bb3"]),
        ("G2",  ["G2","Bb2","D3"],  ["G2","D3","Bb3","D4","Bb3","D3"]),     // 단조 그림자
        ("Ab2", ["Ab2","C3","Eb3"], ["Ab2","Eb3","C4","Eb4","C4","Eb3"]),
        ("Bb2", ["Bb2","D3","F3"],  ["Bb2","F3","D4","F4","D4","F3"]),
        ("Eb2", ["Eb3","G3","Bb3"], ["Eb3","Bb3","G4","Bb4","G4","Bb3"]),
        ("Eb2", ["Eb3","Gb3","Bb3"], ["Eb3","Bb3","Gb4","Bb4","Gb4","Bb3"]), // Eb단조로 잠깐 어두워진다
        ("Ab2", ["Ab2","C3","Eb3"], ["Ab2","Eb3","C4","Eb4","C4","Eb3"]),
        ("F2",  ["F2","Ab2","C3"],  ["F2","C3","Ab3","C4","Ab3","C3"]),
        ("Bb2", ["Bb2","D3","F3"],  ["Bb2","F3","D4","F4","D4","F3"]),
        ("Bb2", ["Bb2","Eb3","F3"], ["Bb2","F3","Eb4","F4","Eb4","F3"]),
        ("Eb2", ["Eb3","G3","Bb3"], ["Eb3","Bb3","G4","Bb4","G4","Bb3"]),
        ("C2",  ["C3","Eb3","G3"],  ["C3","G3","Eb4","G4","Eb4","G3"]),
        ("Ab2", ["Ab2","C3","Eb3"], ["Ab2","Eb3","C4","Eb4","C4","Eb3"]),
        ("Ab2", ["Ab2","Cb3","Eb3"], ["Ab2","Eb3","Cb4","Eb4","Cb4","Eb3"]), // Ab단조 그림자
        ("Eb2", ["Eb3","G3","Bb3"], ["Eb3","Bb3","G4","Bb4","G4","Bb3"]),
        ("G2",  ["G2","Bb2","D3"],  ["G2","D3","Bb3","D4","Bb3","D3"]),
        ("C2",  ["C3","Eb3","G3"],  ["C3","G3","Eb4","G4","Eb4","G3"]),
        ("Ab2", ["Ab2","C3","Eb3"], ["Ab2","Eb3","C4","Eb4","C4","Eb3"]),
        ("Bb2", ["Bb2","D3","F3"],  ["Bb2","F3","D4","F4","D4","F3"]),
        ("Bb2", ["Bb2","D3","Ab3"], ["Bb2","F3","D4","Ab4","D4","F3"]),     // Bb7 → 처음으로 되돌아간다
    ]
    for (k, c) in prog.enumerated() {
        let bar = 1 + Double(k)
        t.add(c.0, bar, 1, 3, 0.4, .bass)                     // 왈츠의 '하나'
        t.chord(c.1, bar, 1, 3, 0.26, .pad)
        for (i, nm) in c.2.enumerated() { t.add(nm, bar, 1 + Double(i) * 0.5, 0.7, 0.3 - 0.03 * Double(i % 2), .pluck) }   // 하프
        t.chord(Array(c.1.dropFirst()), bar, 2, 0.8, 0.14, .piano)   // '둘'·'셋' 가벼운 피아노
        t.chord(Array(c.1.dropFirst()), bar, 3, 0.8, 0.12, .piano)
    }
    // 선율 (피아노, 길게 흐르는 음)
    let mel: [(String, Double, Double, Double)] = [
        ("Bb4",1,1,3),("G4",2,1,2),("Ab4",2,3,1),("Eb5",3,1,3),("D5",4,1,2),("Bb4",4,3,1),
        ("G4",5,1,3),("Bb4",6,1,1.5),("D5",6,2.5,1.5),("C5",7,1,3),("Bb4",8,1,2),("F4",8,3,1),
        ("Eb5",9,1,3),("Gb5",10,1,2),("Eb5",10,3,1),("C5",11,1,3),("Ab4",12,1,2),("C5",12,3,1),
        ("Bb4",13,1,3),("Eb5",14,1,2),("F5",14,3,1),("G5",15,1,3),("Eb5",16,1,2),("C5",16,3,1),
        ("Ab4",17,1,3),("Cb5",18,1,2),("Ab4",18,3,1),("Bb4",19,1,3),("D5",20,1,2),("Bb4",20,3,1),
        ("Eb5",21,1,2),("C5",21,3,1),("Ab4",22,1,3),("F4",23,1,2),("Ab4",23,3,1),("D5",24,1,3),
    ]
    for (nm, bar, beat, len) in mel { t.add(nm, bar, beat, len, 0.5, .piano) }
    // 멀리서 반짝이는 종 (물 방울)
    let bells: [(String, Double, Double)] = [("Bb5",3,3),("G5",7,2),("Eb6",11,3),("Bb5",15,2),("Gb5",18,3),("Eb6",23,2)]
    for (nm, bar, beat) in bells { t.add(nm, bar, beat, 2, 0.22, .bell) }
    t.add("Eb1", 1, 1, 72, 0.18, .drone)
    bounce(t, "ambient_sap_lake", loopBeats: 72, mix: 0.42, size: 1.5)
}
// 수액의 여왕 보스: 비극적인 어두운 왈츠. 휘몰아치는 현악, 하프 분산화음, 다급한 피아노, 애절한 바이올린 선율. C단조, 138bpm, 32마디 반복 (41.7초).
// 보스 코드는 이 곡의 박자(한 박 0.4348초, 한 마디 3박)에 맞춰 '하나·둘·셋'으로 공격한다 (scripts/bosses/sap_queen.gd BEAT).
do {
    let t = Track(bpm: 138, beatsPerBar: 3)
    let prog: [(String, [String])] = [
        ("C2", ["C3","Eb3","G3"]), ("C2", ["C3","Eb3","G3"]), ("Ab1", ["Ab2","C3","Eb3"]), ("Ab1", ["Ab2","C3","Eb3"]),
        ("F2", ["F2","Ab2","C3"]), ("F2", ["F2","Ab2","C3"]), ("G1", ["G2","B2","D3"]), ("G1", ["G2","B2","D3"]),
        ("C2", ["C3","Eb3","G3"]), ("Eb2", ["Eb3","G3","Bb3"]), ("Ab1", ["Ab2","C3","Eb3"]), ("Bb1", ["Bb2","D3","F3"]),
        ("C2", ["C3","Eb3","G3"]), ("F2", ["F2","Ab2","C3"]), ("G1", ["G2","B2","D3"]), ("G1", ["G2","B2","D3","F3"]),
    ]
    for rep in 0..<2 {
        for (k, c) in prog.enumerated() {
            let bar = 1 + Double(rep * 16 + k)
            let b0 = (bar - 1) * 3
            t.add(c.0, bar, 1, 1.2, 0.75, .bass)                    // 하나
            t.midiNote(36, b0, 0.4, 0.95, .kick)                     // 하나: 북
            t.midiNote(38, b0 + 1, 0.3, 0.45, .snare)                // 둘
            t.midiNote(38, b0 + 2, 0.3, 0.5, .snare)                 // 셋
            t.chord(c.1, bar, 1, 3, 0.36 + 0.08 * Double(rep), .strings)   // 휘몰아치는 현악 화음
            // 다급한 피아노: 둘·셋에 옥타브 화음을 찍는다
            for beat in [2.0, 3.0] { for nm in c.1 { t.midiNote(n(nm) + 12, b0 + beat - 1, 0.45, 0.42, .piano) } }
            // 하프 분산화음 (8분음표 여섯): 오르내림
            let arp = [n(c.1[0]) + 12, n(c.1[1]) + 12, n(c.1[2]) + 12, n(c.1[0]) + 24, n(c.1[2]) + 12, n(c.1[1]) + 12]
            for (i, m) in arp.enumerated() { t.midiNote(m, b0 + Double(i) * 0.5, 0.5, 0.33, .pluck) }
            if rep == 1 { t.midiNote(n(c.0) + 12, b0 + 1.5, 0.4, 0.4, .bass); t.midiNote(n(c.0) + 19, b0 + 2.5, 0.4, 0.35, .bass) }
        }
    }
    // 애절한 바이올린 선율 (16마디 × 2, 두 번째는 한 옥타브 위)
    let mel: [(String, Double, Double, Double)] = [
        ("G5",1,1,3),("Eb5",2,1,2),("D5",2,3,1),("C5",3,1,3),("Eb5",4,1,1),("D5",4,2,1),("C5",4,3,1),
        ("Ab4",5,1,3),("C5",6,1,2),("Eb5",6,3,1),("D5",7,1,3),("B4",8,1,2),("D5",8,3,1),
        ("G5",9,1,2),("F5",9,3,1),("Eb5",10,1,3),("C6",11,1,2),("Bb5",11,3,1),("Ab5",12,1,2),("F5",12,3,1),
        ("G5",13,1,3),("Ab5",14,1,1),("G5",14,2,1),("F5",14,3,1),("D5",15,1,3),("B4",16,1,1.5),("D5",16,2.5,1.5),
    ]
    for (nm, bar, beat, len) in mel {
        t.add(nm, bar, beat, len, 0.85, .strings)
        t.midiNote(n(nm) + 12, (bar + 16 - 1) * 3 + beat - 1, len, 0.9, .strings)
        t.midiNote(n(nm), (bar + 16 - 1) * 3 + beat - 1, len, 0.5, .piano)
    }
    bounce(t, "boss_sap_queen", loopBeats: 96, tailSec: 2.5, mix: 0.28, size: 1.1)
}
=======
// 확장판 · 잠긴 채굴장. EXPANSION.md 10장의 Suno 프롬프트를 흉내 낸 임시곡.
// 기획자의 진짜 곡(field_flooded_mine.mp3 / boss_iron_pump.mp3)이 오면 같은 이름의 wav 로 바꿔 끼운다.
// =====================================================================
// 잠긴 채굴장 필드: 어두운 앰비언트, 느린 기계 오스티나토(8분음표 베이스 맥동), 물방울(종), 낮은 피아노, 멀리서 금속이 끙끙대는 소리(현악 불협). C단조 70bpm, 16마디 반복 (54.9초).
do {
    let t = Track(bpm: 70)
    t.add("C1", 1, 1, 64, 0.45, .drone)
    let roots = ["C2","C2","Ab1","Ab1","C2","C2","G1","G1","C2","C2","F1","F1","Ab1","Ab1","G1","G1"]
    for bar in 1...16 {
        let r = n(roots[bar - 1])
        let base = Double(bar - 1) * 4
        // 기계 오스티나토: 8분음표로 뿌리음·5도를 번갈아 (물에 잠긴 듯 낮고 둔하게)
        for e in 0..<8 {
            let m = (e % 4 == 2) ? r + 7 : ((e % 4 == 3) ? r + 3 : r)
            t.midiNote(m, base + Double(e) * 0.5, 0.42, e % 2 == 0 ? 0.5 : 0.32, .bass)
        }
        // 느린 피스톤 (북): 매 마디 첫 박과 셋째 박 뒤
        t.midiNote(36, base, 0.5, 0.55, .kick)
        t.midiNote(36, base + 2.5, 0.5, 0.35, .kick)
        if bar % 4 == 0 { t.midiNote(38, base + 3.5, 0.3, 0.25, .snare) }
    }
    // 물방울: 높은 종이 불규칙하게
    let drips: [(String, Double, Double)] = [("G5",1,2.5),("C6",2,4),("Eb5",4,1.5),("G5",5,3),("Bb5",7,2),("C6",8,3.5),("F5",10,1),("Ab5",11,4),("G5",13,2.5),("Eb6",14,3),("D5",15,1.5),("G5",16,4)]
    for (nm, bar, beat) in drips { t.add(nm, bar, beat, 1.5, 0.22, .bell) }
    // 낮은 피아노 (절정 없이 맴도는 두 음)
    let low: [(String, Double, Double, Double)] = [("Eb3",1,1,4),("D3",3,1,4),("C3",5,1,6),("Ab2",9,1,4),("G2",11,1,4),("Bb2",13,1,4),("G2",15,1,4)]
    for (nm, bar, beat, len) in low { t.add(nm, bar, beat, len, 0.3, .piano) }
    // 금속이 끙끙대는 소리: 단2도로 겹친 현악이 길게
    t.chord(["C3","Db3"], 3, 1, 6, 0.1, .strings); t.chord(["G2","Ab2"], 9, 1, 6, 0.1, .strings); t.chord(["C3","B2"], 14, 1, 6, 0.12, .strings)
    bounce(t, "ambient_flooded_mine", loopBeats: 64, mix: 0.4, size: 1.6)
}
// 무쇠 펌프 보스: 산업적이고 비극적인 보스곡. 쉼 없는 기계 오스티나토(16분음표), 매 박 두드리는 낮은 북, 모루(높은 종+스네어), 무거운 금관(낮은 현악 화음),
// 비명 같은 높은 현악 선율, 피아노. C단조 128bpm, 32마디 반복(60초). 뒤 8마디는 리듬이 조금씩 무너진다(엇박 건너뛰기).
// 보스 코드는 이 곡의 박(0.46875초)에 맞춰 2박 예고로 공격한다 (scripts/bosses/iron_pump.gd BEAT).
// boss_iron_pump_2: 2페이즈(규칙이 무너짐)용 — 같은 곡을 처음부터 끝까지 '무너지는 리듬'으로: 16분음표가 빠지고 밀리며, 북은 엇박으로 끌려가고,
//  모루는 박을 놓친다 (scripts/bosses/iron_pump_room.gd 가 페이즈 2 에서 바꿔 튼다).
func ironPump(_ name: String, broken: Bool) {
    let t = Track(bpm: 128)
    let roots = ["C2","C2","C2","C2","Ab1","Ab1","G1","G1","C2","C2","Eb2","Eb2","F2","F2","G1","G1",
                 "C2","C2","C2","C2","Ab1","Ab1","Bb1","Bb1","C2","C2","Db2","Db2","G1","G1","G1","G1"]
    for bar in 1...32 {
        let r = n(roots[bar - 1])
        let base = Double(bar - 1) * 4
        let breaking = broken || bar > 24
        for e in 0..<16 {
            // 뒤 8마디: 16분음표 몇 개를 건너뛰고 몇 개는 밀린다 (무너지는 리듬)
            if breaking && (e * 7 + bar) % 11 == 0 { continue }
            let shift = breaking && (e * 5 + bar) % 9 == 0 ? 0.12 : 0.0
            let m = (e % 4 == 0) ? r : ((e % 4 == 2) ? r + 12 : ((e % 8 == 5) ? r + 7 : r + (e % 2 == 0 ? 0 : 3)))
            t.midiNote(m, base + Double(e) * 0.25 + shift, 0.22, e % 4 == 0 ? 0.62 : 0.4, .bass)
        }
        for b in 0..<4 {
            if breaking && (b + bar) % 7 == 0 { continue }
            // 무너진 판: 셋째 박 북이 반 박 늦게 끌려온다
            let late = broken && b == 2 && bar % 2 == 0 ? 0.5 : 0.0
            t.midiNote(36, base + Double(b) + late, 0.4, b == 0 ? 1.0 : 0.75, .kick)
        }
        // 모루: 둘째·넷째 박 (스네어 + 금속 종). 무너진 판은 넷째 박을 가끔 놓치고 엇박(3.5)에 친다
        t.midiNote(38, base + 1, 0.3, 0.6, .snare)
        let anvil = broken && bar % 3 == 0 ? 3.5 : 3.0
        t.midiNote(38, base + anvil, 0.3, 0.65, .snare)
        t.midiNote(n("G6"), base + 1, 0.2, 0.22, .bell); t.midiNote(n(broken ? "F#6" : "G6"), base + anvil, 0.2, 0.25, .bell)
        // 무거운 금관 (낮은 현악 화음, 두 마디마다)
        if bar % 2 == 1 { t.midiNote(r, base, 8.0, 0.45, .strings); t.midiNote(r + 12, base, 8.0, 0.4, .strings) }
        t.midiNote(r + 12 + 3, base, 8.0, 0.3, .strings); t.midiNote(r + 12 + 7, base, 8.0, 0.28, .strings)
    }
    // 비명 같은 높은 현악 선율 (8마디 두 번 + 변주 두 번)
    let mel: [(String, Double, Double, Double)] = [
        ("G6",1,1,3),("Ab6",1,4,1),("G6",2,1,2),("Eb6",2,3,2),("C6",3,1,3),("D6",3,4,1),("Eb6",4,1,4),
        ("F6",5,1,2),("Eb6",5,3,1),("D6",5,4,1),("C6",6,1,3),("B5",6,4,1),("D6",7,1,2),("G6",7,3,2),("G6",8,1,4),
        ("C7",9,1,3),("Bb6",9,4,1),("Ab6",10,1,2),("G6",10,3,2),("Eb6",11,1,3),("F6",11,4,1),("G6",12,1,4),
        ("Ab6",13,1,2),("G6",13,3,1),("F6",13,4,1),("Eb6",14,1,3),("D6",14,4,1),("B5",15,1,2),("D6",15,3,2),("G6",16,1,4),
    ]
    for (nm, bar, beat, len) in mel {
        t.add(nm, bar, beat, len, 0.9, .strings)
        t.add(nm, bar + 16, beat, len, 0.95, .strings)
        t.midiNote(n(nm) - 12, (bar - 1) * 4 + beat - 1, len, 0.45, .piano)
        t.midiNote(n(nm) - 12, (bar + 15) * 4 + beat - 1, len, 0.5, .piano)
    }
    bounce(t, name, loopBeats: 128, tailSec: 2.5, mix: 0.22, size: 0.9)
}
ironPump("boss_iron_pump", broken: false)
ironPump("boss_iron_pump_2", broken: true)
print("음악 생성 완료")
