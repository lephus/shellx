// Keyboard, IME composition and paste events → terminal bytes for the share viewer.
//
// Special keys and Ctrl combinations are taken from `keydown` (the caller prevents the default).
// Printable text comes from `input` events only, because phone keyboards report most keys as
// "Unidentified" on keydown. While an IME composes (Vietnamese Telex, Gboard, iOS), nothing is sent;
// `compositionend` sends the composed text once, and the trailing composition `input` that Safari
// fires after `compositionend` is ignored.

const encoder = new TextEncoder();

const KEYS = {
  Enter: '\r',
  Backspace: '\x7f',
  Tab: '\t',
  Escape: '\x1b',
  ArrowUp: '\x1b[A',
  ArrowDown: '\x1b[B',
  ArrowRight: '\x1b[C',
  ArrowLeft: '\x1b[D',
  Home: '\x1b[H',
  End: '\x1b[F',
  Insert: '\x1b[2~',
  Delete: '\x1b[3~',
  PageUp: '\x1b[5~',
  PageDown: '\x1b[6~',
};

const COMPOSITION_INPUT = new Set(['insertCompositionText', 'insertFromComposition', 'deleteCompositionText']);

/** Ctrl + one character → C0 control byte, or null when the combination has none. */
function ctrlByte(ch) {
  if (ch.length !== 1) return null;
  const c = ch.toLowerCase();
  if (c >= 'a' && c <= 'z') return String.fromCharCode(c.charCodeAt(0) - 96);
  const table = { '@': '\x00', ' ': '\x00', '2': '\x00', '[': '\x1b', '3': '\x1b', '\\': '\x1c', '4': '\x1c',
    ']': '\x1d', '5': '\x1d', '^': '\x1e', '6': '\x1e', '_': '\x1f', '-': '\x1f', '7': '\x1f', '/': '\x1f',
    '?': '\x7f', '8': '\x7f' };
  return table[c] ?? null;
}

export function createInput({ onData }) {
  let composing = false;
  let ctrlArmed = false;
  const emit = (s) => {
    if (s) onData(encoder.encode(s));
  };

  // Text typed while the on-screen Ctrl is armed: first character becomes its control byte.
  function emitText(s) {
    if (!s) return;
    if (ctrlArmed) {
      ctrlArmed = false;
      const first = String.fromCodePoint(s.codePointAt(0));
      emit((ctrlByte(first) ?? first) + s.slice(first.length));
      return;
    }
    emit(s);
  }

  /** Feeds a DOM-like event; returns true when the caller should call preventDefault(). */
  function handle(ev) {
    switch (ev.type) {
      case 'compositionstart':
        composing = true;
        return false;
      case 'compositionupdate':
        return false;
      case 'compositionend':
        composing = false;
        emitText(ev.data ?? '');
        return false;
      case 'keydown': {
        if (composing || ev.isComposing || ev.keyCode === 229) return false;
        if (ev.metaKey) return false;
        const key = ev.key;
        if (ev.ctrlKey && !ev.altKey) {
          const b = ctrlByte(key);
          if (b !== null) {
            ctrlArmed = false;
            emit(b);
            return true;
          }
        }
        if (Object.hasOwn(KEYS, key)) {
          if (ctrlArmed && key === 'Escape') ctrlArmed = false;
          emit(key === 'Tab' && ev.shiftKey ? '\x1b[Z' : KEYS[key]);
          return true;
        }
        return false;
      }
      case 'input': {
        if (ev.isComposing || composing || COMPOSITION_INPUT.has(ev.inputType)) return false;
        switch (ev.inputType) {
          case 'deleteContentBackward':
            emit('\x7f');
            return false;
          case 'deleteContentForward':
            emit('\x1b[3~');
            return false;
          case 'insertLineBreak':
          case 'insertParagraph':
            emit('\r');
            return false;
          default:
            if (typeof ev.data === 'string') emitText(ev.data.replace(/\r?\n/g, '\r'));
            return false;
        }
      }
      case 'paste':
        if (typeof ev.text === 'string' && ev.text) emit(ev.text.replace(/\r?\n/g, '\r'));
        return true;
      default:
        return false;
    }
  }

  return {
    handle,
    /** On-screen key row button (Esc, Tab, arrows). */
    press(key) {
      if (Object.hasOwn(KEYS, key)) emit(KEYS[key]);
    },
    toggleCtrl() {
      ctrlArmed = !ctrlArmed;
      return ctrlArmed;
    },
    get ctrlArmed() {
      return ctrlArmed;
    },
    get composing() {
      return composing;
    },
  };
}
