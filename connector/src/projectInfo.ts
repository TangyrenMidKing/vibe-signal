import * as fs from "fs";
import * as path from "path";
import { execFileSync } from "child_process";

export interface ProjectRepoInfo {
  /** Folder / workspace name, e.g. "Jareturn" */
  project?: string;
  /** Git identity, preferably "owner/repo", else root folder name */
  repo?: string;
  /** Absolute cwd from Codex */
  cwd?: string;
}

const cache = new Map<string, ProjectRepoInfo>();

function findGitRoot(start: string): string | undefined {
  let dir = path.resolve(start);
  for (let i = 0; i < 24; i++) {
    const gitPath = path.join(dir, ".git");
    if (fs.existsSync(gitPath)) return dir;
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return undefined;
}

function parseRemote(url: string): string | undefined {
  const trimmed = url.trim().replace(/\.git$/i, "");
  // git@github.com:owner/repo
  let m = trimmed.match(/[:/]([^/]+\/[^/]+?)(?:\.git)?$/i);
  if (m) return m[1].replace(/\.git$/i, "");
  // https://github.com/owner/repo
  m = trimmed.match(/https?:\/\/[^/]+\/([^/]+\/[^/]+)/i);
  if (m) return m[1].replace(/\.git$/i, "");
  return undefined;
}

function remoteFromGit(cwd: string): string | undefined {
  try {
    const out = execFileSync("git", ["remote", "get-url", "origin"], {
      cwd,
      encoding: "utf8",
      timeout: 1500,
      windowsHide: true,
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    return parseRemote(out) ?? undefined;
  } catch {
    return undefined;
  }
}

/**
 * Derive display project + repo names from a Codex session cwd.
 */
export function resolveProjectRepo(cwd?: string): ProjectRepoInfo {
  if (!cwd || typeof cwd !== "string") return {};
  const normalized = path.resolve(cwd);
  const hit = cache.get(normalized);
  if (hit) return hit;

  const project = path.basename(normalized) || undefined;
  const gitRoot = findGitRoot(normalized);
  let repo: string | undefined;
  if (gitRoot) {
    repo = remoteFromGit(gitRoot) ?? path.basename(gitRoot);
  }

  const info: ProjectRepoInfo = {
    project,
    repo,
    cwd: normalized,
  };
  cache.set(normalized, info);
  return info;
}
