package ziyu.frontend

import std.collection.ArrayList

/* ============================================================================
 * 中文数字读法引擎（TN 核心）
 *
 * 把阿拉伯数字串展开成中文读法：
 *   - 数量：2026 → 两千零二十六；12 → 十二；100001 → 十万零一
 *   - 逐位：2026 → 二零二六（年份/电话/小数部分）
 *   - 小数：3.5 → 三点五
 *   - 分数：1/2 → 二分之一
 *   - 金额 / 百分号由归一化扫描器组装
 *
 * 纯仓颉：Rune 扫描 + 字符串拼接，零 FFI / 零正则回调依赖。
 * ========================================================================== */

/// 中文数字字符（下标即数值 0-9）
let CN_DIGITS: Array<String> = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
/// 万以下位权（下标 = 组内位置：0 个位 … 3 千位）
let CN_UNITS: Array<String> = ["", "十", "百", "千"]
/// 分组位权（每 4 位一组）
let CN_BIG_UNITS: Array<String> = ["", "万", "亿", "万亿", "亿亿"]

/// Rune → 数值（仅 ASCII '0'-'9'，其余返回 -1）
func digitValue(c: Rune): Int64 {
    let code = UInt32(c)
    if (code >= UInt32(48) && code <= UInt32(57)) {
        Int64(code - UInt32(48))
    } else {
        -1
    }
}

/// 是否 ASCII 数字
func isDigitRune(c: Rune): Bool {
    digitValue(c) >= 0
}

/// 把字符串的 rune 追加到列表
func appendStr(out: ArrayList<Rune>, s: String): Unit {
    for (c in s.toRuneArray()) {
        out.add(c)
    }
}

/// 汇总 rune 列表为 String
func runesToStr(out: ArrayList<Rune>): String {
    String(out.toArray())
}

/// 逐位读法：2026 → 二零二六
public func readDigits(digits: String): String {
    let out = ArrayList<Rune>()
    for (c in digits.toRuneArray()) {
        let v = digitValue(c)
        if (v >= 0) {
            appendStr(out, CN_DIGITS[v])
        }
    }
    runesToStr(out)
}

/// 数量读法：2026 → 两千零二十六；12 → 十二；100001 → 十万零一
public func readCardinal(digits: String): String {
    let rs = digits.toRuneArray()
    // 去前导零
    var start: Int64 = 0
    while (start < rs.size && digitValue(rs[start]) == 0) {
        start++
    }
    if (start >= rs.size) {
        return "零"
    }
    let n = rs.size - start
    let out = ArrayList<Rune>()
    let groupCount = (n + 3) / 4
    var seenNonZero = false
    var lastNonZeroGroup: Int64 = -1
    // 从最高组读到最低组
    for (idx in 0..groupCount) {
        let g = groupCount - 1 - idx // 组号：0 = 最低位组
        var gStart = n - 4 * (g + 1)
        if (gStart < 0) {
            gStart = 0
        }
        let gEnd = n - 4 * g
        // 判断该组是否全零
        var groupZero = true
        for (k in gStart..gEnd) {
            if (digitValue(rs[start + k]) != 0) {
                groupZero = false
                break
            }
        }
        if (groupZero) {
            continue
        }
        // 组间零：跨过整组零后需补一个"零"
        if (seenNonZero && idx > lastNonZeroGroup + 1) {
            appendStr(out, "零")
        }
        readGroup(rs, start + gStart, start + gEnd, g == groupCount - 1, out)
        if (g < CN_BIG_UNITS.size) {
            appendStr(out, CN_BIG_UNITS[g])
        }
        seenNonZero = true
        lastNonZeroGroup = idx
    }
    runesToStr(out)
}

/// 读一个 4 位以内组（rs[gStart, gEnd)）
func readGroup(rs: Array<Rune>, gStart: Int64, gEnd: Int64, isHighest: Bool, out: ArrayList<Rune>): Unit {
    var zeroPending = false
    for (i in gStart..gEnd) {
        let v = digitValue(rs[i])
        let posInGroup = gEnd - 1 - i // 0 = 个位
        if (v == 0) {
            zeroPending = true
        } else {
            if (zeroPending && out.size > 0) {
                appendStr(out, "零")
            }
            zeroPending = false
            if (v == 1 && posInGroup == 1 && isHighest && out.size == 0) {
                // 一十 → 十（10-19 读作"十X"）
                appendStr(out, "十")
            } else {
                appendStr(out, CN_DIGITS[v])
                appendStr(out, CN_UNITS[posInGroup])
            }
        }
    }
}
