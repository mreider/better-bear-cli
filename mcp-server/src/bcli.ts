import { execFile, spawn } from "node:child_process";
import { access, constants } from "node:fs/promises";
import { homedir } from "node:os";
import { join } from "node:path";

const TIMEOUT_MS = 30_000;
const MAX_BUFFER = 10 * 1024 * 1024; // 10MB
const REAUTH_TIMEOUT_MS = 120_000; // 2 minutes

export class BcliError extends Error {
  constructor(
    message: string,
    public readonly stderr: string,
    public readonly exitCode: number | null,
  ) {
    super(message);
    this.name = "BcliError";
  }
}

export class AuthError extends BcliError {
  constructor(stderr: string, exitCode: number | null) {
    super(
      "iCloud session expired. Re-authentication required.",
      stderr,
      exitCode,
    );
    this.name = "AuthError";
  }
}

export class NotFoundError extends BcliError {
  constructor(stderr: string, exitCode: number | null) {
    super("Note not found.", stderr, exitCode);
    this.name = "NotFoundError";
  }
}

export class NetworkError extends BcliError {
  constructor(stderr: string, exitCode: number | null) {
    super(
      "Network error communicating with iCloud.",
      stderr,
      exitCode,
    );
    this.name = "NetworkError";
  }
}

let cachedBcliPath: string | null = null;

async function fileExists(path: string): Promise<boolean> {
  try {
    await access(path, constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

function whichSync(cmd: string): Promise<string | null> {
  return new Promise((resolve) => {
    execFile("which", [cmd], (err, stdout) => {
      if (err) {
        resolve(null);
      } else {
        resolve(stdout.trim() || null);
      }
    });
  });
}

export async function findBcli(): Promise<string> {
  if (cachedBcliPath) return cachedBcliPath;

  // 1. Explicit env var
  const envPath = process.env.BCLI_PATH;
  if (envPath && (await fileExists(envPath))) {
    cachedBcliPath = envPath;
    return envPath;
  }

  // 2. PATH lookup
  const whichResult = await whichSync("bcli");
  if (whichResult) {
    cachedBcliPath = whichResult;
    return whichResult;
  }

  // 3. Common install locations
  const candidates = [
    join(homedir(), ".local", "bin", "bcli"),
    "/usr/local/bin/bcli",
    "/opt/homebrew/bin/bcli",
  ];

  for (const candidate of candidates) {
    if (await fileExists(candidate)) {
      cachedBcliPath = candidate;
      return candidate;
    }
  }

  throw new Error(
    "bcli not found. Install it from https://github.com/mreider/better-bear-cli/releases " +
      "or set BCLI_PATH environment variable.",
  );
}

function classifyError(
  stderr: string,
  exitCode: number | null,
): BcliError {
  const lower = stderr.toLowerCase();
  if (
    lower.includes("auth token expired") ||
    lower.includes("not authenticated")
  ) {
    return new AuthError(stderr, exitCode);
  }
  if (lower.includes("note not found")) {
    return new NotFoundError(stderr, exitCode);
  }
  if (
    lower.includes("network error") ||
    lower.includes("cloudkit api error")
  ) {
    return new NetworkError(stderr, exitCode);
  }
  return new BcliError(stderr.trim() || "bcli command failed", stderr, exitCode);
}

export function execBcli(
  args: string[],
): Promise<{ stdout: string; stderr: string }> {
  return new Promise(async (resolve, reject) => {
    const bcliPath = await findBcli();
    execFile(
      bcliPath,
      args,
      { timeout: TIMEOUT_MS, maxBuffer: MAX_BUFFER },
      (error, stdout, stderr) => {
        if (error) {
          reject(classifyError(stderr || error.message, error.code ? null : 1));
        } else {
          resolve({ stdout, stderr });
        }
      },
    );
  });
}

export function execBcliWithStdin(
  args: string[],
  input: string,
): Promise<{ stdout: string; stderr: string }> {
  return new Promise(async (resolve, reject) => {
    const bcliPath = await findBcli();
    const child = spawn(bcliPath, args, {
      stdio: ["pipe", "pipe", "pipe"],
    });

    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (data: Buffer) => {
      stdout += data.toString();
    });
    child.stderr.on("data", (data: Buffer) => {
      stderr += data.toString();
    });

    child.on("close", (code) => {
      if (code !== 0) {
        reject(classifyError(stderr, code));
      } else {
        resolve({ stdout, stderr });
      }
    });

    child.on("error", (err) => {
      reject(new BcliError(err.message, "", null));
    });

    const timer = setTimeout(() => {
      child.kill();
      reject(new BcliError("bcli command timed out", "", null));
    }, TIMEOUT_MS);

    child.on("close", () => clearTimeout(timer));

    child.stdin.write(input);
    child.stdin.end();
  });
}

// Re-auth mutex: only one re-auth attempt at a time
let reauthPromise: Promise<void> | null = null;

export async function performReauth(): Promise<void> {
  // If a re-auth is already in flight, wait for it
  if (reauthPromise) {
    return reauthPromise;
  }

  reauthPromise = doReauth();
  try {
    await reauthPromise;
  } finally {
    reauthPromise = null;
  }
}

function doReauth(): Promise<void> {
  return new Promise(async (resolve, reject) => {
    const bcliPath = await findBcli();
    const child = spawn(bcliPath, ["auth"], {
      stdio: "ignore",
      detached: false,
    });

    const timer = setTimeout(() => {
      child.kill();
      reject(
        new BcliError(
          "Session expired. A sign-in window was opened but timed out after 2 minutes. " +
            "Run 'bcli auth' manually to re-authenticate.",
          "",
          null,
        ),
      );
    }, REAUTH_TIMEOUT_MS);

    child.on("close", (code) => {
      clearTimeout(timer);
      if (code === 0) {
        resolve();
      } else {
        reject(
          new BcliError(
            "Re-authentication failed. Run 'bcli auth' manually.",
            "",
            code,
          ),
        );
      }
    });

    child.on("error", (err) => {
      clearTimeout(timer);
      reject(new BcliError(`Failed to launch bcli auth: ${err.message}`, "", null));
    });
  });
}

export async function execBcliWithReauth(
  args: string[],
): Promise<{ stdout: string; stderr: string }> {
  try {
    return await execBcli(args);
  } catch (error) {
    if (error instanceof AuthError) {
      await performReauth();
      return await execBcli(args);
    }
    throw error;
  }
}

export async function execBcliWithStdinAndReauth(
  args: string[],
  input: string,
): Promise<{ stdout: string; stderr: string }> {
  try {
    return await execBcliWithStdin(args, input);
  } catch (error) {
    if (error instanceof AuthError) {
      await performReauth();
      return await execBcliWithStdin(args, input);
    }
    throw error;
  }
}
