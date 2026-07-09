const ZWSP = "​";

export function neutralizeMentions(s: string): string {
  return s.replace(/([@#])/g, `$1${ZWSP}`);
}

export function fenceBlock(s: string): string {
  // Collapse any backtick run so the user cannot break out of the fence.
  const safe = s.replace(/`{3,}/g, "``");
  return "```\n" + safe + "\n```";
}

export function obfuscateEmail(s: string): string {
  return s.replace(/@/g, " [at] ");
}

export function slugTitle(category: string, message: string): string {
  const firstLine = message.split(/\r?\n/)[0] ?? "";
  const cleaned = neutralizeMentions(firstLine).replace(/\s+/g, " ").trim();
  const prefix = `[${category}] `;
  const room = 80 - prefix.length;
  return prefix + (cleaned.length > room ? cleaned.slice(0, room - 1) + "…" : cleaned);
}
