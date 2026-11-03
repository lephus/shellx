import { useState } from "react";
import { ChatTranscript } from "./ChatTranscript";
import { DraftCard } from "./DraftCard";
import type { AutomationLabelResolver } from "./labels";
import { PerspectiveGrid } from "./PerspectiveGrid";
import { draftIsReady, type AutomationsStore, type CreatorState, type CreatorType } from "./store";

const TYPES: { value: CreatorType; key: "typeAuto" | "typeSkill" | "typeWorkflow" | "typeCronjob" }[] = [
  { value: "auto", key: "typeAuto" },
  { value: "skill", key: "typeSkill" },
  { value: "workflow", key: "typeWorkflow" },
  { value: "cronjob", key: "typeCronjob" },
];

export function CreatorView({
  store,
  creator,
  label,
  reduceMotion,
}: {
  store: AutomationsStore;
  creator: CreatorState;
  label: AutomationLabelResolver;
  reduceMotion: boolean;
}) {
  const [text, setText] = useState("");
  const ready = draftIsReady(creator);
  const firstMessage = creator.messages.every((m) => m.role !== "user");
  const submit = (value: string) => {
    if (creator.busy || value.trim() === "") return;
    setText("");
    void store.sendMessage(value);
  };
  return (
    <div className="au-creator">
      <section className="au-chat">
        <header className="au-chat-head">
          <button type="button" className="au-button" onClick={() => void store.leaveCreator()}>
            ← {label("back")}
          </button>
          <h2>{label("creatorTitle")}</h2>
        </header>
        <ChatTranscript
          label={label}
          messages={creator.messages}
          streaming={creator.streaming}
          busy={creator.busy}
          onAnswer={submit}
        />
        <form
          className="au-input"
          onSubmit={(e) => {
            e.preventDefault();
            submit(text);
          }}
        >
          <textarea
            className="au-textarea"
            value={text}
            rows={2}
            placeholder={label("inputPlaceholder")}
            aria-label={label("inputPlaceholder")}
            onChange={(e) => setText(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing) {
                e.preventDefault();
                submit(text);
              }
            }}
          />
          <div className="au-input-row">
            <label className="au-type">
              <span>{label("typePicker")}</span>
              <select
                value={creator.type}
                disabled={!firstMessage}
                onChange={(e) => store.setCreatorType(e.target.value as CreatorType)}
              >
                {TYPES.map((t) => (
                  <option key={t.value} value={t.value}>{label(t.key)}</option>
                ))}
              </select>
            </label>
            <button type="submit" className="au-button au-primary au-send" disabled={creator.busy || text.trim() === ""}>
              {label("send")}
            </button>
          </div>
        </form>
      </section>
      <section className="au-draft-pane">
        <PerspectiveGrid busy={creator.busy} reduceMotion={reduceMotion} />
        <div className="au-draft-wrap">
          {creator.draft ? (
            <>
              <DraftCard label={label} draft={creator.draft} issues={creator.issues} ready={ready} />
              <div className="au-draft-actions">
                <button
                  type="button"
                  className="au-button au-primary"
                  disabled={!ready || creator.saving}
                  onClick={() => void store.save()}
                >
                  {creator.saving ? label("saving") : label("save")}
                </button>
                <button type="button" className="au-button" onClick={() => document.querySelector<HTMLTextAreaElement>(".au-textarea")?.focus()}>
                  {label("keepEditing")}
                </button>
              </div>
            </>
          ) : (
            <p className="au-draft-empty">{label("draftEmpty")}</p>
          )}
        </div>
      </section>
    </div>
  );
}
