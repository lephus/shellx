import { useEffect, useRef, useState } from "react";
import type { ChatMessage } from "./store";
import type { AutomationLabelResolver } from "./labels";
import type { ChoiceSet } from "./types";

function Choices({
  choices,
  label,
  onAnswer,
  disabled,
}: {
  choices: ChoiceSet;
  label: AutomationLabelResolver;
  onAnswer: (text: string) => void;
  disabled: boolean;
}) {
  const [selected, setSelected] = useState<string[]>([]);
  const toggle = (option: string) => {
    if (!choices.multi) {
      onAnswer(option);
      return;
    }
    setSelected((s) => (s.includes(option) ? s.filter((o) => o !== option) : [...s, option]));
  };
  return (
    <div className="au-choices">
      {choices.question !== "" ? <p className="au-choices-q">{choices.question}</p> : null}
      <div className="au-chips">
        {choices.options.map((option) => {
          const on = selected.includes(option);
          return (
            <button
              key={option}
              type="button"
              className="au-chip"
              data-selected={on ? "true" : "false"}
              aria-pressed={choices.multi ? on : undefined}
              disabled={disabled}
              onClick={() => toggle(option)}
            >
              {on ? "✓ " : ""}
              {option}
            </button>
          );
        })}
      </div>
      {choices.multi ? (
        <button
          type="button"
          className="au-button au-primary"
          disabled={disabled || selected.length === 0}
          onClick={() => onAnswer(selected.join(", "))}
        >
          {label("chooseSend")}
        </button>
      ) : null}
    </div>
  );
}

export function ChatTranscript({
  label,
  messages,
  streaming,
  busy,
  onAnswer,
}: {
  label: AutomationLabelResolver;
  messages: ChatMessage[];
  streaming: string | null;
  busy: boolean;
  onAnswer: (text: string) => void;
}) {
  const endRef = useRef<HTMLDivElement>(null);
  const lastAssistant = [...messages].reverse().find((m) => m.role === "assistant")?.id;
  useEffect(() => {
    endRef.current?.scrollIntoView?.({ block: "end" });
  }, [messages, streaming, busy]);
  return (
    <div className="au-msgs" aria-live="polite">
      {messages.map((m) =>
        m.role === "user" ? (
          <div key={m.id} className="au-msg-user">{m.text}</div>
        ) : m.role === "error" ? (
          <div key={m.id} className="au-msg-error" role="alert">{label("creatorFailed", { message: m.text })}</div>
        ) : (
          <div key={m.id} className="au-msg-ai">
            <div className="au-msg-who">{label("assistantName")}</div>
            <div className="au-msg-text">{m.text}</div>
            {m.choices && m.id === lastAssistant ? (
              <Choices choices={m.choices} label={label} onAnswer={onAnswer} disabled={busy} />
            ) : null}
          </div>
        ),
      )}
      {streaming !== null ? (
        <div className="au-msg-ai">
          <div className="au-msg-who">{label("assistantName")}</div>
          <div className="au-msg-text">{streaming}</div>
        </div>
      ) : null}
      {busy && (streaming === null || streaming === "") ? (
        <div className="au-msg-ai au-thinking" data-thinking="true" role="status">
          <div className="au-msg-who">{label("assistantName")}</div>
          <div className="au-msg-text">
            <span className="au-thinking-dots" aria-hidden="true">
              <span />
              <span />
              <span />
            </span>
            {label("thinking")}
          </div>
        </div>
      ) : null}
      <div ref={endRef} />
    </div>
  );
}
