import { expect, test } from "bun:test";
import { copyTextToClipboard } from "./utils";

async function clipboardEnvironment(
  writeText: (text: string) => Promise<void>,
  run: (state: { writes: string[]; focused: () => unknown; original: object; removed: () => boolean }) => Promise<void>,
  fallbackResult = true,
) {
  const navigatorDescriptor = Object.getOwnPropertyDescriptor(globalThis, "navigator");
  const documentDescriptor = Object.getOwnPropertyDescriptor(globalThis, "document");
  const writes: string[] = [];
  let removed = false;
  let active: unknown;
  const original = { isConnected: true, focus: () => { active = original; } };
  active = original;
  const textarea = {
    value: "",
    style: {},
    setAttribute() {},
    focus: () => { active = textarea; },
    select() {},
    setSelectionRange() {},
  };
  Object.defineProperty(globalThis, "navigator", { configurable: true, value: { clipboard: { writeText } } });
  Object.defineProperty(globalThis, "document", {
    configurable: true,
    value: {
      get activeElement() { return active; },
      createElement: () => textarea,
      body: {
        appendChild() {},
        removeChild() { removed = true; if (active === textarea) active = null; },
      },
      execCommand(command: string) {
        expect(command).toBe("copy");
        writes.push(textarea.value);
        return fallbackResult;
      },
    },
  });
  try {
    await run({ writes, focused: () => active, original, removed: () => removed });
  } finally {
    if (navigatorDescriptor) Object.defineProperty(globalThis, "navigator", navigatorDescriptor);
    else Reflect.deleteProperty(globalThis, "navigator");
    if (documentDescriptor) Object.defineProperty(globalThis, "document", documentDescriptor);
    else Reflect.deleteProperty(globalThis, "document");
  }
}

test("an already abandoned copy never writes to either clipboard path", async () => {
  let calls = 0;
  await clipboardEnvironment(async () => { calls++; }, async ({ writes }) => {
    const controller = new AbortController();
    controller.abort();
    expect(await copyTextToClipboard("old brief", { signal: controller.signal })).toBe(false);
    expect(calls).toBe(0);
    expect(writes).toEqual([]);
  });
});

test("late rejection cannot start a fallback after its copy was abandoned", async () => {
  let rejectWrite!: (reason: Error) => void;
  const pending = new Promise<void>((_resolve, reject) => { rejectWrite = reject; });
  await clipboardEnvironment(() => pending, async ({ writes, focused, original }) => {
    const controller = new AbortController();
    const result = copyTextToClipboard("old provider", { signal: controller.signal });
    controller.abort();
    rejectWrite(new Error("permission denied after provider changed"));
    expect(await result).toBe(false);
    expect(writes).toEqual([]);
    expect(focused()).toBe(original);
  });
});

test("late native completion does not report success for an abandoned copy", async () => {
  let resolveWrite!: () => void;
  const pending = new Promise<void>((resolve) => { resolveWrite = resolve; });
  await clipboardEnvironment(() => pending, async ({ writes }) => {
    const controller = new AbortController();
    const result = copyTextToClipboard("old provider", { signal: controller.signal });
    controller.abort();
    resolveWrite();
    expect(await result).toBe(false);
    expect(writes).toEqual([]);
  });
});

test("an active native copy succeeds without invoking the fallback", async () => {
  const native: string[] = [];
  await clipboardEnvironment(async (text) => { native.push(text); }, async ({ writes }) => {
    expect(await copyTextToClipboard("current brief")).toBe(true);
    expect(native).toEqual(["current brief"]);
    expect(writes).toEqual([]);
  });
});

test("current fallback copies its actual text and restores keyboard focus", async () => {
  await clipboardEnvironment(async () => { throw new Error("permission denied"); }, async ({ writes, focused, original, removed }) => {
    expect(await copyTextToClipboard("current brief")).toBe(true);
    expect(writes).toEqual(["current brief"]);
    expect(removed()).toBe(true);
    expect(focused()).toBe(original);
  });
});

test("failed fallback still restores focus and reports failure", async () => {
  await clipboardEnvironment(async () => { throw new Error("permission denied"); }, async ({ focused, original, removed }) => {
    expect(await copyTextToClipboard("current brief")).toBe(false);
    expect(removed()).toBe(true);
    expect(focused()).toBe(original);
  }, false);
});
