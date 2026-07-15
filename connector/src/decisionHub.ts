import type { PermissionDecision, StopDecision } from "./types";

type Waiter<T> = {
  resolve: (value: T) => void;
  timer: NodeJS.Timeout;
};

/**
 * Queues pending decisions for long-polling hook scripts.
 * Phone/watch commands resolve the waiters.
 */
export class DecisionHub {
  private permissionWaiters = new Map<string, Waiter<PermissionDecision>>();
  private stopWaiters = new Map<string, Waiter<StopDecision>>();
  private pendingPermission: PermissionDecision | null = null;
  private pendingStop: StopDecision | null = null;
  private activePermissionKey: string | null = null;
  private activeStopKey: string | null = null;
  private permissionStartTimer?: NodeJS.Timeout;
  private stopStartTimer?: NodeJS.Timeout;

  // A phone can receive the state broadcast just before the hook begins its
  // long-poll. Keep that short hand-off window, but never retain a command
  // when Codex is not actually waiting for one.
  private static readonly HANDOFF_WINDOW_MS = 10_000;

  beginPermission(key: string): void {
    if (this.permissionStartTimer) clearTimeout(this.permissionStartTimer);
    this.activePermissionKey = key;
    this.pendingPermission = null;
    this.permissionStartTimer = setTimeout(() => {
      this.activePermissionKey = null;
      this.pendingPermission = null;
    }, DecisionHub.HANDOFF_WINDOW_MS);
  }

  beginStop(key: string): void {
    if (this.stopStartTimer) clearTimeout(this.stopStartTimer);
    this.activeStopKey = key;
    this.pendingStop = null;
    this.stopStartTimer = setTimeout(() => {
      this.activeStopKey = null;
      this.pendingStop = null;
    }, DecisionHub.HANDOFF_WINDOW_MS);
  }

  waitPermission(key: string, timeoutMs: number): Promise<PermissionDecision> {
    if (this.activePermissionKey !== key) {
      return Promise.resolve({ decision: "timeout" });
    }
    if (this.permissionStartTimer) clearTimeout(this.permissionStartTimer);
    if (this.pendingPermission) {
      const d = this.pendingPermission;
      this.pendingPermission = null;
      this.activePermissionKey = null;
      return Promise.resolve(d);
    }
    return new Promise((resolve) => {
      const existing = this.permissionWaiters.get(key);
      if (existing) {
        clearTimeout(existing.timer);
        existing.resolve({ decision: "timeout" });
      }
      const timer = setTimeout(() => {
        this.permissionWaiters.delete(key);
        this.activePermissionKey = null;
        resolve({ decision: "timeout" });
      }, timeoutMs);
      this.permissionWaiters.set(key, { resolve, timer });
    });
  }

  waitStop(key: string, timeoutMs: number): Promise<StopDecision> {
    if (this.activeStopKey !== key) {
      return Promise.resolve({ decision: "timeout" });
    }
    if (this.stopStartTimer) clearTimeout(this.stopStartTimer);
    if (this.pendingStop) {
      const d = this.pendingStop;
      this.pendingStop = null;
      this.activeStopKey = null;
      return Promise.resolve(d);
    }
    return new Promise((resolve) => {
      const existing = this.stopWaiters.get(key);
      if (existing) {
        clearTimeout(existing.timer);
        existing.resolve({ decision: "timeout" });
      }
      const timer = setTimeout(() => {
        this.stopWaiters.delete(key);
        this.activeStopKey = null;
        resolve({ decision: "timeout" });
      }, timeoutMs);
      this.stopWaiters.set(key, { resolve, timer });
    });
  }

  resolvePermission(decision: Exclude<PermissionDecision, { decision: "timeout" }>): boolean {
    const key = this.activePermissionKey;
    if (!key) return false;
    if (key && this.permissionWaiters.has(key)) {
      const w = this.permissionWaiters.get(key)!;
      clearTimeout(w.timer);
      this.permissionWaiters.delete(key);
      this.activePermissionKey = null;
      w.resolve(decision);
      return true;
    }
    this.pendingPermission = decision;
    return true;
  }

  resolveStop(decision: Exclude<StopDecision, { decision: "timeout" }>): boolean {
    const key = this.activeStopKey;
    if (!key) return false;
    if (key && this.stopWaiters.has(key)) {
      const w = this.stopWaiters.get(key)!;
      clearTimeout(w.timer);
      this.stopWaiters.delete(key);
      this.activeStopKey = null;
      w.resolve(decision);
      return true;
    }
    this.pendingStop = decision;
    return true;
  }

  clear(): void {
    if (this.permissionStartTimer) clearTimeout(this.permissionStartTimer);
    if (this.stopStartTimer) clearTimeout(this.stopStartTimer);
    for (const w of this.permissionWaiters.values()) {
      clearTimeout(w.timer);
      w.resolve({ decision: "timeout" });
    }
    for (const w of this.stopWaiters.values()) {
      clearTimeout(w.timer);
      w.resolve({ decision: "timeout" });
    }
    this.permissionWaiters.clear();
    this.stopWaiters.clear();
    this.activePermissionKey = null;
    this.activeStopKey = null;
    this.pendingPermission = null;
    this.pendingStop = null;
  }
}
