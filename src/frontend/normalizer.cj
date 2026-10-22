package ziyu.frontend

import std.collection.ArrayList
import std.regex.Regex
import std.unicode.*

/* ============================================================================
 * 文本归一化 TN（Text Normalization）—— 前端护城河第一道
 *
 * 在分词/音素转换之前，把数字符号展开成中文读法，避免"3.5元"被念成
 * "三点五美元"之类的错误。覆盖：
 *   - 数量：2026 → 两千零二十六
 *   - 年份：2026年 → 二零二六年
 *   - 小数：3.5 → 三点五
 *   - 日期：2026/10/21 → 二零二六年十月二十一日；2026年10月21日 天然分段
 *   - 金额：¥99 / $99 → 九十九元 / 九十九美元
 *   - 分数：1/2 → 二分之一
 *   - 百分号：50% → 百分之五十
 *   - 电话：13800138000 → 逐位念
 *
 * 纯仓颉：Rune 扫描，零 FFI。
 * ========================================================================== */

/// 文本归一化接口
public interface TextNormalizer {
    func normalize(text: String, language: String): String
}

/// 通用归一化器：空白合并 + 数字符号展开（TN）
public class DefaultNormalizer <: TextNormalizer {
    private let wsRegex = Regex("\\s+")

    public init() {}

    public func normalize(text: String, language: String): String {
        // 多个空白字符合并为单个空格，再去首尾空白
        let collapsed = wsRegex.replaceAll(text, " ").trim()
        expandNumbers(collapsed)
    }
}

/// 扫描并展开文本中的数字/货币符号为中文读法
func expandNumbers(text: String): String {
    let runes = text.toRuneArray()
    let out = ArrayList<Rune>()
    let n = runes.size
    var i: Int64 = 0
    while (i < n) {
        let r = runes[i]
        if (isCurrencySign(r)) {
            let (consumed, repl) = tryCurrency(runes, i)
            if (consumed > 0) {
                appendStr(out, repl)
                i += consumed
                continue
            }
        }
        if (isDigitRune(r)) {
            let (consumed, repl) = readNumberContext(runes, i)
            if (consumed > 0) {
                appendStr(out, repl)
                i += consumed
                continue
            }
        }
        out.add(r)
        i++
    }
    runesToStr(out)
}

/// 按上下文选择读法：日期 → 分数 → 电话 → 普通数字
func readNumberContext(runes: Array<Rune>, i: Int64): (Int64, String) {
    let (dc, ds) = tryReadDate(runes, i)
    if (dc > 0) {
        return (dc, ds)
    }
    let (fc, fs) = tryReadFraction(runes, i)
    if (fc > 0) {
        return (fc, fs)
    }
    let (pc, ps) = tryReadPhone(runes, i)
    if (pc > 0) {
        return (pc, ps)
    }
    readPlain(runes, i)
}

/// 日期：YYYY/MM/DD 或 YYYY-MM-DD（首段须 4 位、共三段）
func tryReadDate(runes: Array<Rune>, i: Int64): (Int64, String) {
    let (d1, l1) = readDigitRun(runes, i, 4)
    if (l1 != 4) {
        return (0, "")
    }
    let p1 = i + l1
    if (p1 >= runes.size || !isDateSep(runes[p1])) {
        return (0, "")
    }
    let (d2, l2) = readDigitRun(runes, p1 + 1, 2)
    if (l2 == 0) {
        return (0, "")
    }
    let p2 = p1 + 1 + l2
    if (p2 >= runes.size || !isDateSep(runes[p2])) {
        return (0, "")
    }
    let (d3, l3) = readDigitRun(runes, p2 + 1, 2)
    if (l3 == 0) {
        return (0, "")
    }
    var end = p2 + 1 + l3
    var tail = ""
    if (end < runes.size && (runes[end] == r'日' || runes[end] == r'号')) {
        tail = runes[end].toString()
        end++
    }
    let text = readDigits(d1) + "年" + readCardinal(d2) + "月" + readCardinal(d3) + "日" + tail
    (end - i, text)
}

/// 分数：a/b（两段，且其后不再接数字或分隔符）
func tryReadFraction(runes: Array<Rune>, i: Int64): (Int64, String) {
    let (d1, l1) = readDigitRun(runes, i, 3)
    if (l1 == 0) {
        return (0, "")
    }
    let p1 = i + l1
    if (p1 >= runes.size || runes[p1] != r'/') {
        return (0, "")
    }
    let (d2, l2) = readDigitRun(runes, p1 + 1, 4)
    if (l2 == 0) {
        return (0, "")
    }
    let p2 = p1 + 1 + l2
    if (p2 < runes.size && (isDateSep(runes[p2]) || isDigitRune(runes[p2]))) {
        return (0, "")
    }
    (p2 - i, readCardinal(d2) + "分之" + readCardinal(d1))
}

/// 电话：11 位以 1 开头，或含 '-' 的 7-12 位号码 → 逐位念
func tryReadPhone(runes: Array<Rune>, i: Int64): (Int64, String) {
    let digits = ArrayList<Rune>()
    var j = i
    var hasDash = false
    while (j < runes.size) {
        let c = runes[j]
        if (isDigitRune(c)) {
            digits.add(c)
            j++
        } else if (c == r'-' && j > i && j + 1 < runes.size && isDigitRune(runes[j + 1])) {
            hasDash = true
            j++
        } else {
            break
        }
    }
    let count = digits.size
    if (count == 0) {
        return (0, "")
    }
    let isMobile = count == 11 && digits[0] == r'1'
    if (isMobile || (hasDash && count >= 7 && count <= 12)) {
        return (j - i, readDigits(runesToStr(digits)))
    }
    (0, "")
}

/// 普通数字：带单位（年/月/日/号/百分号）或小数/千分位数量
func readPlain(runes: Array<Rune>, i: Int64): (Int64, String) {
    let (raw, len) = scanDigitsWithSep(runes, i)
    if (len == 0) {
        return (0, "")
    }
    let next = i + len
    if (next < runes.size) {
        let u = runes[next]
        let pure = stripSep(raw)
        if (u == r'年' && isAllDigits(raw) && raw.size == 4) {
            return (len + 1, readDigits(raw) + "年")
        }
        if (u == r'月' || u == r'日' || u == r'号') {
            return (len + 1, readCardinal(pure) + u.toString())
        }
        if (u == r'%' || u == r'％') {
            return (len + 1, "百分之" + readCardinal(pure))
        }
    }
    if (containsChar(raw, r'.')) {
        let parts = splitDot(raw)
        let intRead = if (parts[0].size == 0) {
            "零"
        } else {
            readCardinal(parts[0])
        }
        return (len, intRead + "点" + readDigits(parts[1]))
    }
    (len, readCardinal(stripSep(raw)))
}

/// 货币：¥99 / ￥99 → 九十九元；$99 → 九十九美元（支持小数）
func tryCurrency(runes: Array<Rune>, i: Int64): (Int64, String) {
    let (raw, len) = scanDigitsWithSep(runes, i + 1)
    if (len == 0) {
        return (0, "")
    }
    let unit = currencyUnit(runes[i])
    var body = ""
    if (containsChar(raw, r'.')) {
        let parts = splitDot(raw)
        let intRead = if (parts[0].size == 0) {
            "零"
        } else {
            readCardinal(parts[0])
        }
        body = intRead + "点" + readDigits(parts[1])
    } else {
        body = readCardinal(stripSep(raw))
    }
    (1 + len, body + unit)
}

// ── 基础扫描辅助 ──

/// 读取连续数字（最多 maxLen 位）
func readDigitRun(runes: Array<Rune>, i: Int64, maxLen: Int64): (String, Int64) {
    let out = ArrayList<Rune>()
    var j = i
    while (j < runes.size && j - i < maxLen && isDigitRune(runes[j])) {
        out.add(runes[j])
        j++
    }
    (runesToStr(out), j - i)
}

/// 读取数字与小数/千分位符号组合串（如 "3.5"、"1,000"）
func scanDigitsWithSep(runes: Array<Rune>, i: Int64): (String, Int64) {
    let out = ArrayList<Rune>()
    var j = i
    var lastWasDigit = false
    while (j < runes.size) {
        let c = runes[j]
        if (isDigitRune(c)) {
            out.add(c)
            lastWasDigit = true
            j++
        } else if ((c == r'.' || c == r',') && lastWasDigit) {
            if (j + 1 < runes.size && isDigitRune(runes[j + 1])) {
                out.add(c)
                lastWasDigit = false
                j++
            } else {
                break
            }
        } else {
            break
        }
    }
    (runesToStr(out), j - i)
}

/// 是否是货币符号（$ ¥ ￥）
func isCurrencySign(c: Rune): Bool {
    let code = UInt32(c)
    code == UInt32(0x24) || code == UInt32(0xA5) || code == UInt32(0xFFE5)
}

/// 货币符号 → 单位词
func currencyUnit(c: Rune): String {
    if (UInt32(c) == UInt32(0x24)) {
        "美元"
    } else {
        "元"
    }
}

/// 是否日期分隔符（'/' 或 '-'）
func isDateSep(c: Rune): Bool {
    c == r'/' || c == r'-'
}

/// 去掉千分位逗号
func stripSep(s: String): String {
    let out = ArrayList<Rune>()
    for (c in s.toRuneArray()) {
        if (c != r',') {
            out.add(c)
        }
    }
    runesToStr(out)
}

/// 是否全为 ASCII 数字
func isAllDigits(s: String): Bool {
    for (c in s.toRuneArray()) {
        if (!isDigitRune(c)) {
            return false
        }
    }
    s.size > 0
}

/// 是否含指定字符
func containsChar(s: String, target: Rune): Bool {
    for (c in s.toRuneArray()) {
        if (c == target) {
            return true
        }
    }
    false
}

/// 按第一个 '.' 拆成 [整数部分, 小数部分]
func splitDot(s: String): Array<String> {
    let runes = s.toRuneArray()
    for (i in 0..runes.size) {
        if (runes[i] == r'.') {
            let left = String(Array<Rune>(i, {k => runes[k]}))
            let right = String(Array<Rune>(runes.size - i - 1, {k => runes[i + 1 + k]}))
            return [left, right]
        }
    }
    [s, ""]
}
