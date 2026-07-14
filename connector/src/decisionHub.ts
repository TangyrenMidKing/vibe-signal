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

  beginPermission(key: string): void {
    this.activePermissionKey = key;
    this.pendingPermission = null;
  }

  beginStop(key: string): void {
    this.activeStopKey = key;
    this.pendingStop = null;
  }

  waitPermission(key: string, timeoutMs: number): Promise<PermissionDecision> {
    if (this.pendingPermission) {
      const d = this.pendingPermission;
      this.pendingPermission = null;
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
        resolve({ decision: "timeout" });
      }, timeoutMs);
      this.permissionWaiters.set(key, { resolve, timer });
    });
  }

  waitStop(key: string, timeoutMs: number): Promise<StopDecision> {
    if (this.pendingStop) {
      const d = this.pendingStop;
      this.pendingStop = null;
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
        resolve({ decision: "timeout" });
      }, timeoutMs);
      this.stopWaiters.set(key, { resolve, timer });
    });
  }

  resolvePermission(decision: Exclude<PermissionDecision, { decision: "timeout" }>): boolean {
    const key = this.activePermissionKey;
    if (key && this.permissionWaiters.has(key)) {
      const w = this.permissionWaiters.get(key)!;
      clearTimeout(w.timer);
      this.permissionWaiters.delete(key);
      w.resolve(decision);
      return true;
    }
    this.pendingPermission = decision;
    return true;
  }

  resolveStop(decision: Exclude<StopDecision, { decision: "timeout" }>): boolean {
    const key = this.activeStopKey;
    if (key && this.stopWaiters.has(key)) {
      const w = this.stopWaiters.get(key)!;
      clearTimeout(w.timer);
      this.stopWaiters.delete(key);
      w.resolve(decision);
      return true;
    }
    this.pendingStop = decision;
    return true;
  }

  clear(): void {
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
  }
}
