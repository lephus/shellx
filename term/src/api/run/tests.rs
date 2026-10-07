use super::*;
use crate::api::args::{parse, Invocation};
use std::cell::RefCell;
use std::collections::VecDeque;
use std::rc::Rc;

type Log = Rc<RefCell<Vec<Message>>>;

struct Fake {
    log: Log,
    caps: Vec<&'static str>,
    answers: VecDeque<(&'static str, Result<Message, ApiError>)>,
    events: VecDeque<Message>,
}

impl Session for Fake {
    fn request(&mut self, t: &str, fields: Vec<(&str, Value)>) -> Result<Message, ApiError> {
        self.log.borrow_mut().push(Message::new(t, fields));
        if t == "api.version" {
            let caps = self.caps.iter().map(|c| Value::text(*c)).collect();
            return Ok(Message::new(
                "result",
                vec![("api", Value::Int(1)), ("caps", Value::Array(caps))],
            ));
        }
        match self.answers.iter().position(|(n, _)| *n == t) {
            Some(i) => self.answers.remove(i).unwrap().1,
            None => Ok(Message::new("result", vec![])),
        }
    }
    fn next_event(&mut self) -> Result<Message, ApiError> {
        self.events
            .pop_front()
            .ok_or(ApiError::NotRunning("closed".into()))
    }
}

const ALL: &[&str] = &[
    "cli.notify",
    "cli.events.subscribe",
    "ui.ls",
    "ui.tab.new",
    "ui.tab.rename",
    "ui.pane.split",
    "ui.focus",
    "ui.close",
    "ui.pane.send",
    "ui.pane.read",
    "ui.pane.wait",
    "ui.workspace.new",
    "ui.workspace.rename",
    "ui.workspace.move",
    "ui.config",
    "ui.browser",
    "ui.ssh",
    "ui.tmux",
];

struct Out {
    code: i32,
    out: String,
    err: String,
    log: Vec<Message>,
    tty: String,
    connected: bool,
}

fn ok(fields: Vec<(&str, Value)>) -> Result<Message, ApiError> {
    Ok(Message::new("result", fields))
}
fn remote(code: &str, message: &str) -> Result<Message, ApiError> {
    Err(ApiError::Remote {
        code: code.into(),
        message: message.into(),
    })
}

type Opts = (bool, bool, Option<ApiError>); // (has tty, shared terminal, connect error)

fn go_caps(
    args: &[&str],
    env: &[(&str, &str)],
    answers: Vec<(&'static str, Result<Message, ApiError>)>,
    stdin: &str,
    opts: Opts,
    caps: &[&'static str],
) -> Out {
    let args: Vec<String> = args.iter().map(|s| s.to_string()).collect();
    let Ok(Invocation::Run(p)) = parse(&args) else {
        panic!("not a run")
    };
    let env: Vec<(String, String)> = env
        .iter()
        .map(|(k, v)| (k.to_string(), v.to_string()))
        .collect();
    let get = move |k: &str| env.iter().find(|(n, _)| n == k).map(|(_, v)| v.clone());
    let log: Log = Rc::new(RefCell::new(vec![]));
    let connected = Rc::new(RefCell::new(false));
    let answers = RefCell::new(Some(answers));
    let caps = caps.to_vec();
    let (log2, connected2, err) = (log.clone(), connected.clone(), opts.2.clone());
    let connect = move |_: Option<&str>| -> Result<Box<dyn Session>, ApiError> {
        *connected2.borrow_mut() = true;
        if let Some(e) = err.clone() {
            return Err(e);
        }
        Ok(Box::new(Fake {
            log: log2.clone(),
            caps: caps.clone(),
            answers: answers.borrow_mut().take().unwrap_or_default().into(),
            events: VecDeque::new(),
        }))
    };
    let (mut out, mut errb, mut tty) = (Vec::new(), Vec::new(), Vec::new());
    let mut input = stdin.as_bytes();
    let code = {
        let mut ctx = Ctx {
            env: &get,
            out: &mut out,
            err: &mut errb,
            stdin: &mut input,
            stdin_is_tty: false,
            cwd: PathBuf::from("/work"),
            home: Some(PathBuf::from("/Users/me")),
            tty: if opts.0 {
                Some(&mut tty as &mut dyn Write)
            } else {
                None
            },
            shared_terminal: opts.1,
            connect: &connect,
            stdout_gone: None,
        };
        run(&p, &mut ctx)
    };
    let log = log.borrow().clone();
    let connected = *connected.borrow();
    Out {
        code,
        out: String::from_utf8(out).unwrap(),
        err: String::from_utf8(errb).unwrap(),
        log,
        tty: String::from_utf8(tty).unwrap(),
        connected,
    }
}

fn go(
    args: &[&str],
    env: &[(&str, &str)],
    answers: Vec<(&'static str, Result<Message, ApiError>)>,
    stdin: &str,
    opts: Opts,
) -> Out {
    go_caps(args, env, answers, stdin, opts, ALL)
}

const PLAIN: Opts = (false, false, None);

fn sent<'a>(o: &'a Out, t: &str) -> &'a Message {
    o.log
        .iter()
        .find(|m| m.t == t)
        .unwrap_or_else(|| panic!("no {t} in {:?}", o.log))
}

#[test]
fn split_defaults_to_self_and_prints_only_the_id() {
    let o = go(
        &["split", "--cmd", "npm run dev"],
        &[("SHELLX_PANE_ID", "100")],
        vec![(
            "ui.pane.split",
            ok(vec![("pane", Value::Int(102)), ("tab", Value::Int(100))]),
        )],
        "",
        PLAIN,
    );
    assert_eq!((o.code, o.out.as_str()), (0, "p102\n"));
    let m = sent(&o, "ui.pane.split");
    assert_eq!(m.get("pane"), Some(&Value::Int(100)));
    assert_eq!(m.get("direction"), Some(&Value::text("right")));
    assert_eq!(m.get("cmd"), Some(&Value::text("npm run dev")));
    assert_eq!(m.get("focus"), Some(&Value::Bool(false)));
    let outside = go(&["split", "--down"], &[], vec![], "", PLAIN);
    let m = sent(&outside, "ui.pane.split");
    assert_eq!(m.get("pane"), Some(&Value::text("@focused")));
    assert_eq!(m.get("direction"), Some(&Value::text("down")));
}

#[test]
fn new_tab_absolutizes_cwd_and_json_uses_prefixed_ids() {
    let o = go(
        &["new-tab", "--cwd", "app", "--json"],
        &[],
        vec![(
            "ui.tab.new",
            ok(vec![("tab", Value::Int(101)), ("pane", Value::Int(101))]),
        )],
        "",
        PLAIN,
    );
    assert_eq!(
        sent(&o, "ui.tab.new").get("cwd"),
        Some(&Value::text("/work/app"))
    );
    assert_eq!(o.out, "{\"tab\":\"t101\",\"pane\":\"p101\"}\n");
    let w = go(
        &["workspace", "new", "Build box"],
        &[],
        vec![(
            "ui.workspace.new",
            ok(vec![
                ("workspace", Value::text("ab12")),
                ("tab", Value::Int(7)),
            ]),
        )],
        "",
        PLAIN,
    );
    assert_eq!(w.out, "w:ab12\n");
    assert_eq!(
        sent(&w, "ui.workspace.new").get("name"),
        Some(&Value::text("Build box"))
    );
}

#[test]
fn send_refuses_oversize_stdin_before_connecting() {
    let big = "x".repeat(49_153);
    let o = go(&["send", "p1", "--stdin"], &[], vec![], &big, PLAIN);
    assert_eq!(o.code, 2);
    assert!(!o.connected);
    let t = go(&["send", "p1", "--text", &big], &[], vec![], "", PLAIN);
    assert_eq!((t.code, t.connected), (2, false));
    let k = go(
        &["send", "1", "--key", "ctrl-c", "--key", "up", "--enter"],
        &[],
        vec![],
        "",
        PLAIN,
    );
    let m = sent(&k, "ui.pane.send");
    assert_eq!(
        m.get("keys"),
        Some(&Value::Array(vec![
            Value::text("ctrl-c"),
            Value::text("up")
        ]))
    );
    assert_eq!(m.get("enter"), Some(&Value::Bool(true)));
    assert_eq!(go(&["send", "p1"], &[], vec![], "", PLAIN).code, 2);
}

#[test]
fn read_follows_pages() {
    let o = go(
        &["read", "p1", "--lines", "500"],
        &[],
        vec![
            (
                "ui.pane.read",
                ok(vec![
                    ("text", Value::text("a\nb\n")),
                    ("next", Value::Int(2)),
                ]),
            ),
            ("ui.pane.read", ok(vec![("text", Value::text("c\n"))])),
        ],
        "",
        PLAIN,
    );
    assert_eq!(o.out, "a\nb\nc\n");
    let reads: Vec<_> = o.log.iter().filter(|m| m.t == "ui.pane.read").collect();
    assert_eq!(reads[1].get("offset"), Some(&Value::Int(2)));
    assert_eq!(reads[0].get("lines"), Some(&Value::Int(500)));
    assert_eq!(reads[0].get("offset"), None);
    assert_eq!(
        go(&["read", "p1", "--lines", "10001"], &[], vec![], "", PLAIN).code,
        2
    );
    let j = go(
        &["read", "p1", "--json"],
        &[],
        vec![
            (
                "ui.pane.read",
                ok(vec![("text", Value::text("a\n")), ("next", Value::Int(1))]),
            ),
            (
                "ui.pane.read",
                ok(vec![("text", Value::text("b\n")), ("next", Value::Null)]),
            ),
        ],
        "",
        PLAIN,
    );
    assert_eq!(j.out, "{\"text\":\"a\\nb\\n\"}\n");
}

#[test]
fn wait_modes_and_timeouts() {
    assert_eq!(go(&["wait", "p1"], &[], vec![], "", PLAIN).code, 2);
    assert_eq!(
        go(&["wait", "p1", "--idle", "--exit"], &[], vec![], "", PLAIN).code,
        2
    );
    let e = go(
        &["wait", "p1", "--exit"],
        &[],
        vec![("ui.pane.wait", ok(vec![("exitCode", Value::Int(3))]))],
        "",
        PLAIN,
    );
    assert_eq!((e.code, e.out.as_str()), (0, "3\n"));
    // Final ruling M2: a pane closed before its shell ended has no code.
    let closed = go(
        &["wait", "p1", "--exit"],
        &[],
        vec![(
            "ui.pane.wait",
            ok(vec![
                ("exitCode", Value::Null),
                ("closed", Value::Bool(true)),
            ]),
        )],
        "",
        PLAIN,
    );
    assert_eq!((closed.code, closed.out.as_str()), (0, "closed\n"));
    let m = go(
        &[
            "wait",
            "p1",
            "--match",
            "ready",
            "--timeout",
            "1.5",
            "--from-now",
        ],
        &[],
        vec![(
            "ui.pane.wait",
            ok(vec![
                ("match", Value::text("ready")),
                ("line", Value::text("ready in 4 ms")),
            ]),
        )],
        "",
        PLAIN,
    );
    assert_eq!(m.out, "ready in 4 ms\n");
    let w = sent(&m, "ui.pane.wait");
    assert_eq!(w.get("timeoutMs"), Some(&Value::Int(1500)));
    assert_eq!(w.get("fromNow"), Some(&Value::Bool(true)));
    assert_eq!(w.get("pattern"), Some(&Value::text("ready")));
    let t = go(
        &["wait", "p1", "--idle"],
        &[],
        vec![("ui.pane.wait", remote("timeout", "timed out"))],
        "",
        PLAIN,
    );
    assert_eq!(t.code, 5);
    assert_eq!(
        go(
            &["wait", "p1", "--idle", "--timeout", "3601"],
            &[],
            vec![],
            "",
            PLAIN
        )
        .code,
        2
    );
    assert_eq!(
        go(
            &["wait", "p1", "--idle", "--timeout", "nan"],
            &[],
            vec![],
            "",
            PLAIN
        )
        .code,
        2
    );
    let slow = go(
        &["wait", "p1", "--match", "(a+)+$"],
        &[],
        vec![("ui.pane.wait", remote("bad_request", "pattern is too slow"))],
        "",
        PLAIN,
    );
    assert_eq!(
        (slow.code, slow.err.as_str()),
        (2, "shellx: pattern is too slow (bad_request)\n")
    );
}

#[test]
fn errors_human_and_json() {
    let h = go(
        &["read", "p1"],
        &[],
        vec![("ui.pane.read", remote("not_found", "no pane p1"))],
        "",
        PLAIN,
    );
    assert_eq!(h.code, 4);
    assert_eq!(h.err, "shellx: no pane p1 (not_found)\n");
    let j = go(
        &["read", "p1", "--json"],
        &[],
        vec![("ui.pane.read", remote("not_found", "no pane p1"))],
        "",
        PLAIN,
    );
    assert_eq!(
        j.out,
        "{\"error\":{\"code\":\"not_found\",\"message\":\"no pane p1\"}}\n"
    );
    assert_eq!(j.err, "");
    let n = go(
        &["ls"],
        &[],
        vec![],
        "",
        (
            false,
            false,
            Some(ApiError::NotRunning("ShellX is not running".into())),
        ),
    );
    assert_eq!(n.code, 3);
    let hint = "This terminal is not a ShellX shell. Allow it in the ShellX tray: Command line → Allow other terminals";
    let f = go(
        &["ls"],
        &[],
        vec![("ui.ls", remote("forbidden", hint))],
        "",
        PLAIN,
    );
    assert_eq!(f.code, 6);
    assert_eq!(f.err, format!("shellx: {hint} (forbidden)\n"));
    let c = go(
        &["close", "p1"],
        &[],
        vec![(
            "ui.close",
            remote("running_command", "a command is running; use --force"),
        )],
        "",
        PLAIN,
    );
    assert_eq!(c.code, 6);
}

#[test]
fn missing_cap_is_incompatible() {
    // A host without ui.browser (A6 absent): no browser panes yet.
    let b = go_caps(&["browser", "ls"], &[], vec![], "", PLAIN, &["ui.ls"]);
    assert_eq!(b.code, 7);
    assert!(
        b.err
            .contains("no browser panes yet (update ShellX when available)"),
        "{}",
        b.err
    );
    // Any other missing cap: too old.
    let w = go_caps(
        &["wait", "p1", "--idle"],
        &[],
        vec![],
        "",
        PLAIN,
        &["ui.ls"],
    );
    assert_eq!(w.code, 7);
    assert!(
        w.err.contains("too old") && w.err.contains("update ShellX"),
        "{}",
        w.err
    );
    assert!(!w.log.iter().any(|m| m.t == "ui.pane.wait"));
}

#[test]
fn targets() {
    assert_eq!(go(&["read", "@self"], &[], vec![], "", PLAIN).code, 2);
    let f = go(&["focus", "12"], &[], vec![], "", PLAIN);
    assert_eq!(sent(&f, "ui.focus").get("pane"), Some(&Value::Int(12)));
    let t = go(&["focus", "t5", "--raise"], &[], vec![], "", PLAIN);
    assert_eq!(sent(&t, "ui.focus").get("tab"), Some(&Value::Int(5)));
    assert_eq!(sent(&t, "ui.focus").get("raise"), Some(&Value::Bool(true)));
    let b = go(&["browser", "reload", "p-3"], &[], vec![], "", PLAIN);
    assert_eq!(
        sent(&b, "ui.browser.reload").get("pane"),
        Some(&Value::Int(-3))
    );
    let r = go(
        &["rename", "@tab", "build", "server"],
        &[("SHELLX_TAB_ID", "7")],
        vec![],
        "",
        PLAIN,
    );
    let m = sent(&r, "ui.tab.rename");
    assert_eq!(
        (m.get("tab"), m.get("name")),
        (Some(&Value::Int(7)), Some(&Value::text("build server")))
    );
    // Final ruling M4: a pane command takes a tab — the host resolves it
    // to that tab's focused pane, so it goes out in its written form.
    let st = go(&["send", "t5", "--text", "x"], &[], vec![], "", PLAIN);
    assert_eq!(st.code, 0);
    assert_eq!(
        sent(&st, "ui.pane.send").get("pane"),
        Some(&Value::text("t5"))
    );
    let wt = go(&["wait", "t5", "--idle"], &[], vec![], "", PLAIN);
    assert_eq!(
        sent(&wt, "ui.pane.wait").get("pane"),
        Some(&Value::text("t5"))
    );
    // `cli.notify` takes a pane number only (as with @focused).
    assert_eq!(
        go(&["notify", "--pane", "t5", "hi"], &[], vec![], "", PLAIN).code,
        2
    );
    // @tab stays a tab-command form.
    assert_eq!(
        go(
            &["send", "@tab", "--enter"],
            &[("SHELLX_TAB_ID", "5")],
            vec![],
            "",
            PLAIN
        )
        .code,
        2
    );
    let s = go(
        &["close", "@self"],
        &[("SHELLX_PANE_ID", "9")],
        vec![],
        "",
        PLAIN,
    );
    assert_eq!(sent(&s, "ui.close").get("pane"), Some(&Value::Int(9)));
    let fo = go(&["focus", "@focused"], &[], vec![], "", PLAIN);
    assert_eq!(
        sent(&fo, "ui.focus").get("pane"),
        Some(&Value::text("@focused"))
    );
    let mv = go(&["workspace", "move", "12", "w:x"], &[], vec![], "", PLAIN);
    let m = sent(&mv, "ui.workspace.move");
    assert_eq!(
        (m.get("tab"), m.get("workspace")),
        (Some(&Value::Int(12)), Some(&Value::text("w:x")))
    );
}

#[test]
fn only_canonical_ids_are_sent() {
    // The host accepts p0, p<n>, p-<n>, t<n> (no leading zeros, no -0,
    // at most 15 digits) and plain numbers: anything else is a usage
    // error before connecting.
    for bad in [
        "p007",
        "p-0",
        "p+5",
        "+5",
        "007",
        "t0",
        "t-1",
        "p1234567890123456",
        "p",
        "t",
        "px",
        "p 1",
        "-0",
    ] {
        let o = go(&["read", bad], &[], vec![], "", PLAIN);
        let f = go(&["focus", bad], &[], vec![], "", PLAIN);
        assert_eq!(
            (o.code, o.connected, f.code, f.connected),
            (2, false, 2, false),
            "{bad}"
        );
    }
    assert_eq!(go(&["rename", "-3", "x"], &[], vec![], "", PLAIN).code, 2);
    for (raw, id) in [
        ("p0", 0),
        ("0", 0),
        ("p-12", -12),
        ("p123456789012345", 123_456_789_012_345),
    ] {
        let o = go(&["read", raw], &[], vec![], "", PLAIN);
        assert_eq!(
            sent(&o, "ui.pane.read").get("pane"),
            Some(&Value::Int(id)),
            "{raw}"
        );
    }
    assert_eq!(
        go(
            &["read", "@self"],
            &[("SHELLX_PANE_ID", "x1")],
            vec![],
            "",
            PLAIN
        )
        .code,
        2
    );
}

#[test]
fn notify_paths() {
    // (1) in a pane: the API with the pane.
    let a = go(
        &["notify", "Build", "xong"],
        &[("SHELLX_PANE_ID", "12")],
        vec![],
        "",
        PLAIN,
    );
    let m = sent(&a, "cli.notify");
    assert_eq!(
        (m.get("pane"), m.get("body")),
        (Some(&Value::Int(12)), Some(&Value::text("Build xong")))
    );
    // (2) a shared terminal without a pane: OSC 777 to the tty, no socket.
    let b = go(
        &["notify", "--title", "CI", "ok\u{7}\u{1b}x"],
        &[],
        vec![],
        "",
        (true, true, None),
    );
    assert!(!b.connected);
    assert_eq!(b.tty, "\u{1b}]777;notify;CI;okx\u{7}");
    // (3) elsewhere: the API without a pane.
    let e = go(&["notify", "done"], &[], vec![], "", (true, false, None));
    let m = sent(&e, "cli.notify");
    assert_eq!((m.get("pane"), e.tty.as_str()), (None, ""));
    // Not running, in a pane with a tty: OSC fallback, exit 0.
    let c = go(
        &["notify", "x"],
        &[("SHELLX_PANE_ID", "12")],
        vec![],
        "",
        (true, false, Some(ApiError::NotRunning("no".into()))),
    );
    assert_eq!((c.code, c.tty.as_str()), (0, "\u{1b}]777;notify;;x\u{7}"));
    // Not running, nowhere to fall back: exit 3.
    let d = go(
        &["notify", "x"],
        &[],
        vec![],
        "",
        (false, false, Some(ApiError::NotRunning("no".into()))),
    );
    assert_eq!(d.code, 3);
    // Blank text: usage.
    assert_eq!(go(&["notify", " "], &[], vec![], "", PLAIN).code, 2);
    // Long text is cut as the host cuts it (body 1024, title 128 characters).
    let long = "é".repeat(5000);
    let l = go(&["notify", "--title", &long, &long], &[], vec![], "", PLAIN);
    let m = sent(&l, "cli.notify");
    assert_eq!(
        m.get("body")
            .and_then(Value::as_str)
            .map(|s| s.chars().count()),
        Some(1024)
    );
    assert_eq!(
        m.get("title")
            .and_then(Value::as_str)
            .map(|s| s.chars().count()),
        Some(128)
    );
}

#[test]
fn browser_eval_prints_raw_json_and_helpers_escape() {
    let e = go(
        &["browser", "eval", "p-1", "--script", "return {a: 1}"],
        &[],
        vec![(
            "ui.browser.eval",
            ok(vec![("json", Value::text("{\"a\":1}"))]),
        )],
        "",
        PLAIN,
    );
    assert_eq!(e.out, "{\"a\":1}\n");
    let f = go(
        &[
            "browser",
            "fill",
            "p-1",
            "input[name=\"q\"]",
            "it's",
            "\"x\"",
        ],
        &[],
        vec![],
        "",
        PLAIN,
    );
    let script = sent(&f, "ui.browser.eval")
        .get("script")
        .and_then(Value::as_str)
        .unwrap()
        .to_string();
    assert!(script.contains(r#""input[name=\"q\"]""#), "{script}");
    assert!(script.contains(r#""it's \"x\"""#), "{script}");
    let big = "x".repeat(32 * 1024 + 1);
    assert_eq!(
        go(
            &["browser", "eval", "p-1", "--script", &big],
            &[],
            vec![],
            "",
            PLAIN
        )
        .code,
        2
    );
}

fn tree(cwd: Value, branch: Value, exit: Value) -> Value {
    Value::Array(vec![Value::map(vec![
        ("id", Value::text("default")),
        ("name", Value::text("Default")),
        ("current", Value::Bool(true)),
        (
            "tabs",
            Value::Array(vec![Value::map(vec![
                ("id", Value::Int(100)),
                ("title", Value::text("build")),
                ("selected", Value::Bool(true)),
                ("unread", Value::Int(2)),
                ("agent", Value::Bool(false)),
                (
                    "panes",
                    Value::Array(vec![Value::map(vec![
                        ("id", Value::Int(100)),
                        ("kind", Value::text("terminal")),
                        ("title", Value::text("zsh")),
                        ("cwd", cwd),
                        ("branch", branch),
                        ("ports", Value::Array(vec![Value::Int(3000)])),
                        ("focused", Value::Bool(true)),
                        ("exitCode", exit),
                    ])]),
                ),
            ])]),
        ),
    ])])
}

#[test]
fn ls_human_and_ids() {
    let t = tree(
        Value::text("/Users/me/app"),
        Value::text("main"),
        Value::Null,
    );
    let o = go(
        &["ls"],
        &[],
        vec![("ui.ls", ok(vec![("workspaces", t.clone())]))],
        "",
        PLAIN,
    );
    assert!(
        o.out.contains("t100")
            && o.out.contains("p100")
            && o.out.contains("~/app")
            && o.out.contains("main")
            && o.out.contains(":3000")
            && o.out.contains("●2"),
        "{}",
        o.out
    );
    assert!(!o.out.contains("exited"), "{}", o.out);
    let ids = go(
        &["ls", "--ids"],
        &[],
        vec![("ui.ls", ok(vec![("workspaces", t)]))],
        "",
        PLAIN,
    );
    assert_eq!(ids.out, "t100\np100\n");
}

#[test]
fn ls_accepts_null_optional_keys() {
    let t = tree(Value::Null, Value::Null, Value::Null);
    let fields = vec![
        ("workspaces", t),
        ("selectedTab", Value::Int(100)),
        ("focusedPane", Value::Null),
    ];
    let h = go(&["ls"], &[], vec![("ui.ls", ok(fields.clone()))], "", PLAIN);
    assert_eq!(h.code, 0);
    assert!(
        h.out.contains("p100") && !h.out.contains("null"),
        "{}",
        h.out
    );
    let j = go(
        &["ls", "--json"],
        &[],
        vec![("ui.ls", ok(fields))],
        "",
        PLAIN,
    );
    assert_eq!(j.code, 0);
    assert!(j.out.contains("\"id\":\"w:default\""), "{}", j.out);
    assert!(
        j.out.contains("\"id\":\"t100\"") && j.out.contains("\"id\":\"p100\""),
        "{}",
        j.out
    );
    assert!(
        j.out.contains("\"cwd\":null,\"branch\":null") && j.out.contains("\"exitCode\":null"),
        "{}",
        j.out
    );
    assert!(
        j.out
            .contains("\"selectedTab\":\"t100\",\"focusedPane\":null"),
        "{}",
        j.out
    );
    let e = go(
        &["ls"],
        &[],
        vec![(
            "ui.ls",
            ok(vec![(
                "workspaces",
                tree(Value::Null, Value::Null, Value::Int(-15)),
            )]),
        )],
        "",
        PLAIN,
    );
    assert!(e.out.contains("[exited -15]"), "{}", e.out);
}

#[test]
fn events_print_json_lines_until_closed() {
    let args: Vec<String> = ["events", "--follow", "--kinds", "tab.opened,notice"]
        .iter()
        .map(|s| s.to_string())
        .collect();
    let Ok(Invocation::Run(p)) = parse(&args) else {
        panic!()
    };
    let log: Log = Rc::new(RefCell::new(vec![]));
    let l2 = log.clone();
    let connect = move |_: Option<&str>| -> Result<Box<dyn Session>, ApiError> {
        Ok(Box::new(Fake {
            log: l2.clone(),
            caps: ALL.to_vec(),
            answers: VecDeque::new(),
            events: VecDeque::from(vec![Message::new(
                "event",
                vec![
                    ("kind", Value::text("tab.opened")),
                    ("tab", Value::Int(5)),
                    ("workspace", Value::text("default")),
                ],
            )]),
        }))
    };
    let get = |_: &str| None;
    let (mut out, mut err) = (Vec::new(), Vec::new());
    let mut input: &[u8] = b"";
    let mut ctx = Ctx {
        env: &get,
        out: &mut out,
        err: &mut err,
        stdin: &mut input,
        stdin_is_tty: false,
        cwd: PathBuf::from("/"),
        home: None,
        tty: None,
        shared_terminal: false,
        connect: &connect,
        stdout_gone: None,
    };
    assert_eq!(run(&p, &mut ctx), 3); // ShellX closed the stream
    assert_eq!(
        String::from_utf8(out).unwrap(),
        "{\"kind\":\"tab.opened\",\"tab\":\"t5\",\"workspace\":\"w:default\"}\n"
    );
    let sub = log
        .borrow()
        .iter()
        .find(|m| m.t == "cli.events.subscribe")
        .unwrap()
        .clone();
    assert_eq!(
        sub.get("kinds"),
        Some(&Value::Array(vec![
            Value::text("tab.opened"),
            Value::text("notice")
        ]))
    );
    // Without --follow/--for: subscribe and exit 0.
    let once = go(&["events"], &[], vec![], "", PLAIN);
    assert_eq!((once.code, once.out.as_str()), (0, ""));
    assert_eq!(
        go(&["events", "--for", "x"], &[], vec![], "", PLAIN).code,
        2
    );
}

/// Counts `next_event` calls and notes when the session is dropped (the
/// connection closes, the host frees its listener slot).
struct Events {
    events: VecDeque<Message>,
    pulled: Rc<RefCell<usize>>,
    dropped: Rc<RefCell<bool>>,
}

impl Session for Events {
    fn request(&mut self, t: &str, _: Vec<(&str, Value)>) -> Result<Message, ApiError> {
        if t == "api.version" {
            let caps = ALL.iter().map(|c| Value::text(*c)).collect();
            return Ok(Message::new(
                "result",
                vec![("api", Value::Int(1)), ("caps", Value::Array(caps))],
            ));
        }
        Ok(Message::new("result", vec![]))
    }
    fn next_event(&mut self) -> Result<Message, ApiError> {
        *self.pulled.borrow_mut() += 1;
        self.events
            .pop_front()
            .ok_or(ApiError::NotRunning("closed".into()))
    }
}

impl Drop for Events {
    fn drop(&mut self) {
        *self.dropped.borrow_mut() = true;
    }
}

/// A stdout whose reader went away (`shellx events … | head -1`).
struct Broken(std::io::ErrorKind);

impl Write for Broken {
    fn write(&mut self, _: &[u8]) -> std::io::Result<usize> {
        Err(self.0.into())
    }
    fn flush(&mut self) -> std::io::Result<()> {
        Err(self.0.into())
    }
}

fn follow_into(kind: std::io::ErrorKind) -> (i32, usize, bool) {
    let args: Vec<String> = ["events", "--follow"]
        .iter()
        .map(|s| s.to_string())
        .collect();
    let Ok(Invocation::Run(p)) = parse(&args) else {
        panic!()
    };
    let pulled = Rc::new(RefCell::new(0));
    let dropped = Rc::new(RefCell::new(false));
    let (p2, d2) = (pulled.clone(), dropped.clone());
    let connect = move |_: Option<&str>| -> Result<Box<dyn Session>, ApiError> {
        let e = || Message::new("event", vec![("kind", Value::text("pane.exited"))]);
        Ok(Box::new(Events {
            events: VecDeque::from(vec![e(), e(), e()]),
            pulled: p2.clone(),
            dropped: d2.clone(),
        }))
    };
    let get = |_: &str| None;
    let mut out = Broken(kind);
    let mut err = Vec::new();
    let mut input: &[u8] = b"";
    let mut ctx = Ctx {
        env: &get,
        out: &mut out,
        err: &mut err,
        stdin: &mut input,
        stdin_is_tty: false,
        cwd: PathBuf::from("/"),
        home: None,
        tty: None,
        shared_terminal: false,
        connect: &connect,
        stdout_gone: None,
    };
    let code = run(&p, &mut ctx);
    let pulled = *pulled.borrow();
    let dropped = *dropped.borrow();
    (code, pulled, dropped)
}

#[test]
fn events_end_when_stdout_is_gone() {
    // `| head -1`: the first failed write ends the stream (exit 0) and
    // closes the connection; it never keeps reading events.
    assert_eq!(follow_into(std::io::ErrorKind::BrokenPipe), (0, 1, true));
    // Any other write error: exit 1, connection closed too.
    assert_eq!(follow_into(std::io::ErrorKind::Other), (1, 1, true));
}

#[test]
fn notify_pane_must_be_a_pane_id() {
    // The host's cli.notify takes a number: @focused is refused, never
    // silently sent without a pane.
    let o = go(
        &["notify", "--pane", "@focused", "x"],
        &[],
        vec![],
        "",
        PLAIN,
    );
    assert_eq!((o.code, o.connected), (2, false));
    let s = go(
        &["notify", "--pane", "@self", "x"],
        &[("SHELLX_PANE_ID", "4")],
        vec![],
        "",
        PLAIN,
    );
    assert_eq!(sent(&s, "cli.notify").get("pane"), Some(&Value::Int(4)));
}

#[test]
fn notify_falls_back_to_osc_only_inside_a_shellx_pane() {
    let no = || Some(ApiError::NotRunning("no".into()));
    // --pane alone does not make this a ShellX pane: exit 3, nothing written.
    let o = go(
        &["notify", "--pane", "p12", "x"],
        &[],
        vec![],
        "",
        (true, false, no()),
    );
    assert_eq!((o.code, o.tty.as_str()), (3, ""));
    // Inside a ShellX pane, --pane names another pane: still the fallback.
    let i = go(
        &["notify", "--pane", "p12", "x"],
        &[("SHELLX_PANE_ID", "3")],
        vec![],
        "",
        (true, false, no()),
    );
    assert_eq!((i.code, i.tty.as_str()), (0, "\u{1b}]777;notify;;x\u{7}"));
}

#[cfg(unix)]
#[test]
fn eval_file_reads_at_most_the_limit() {
    // A file that never ends (a FIFO kept open) is refused once it is over
    // 32 KiB, not read to the end.
    let path = std::env::temp_dir().join(format!("shellx-fifo-{}", std::process::id()));
    let _ = std::fs::remove_file(&path);
    let c = std::ffi::CString::new(path.to_str().unwrap()).unwrap();
    // SAFETY: a valid C string; mkfifo has no other preconditions.
    assert_eq!(unsafe { libc::mkfifo(c.as_ptr(), 0o600) }, 0);
    let w = path.clone();
    std::thread::spawn(move || {
        let mut f = std::fs::OpenOptions::new().write(true).open(&w).unwrap();
        let _ = f.write_all(&vec![b'x'; 40 * 1024]);
        std::thread::sleep(std::time::Duration::from_secs(10));
    });
    let (tx, rx) = std::sync::mpsc::channel();
    let p = path.to_str().unwrap().to_string();
    std::thread::spawn(move || {
        let o = go(
            &["browser", "eval", "p-1", "--file", &p],
            &[],
            vec![],
            "",
            PLAIN,
        );
        let _ = tx.send((o.code, o.connected));
    });
    let r = rx.recv_timeout(std::time::Duration::from_secs(3));
    let _ = std::fs::remove_file(&path);
    assert_eq!(r, Ok((2, false)));
}

#[test]
fn json_is_honoured_for_eval() {
    let e = go(
        &["browser", "eval", "p-1", "--script", "return 1", "--json"],
        &[],
        vec![(
            "ui.browser.eval",
            ok(vec![("json", Value::text("{\"a\":[1,2]}"))]),
        )],
        "",
        PLAIN,
    );
    assert_eq!(e.out, "{\"json\":{\"a\":[1,2]}}\n");
    let c = go(
        &["browser", "click", "p-1", "a", "--json"],
        &[],
        vec![("ui.browser.eval", ok(vec![("json", Value::text("true"))]))],
        "",
        PLAIN,
    );
    assert_eq!(c.out, "{\"json\":true}\n");
    let n = go(
        &["browser", "click", "p-1", "a"],
        &[],
        vec![("ui.browser.eval", ok(vec![("json", Value::text("true"))]))],
        "",
        PLAIN,
    );
    assert_eq!(n.out, "");
}

#[test]
fn human_output_never_carries_control_characters() {
    let evil = "x\u{1b}]52;c;aGk=\u{7}\u{1b}[2J\u{9b}31m";
    let tree = Value::Array(vec![Value::map(vec![
        ("id", Value::text("w")),
        ("name", Value::text(evil)),
        (
            "tabs",
            Value::Array(vec![Value::map(vec![
                ("id", Value::Int(1)),
                ("title", Value::text(evil)),
                (
                    "panes",
                    Value::Array(vec![Value::map(vec![
                        ("id", Value::Int(1)),
                        ("title", Value::text(evil)),
                        ("cwd", Value::text(evil)),
                        ("branch", Value::text(evil)),
                    ])]),
                ),
            ])]),
        ),
    ])]);
    let l = go(
        &["ls"],
        &[],
        vec![("ui.ls", ok(vec![("workspaces", tree)]))],
        "",
        PLAIN,
    );
    let entries = Value::Array(vec![Value::map(vec![
        ("seq", Value::Int(1)),
        ("level", Value::text(evil)),
        ("text", Value::text(evil)),
        ("method", Value::text(evil)),
        ("url", Value::text(evil)),
    ])]);
    let c = go(
        &["browser", "console", "p-1"],
        &[],
        vec![("ui.browser.console", ok(vec![("entries", entries.clone())]))],
        "",
        PLAIN,
    );
    let n = go(
        &["browser", "network", "p-1"],
        &[],
        vec![("ui.browser.network", ok(vec![("entries", entries)]))],
        "",
        PLAIN,
    );
    let panes = Value::Array(vec![Value::map(vec![
        ("pane", Value::Int(-1)),
        ("tab", Value::Int(1)),
        ("title", Value::text(evil)),
        ("url", Value::text(evil)),
    ])]);
    let b = go(
        &["browser", "ls"],
        &[],
        vec![("ui.browser.list", ok(vec![("panes", panes)]))],
        "",
        PLAIN,
    );
    let h = go(
        &["read", "p1"],
        &[],
        vec![("ui.pane.read", remote("not_found", evil))],
        "",
        PLAIN,
    );
    for (name, s) in [
        ("ls", &l.out),
        ("console", &c.out),
        ("network", &n.out),
        ("browser ls", &b.out),
        ("error", &h.err),
    ] {
        let body = s.trim_end_matches('\n');
        assert!(
            !body.chars().any(|ch| ch.is_control() && ch != '\n'),
            "{name}: {s:?}"
        );
        assert!(body.contains("x]52;c;aGk="), "{name}: {s:?}");
    }
}

fn problem_answer(severity: &str) -> Vec<(&'static str, Result<Message, ApiError>)> {
    let p = Value::map(vec![
        ("file", Value::text("/h/.config/shellx/config")),
        ("line", Value::Int(1)),
        ("severity", Value::text(severity)),
        ("code", Value::text("badValue")),
        ("key", Value::text("font-size")),
        (
            "message",
            Value::text("font-size: “to” is not valid (expected 9–28)"),
        ),
    ]);
    vec![
        (
            "ui.config.check",
            ok(vec![
                ("problems", Value::Array(vec![p.clone()])),
                ("generation", Value::Int(0)),
            ]),
        ),
        (
            "ui.config.reload",
            ok(vec![
                ("problems", Value::Array(vec![p])),
                ("generation", Value::Int(1)),
            ]),
        ),
    ]
}

#[test]
fn config_path_is_local_and_never_connects() {
    let o = go(
        &["config", "path", "--ghostty"],
        &[("HOME", "/Users/me")],
        vec![],
        "",
        PLAIN,
    );
    assert_eq!(o.code, 0);
    assert!(!o.connected);
    let lines: Vec<&str> = o.out.lines().collect();
    assert_eq!(lines[0], "/Users/me/.config/shellx/config");
    assert_eq!(lines.len(), 5);
    let j = go(
        &["config", "path", "--json"],
        &[("HOME", "/Users/me")],
        vec![],
        "",
        PLAIN,
    );
    assert_eq!(j.out.lines().count(), 1);
    assert!(j
        .out
        .contains("\"shellx\":\"/Users/me/.config/shellx/config\""));
    let none = go(&["config", "path"], &[], vec![], "", PLAIN);
    assert_eq!(none.code, 2);
}

#[test]
fn config_check_exits_1_on_errors_and_prints_them() {
    let o = go(
        &["config", "check"],
        &[],
        problem_answer("error"),
        "",
        PLAIN,
    );
    assert_eq!(o.code, 1);
    assert_eq!(
        o.out,
        "/h/.config/shellx/config:1: error: font-size: “to” is not valid (expected 9–28)\n"
    );
    assert_eq!(o.err, "");
    let w = go(
        &["config", "check"],
        &[],
        problem_answer("warning"),
        "",
        PLAIN,
    );
    assert_eq!(w.code, 0);
}

#[test]
fn config_reload_and_json() {
    let o = go(
        &["config", "reload"],
        &[],
        problem_answer("error"),
        "",
        PLAIN,
    );
    assert_eq!(o.code, 1);
    assert!(o.out.contains("error:"));
    let j = go(
        &["config", "reload", "--json"],
        &[],
        problem_answer("error"),
        "",
        PLAIN,
    );
    assert_eq!(j.code, 1);
    assert_eq!(j.out.lines().count(), 1, "{}", j.out);
    assert!(j.out.starts_with("{\"problems\":[{"), "{}", j.out);
    assert_eq!(j.err, "");
}

#[test]
fn config_show_asks_for_defaults_only_when_told() {
    let a = go(
        &["config", "show"],
        &[],
        vec![(
            "ui.config.show",
            ok(vec![("template", Value::text("# hi\n"))]),
        )],
        "",
        PLAIN,
    );
    assert_eq!((a.code, a.out.as_str()), (0, "# hi\n"));
    assert_eq!(
        sent(&a, "ui.config.show").get("defaults"),
        Some(&Value::Bool(false))
    );
    let b = go(&["config", "show", "--defaults"], &[], vec![], "", PLAIN);
    assert_eq!(
        sent(&b, "ui.config.show").get("defaults"),
        Some(&Value::Bool(true))
    );
}

#[test]
fn config_needs_the_cap_and_maps_refusals() {
    let o = go_caps(&["config", "check"], &[], vec![], "", PLAIN, &["ui.ls"]);
    assert_eq!(o.code, 7);
    assert!(o.err.contains("too old"), "{}", o.err);
    let d = go(
        &["config", "reload"],
        &[],
        vec![("ui.config.reload", remote("cli_disabled", "off"))],
        "",
        PLAIN,
    );
    assert_eq!(d.code, 6);
    let f = go(
        &["config", "show"],
        &[],
        vec![("ui.config.show", remote("forbidden", "no token"))],
        "",
        PLAIN,
    );
    assert_eq!(f.code, 6);
}

#[test]
fn ssh_prints_the_tab_and_maps_errors() {
    let o = go(
        &[
            "ssh",
            "me@devbox:2222",
            "--cwd",
            "~/app",
            "--cmd",
            "make test",
            "--no-hook",
        ],
        &[],
        vec![(
            "ui.ssh.open",
            ok(vec![("tab", Value::Int(41)), ("pane", Value::Int(41))]),
        )],
        "",
        PLAIN,
    );
    assert_eq!((o.code, o.out.as_str()), (0, "t41\n"));
    let m = sent(&o, "ui.ssh.open");
    assert_eq!(m.get("target"), Some(&Value::text("me@devbox:2222")));
    // A server path is never made absolute against the local directory.
    assert_eq!(m.get("cwd"), Some(&Value::text("~/app")));
    assert_eq!(m.get("cmd"), Some(&Value::text("make test")));
    assert_eq!(m.get("hook"), Some(&Value::Bool(false)));
    assert_eq!(m.get("focus"), Some(&Value::Bool(false)));
    assert_eq!(m.get("workspace"), None);
    let j = go(
        &["ssh", "devbox", "--json"],
        &[],
        vec![(
            "ui.ssh.open",
            ok(vec![("tab", Value::Int(41)), ("pane", Value::Int(41))]),
        )],
        "",
        PLAIN,
    );
    assert_eq!(j.out, "{\"tab\":\"t41\",\"pane\":\"p41\"}\n");
    assert_eq!(
        sent(&j, "ui.ssh.open").get("hook"),
        Some(&Value::Bool(true))
    );
    for code in ["ssh_unavailable", "tmux_unavailable", "tmux_failed"] {
        let e = go(
            &["ssh", "devbox"],
            &[],
            vec![("ui.ssh.open", remote(code, ""))],
            "",
            PLAIN,
        );
        assert_eq!(e.code, 1, "{code}");
        assert!(
            e.err.starts_with("shellx: ") && e.err.contains(&format!("({code})")),
            "{}",
            e.err
        );
    }
    // A host without ui.ssh: exit 7 before any ui.ssh.open is sent.
    let old = go_caps(&["ssh", "devbox"], &[], vec![], "", PLAIN, &["ui.ls"]);
    assert_eq!(old.code, 7);
    assert!(old.log.iter().all(|m| m.t != "ui.ssh.open"));
    // A too long --cmd fails before connecting.
    let long = "x".repeat(MAX_CMD + 1);
    let big = go(&["ssh", "devbox", "--cmd", &long], &[], vec![], "", PLAIN);
    assert_eq!((big.code, big.connected), (2, false));
}

#[test]
fn tmux_ls_prints_a_table_or_json() {
    let sessions = || {
        ok(vec![(
            "sessions",
            Value::Array(vec![
                Value::map(vec![
                    ("name", Value::text("main")),
                    ("windows", Value::Int(3)),
                    ("attached", Value::Int(0)),
                    ("activity", Value::Int(1_759_831_200)),
                ]),
                Value::map(vec![
                    ("name", Value::text("a\u{1b}[2Jb")),
                    ("windows", Value::Int(1)),
                    ("attached", Value::Int(2)),
                ]),
            ]),
        )])
    };
    let o = go(
        &["tmux", "ls", "--host", "devbox"],
        &[],
        vec![("ui.tmux.list", sessions())],
        "",
        PLAIN,
    );
    assert_eq!(o.code, 0);
    assert_eq!(o.out, "main\t3 windows\na[2Jb\t1 window\tattached\n");
    assert_eq!(
        sent(&o, "ui.tmux.list").get("host"),
        Some(&Value::text("devbox"))
    );
    let j = go(
        &["tmux", "ls", "--json"],
        &[],
        vec![("ui.tmux.list", sessions())],
        "",
        PLAIN,
    );
    assert!(
        j.out
            .starts_with("{\"sessions\":[{\"name\":\"main\",\"windows\":3"),
        "{}",
        j.out
    );
    assert_eq!(sent(&j, "ui.tmux.list").get("host"), None);
    let empty = go(
        &["tmux", "ls"],
        &[],
        vec![("ui.tmux.list", ok(vec![("sessions", Value::Array(vec![]))]))],
        "",
        PLAIN,
    );
    assert_eq!((empty.code, empty.out.as_str()), (0, ""));
    let none = go(
        &["tmux", "ls"],
        &[],
        vec![("ui.tmux.list", remote("tmux_unavailable", ""))],
        "",
        PLAIN,
    );
    assert_eq!(none.code, 1);
    // A host without ui.tmux: exit 7, nothing sent.
    let old = go_caps(
        &["tmux", "ls"],
        &[],
        vec![],
        "",
        PLAIN,
        &["ui.ls", "ui.ssh"],
    );
    assert_eq!(old.code, 7);
    assert!(old.log.iter().all(|m| m.t != "ui.tmux.list"));
}

#[test]
fn tmux_attach_prints_the_tab() {
    let o = go(
        &[
            "tmux", "attach", "main", "--host", "devbox", "--create", "--focus",
        ],
        &[],
        vec![(
            "ui.tmux.attach",
            ok(vec![("tab", Value::Int(7)), ("pane", Value::Int(7))]),
        )],
        "",
        PLAIN,
    );
    assert_eq!((o.code, o.out.as_str()), (0, "t7\n"));
    let m = sent(&o, "ui.tmux.attach");
    assert_eq!(m.get("name"), Some(&Value::text("main")));
    assert_eq!(m.get("host"), Some(&Value::text("devbox")));
    assert_eq!(m.get("create"), Some(&Value::Bool(true)));
    assert_eq!(m.get("focus"), Some(&Value::Bool(true)));
}

#[test]
fn ls_shows_where_a_pane_is_remote() {
    let evil = "dev\u{1b}]52;c;x\u{7}box";
    let mut t = tree(Value::Null, Value::Null, Value::Null);
    let Value::Array(ws) = &mut t else { panic!() };
    let Value::Map(w) = &mut ws[0] else { panic!() };
    let tabs = w.iter_mut().find(|(k, _)| k == "tabs").unwrap();
    let Value::Array(ts) = &mut tabs.1 else {
        panic!()
    };
    let Value::Map(tab) = &mut ts[0] else {
        panic!()
    };
    let panes = tab.iter_mut().find(|(k, _)| k == "panes").unwrap();
    let Value::Array(ps) = &mut panes.1 else {
        panic!()
    };
    let Value::Map(pane) = &mut ps[0] else {
        panic!()
    };
    pane.push((
        "remote".into(),
        Value::map(vec![
            ("kind", Value::text("tmux")),
            ("host", Value::text(evil)),
            ("tmux", Value::text("main")),
            ("state", Value::text("reconnecting")),
        ]),
    ));
    let o = go(
        &["ls"],
        &[],
        vec![("ui.ls", ok(vec![("workspaces", t)]))],
        "",
        PLAIN,
    );
    assert!(
        o.out.contains("[tmux dev]52;c;xbox:main reconnecting]"),
        "{}",
        o.out
    );
    assert!(!o.out.chars().any(|c| c.is_control() && c != '\n'));
}
