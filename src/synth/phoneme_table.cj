package ziyu.synth

import std.collection.ArrayList
import std.collection.HashMap

/* ============================================================================
 * 共振峰参数表与拼音→共振峰推断
 *
 * 共振峰合成（formant synthesis）的核心是把每个音素描述为一组共振峰
 * (F1/F2/F3) 及其带宽，再用级联二阶节 IIR 滤波器对声源激励做谐振
 * 染色。本文件负责"拼音 → 合成段序列"的声学映射：
 *
 *   pinyin → [声母段?] + [韵母段]
 *
 * 韵母共振峰取自汉语语音学文献参考值（成年男性），覆盖全部 59 个韵母
 * （含 y/w 零声母变体）。声母按发音部位/方式细化参数（23 个声母）。
 *
 * 纯仓颉：HashMap 查表 + Rune 比较，零 FFI。
 * ========================================================================== */

/// 共振峰参数集（一个音素段的声学描述）
public struct FormantSet {
    public let f1: Float64 // 第一共振峰频率 Hz
    public let f2: Float64 // 第二共振峰频率 Hz
    public let f3: Float64 // 第三共振峰频率 Hz
    public let b1: Float64 // 第一共振峰带宽 Hz
    public let b2: Float64 // 第二共振峰带宽 Hz
    public let b3: Float64 // 第三共振峰带宽 Hz
    public let voiced: Bool // 是否浊音（需声带激励）
    public let durationMs: Float64 // 该段默认时长 ms
    public init(f1: Float64, f2: Float64, f3: Float64, b1: Float64, b2: Float64, b3: Float64, voiced: Bool,
        durationMs: Float64) {
        this.f1 = f1
        this.f2 = f2
        this.f3 = f3
        this.b1 = b1
        this.b2 = b2
        this.b3 = b3
        this.voiced = voiced
        this.durationMs = durationMs
    }
}

/// 合成段：共振峰参数 + 激励类型（浊音谐波 / 清音噪声）
public struct PhonemeSegment {
    public let formants: FormantSet
    public let isNoise: Bool // true=噪声激励(清音)，false=浊音激励
    public let isConsonant: Bool // true=声母段，false=韵母段
    public init(formants: FormantSet, isNoise: Bool, isConsonant!: Bool = false) {
        this.formants = formants
        this.isNoise = isNoise
        this.isConsonant = isConsonant
    }
}

/// 默认共振峰带宽（Klatt 1980 推荐值，成年男性）
let DEFAULT_B1: Float64 = 60.0
let DEFAULT_B2: Float64 = 80.0
let DEFAULT_B3: Float64 = 100.0
/// 宽带噪声带宽（清音声母用）
let WIDE_B: Float64 = 200.0
/// 元音默认时长
let VOWEL_DURATION_MS: Float64 = 250.0

/// 快捷构造浊音共振峰（默认带宽）
func vf(f1: Float64, f2: Float64, f3: Float64): FormantSet {
    FormantSet(f1, f2, f3, DEFAULT_B1, DEFAULT_B2, DEFAULT_B3, true, VOWEL_DURATION_MS)
}

/// 快捷构造带自定义带宽的浊音共振峰（元音：按男声参考值给带宽）
func vfb(f1: Float64, f2: Float64, f3: Float64, b1: Float64, b2: Float64, b3: Float64): FormantSet {
    FormantSet(f1, f2, f3, b1, b2, b3, true, VOWEL_DURATION_MS)
}

/// 快捷构造清音噪声段（宽带，声母）
func nf(f1: Float64, f2: Float64, f3: Float64, dur: Float64): PhonemeSegment {
    PhonemeSegment(FormantSet(f1, f2, f3, WIDE_B, WIDE_B, WIDE_B, false, dur), true, isConsonant: true)
}

/// 快捷构造浊音段（默认带宽，声母）
func vs(f1: Float64, f2: Float64, f3: Float64, dur: Float64): PhonemeSegment {
    PhonemeSegment(FormantSet(f1, f2, f3, DEFAULT_B1, DEFAULT_B2, DEFAULT_B3, true, dur), false, isConsonant: true)
}

/// 中性浊音（无明确元音时的兜底）
func neutralVoiced(): FormantSet {
    FormantSet(500.0, 1500.0, 2500.0, DEFAULT_B1, DEFAULT_B2, DEFAULT_B3, true, 120.0)
}

/* ============================================================================
 * 韵母共振峰表（59 个韵母，含 y/w 零声母变体）
 *
 * 数据来源（成年男性测量值）：
 *   [1] 吴宗济、林茂灿《实验语音学概要》中国社会科学出版社 1989
 *   [2] Lee & Zee, "Standard Chinese (Beijing)", IPA Handbook 2003
 *   [3] eSpeak NG phsource/ph_cmn — 声母 F2 locus 参考值
 * 复韵母取过渡段稳态中点，鼻韵母考虑鼻音耦合对 F1 的影响。
 * ========================================================================== */
func buildFinalTable(): HashMap<String, FormantSet> {
    let t = HashMap<String, FormantSet>()
    // --- 单韵母 [1][2] ---
    t.add("a", vfb(850.0, 1200.0, 2600.0, 80.0, 100.0, 160.0))
    t.add("o", vfb(500.0, 800.0, 2500.0, 70.0, 90.0, 150.0))
    t.add("e", vfb(500.0, 2100.0, 2700.0, 70.0, 100.0, 160.0))
    t.add("i", vfb(300.0, 2300.0, 3000.0, 60.0, 100.0, 160.0))
    t.add("u", vfb(350.0, 700.0, 2500.0, 60.0, 90.0, 150.0))
    t.add("v", vfb(300.0, 1900.0, 2400.0, 60.0, 100.0, 160.0))
    // --- 复韵母（过渡段稳态中点）---
    t.add("ai", vf(720.0, 1240.0, 2680.0))
    t.add("ei", vf(480.0, 1700.0, 2530.0))
    t.add("ui", vf(350.0, 1200.0, 2400.0))
    t.add("ao", vf(720.0, 1080.0, 2620.0))
    t.add("ou", vf(500.0, 820.0, 2400.0))
    t.add("iu", vf(350.0, 1500.0, 2400.0))
    t.add("ie", vf(400.0, 2000.0, 2530.0))
    t.add("ve", vf(400.0, 1600.0, 2300.0))
    // --- 鼻韵母（鼻音耦合使 F1 略降，F3 保持较高以维持明亮度）---
    t.add("an", vf(800.0, 1480.0, 2800.0))
    t.add("en", vf(510.0, 1700.0, 2600.0))
    t.add("in", vf(330.0, 2100.0, 3000.0))
    t.add("un", vf(370.0, 1400.0, 2400.0))
    t.add("vn", vf(340.0, 1600.0, 2300.0))
    t.add("ang", vf(780.0, 1180.0, 2840.0))
    t.add("eng", vf(560.0, 1500.0, 2600.0))
    t.add("ing", vf(420.0, 1900.0, 2900.0))
    t.add("ong", vf(500.0, 800.0, 2400.0))
    // --- 带介音复韵母 ---
    t.add("ia", vf(600.0, 1200.0, 2800.0))
    t.add("iao", vf(600.0, 1100.0, 2700.0))
    t.add("ian", vf(500.0, 1600.0, 2800.0))
    t.add("iang", vf(700.0, 1200.0, 2800.0))
    t.add("iong", vf(450.0, 900.0, 2400.0))
    t.add("ua", vf(600.0, 1000.0, 2600.0))
    t.add("uo", vf(500.0, 850.0, 2400.0))
    t.add("uai", vf(600.0, 1200.0, 2700.0))
    t.add("uei", vf(400.0, 1500.0, 2500.0))
    t.add("uan", vf(550.0, 1100.0, 2600.0))
    t.add("uang", vf(700.0, 1100.0, 2700.0))
    t.add("ueng", vf(550.0, 1100.0, 2500.0))
    t.add("van", vf(450.0, 1600.0, 2400.0))
    // --- y 变体（零声母，同对应韵母）---
    t.add("yi", vf(290.0, 2360.0, 3570.0))
    t.add("ya", vf(600.0, 1200.0, 2800.0))
    t.add("ye", vf(400.0, 2000.0, 2530.0))
    t.add("yao", vf(600.0, 1100.0, 2700.0))
    t.add("you", vf(350.0, 1500.0, 2400.0))
    t.add("yan", vf(500.0, 1600.0, 2800.0))
    t.add("yin", vf(330.0, 2100.0, 3000.0))
    t.add("yang", vf(700.0, 1200.0, 2800.0))
    t.add("ying", vf(420.0, 1900.0, 2900.0))
    t.add("yong", vf(450.0, 900.0, 2400.0))
    t.add("yu", vf(300.0, 1640.0, 2150.0))
    t.add("yue", vf(400.0, 1600.0, 2300.0))
    t.add("yuan", vf(450.0, 1600.0, 2400.0))
    t.add("yun", vf(340.0, 1600.0, 2300.0))
    // --- w 变体（零声母）---
    t.add("wu", vf(320.0, 770.0, 2240.0))
    t.add("wa", vf(600.0, 1000.0, 2600.0))
    t.add("wo", vf(500.0, 850.0, 2400.0))
    t.add("wai", vf(600.0, 1200.0, 2700.0))
    t.add("wei", vf(400.0, 1500.0, 2500.0))
    t.add("wan", vf(550.0, 1100.0, 2600.0))
    t.add("wen", vf(370.0, 1400.0, 2400.0))
    t.add("wang", vf(700.0, 1100.0, 2700.0))
    t.add("weng", vf(550.0, 1100.0, 2500.0))
    t
}

/// 韵母共振峰表（全局唯一实例）
let FINAL_TABLE: HashMap<String, FormantSet> = buildFinalTable()

/* ============================================================================
 * 声母参数表（23 个声母，按发音部位/方式细化）
 *
 * F2 locus 数据来源：eSpeak NG phsource/ph_cmn Vowelout/Vowelin 参数
 *   唇音(b/p/m/f):     F2 locus ~1000
 *   齿龈音(d/t/n/s/z/c): F2 locus ~1700
 *   软腭音(g/k/h):     F2 locus ~1700
 *   龈颚音(j/q/x):     F2 locus ~2700
 *   龈后音(zh/ch/sh/r): F2 locus ~1800
 * ========================================================================== */
func buildConsonantTable(): HashMap<String, PhonemeSegment> {
    let t = HashMap<String, PhonemeSegment>()
    // --- 浊音声母（声带激励 + 共振峰过渡段）---
    t.add("m", vs(300.0, 1000.0, 2500.0, 50.0)) // 双唇鼻音 F2locus=1000
    t.add("n", vs(300.0, 1700.0, 2500.0, 50.0)) // 齿龈鼻音 F2locus=1700
    t.add("l", vs(360.0, 1700.0, 2500.0, 50.0)) // 齿龈边音 F2locus=1700
    t.add("r", vs(400.0, 1800.0, 2500.0, 50.0)) // 龈后浊擦 F2locus=1800

    // --- 清音声母（噪声激励 + 频率集中区域）---
    t.add("f", nf(500.0, 1000.0, 2500.0, 70.0)) // 唇齿摩擦 F2locus=1000
    t.add("s", nf(500.0, 1700.0, 4000.0, 70.0)) // 齿龈摩擦 F2locus=1700 高频
    t.add("sh", nf(500.0, 1800.0, 3500.0, 80.0)) // 龈后摩擦 F2locus=1800
    t.add("h", nf(500.0, 1700.0, 2500.0, 70.0)) // 软腭摩擦 F2locus=1700 宽带
    t.add("x", nf(400.0, 2700.0, 3500.0, 70.0)) // 龈颚摩擦 F2locus=2700 高频
    t.add("b", nf(500.0, 1000.0, 2500.0, 50.0)) // 双唇爆破 F2locus=1000
    t.add("p", nf(500.0, 1000.0, 2500.0, 60.0)) // 双唇爆破送气
    t.add("d", nf(500.0, 1700.0, 2500.0, 50.0)) // 齿龈爆破 F2locus=1700
    t.add("t", nf(500.0, 1700.0, 2500.0, 60.0)) // 齿龈爆破送气
    t.add("g", nf(500.0, 1700.0, 2500.0, 50.0)) // 软腭爆破 F2locus=1700
    t.add("k", nf(500.0, 1700.0, 2500.0, 60.0)) // 软腭爆破送气
    t.add("z", nf(500.0, 1700.0, 3500.0, 70.0)) // 齿龈塞擦 F2locus=1700
    t.add("c", nf(500.0, 1700.0, 3500.0, 80.0)) // 齿龈塞擦送气
    t.add("zh", nf(500.0, 1800.0, 3500.0, 70.0)) // 龈后塞擦 F2locus=1800
    t.add("ch", nf(500.0, 1800.0, 3500.0, 80.0)) // 龈后塞擦送气
    t
}

/// 声母参数表（全局唯一实例）
let CONSONANT_TABLE: HashMap<String, PhonemeSegment> = buildConsonantTable()

/// 判断字符是否为单字母声母（不含 y/w，不含 zh/ch/sh）
func isInitialRune(r: Rune): Bool {
    r == r'b' || r == r'p' || r == r'm' || r == r'f' || r == r'd' || r == r't' || r == r'n' || r == r'l' || r == r'g' ||
        r == r'k' || r == r'h' || r == r'j' || r == r'q' || r == r'x' || r == r'r' || r == r'z' || r == r'c' || r == r's'
}

/// 拆分复韵母为单韵母序列，实现共振峰过渡
///
/// 单韵母原样返回；复韵母拆成 [起始元音, 结束元音]；
/// 鼻韵母拆成 [起始元音, 鼻化韵母整体]；
/// 带介音复韵母拆成 [介音, 主韵母]。
/// 这样每个段用各自共振峰，听感上有明确的元音过渡，而非模糊中间音。
func splitCompoundFinal(finalStr: String): Array<String> {
    // 复韵母 → [起始, 结束]
    if (finalStr == "ai") {
        ["a", "i"]
    } else if (finalStr == "ei") {
        ["e", "i"]
    } else if (finalStr == "ui") {
        ["u", "i"]
    } else if (finalStr == "ao") {
        ["a", "o"]
    } else if (finalStr == "ou") {
        ["o", "u"]
    } else if (finalStr == "iu") {
        ["i", "u"]
    } else if (finalStr == "ie") {
        ["i", "e"]
    } else if (finalStr == "ve") {
        ["v", "e"]
    }
        // 鼻韵母 → [起始元音, 鼻化韵母]
        else if (finalStr == "an") {
        ["a", "an"]
    } else if (finalStr == "en") {
        ["e", "en"]
    } else if (finalStr == "in") {
        ["i", "in"]
    } else if (finalStr == "un") {
        ["u", "un"]
    } else if (finalStr == "vn") {
        ["v", "vn"]
    } else if (finalStr == "ang") {
        ["a", "ang"]
    } else if (finalStr == "eng") {
        ["e", "eng"]
    } else if (finalStr == "ing") {
        ["i", "ing"]
    } else if (finalStr == "ong") {
        ["o", "ong"]
    }
        // 带介音复韵母 → [介音, 主韵母]
        else if (finalStr == "ia") {
        ["i", "a"]
    } else if (finalStr == "iao") {
        ["i", "ao"]
    } else if (finalStr == "ian") {
        ["i", "an"]
    } else if (finalStr == "iang") {
        ["i", "ang"]
    } else if (finalStr == "iong") {
        ["v", "ong"]
    } else if (finalStr == "ua") {
        ["u", "a"]
    } else if (finalStr == "uo") {
        ["u", "o"]
    } else if (finalStr == "uai") {
        ["u", "ai"]
    } else if (finalStr == "uei") {
        ["u", "ei"]
    } else if (finalStr == "uan") {
        ["u", "an"]
    } else if (finalStr == "uang") {
        ["u", "ang"]
    } else if (finalStr == "ueng") {
        ["u", "eng"]
    } else if (finalStr == "van") {
        ["v", "an"]
    }
        // y 变体（零声母）
        else if (finalStr == "ya") {
        ["i", "a"]
    } else if (finalStr == "ye") {
        ["i", "e"]
    } else if (finalStr == "yao") {
        ["i", "ao"]
    } else if (finalStr == "you") {
        ["i", "ou"]
    } else if (finalStr == "yan") {
        ["i", "an"]
    } else if (finalStr == "yin") {
        ["i", "in"]
    } else if (finalStr == "yang") {
        ["i", "ang"]
    } else if (finalStr == "ying") {
        ["i", "ing"]
    } else if (finalStr == "yong") {
        ["v", "ong"]
    } else if (finalStr == "yue") {
        ["v", "e"]
    } else if (finalStr == "yuan") {
        ["v", "an"]
    } else if (finalStr == "yun") {
        ["v", "un"]
    }
        // w 变体（零声母）
        else if (finalStr == "wa") {
        ["u", "a"]
    } else if (finalStr == "wo") {
        ["u", "o"]
    } else if (finalStr == "wai") {
        ["u", "ai"]
    } else if (finalStr == "wei") {
        ["u", "ei"]
    } else if (finalStr == "wan") {
        ["u", "an"]
    } else if (finalStr == "wen") {
        ["u", "un"]
    } else if (finalStr == "wang") {
        ["u", "ang"]
    } else if (finalStr == "weng") {
        ["u", "eng"]
    }
        // 单韵母和未知韵母原样返回
        else {
        [finalStr]
    }
}

/// 把拼音映射为合成段序列 + 声调：[声母段?] + [韵母段...]
///
/// - param pinyin: 带数字调拼音串（如 "ni3"、"hao3"、"cang1"），末尾 1-5 为声调
/// - returns: (按时序排列的合成段数组, 声调 1-5)
public func pinyinToSegments(pinyin: String): (Array<PhonemeSegment>, Int64) {
    let segments = ArrayList<PhonemeSegment>()
    if (pinyin.size == 0) {
        return (segments.toArray(), 5)
    }
    let runes = pinyin.toRuneArray()
    var n = runes.size
    // 儿化后缀：汉语拼音韵母不以 r 结尾，故末尾 'r' 必为儿化标记，剥离后按原韵母合成
    if (n >= 2 && runes[n - 1] == r'r') {
        n -= 1
    }
    // 解析末尾声调数字（1-5）
    var tone: Int64 = 5
    var bodyEnd = n
    let last = runes[n - 1]
    if (last == r'1' || last == r'2' || last == r'3' || last == r'4' || last == r'5') {
        bodyEnd = n - 1
        if (last == r'1') {
            tone = 1
        } else if (last == r'2') {
            tone = 2
        } else if (last == r'3') {
            tone = 3
        } else if (last == r'4') {
            tone = 4
        }
    }
    if (bodyEnd == 0) {
        return (segments.toArray(), tone)
    }
    // 分离声母和韵母
    var initialLen = 0
    var initialStr = ""
    // 检查双字母声母 zh/ch/sh
    if (bodyEnd >= 2) {
        let c0 = runes[0]
        let c1 = runes[1]
        if ((c0 == r'z' || c0 == r'c' || c0 == r's') && c1 == r'h') {
            initialLen = 2
            initialStr = "${c0}h"
        }
    }
    // 检查单字母声母（不含 y/w，y/w 开头视为零声母）
    if (initialLen == 0 && bodyEnd >= 1) {
        if (isInitialRune(runes[0])) {
            initialLen = 1
            initialStr = "${runes[0]}"
        }
    }
    // 声母段
    if (initialLen > 0) {
        match (CONSONANT_TABLE.get(initialStr)) {
            case Some(seg) => segments.add(seg)
            case None => ()
        }
    }
    // 韵母段：从 runes[initialLen..bodyEnd] 构造字符串查表
    let finalList = ArrayList<Rune>()
    for (i in initialLen..bodyEnd) {
        finalList.add(runes[i])
    }
    var finalStr = String(finalList.toArray())
    // j/q/x 后面的 u 实际是 ü(v)，需替换
    if (initialStr == "j" || initialStr == "q" || initialStr == "x") {
        finalStr = finalStr.replace("u", "v")
    }
    // 拆分复韵母为多段，每段用对应单韵母共振峰，实现共振峰过渡
    let parts = splitCompoundFinal(finalStr)
    let nParts = Float64(parts.size)
    for (part in parts) {
        match (FINAL_TABLE.get(part)) {
            case Some(f) => segments.add(
                PhonemeSegment(FormantSet(f.f1, f.f2, f.f3, f.b1, f.b2, f.b3, f.voiced, f.durationMs / nParts), false))
            case None => segments.add(PhonemeSegment(neutralVoiced(), false))
        }
    }
    (segments.toArray(), tone)
}
