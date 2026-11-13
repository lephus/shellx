//! Settings search (spec §5.7): sections and wired rows, matched without case or Vietnamese
//! marks. Every word of the query must match somewhere in the row; the best hits come first.

use crate::settings_catalog::{Row, Section, groups, rows, section_title};
use crate::strings::{Lang, t};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Hit {
    pub section: Section,
    /// The row's id; `None` for the section itself.
    pub row: Option<&'static str>,
    /// Lower is better: 0–3 the whole query in the title (exact, prefix, word start, inside);
    /// 4–7 the same in the other language's title, the subtitle or the synonyms; 8–11 the words
    /// matched apart, by the best word's place in the title; 12 no word in the title.
    pub rank: u8,
}

/// Lower case without Vietnamese marks: "Phím tắt Đổi" is "phim tat doi".
pub fn fold(text: &str) -> String {
    const BASES: &[(&str, char)] = &[
        ("àáảãạăằắẳẵặâầấẩẫậ", 'a'),
        ("èéẻẽẹêềếểễệ", 'e'),
        ("ìíỉĩị", 'i'),
        ("òóỏõọôồốổỗộơờớởỡợ", 'o'),
        ("ùúủũụưừứửữự", 'u'),
        ("ỳýỷỹỵ", 'y'),
        ("đ", 'd'),
    ];
    text.chars()
        .flat_map(char::to_lowercase)
        // Combining marks, for text typed in decomposed form.
        .filter(|c| !('\u{0300}'..='\u{036f}').contains(c))
        .map(|c| {
            if c.is_ascii() {
                return c;
            }
            BASES
                .iter()
                .find(|(marked, _)| marked.contains(c))
                .map_or(c, |(_, base)| *base)
        })
        .collect()
}

/// Sections with a wired row, and wired rows, best first.
pub fn search(query: &str, lang: Lang) -> Vec<Hit> {
    search_rows(query, lang, |row| row.wired)
}

fn search_rows(query: &str, lang: Lang, include: impl Fn(&Row) -> bool) -> Vec<Hit> {
    let folded = fold(query);
    let words: Vec<&str> = folded.split_whitespace().collect();
    if words.is_empty() {
        return Vec::new();
    }
    let query = Query {
        whole: words.join(" "),
        words,
    };
    let other = match lang {
        Lang::En => Lang::Vi,
        Lang::Vi => Lang::En,
    };
    let mut hits = Vec::new();
    for &section in groups().iter().flat_map(|(_, sections)| sections.iter()) {
        let shown: Vec<&'static Row> = rows(section).filter(|r| include(r)).collect();
        if shown.is_empty() {
            continue;
        }
        let section_name = fold(t(lang, section_title(section)));
        let section_alias = fold(t(other, section_title(section)));
        if let Some(rank) = query.rank(&section_name, &[&section_alias], &[]) {
            hits.push(Hit {
                section,
                row: None,
                rank,
            });
        }
        for row in shown {
            let title = fold(t(lang, row.title));
            let alias = fold(t(other, row.title));
            let subtitle = row.subtitle.map(|s| fold(t(lang, s))).unwrap_or_default();
            let aliases = [alias.as_str(), subtitle.as_str(), row.synonyms];
            if let Some(rank) = query.rank(&title, &aliases, &[&section_name, &section_alias]) {
                hits.push(Hit {
                    section,
                    row: Some(row.id),
                    rank,
                });
            }
        }
    }
    // Stable: equal ranks keep the sidebar's order, a section before its rows.
    hits.sort_by_key(|h| h.rank);
    hits
}

struct Query<'a> {
    whole: String,
    words: Vec<&'a str>,
}

impl Query<'_> {
    /// `None` unless every word is in the title, an alias or the context (the section's title).
    fn rank(&self, title: &str, aliases: &[&str], context: &[&str]) -> Option<u8> {
        let everywhere = || std::iter::once(title).chain(aliases.iter().chain(context).copied());
        if !self
            .words
            .iter()
            .all(|w| everywhere().any(|field| field.contains(w)))
        {
            return None;
        }
        if let Some(in_title) = place(title, &self.whole) {
            return Some(in_title);
        }
        if let Some(in_alias) = aliases.iter().filter_map(|a| place(a, &self.whole)).min() {
            return Some(4 + in_alias);
        }
        Some(
            8 + self
                .words
                .iter()
                .filter_map(|w| place(title, w))
                .min()
                .unwrap_or(4),
        )
    }
}

/// Where `needle` sits in `hay`: 0 the whole of it, 1 its start, 2 a word's start, 3 inside a word.
fn place(hay: &str, needle: &str) -> Option<u8> {
    if hay == needle {
        return Some(0);
    }
    if hay.starts_with(needle) {
        return Some(1);
    }
    let mut inside = None;
    for (at, _) in hay.match_indices(needle) {
        if hay[..at]
            .chars()
            .next_back()
            .is_none_or(|c| !c.is_alphanumeric())
        {
            return Some(2);
        }
        inside = Some(3);
    }
    inside
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::settings_catalog::row;

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
        assert_eq!(
            fold("Tie\u{0302}\u{0301}ng Vie\u{0323}\u{0302}t"),
            "tieng viet"
        );
        assert_eq!(fold("Show Branch + Directory"), "show branch + directory");
    }

    #[test]
    fn every_token_must_match_and_rank_is_exact_prefix_word_substring() {
        let font = everything("font", Lang::En);
        assert_eq!(
            rank_of(&font, "terminalConfig.font-family"),
            Some(0),
            "exact title"
        );
        assert_eq!(
            rank_of(&font, "terminalConfig.font-size"),
            Some(1),
            "title prefix"
        );
        assert_eq!(
            rank_of(&font, "terminalConfig.surface-tab-bar-font-size"),
            Some(2),
            "word start"
        );
        assert_eq!(
            rank_of(&font, "terminalConfig.sidebar-font-size"),
            Some(2),
            "word start"
        );
        assert_eq!(
            row_ids(&font)[..4],
            [
                "terminalConfig.font-family",
                "terminalConfig.font-size",
                "terminalConfig.surface-tab-bar-font-size",
                "terminalConfig.sidebar-font-size",
            ]
        );
        assert!(
            font.windows(2).all(|w| w[0].rank <= w[1].rank),
            "best first"
        );

        let ont = everything("ont", Lang::En);
        assert_eq!(
            rank_of(&ont, "terminalConfig.font-family"),
            Some(3),
            "substring"
        );

        // Titles come before synonyms: "Terminal Theme" by its title, Appearance by a synonym.
        let theme = everything("theme", Lang::En);
        assert_eq!(
            theme[0],
            Hit {
                section: Section::Themes,
                row: None,
                rank: 1
            }
        );
        assert_eq!(
            theme[1],
            Hit {
                section: Section::Themes,
                row: Some("terminalTheme"),
                rank: 2
            }
        );
        assert!(rank_of(&theme, "app.appearance").is_some_and(|r| r >= 4));

        let clipboard = everything("clipboard", Lang::En);
        assert!(rank_of(&clipboard, "terminal.copyOnSelect").is_some_and(|r| r >= 4));

        // Every token must match somewhere in the row, its section title included.
        assert_eq!(
            row_ids(&everything("sidebar font", Lang::En)),
            ["terminalConfig.sidebar-font-size"]
        );
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
        // Font's synonyms hold "terminal font" (4 + word start); the others match word by word,
        // "font" starting Font Size's title (8 + 1) and a word of Tab Bar Font Size's (8 + 2).
        let ranks: Vec<u8> = terminal_font.iter().map(|h| h.rank).collect();
        assert_eq!(ranks, [6, 9, 10]);
        assert!(everything("font zzz", Lang::En).is_empty());

        // Vietnamese, with or without marks, in either language.
        let co_chu = everything("cỡ chữ", Lang::Vi);
        assert_eq!(
            co_chu[0],
            Hit {
                section: Section::Terminal,
                row: Some("terminalConfig.font-size"),
                rank: 0
            }
        );
        assert_eq!(everything("CO CHU", Lang::Vi), co_chu);
        let phim_tat = everything("phim tat", Lang::En);
        assert!(phim_tat.contains(&Hit {
            section: Section::KeyboardShortcuts,
            row: None,
            rank: 4
        }));
        assert!(phim_tat.iter().any(|h| h.row == Some("shortcutList")));
    }

    #[test]
    fn unwired_rows_are_not_found() {
        assert!(!everything("unselected fill", Lang::En).is_empty());
        assert!(search("unselected fill", Lang::En).is_empty());
        // A section without a wired row is not offered either.
        assert!(
            search("workspace colors", Lang::En)
                .iter()
                .all(|h| h.section != Section::WorkspaceColors)
        );
        assert_eq!(
            search("display", Lang::En),
            [
                Hit {
                    section: Section::Terminal,
                    row: Some("display"),
                    rank: 0
                },
                // Its subtitle says "Display git branches and working directories."
                Hit {
                    section: Section::Sidebar,
                    row: Some("sidebar.showBranchDirectory"),
                    rank: 5
                }
            ]
        );
        let updates = search("cập nhật", Lang::Vi);
        assert_eq!(
            updates[0],
            Hit {
                section: Section::Updates,
                row: None,
                rank: 0
            }
        );
        assert!(
            updates
                .iter()
                .all(|h| h.row.is_none_or(|id| row(id).unwrap().wired))
        );
    }

    #[test]
    fn an_empty_query_has_no_hits() {
        assert!(search("", Lang::En).is_empty());
        assert!(search("   ", Lang::Vi).is_empty());
        assert!(everything(" \t ", Lang::En).is_empty());
    }
}
