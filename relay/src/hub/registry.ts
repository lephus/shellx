import type { Db } from "../db/db.js";
import { FrameBudgets } from "./frame-budgets.js";
import { HubState, UserHub, type HubHost } from "./user-hub.js";

export interface HubRegistryOptions {
  db: Db;
  /** Unix milliseconds; injectable so frame-budget tests can freeze time. */
  now?: () => number;
}

/**
 * Every account's hub in this process (replaces the Durable Object namespace, spec §4.2): at most
 * one `HubState` per user id, created on first use (a connection or a REST call) and dropped once
 * it has no socket and no queued work. `forUser` hands out `UserHub` handles that always reach the
 * live state.
 */
export class HubRegistry implements HubHost {
  readonly db: Db;
  readonly now: () => number;
  readonly budgets: FrameBudgets;
  private readonly states = new Map<string, HubState>();
  private stopping = false;
  private emptyWaiters: (() => void)[] = [];

  constructor(options: HubRegistryOptions) {
    this.db = options.db;
    this.now = options.now ?? Date.now;
    this.budgets = new FrameBudgets(this.now);
  }

  forUser(userId: string): UserHub {
    return new UserHub(userId, this);
  }

  stateFor(userId: string): HubState {
    let state = this.states.get(userId);
    if (state === undefined) {
      const created = new HubState(userId, this);
      this.states.set(userId, created);
      // A caller that never queues anything must not leave the state behind.
      queueMicrotask(() => created.releaseIfIdle());
      state = created;
    }
    return state;
  }

  existingState(userId: string): HubState | undefined {
    return this.states.get(userId);
  }

  /** Accounts whose hub state is in memory right now. */
  get size(): number {
    return this.states.size;
  }

  /** True once `goAway` ran: hubs close new sockets with 1001 instead of admitting them. */
  get shuttingDown(): boolean {
    return this.stopping;
  }

  release(state: HubState): void {
    if (this.states.get(state.userId) === state) this.states.delete(state.userId);
    if (this.states.size === 0) for (const resolve of this.emptyWaiters.splice(0)) resolve();
  }

  /** Resolves when no hub state is left in memory (every socket closed, every queue drained). */
  whenEmpty(): Promise<void> {
    if (this.states.size === 0) return Promise.resolve();
    return new Promise((resolve) => this.emptyWaiters.push(resolve));
  }

  /**
   * Shutdown steps 2–3 (spec §4.3): every socket is closed with 1001 and later connections are
   * refused the same way. Resolves once every hub has drained and every socket reported its close.
   */
  async goAway(): Promise<void> {
    this.stopping = true;
    await Promise.all([...this.states.values()].map((state) => state.goAway()));
    await this.whenEmpty();
  }

  /** Drops every remaining socket without a close handshake (after the shutdown grace period). */
  terminateAll(): void {
    for (const state of this.states.values()) state.terminateAll();
  }
}
