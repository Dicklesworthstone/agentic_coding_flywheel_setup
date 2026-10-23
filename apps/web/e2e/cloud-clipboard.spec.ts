import { expect, test, type Page } from "@playwright/test";

type ClipboardProbe = Window & {
  clipboardWrites: string[];
  clipboardRequests: number;
  rejectPendingCopy: () => void;
};

async function installClipboardProbe(page: Page, mode: "pending-first" | "fallback" | "denied") {
  // Control permission outcomes only; the real page, hooks, DOM fallback,
  // textarea selection/focus, provider changes and instruction text still run.
  await page.addInitScript(({ mode }) => {
    const probe = window as unknown as ClipboardProbe;
    probe.clipboardWrites = [];
    probe.clipboardRequests = 0;
    let calls = 0;
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: {
        writeText(text: string) {
          calls++;
          probe.clipboardRequests = calls;
          if (mode === "pending-first" && calls === 1) {
            return new Promise<void>((_resolve, reject) => {
              probe.rejectPendingCopy = () => reject(new Error("Clipboard permission rejected"));
            });
          }
          if (mode !== "pending-first") return Promise.reject(new Error("Clipboard permission rejected"));
          probe.clipboardWrites.push(text);
          return Promise.resolve();
        },
      },
    });
    document.execCommand = (command: string) => {
      if (command !== "copy" || mode === "denied") return false;
      probe.clipboardWrites.push((document.activeElement as HTMLTextAreaElement).value);
      return true;
    };
  }, { mode });
}

async function rejectPendingCopy(page: Page) {
  await page.evaluate(async () => {
    (window as unknown as ClipboardProbe).rejectPendingCopy();
    // Let the abandoned request and any erroneous fallback finish.
    await new Promise((resolve) => setTimeout(resolve, 50));
  });
}

async function chooseCodex(page: Page) {
  await page.locator("label").filter({
    has: page.getByRole("radio", { name: "ChatGPT / Codex Hosted test", exact: true }),
  }).click();
  await expect(page.getByRole("button", { name: "Copy full instructions for ChatGPT / Codex", exact: true })).toBeVisible();
}

test("an abandoned provider brief cannot overwrite the newer copied brief through fallback", async ({ page }) => {
  await installClipboardProbe(page, "pending-first");
  await page.goto("/cloud-agents");
  const claude = page.getByRole("button", { name: "Copy full instructions for Claude Code", exact: true });
  await claude.click();
  await expect(claude).toHaveText("Copying…");
  await chooseCodex(page);
  const codex = page.getByRole("button", { name: "Copy full instructions for ChatGPT / Codex", exact: true });
  await codex.click();
  await expect(codex).toHaveText("Full instructions copied");
  await rejectPendingCopy(page);
  const writes = await page.evaluate(() => (window as unknown as ClipboardProbe).clipboardWrites);
  expect(writes).toHaveLength(1);
  expect(writes[0].startsWith("# Set up Agent Flywheel for ChatGPT / Codex\n")).toBe(true);
  await expect(codex).toBeFocused();
});

test("a pending copy keeps focus and ignores repeated keyboard activation", async ({ page }) => {
  await installClipboardProbe(page, "pending-first");
  await page.goto("/cloud-agents");
  const copy = page.getByRole("button", { name: "Copy full instructions for Claude Code", exact: true });
  await copy.click();
  await expect(copy).toHaveText("Copying…");
  await expect(copy).toHaveAttribute("aria-disabled", "true");
  await expect(copy).toBeFocused();
  await copy.press("Enter");
  await copy.press("Space");
  expect(await page.evaluate(() => (window as unknown as ClipboardProbe).clipboardRequests)).toBe(1);
  await expect(copy).toHaveText("Copying…");
});

test("an abandoned subset request cannot copy its old recipe after a provider change", async ({ page }) => {
  await installClipboardProbe(page, "pending-first");
  await page.goto("/cloud-agents");
  await page.getByText("Options and environment variables", { exact: true }).click();
  const claude = page.getByRole("button", { name: "Copy subset install example for Claude Code", exact: true });
  await claude.click();
  await expect(claude).toHaveText("Copying…");
  await chooseCodex(page);
  const codex = page.getByRole("button", { name: "Copy subset install example for ChatGPT / Codex", exact: true });
  await codex.click();
  await expect(codex).toHaveText("Copied");
  await rejectPendingCopy(page);
  const writes = await page.evaluate(() => (window as unknown as ClipboardProbe).clipboardWrites);
  expect(writes).toHaveLength(1);
  expect(writes[0]).toContain("ACFS_CLOUD_AGENT=codex");
  expect(writes[0]).not.toContain("ACFS_CLOUD_AGENT=claude");
  await expect(codex).toBeFocused();
});

test("changing the subset recipe clears its previous copy confirmation", async ({ page }) => {
  await installClipboardProbe(page, "fallback");
  await page.goto("/cloud-agents");
  await page.getByText("Options and environment variables", { exact: true }).click();
  const oldSubset = page.getByRole("button", { name: "Copy subset install example for Claude Code", exact: true });
  await oldSubset.click();
  await expect(oldSubset).toHaveText("Copied");
  await chooseCodex(page);
  // Read immediately after the provider commits. Waiting for "Copy" would also
  // pass the old code once its unrelated two-second confirmation expires.
  expect(await page.getByRole("button", { name: "Copy subset install example for ChatGPT / Codex", exact: true }).innerText()).toBe("Copy");
  await page.locator("label").filter({
    has: page.getByRole("radio", { name: "Claude Code Hosted test", exact: true }),
  }).click();
  // Returning to the original source must not resurrect its old confirmation.
  expect(await page.getByRole("button", { name: "Copy subset install example for Claude Code", exact: true }).innerText()).toBe("Copy");
});

test("timed-out permission requests keep manual instructions visible and never start late fallback", async ({ page }) => {
  await installClipboardProbe(page, "pending-first");
  await page.goto("/cloud-agents");
  const copy = page.getByRole("button", { name: "Copy full instructions for Claude Code", exact: true });
  await copy.click();
  await expect(copy).toHaveText("Copying…");
  await expect(page.getByRole("alert").filter({ hasText: "Clipboard access failed" })).toBeVisible({ timeout: 10000 });
  await expect(copy).toBeEnabled();
  await expect(page.getByRole("region", { name: "Full agent instructions for Claude Code", exact: true })).toContainText("# Set up Agent Flywheel for Claude Code");
  await rejectPendingCopy(page);
  expect(await page.evaluate(() => (window as unknown as ClipboardProbe).clipboardWrites)).toEqual([]);
  await expect(page.getByRole("alert").filter({ hasText: "Clipboard access failed" })).toBeVisible();
});

test("current fallback retains instruction text and keyboard focus", async ({ page }) => {
  await installClipboardProbe(page, "fallback");
  await page.goto("/cloud-agents");
  const copy = page.getByRole("button", { name: "Copy full instructions for Claude Code", exact: true });
  await copy.click();
  await expect(copy).toHaveText("Full instructions copied");
  await expect(copy).toBeFocused();
  const writes = await page.evaluate(() => (window as unknown as ClipboardProbe).clipboardWrites);
  expect(writes).toHaveLength(1);
  expect(writes[0].startsWith("# Set up Agent Flywheel for Claude Code\n")).toBe(true);
});

test("denied clipboard access leaves the full selectable brief and retry available", async ({ page }) => {
  await installClipboardProbe(page, "denied");
  await page.goto("/cloud-agents");
  const copy = page.getByRole("button", { name: "Copy full instructions for Claude Code", exact: true });
  await copy.click();
  await expect(page.getByRole("alert").filter({ hasText: "Clipboard access failed" })).toBeVisible();
  await expect(copy).toBeEnabled();
  await expect(page.getByRole("region", { name: "Full agent instructions for Claude Code", exact: true })).toContainText("# Set up Agent Flywheel for Claude Code");
});
