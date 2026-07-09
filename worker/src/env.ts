export interface Env {
  FEEDBACK_KV: KVNamespace;
  REPO: string;
  ALLOWED_ORIGIN: string;
  RATE_PER_IP_PER_HOUR: string;
  GLOBAL_CAP_PER_DAY: string;
  IDEMPOTENCY_TTL_SECONDS: string;
  APPLE_APP_ID: string;
  PLAY_PACKAGE_NAME: string;
  GITHUB_APP_ID: string;
  GITHUB_APP_INSTALLATION_ID: string;
  GITHUB_APP_PRIVATE_KEY: string;
  TURNSTILE_SECRET: string;
  PLAY_SA_CLIENT_EMAIL: string;
  PLAY_SA_PRIVATE_KEY: string;
}
