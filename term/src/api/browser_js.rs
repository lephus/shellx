//! D25: DOM helpers built on `ui.browser.eval` (async function bodies).
//! Every caller value is a JSON string literal, never spliced raw.

use super::value::json_string;

/// Tag, text (≤ 500 characters), value and href of up to `limit` matches.
pub fn query(selector: &str, limit: i64) -> String {
    format!(
        "const els = [...document.querySelectorAll({sel})].slice(0, {limit});\n\
         return els.map(e => ({{tag: e.tagName.toLowerCase(), text: (e.innerText || e.textContent || '').trim().slice(0, 500), value: ('value' in e) ? String(e.value) : null, href: e.href || null}}));",
        sel = json_string(selector)
    )
}

/// Scrolls the first match into view and clicks it.
pub fn click(selector: &str) -> String {
    format!(
        "const sel = {sel};\nconst e = document.querySelector(sel);\n\
         if (!e) throw new Error('no element matches ' + sel);\n\
         e.scrollIntoView({{block: 'center'}});\ne.click();\nreturn true;",
        sel = json_string(selector)
    )
}

/// Sets the first match's value and fires `input` and `change`.
pub fn fill(selector: &str, text: &str) -> String {
    format!(
        "const sel = {sel};\nconst e = document.querySelector(sel);\n\
         if (!e) throw new Error('no element matches ' + sel);\n\
         e.focus();\ne.value = {text};\n\
         e.dispatchEvent(new Event('input', {{bubbles: true}}));\n\
         e.dispatchEvent(new Event('change', {{bubbles: true}}));\nreturn true;",
        sel = json_string(selector),
        text = json_string(text)
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn selectors_and_text_are_json_literals() {
        let s = click("a[href=\"/x\"]</script>");
        assert!(s.contains(r#""a[href=\"/x\"]</script>""#));
        assert!(!s.contains("eval("));
        let f = fill("#q", "line1\nline2");
        assert!(f.contains(r#""line1\nline2""#));
        assert!(f.contains("dispatchEvent(new Event('input', {bubbles: true}))"));
        assert!(query("li", 5).contains(".slice(0, 5)"));
    }
}
