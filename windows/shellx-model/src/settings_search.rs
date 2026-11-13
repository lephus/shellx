#[cfg(test)]
mod tests {
    use super::*;

    /// Searches every row as if its feature were done, so ranking can be tested before then.
    fn everything(query: &str, lang: Lang) -> Vec<Hit> {
        search_rows(query, lang, |_| true)
    }

    fn row_ids(hits: &[Hit]) -> Vec<&'static str> {
        hits.iter().filter_map(|h| h.row).collect()
    }

    fn rank_of(hits: &[Hit], id: &str) -> Option<u8> {
        hits.iter().find(|h| h.row == Some(id)).map(|h| h.rank)
    }

    #[test]
    fn search_folds_vietnamese_marks() {
        assert_eq!(fold("Phím tắt Đổi"), "phim tat doi");
        assert_eq!(fold("ẮẰẲẴẶ Ừ ỵ Ơ ê"), "aaaaa u y o e");
        // Decomposed input (a base letter followed by combining marks) folds the same way.
        assert_eq!(fold("Tie\u{0302}\u{0301}ng Vie\u{0323}\u{0302}t"), "tieng viet");
        assert_eq!(fold("Show Branch + Directory"), "show branch + directory");
    }

    #[test]
    fn every_token_must_match_and_rank_is_exact_prefix_word_substring() {
        let font = everything("font", Lang::En);
        assert_eq!(rank_of(&font, "terminalConfig.font-family"), Some(0), "exact title");
        assert_eq!(rank_of(&font, "terminalConfig.font-size"), Some(1), "title prefix");
        assert_eq!(rank_of(&font, "terminalConfig.surface-tab-bar-font-size"), Some(2), "word start");
        assert_eq!(rank_of(&font, "terminalConfig.sidebar-font-size"), Some(2), "word start");
        assert_eq!(
            row_ids(&font)[..4],
            [
                "terminalConfig.font-family",
                "terminalConfig.font-size",
                "terminalConfig.surface-tab-bar-font-size",
                "terminalConfig.sidebar-font-size",
            ]
        );
        assert!(font.windows(2).all(|w| w[0].rank <= w[1].rank), "best first");

        let ont = everything("ont", Lang::En);
        assert_eq!(rank_of(&ont, "terminalConfig.font-family"), Some(3), "substring");

        // Titles come before synonyms: "Terminal Theme" by its title, Appearance by a synonym.
        let theme = everything("theme", Lang::En);
        assert_eq!(theme[0], Hit { section: Section::Themes, row: None, rank: 1 });
        assert_eq!(theme[1], Hit { section: Section::Themes, row: Some("terminalTheme"), rank: 2 });
        assert!(rank_of(&theme, "app.appearance").is_some_and(|r| r >= 4));

        let clipboard = everything("clipboard", Lang::En);
        assert!(rank_of(&clipboard, "terminal.copyOnSelect").is_some_and(|r| r >= 4));

        // Every token must match somewhere in the row, its section title included.
        assert_eq!(row_ids(&everything("sidebar font", Lang::En)), ["terminalConfig.sidebar-font-size"]);
        // Tokens matched apart rank after whole-query matches, by how well a token fits the title.
        let terminal_font = everything("terminal font", Lang::En);
        assert_eq!(
            row_ids(&terminal_font),
            [
                "terminalConfig.font-family",
                "terminalConfig.font-size",
                "terminalConfig.surface-tab-bar-font-size",
            ]
        );
        let ranks: Vec<u8> = terminal_font.iter().map(|h| h.rank).collect();
        assert_eq!(ranks, [8, 9, 10]);
        assert!(everything("font zzz", Lang::En).is_empty());

        // Vietnamese, with or without marks, in either language.
        let co_chu = everything("cỡ chữ", Lang::Vi);
        assert_eq!(co_chu[0], Hit { section: Section::Terminal, row: Some("terminalConfig.font-size"), rank: 0 });
        assert_eq!(everything("CO CHU", Lang::Vi), co_chu);
        let phim_tat = everything("phim tat", Lang::En);
        assert!(phim_tat.contains(&Hit { section: Section::KeyboardShortcuts, row: None, rank: 4 }));
        assert!(phim_tat.iter().any(|h| h.row == Some("shortcutList")));
    }

    #[test]
    fn unwired_rows_are_not_found() {
        assert!(!everything("font size", Lang::En).is_empty());
        assert!(search("font size", Lang::En).is_empty());
        // A section without a wired row is not offered either.
        assert!(search("themes", Lang::En).iter().all(|h| h.section != Section::Themes));
        assert_eq!(
            search("display", Lang::En),
            [Hit { section: Section::Terminal, row: Some("display"), rank: 0 }]
        );
        let updates = search("cập nhật", Lang::Vi);
        assert_eq!(updates[0], Hit { section: Section::Updates, row: None, rank: 0 });
        assert!(updates.iter().all(|h| h.row.is_none_or(|id| row(id).unwrap().wired)));
    }

    #[test]
    fn an_empty_query_has_no_hits() {
        assert!(search("", Lang::En).is_empty());
        assert!(search("   ", Lang::Vi).is_empty());
        assert!(everything(" \t ", Lang::En).is_empty());
    }
}
