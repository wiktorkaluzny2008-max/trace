//
//  BodyMapShapes.swift
//  RecoverySignal2
//
//  Front and back anatomy as SVG path data on a 120 x 250 grid. Only the left
//  half (x ≤ 60) is stored; the view mirrors it for the right side.
//  Regions with no muscle (head, hands, knees, feet) draw in a neutral tone.
//

import Foundation

struct BodyRegion {
    let muscle: Muscle?
    let path: String
}

enum BodyMapShapes {
    static let width: Double = 120
    static let height: Double = 244

    static let front: [BodyRegion] = [
        BodyRegion(muscle: nil, path: "M60 4 C53 4 49 10 49 17 C49 25 54 30 60 30 Z"),
        BodyRegion(muscle: nil, path: "M55 29 L60 29 L60 38 L54 38 Z"),
        BodyRegion(muscle: nil, path: "M30 136 C26 138 25 144 27 150 C29 153 33 152 34 147 L33 136 Z"),
        BodyRegion(muscle: nil, path: "M42 181 C41 186 43 191 47 192 C51 191 52 186 51 181 Z"),
        BodyRegion(muscle: nil, path: "M43 233 C40 235 40 239 44 240 L52 240 C53 237 52 234 50 233 Z"),
        BodyRegion(muscle: .traps, path: "M54 32 C51 36 46 38 41 40 L56 41 L56 34 Z"),
        BodyRegion(muscle: .sideDelts, path: "M36 40 C29 41 24 47 24 55 C24 59 25 62 27 64 C27 56 29 48 37 41 Z"),
        BodyRegion(muscle: .frontDelts, path: "M38 41 C32 45 29 53 29 63 C33 58 38 53 45 49 L44 42 Z"),
        BodyRegion(muscle: .chest, path: "M45 43 L60 43 L60 65 C52 69 43 67 36 60 C37 53 40 48 45 43 Z"),
        BodyRegion(muscle: .biceps, path: "M28 66 C25 74 25 85 28 95 L36 95 C38 85 38 73 35 62 Z"),
        BodyRegion(muscle: .forearms, path: "M28 97 C25 108 25 122 27 134 L33 134 C36 122 37 108 36 97 Z"),
        BodyRegion(muscle: .abs, path: "M53 69 L60 69 L60 122 L54 122 C52 106 52 86 53 69 Z"),
        BodyRegion(muscle: .obliques, path: "M39 64 C44 68 49 70 52 72 C51 88 51 106 53 122 C47 122 42 119 40 112 C37 96 37 78 39 64 Z"),
        BodyRegion(muscle: .quads, path: "M40 116 C44 122 49 124 54 126 C52 146 52 164 51 180 L42 180 C37 164 35 138 40 116 Z"),
        BodyRegion(muscle: .adductors, path: "M55 127 L60 124 L60 132 C60 146 58 160 55 172 L52 172 C52 156 53 140 55 127 Z"),
        BodyRegion(muscle: .calves, path: "M42 194 C40 206 41 220 44 232 L50 232 C52 220 52 205 50 194 Z"),
    ]

    static let back: [BodyRegion] = [
        BodyRegion(muscle: nil, path: "M60 4 C53 4 49 10 49 17 C49 25 54 30 60 30 Z"),
        BodyRegion(muscle: nil, path: "M55 29 L60 29 L60 34 L54 34 Z"),
        BodyRegion(muscle: nil, path: "M30 136 C26 138 25 144 27 150 C29 153 33 152 34 147 L33 136 Z"),
        BodyRegion(muscle: nil, path: "M42 181 C41 186 43 191 47 192 C51 191 52 186 51 181 Z"),
        BodyRegion(muscle: nil, path: "M43 229 C40 233 40 239 44 240 L52 240 C53 236 52 232 50 229 Z"),
        BodyRegion(muscle: .traps, path: "M54 31 C51 36 45 39 38 41 C46 45 53 53 60 63 L60 31 Z"),
        BodyRegion(muscle: .sideDelts, path: "M35 40 C28 41 24 47 24 55 C24 59 25 62 27 64 C26 56 28 48 36 41 Z"),
        BodyRegion(muscle: .rearDelts, path: "M38 42 C32 44 28 50 27 58 C31 53 36 49 43 47 Z"),
        BodyRegion(muscle: .upperBack, path: "M39 48 C44 46 50 52 57 62 C55 68 52 72 49 73 C43 68 39 60 38 52 Z"),
        BodyRegion(muscle: .lats, path: "M37 56 C40 66 45 72 51 75 C50 87 50 99 52 112 C46 108 41 100 39 90 C36 78 35 66 37 56 Z"),
        BodyRegion(muscle: .lowerBack, path: "M53 76 L60 68 L60 118 L54 118 C52 104 52 90 53 76 Z"),
        BodyRegion(muscle: .triceps, path: "M28 66 C25 74 25 85 28 95 L36 95 C38 85 38 73 35 61 Z"),
        BodyRegion(muscle: .forearms, path: "M28 97 C25 108 25 122 27 134 L33 134 C36 122 37 108 36 97 Z"),
        BodyRegion(muscle: .glutes, path: "M41 119 C48 117 55 119 60 123 L60 141 C52 147 44 146 39 139 C38 131 39 125 41 119 Z"),
        BodyRegion(muscle: .hamstrings, path: "M40 145 C46 148 53 148 57 147 C56 159 54 170 51 180 L42 180 C38 168 38 157 40 145 Z"),
        BodyRegion(muscle: .calves, path: "M41 192 C37 202 38 216 42 228 L51 228 C54 216 54 202 50 192 Z"),
    ]
}
