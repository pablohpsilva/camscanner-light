import type { Env } from "./env";

/** True iff the Worker has the essential secrets to actually create issues + verify callers,
 * checked WITHOUT any external call. GitHub App (create issue) + Turnstile (universal fallback). */
export function checkHealth(env: Env): boolean {
  return Boolean(
    env.GITHUB_APP_ID &&
    env.GITHUB_APP_INSTALLATION_ID &&
    env.GITHUB_APP_PRIVATE_KEY &&
    env.TURNSTILE_SECRET
  );
}
