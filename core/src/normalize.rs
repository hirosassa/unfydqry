use unicode_normalization::UnicodeNormalization;

fn katakana_to_hiragana(c: char) -> char {
    match c as u32 {
        // Dakuten-marked forms (ガ=U+30AC, ヴ=U+30F4 etc.) also map correctly via -0x60.
        0x30A1..=0x30F6 => char::from_u32(c as u32 - 0x60).unwrap_or(c),
        _ => c,
    }
}

/// Folds case, full-width/half-width, and kana variant (katakana → hiragana).
/// Dakuten / handakuten are preserved (kept distinct).
pub fn normalize_loose(input: &str) -> String {
    input
        .nfkc()
        .map(katakana_to_hiragana)
        .flat_map(char::to_lowercase)
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    // Verifies the trace table from design doc §2.2 verbatim.
    #[test]
    fn dakuten_kept_kana_unified() {
        // With dakuten, everything collapses to「が」.
        for s in ["ガ", "が", "ｶﾞ"] {
            assert_eq!(normalize_loose(s), "が", "input={s}");
        }
        // Without dakuten, everything collapses to「か」 (a different key from「が」).
        for s in ["カ", "か", "ｶ"] {
            assert_eq!(normalize_loose(s), "か", "input={s}");
        }
        assert_ne!(normalize_loose("が"), normalize_loose("か"));
    }

    #[test]
    fn handakuten_kept_kana_unified() {
        for s in ["パ", "ぱ", "ﾊﾟ"] {
            assert_eq!(normalize_loose(s), "ぱ", "input={s}");
        }
        assert_ne!(normalize_loose("ぱ"), normalize_loose("は"));
    }

    #[test]
    fn vu_kana_unified() {
        for s in ["ヴ", "ｳﾞ"] {
            assert_eq!(normalize_loose(s), "ゔ", "input={s}");
        }
    }

    #[test]
    fn fullwidth_and_case_folded() {
        for s in ["Ｐ", "P", "ｐ", "p"] {
            assert_eq!(normalize_loose(s), "p", "input={s}");
        }
    }

    #[test]
    fn mixed_string() {
        // 「東京 ﾄｳｷｮｳ Tokyo」 → kanji passes through, kana → hiragana, ASCII → lowercase.
        let s = "東京 ﾄｳｷｮｳ Tokyo";
        let n = normalize_loose(s);
        assert_eq!(n, "東京 とうきょう tokyo");
    }

    #[test]
    fn empty_is_empty() {
        assert_eq!(normalize_loose(""), "");
    }
}
