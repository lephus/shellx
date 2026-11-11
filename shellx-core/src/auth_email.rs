#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn locale_of_is_vi_only_for_a_vi_prefix() {
        assert_eq!(locale_of(Some("vi")), "vi");
        assert_eq!(locale_of(Some("Vi-VN")), "vi");
        for other in [Some("en"), Some("ja"), None] {
            assert_eq!(locale_of(other), "en");
        }
    }

    #[test]
    fn sendable_email_trims_and_refuses_what_the_relay_would() {
        assert_eq!(sendable_email("  a@b.cd "), Some("a@b.cd"));
        let max = format!("{}@b.cd", "a".repeat(MAX_EMAIL_BYTES - "@b.cd".len()));
        assert_eq!(max.len(), 254);
        assert_eq!(sendable_email(&max), Some(max.as_str()));
        let over = format!("{}@b.cd", "a".repeat(MAX_EMAIL_BYTES - "@b.cd".len() + 1));
        assert_eq!(over.len(), 255);
        for bad in ["", "   ", "phu@ẽample.com", over.as_str()] {
            assert_eq!(sendable_email(bad), None, "{bad:?}");
        }
    }

    #[test]
    fn decimal_digit_maps_unicode_decimal_digits() {
        assert_eq!(decimal_digit('7'), Some(7));
        assert_eq!(decimal_digit('\u{0663}'), Some(3));
        assert_eq!(decimal_digit('\u{06F5}'), Some(5));
        assert_eq!(decimal_digit('\u{096B}'), Some(5));
        assert_eq!(decimal_digit('\u{FF15}'), Some(5));
        for not in ['a', '½', '²', '四', 'Ⅳ'] {
            assert_eq!(decimal_digit(not), None, "{not}");
        }
        for &z in DECIMAL_ZEROS {
            for i in 0..10 {
                let c = char::from_u32(z + i).unwrap();
                assert!(c.is_numeric(), "U+{:04X}", z + i);
                assert_eq!(decimal_digit(c), Some(i), "U+{:04X}", z + i);
            }
        }
    }

    #[test]
    fn clean_code_keeps_six_digits_as_ascii() {
        for ok in ["123456", " 123 456\n", "１２３４５６", "١٢٣٤٥٦"] {
            assert_eq!(clean_code(ok).as_deref(), Some("123456"), "{ok:?}");
        }
        assert_eq!(clean_code("004217").as_deref(), Some("004217"));
        for bad in ["12345", "1234567", "12a456", "123-456", "四五六七八九"] {
            assert_eq!(clean_code(bad), None, "{bad:?}");
        }
    }
}
