//
//  ReelMorph.swift
//  SilverScreen
//
//  How the icon artwork turns into the 3D film and back. The icon's strip was traced into
//  cuts across the film; each cut knows where it sits on the spiral, so a loop can carry
//  every piece of the real artwork from its place in the icon onto the moving film (and
//  back) while its pixels blend into the 3D film's.
//

import CoreGraphics

/// A line across the icon's film strip, traced from IconReel.png in the artwork's pixels,
/// and where that cut sits on the 3D film.
struct ReelMorphCut: Sendable {
    /// The cut's ends in the icon, on the strip's left-hand edge walking from its left end
    /// (bottom left of the icon) to its right end (top right), and its right-hand edge.
    var left: CGPoint
    var right: CGPoint
    /// The cut's angle on `ReelHelix.icon`'s spiral.
    var angle: Double
    /// True where the trace's left edge is the 3D film's right edge.
    var swapped: Bool
}

/// The traced icon strip, from its left end to its right end.
enum ReelMorph {
    static let cuts: [ReelMorphCut] = [
        ReelMorphCut(left: CGPoint(x: 88.60, y: 497.50), right: CGPoint(x: 258.00, y: 427.00), angle: -1.71648, swapped: false),
        ReelMorphCut(left: CGPoint(x: 77.76, y: 472.17), right: CGPoint(x: 253.27, y: 414.18), angle: -1.65399, swapped: false),
        ReelMorphCut(left: CGPoint(x: 66.91, y: 446.84), right: CGPoint(x: 248.53, y: 401.35), angle: -1.58826, swapped: false),
        ReelMorphCut(left: CGPoint(x: 56.07, y: 421.51), right: CGPoint(x: 243.80, y: 388.53), angle: -1.52146, swapped: false),
        ReelMorphCut(left: CGPoint(x: 50.10, y: 407.53), right: CGPoint(x: 237.84, y: 375.98), angle: -1.47405, swapped: false),
        ReelMorphCut(left: CGPoint(x: 44.13, y: 393.56), right: CGPoint(x: 231.88, y: 363.43), angle: -1.42772, swapped: false),
        ReelMorphCut(left: CGPoint(x: 38.66, y: 379.20), right: CGPoint(x: 225.89, y: 350.95), angle: -1.37924, swapped: false),
        ReelMorphCut(left: CGPoint(x: 33.19, y: 364.83), right: CGPoint(x: 219.89, y: 338.48), angle: -1.33075, swapped: false),
        ReelMorphCut(left: CGPoint(x: 27.63, y: 350.58), right: CGPoint(x: 213.91, y: 325.19), angle: -1.28119, swapped: false),
        ReelMorphCut(left: CGPoint(x: 22.07, y: 336.32), right: CGPoint(x: 207.94, y: 311.91), angle: -1.23054, swapped: false),
        ReelMorphCut(left: CGPoint(x: 17.69, y: 321.77), right: CGPoint(x: 202.36, y: 298.71), angle: -1.17990, swapped: false),
        ReelMorphCut(left: CGPoint(x: 13.32, y: 307.21), right: CGPoint(x: 196.78, y: 285.52), angle: -1.12819, swapped: false),
        ReelMorphCut(left: CGPoint(x: 10.29, y: 293.19), right: CGPoint(x: 191.35, y: 271.89), angle: -1.07539, swapped: false),
        ReelMorphCut(left: CGPoint(x: 7.26, y: 279.16), right: CGPoint(x: 185.93, y: 258.27), angle: -1.02259, swapped: false),
        ReelMorphCut(left: CGPoint(x: 5.75, y: 265.54), right: CGPoint(x: 180.90, y: 244.22), angle: -0.96872, swapped: false),
        ReelMorphCut(left: CGPoint(x: 4.24, y: 251.93), right: CGPoint(x: 175.87, y: 230.18), angle: -0.91269, swapped: false),
        ReelMorphCut(left: CGPoint(x: 4.19, y: 239.67), right: CGPoint(x: 171.89, y: 216.73), angle: -0.86097, swapped: false),
        ReelMorphCut(left: CGPoint(x: 4.13, y: 227.40), right: CGPoint(x: 167.91, y: 203.27), angle: -0.80602, swapped: false),
        ReelMorphCut(left: CGPoint(x: 6.68, y: 215.91), right: CGPoint(x: 183.54, y: 189.42), angle: -0.76077, swapped: false),
        ReelMorphCut(left: CGPoint(x: 9.22, y: 204.42), right: CGPoint(x: 186.00, y: 207.00), angle: -0.75468, swapped: false),
        ReelMorphCut(left: CGPoint(x: 16.93, y: 186.05), right: CGPoint(x: 185.87, y: 207.07), angle: -0.64663, swapped: false),
        ReelMorphCut(left: CGPoint(x: 31.94, y: 170.63), right: CGPoint(x: 185.73, y: 207.13), angle: -0.52335, swapped: false),
        ReelMorphCut(left: CGPoint(x: 43.93, y: 156.67), right: CGPoint(x: 185.60, y: 207.20), angle: -0.41793, swapped: false),
        ReelMorphCut(left: CGPoint(x: 53.02, y: 142.88), right: CGPoint(x: 185.47, y: 207.27), angle: -0.32336, swapped: false),
        ReelMorphCut(left: CGPoint(x: 64.24, y: 130.99), right: CGPoint(x: 185.34, y: 207.33), angle: -0.22970, swapped: false),
        ReelMorphCut(left: CGPoint(x: 74.48, y: 119.19), right: CGPoint(x: 185.20, y: 207.40), angle: -0.14020, swapped: false),
        ReelMorphCut(left: CGPoint(x: 84.78, y: 107.65), right: CGPoint(x: 185.07, y: 207.47), angle: -0.05157, swapped: false),
        ReelMorphCut(left: CGPoint(x: 95.96, y: 96.91), right: CGPoint(x: 184.94, y: 207.53), angle: 0.03726, swapped: false),
        ReelMorphCut(left: CGPoint(x: 106.41, y: 84.47), right: CGPoint(x: 184.80, y: 207.60), angle: 0.13030, swapped: true),
        ReelMorphCut(left: CGPoint(x: 118.53, y: 73.03), right: CGPoint(x: 184.67, y: 207.67), angle: 0.22578, swapped: true),
        ReelMorphCut(left: CGPoint(x: 131.89, y: 61.88), right: CGPoint(x: 184.54, y: 207.74), angle: 0.32548, swapped: true),
        ReelMorphCut(left: CGPoint(x: 145.84, y: 47.71), right: CGPoint(x: 184.40, y: 207.80), angle: 0.43934, swapped: true),
        ReelMorphCut(left: CGPoint(x: 162.53, y: 36.95), right: CGPoint(x: 184.27, y: 207.87), angle: 0.55312, swapped: true),
        ReelMorphCut(left: CGPoint(x: 181.21, y: 32.10), right: CGPoint(x: 184.14, y: 207.94), angle: 0.66365, swapped: true),
        ReelMorphCut(left: CGPoint(x: 198.36, y: 30.58), right: CGPoint(x: 195.93, y: 214.85), angle: 0.72614, swapped: true),
        ReelMorphCut(left: CGPoint(x: 215.51, y: 29.05), right: CGPoint(x: 207.72, y: 221.76), angle: 0.78540, swapped: true),
        ReelMorphCut(left: CGPoint(x: 232.32, y: 31.65), right: CGPoint(x: 219.05, y: 228.86), angle: 0.84251, swapped: true),
        ReelMorphCut(left: CGPoint(x: 249.14, y: 34.25), right: CGPoint(x: 230.38, y: 235.97), angle: 0.89746, swapped: true),
        ReelMorphCut(left: CGPoint(x: 265.28, y: 39.71), right: CGPoint(x: 241.49, y: 244.42), angle: 0.95241, swapped: true),
        ReelMorphCut(left: CGPoint(x: 281.41, y: 45.16), right: CGPoint(x: 252.61, y: 252.87), angle: 1.00520, swapped: true),
        ReelMorphCut(left: CGPoint(x: 296.87, y: 51.72), right: CGPoint(x: 263.60, y: 261.38), angle: 1.05584, swapped: true),
        ReelMorphCut(left: CGPoint(x: 312.32, y: 58.27), right: CGPoint(x: 274.60, y: 269.89), angle: 1.10649, swapped: true),
        ReelMorphCut(left: CGPoint(x: 327.03, y: 66.71), right: CGPoint(x: 285.43, y: 278.40), angle: 1.15497, swapped: true),
        ReelMorphCut(left: CGPoint(x: 341.74, y: 75.14), right: CGPoint(x: 296.27, y: 286.90), angle: 1.20346, swapped: true),
        ReelMorphCut(left: CGPoint(x: 356.03, y: 84.18), right: CGPoint(x: 306.90, y: 295.64), angle: 1.25087, swapped: true),
        ReelMorphCut(left: CGPoint(x: 370.32, y: 93.21), right: CGPoint(x: 317.52, y: 304.37), angle: 1.29720, swapped: true),
        ReelMorphCut(left: CGPoint(x: 383.94, y: 103.73), right: CGPoint(x: 328.39, y: 313.07), angle: 1.34461, swapped: true),
        ReelMorphCut(left: CGPoint(x: 397.56, y: 114.24), right: CGPoint(x: 339.26, y: 321.78), angle: 1.39094, swapped: true),
        ReelMorphCut(left: CGPoint(x: 411.05, y: 124.74), right: CGPoint(x: 350.05, y: 330.75), angle: 1.43727, swapped: true),
        ReelMorphCut(left: CGPoint(x: 424.54, y: 135.24), right: CGPoint(x: 360.84, y: 339.72), angle: 1.48360, swapped: true),
        ReelMorphCut(left: CGPoint(x: 438.04, y: 145.29), right: CGPoint(x: 371.78, y: 348.24), angle: 1.52885, swapped: true),
        ReelMorphCut(left: CGPoint(x: 451.54, y: 155.34), right: CGPoint(x: 382.72, y: 356.75), angle: 1.57411, swapped: true),
        ReelMorphCut(left: CGPoint(x: 464.59, y: 166.55), right: CGPoint(x: 393.70, y: 365.30), angle: 1.61936, swapped: true),
        ReelMorphCut(left: CGPoint(x: 477.64, y: 177.77), right: CGPoint(x: 404.68, y: 373.85), angle: 1.66569, swapped: true),
        ReelMorphCut(left: CGPoint(x: 491.09, y: 188.03), right: CGPoint(x: 416.11, y: 381.81), angle: 1.71202, swapped: true),
        ReelMorphCut(left: CGPoint(x: 504.53, y: 198.29), right: CGPoint(x: 427.53, y: 389.76), angle: 1.75835, swapped: true),
        ReelMorphCut(left: CGPoint(x: 518.16, y: 208.35), right: CGPoint(x: 439.01, y: 397.77), angle: 1.80576, swapped: true),
        ReelMorphCut(left: CGPoint(x: 531.79, y: 218.42), right: CGPoint(x: 450.50, y: 405.78), angle: 1.85317, swapped: true),
        ReelMorphCut(left: CGPoint(x: 545.38, y: 228.85), right: CGPoint(x: 462.33, y: 413.19), angle: 1.90273, swapped: true),
        ReelMorphCut(left: CGPoint(x: 558.96, y: 239.28), right: CGPoint(x: 474.16, y: 420.60), angle: 1.95230, swapped: true),
        ReelMorphCut(left: CGPoint(x: 573.08, y: 248.82), right: CGPoint(x: 486.46, y: 427.18), angle: 2.00294, swapped: true),
        ReelMorphCut(left: CGPoint(x: 587.21, y: 258.36), right: CGPoint(x: 498.75, y: 433.76), angle: 2.05466, swapped: true),
        ReelMorphCut(left: CGPoint(x: 602.02, y: 266.84), right: CGPoint(x: 511.43, y: 439.57), angle: 2.10853, swapped: true),
        ReelMorphCut(left: CGPoint(x: 616.84, y: 275.32), right: CGPoint(x: 524.10, y: 445.39), angle: 2.16348, swapped: true),
        ReelMorphCut(left: CGPoint(x: 632.19, y: 282.88), right: CGPoint(x: 537.36, y: 449.97), angle: 2.22167, swapped: true),
        ReelMorphCut(left: CGPoint(x: 647.55, y: 290.44), right: CGPoint(x: 550.63, y: 454.55), angle: 2.28200, swapped: true),
        ReelMorphCut(left: CGPoint(x: 644.93, y: 291.77), right: CGPoint(x: 576.48, y: 462.94), angle: 2.39857, swapped: true),
        ReelMorphCut(left: CGPoint(x: 642.31, y: 293.10), right: CGPoint(x: 603.31, y: 465.23), angle: 2.51401, swapped: true),
        ReelMorphCut(left: CGPoint(x: 639.69, y: 294.43), right: CGPoint(x: 629.54, y: 465.25), angle: 2.62647, swapped: true),
        ReelMorphCut(left: CGPoint(x: 637.07, y: 295.76), right: CGPoint(x: 654.50, y: 457.23), angle: 2.73889, swapped: true),
        ReelMorphCut(left: CGPoint(x: 634.45, y: 297.09), right: CGPoint(x: 676.04, y: 442.78), angle: 2.85015, swapped: true),
        ReelMorphCut(left: CGPoint(x: 631.83, y: 298.42), right: CGPoint(x: 693.53, y: 425.22), angle: 2.95638, swapped: true),
        ReelMorphCut(left: CGPoint(x: 629.21, y: 299.75), right: CGPoint(x: 709.44, y: 409.57), angle: 3.05208, swapped: true),
        ReelMorphCut(left: CGPoint(x: 626.60, y: 301.08), right: CGPoint(x: 724.23, y: 394.24), angle: 3.14341, swapped: false),
        ReelMorphCut(left: CGPoint(x: 623.98, y: 302.41), right: CGPoint(x: 738.66, y: 378.78), angle: 3.23410, swapped: false),
        ReelMorphCut(left: CGPoint(x: 621.36, y: 303.73), right: CGPoint(x: 752.81, y: 362.25), angle: 3.32741, swapped: false),
        ReelMorphCut(left: CGPoint(x: 618.74, y: 305.06), right: CGPoint(x: 768.21, y: 344.42), angle: 3.42844, swapped: false),
        ReelMorphCut(left: CGPoint(x: 616.12, y: 306.39), right: CGPoint(x: 784.36, y: 323.79), angle: 3.54079, swapped: false),
        ReelMorphCut(left: CGPoint(x: 613.50, y: 307.72), right: CGPoint(x: 804.21, y: 299.13), angle: 3.67652, swapped: false),
        ReelMorphCut(left: CGPoint(x: 610.88, y: 309.05), right: CGPoint(x: 813.80, y: 269.81), angle: 3.80878, swapped: false),
        ReelMorphCut(left: CGPoint(x: 627.20, y: 292.68), right: CGPoint(x: 814.34, y: 258.56), angle: 3.86050, swapped: false),
        ReelMorphCut(left: CGPoint(x: 643.53, y: 276.30), right: CGPoint(x: 814.88, y: 247.31), angle: 3.90898, swapped: false),
        ReelMorphCut(left: CGPoint(x: 639.30, y: 262.83), right: CGPoint(x: 813.33, y: 234.98), angle: 3.96178, swapped: false),
        ReelMorphCut(left: CGPoint(x: 635.06, y: 249.36), right: CGPoint(x: 811.78, y: 222.65), angle: 4.01350, swapped: false),
        ReelMorphCut(left: CGPoint(x: 629.59, y: 236.30), right: CGPoint(x: 808.38, y: 209.33), angle: 4.06629, swapped: false),
        ReelMorphCut(left: CGPoint(x: 624.12, y: 223.23), right: CGPoint(x: 804.97, y: 196.01), angle: 4.11801, swapped: false),
        ReelMorphCut(left: CGPoint(x: 618.64, y: 209.79), right: CGPoint(x: 800.86, y: 183.02), angle: 4.16865, swapped: false),
        ReelMorphCut(left: CGPoint(x: 613.17, y: 196.34), right: CGPoint(x: 796.75, y: 170.02), angle: 4.21821, swapped: false),
        ReelMorphCut(left: CGPoint(x: 607.13, y: 182.88), right: CGPoint(x: 791.82, y: 156.23), angle: 4.26886, swapped: false),
        ReelMorphCut(left: CGPoint(x: 601.09, y: 169.42), right: CGPoint(x: 786.90, y: 142.44), angle: 4.31950, swapped: false),
        ReelMorphCut(left: CGPoint(x: 594.61, y: 155.92), right: CGPoint(x: 780.90, y: 128.21), angle: 4.37014, swapped: false),
        ReelMorphCut(left: CGPoint(x: 588.12, y: 142.42), right: CGPoint(x: 774.91, y: 113.99), angle: 4.41970, swapped: false),
        ReelMorphCut(left: CGPoint(x: 581.12, y: 129.27), right: CGPoint(x: 768.33, y: 99.96), angle: 4.46927, swapped: false),
        ReelMorphCut(left: CGPoint(x: 574.13, y: 116.12), right: CGPoint(x: 761.75, y: 85.94), angle: 4.51883, swapped: false),
        ReelMorphCut(left: CGPoint(x: 567.59, y: 103.49), right: CGPoint(x: 755.36, y: 71.88), angle: 4.56624, swapped: false),
        ReelMorphCut(left: CGPoint(x: 561.04, y: 90.87), right: CGPoint(x: 748.97, y: 57.82), angle: 4.61365, swapped: false),
        ReelMorphCut(left: CGPoint(x: 554.00, y: 74.50), right: CGPoint(x: 720.50, y: 0.50), angle: 4.74833, swapped: false),
    ]
}
