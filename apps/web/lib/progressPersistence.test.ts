import { afterEach, describe, expect, test } from "bun:test";
import {
  addCompletedLesson,
  COMPLETED_LESSONS_CHANGED_EVENT,
  COMPLETED_LESSONS_KEY,
  TOTAL_LESSONS,
} from "./lessonProgress";
import {
  addCompletedStep,
  canAccessWizardStep,
  COMPLETED_STEPS_CHANGED_EVENT,
  COMPLETED_STEPS_KEY,
  getCompletedSteps,
  getNextReachableWizardStep,
  markStepComplete,
  setCompletedSteps,
  TOTAL_STEPS,
} from "./wizardSteps";
import {
  ACFS_REF_KEY,
  CREATE_VPS_CHECKLIST_KEY,
  getACFSRef,
  getCreateVPSChecklist,
  getCheckedServices,
  getSSHUsername,
  getVPSReadinessSelection,
  getVPSIP,
  isCreateVPSChecklistComplete,
  normalizeGitRef,
  normalizeSSHUsername,
  setACFSRef,
  setCheckedServices,
  setCreateVPSChecklist,
  setInstallMode,
  setSSHUsername,
  setVPSReadinessSelection,
  setVPSIP,
  VPS_READINESS_SELECTION_KEY,
} from "./userPreferences";
import {
  isPrivateWizardPath,
  queryContainsSensitiveState,
  sanitizeSensitiveNavigationUrl,
  stripSensitiveQueryState,
  urlContainsSensitiveState,
  vendorEventIsPrivacySafe,
  withCurrentSearch,
} from "./utils";
import {
  analyticsPayloadIsPrivacySafe,
  analyticsContextContainsSensitiveState,
  commandCopyAnalyticsProperties,
  disableAnalyticsForDocument,
  getFunnelData,
  getLessonFunnelData,
  getOrCreateUserId,
  isAnalyticsPrivacyAllowed,
  sanitizeAnalyticsReferrer,
} from "./analytics";

type StorageController = {
  dispatchCalls: Event[];
  getCurrentUrl: () => string | null;
  getStoredValue: (key: string) => string | null;
};

const originalWindow = globalThis.window;
const originalLocalStorage = globalThis.localStorage;
const originalNavigator = globalThis.navigator;
const VPS_IP_TEST_KEY = "agent-flywheel-vps-ip";
const SSH_USERNAME_TEST_KEY = "agent-flywheel-ssh-username";
const CHECKED_SERVICES_TEST_KEY = "agent-flywheel-checked-services";

function installMockBrowser(options?: {
  failReplaceState?: boolean;
  failSetItemForKey?: string;
  globalPrivacyControl?: boolean;
  initialValues?: Record<string, string>;
  navigatorDoNotTrack?: string;
  url?: string;
  windowDoNotTrack?: string;
}): StorageController {
  const dispatchCalls: Event[] = [];
  const storage = new Map(Object.entries(options?.initialValues ?? {}));
  let currentUrl = options?.url ? new URL(options.url) : null;
  let historyState: unknown = null;

  const windowValue = {
    doNotTrack: options?.windowDoNotTrack,
    dispatchEvent(event: Event) {
      dispatchCalls.push(event);
      return true;
    },
  };

  if (currentUrl) {
    Object.defineProperty(windowValue, "location", {
      configurable: true,
      get() {
        return currentUrl;
      },
    });
    Object.defineProperty(windowValue, "history", {
      configurable: true,
      value: {
        get state() {
          return historyState;
        },
        replaceState(state: unknown, _unused: string, url?: string | URL | null) {
          if (options?.failReplaceState) throw new Error("history blocked");
          historyState = state;
          if (url) {
            currentUrl = new URL(String(url), currentUrl?.href);
          }
        },
      },
    });
  }

  Object.defineProperty(globalThis, "window", {
    configurable: true,
    value: windowValue,
  });

  Object.defineProperty(globalThis, "localStorage", {
    configurable: true,
    value: {
      getItem(key: string) {
        return storage.get(key) ?? null;
      },
      setItem(key: string, value: string) {
        if (key === options?.failSetItemForKey) {
          throw new Error("storage blocked");
        }
        storage.set(key, value);
      },
      removeItem(key: string) {
        storage.delete(key);
      },
    },
  });

  Object.defineProperty(globalThis, "navigator", {
    configurable: true,
    value: {
      globalPrivacyControl: options?.globalPrivacyControl,
      doNotTrack: options?.navigatorDoNotTrack,
    },
  });

  return {
    dispatchCalls,
    getCurrentUrl() {
      return currentUrl?.toString() ?? null;
    },
    getStoredValue(key: string) {
      return storage.get(key) ?? null;
    },
  };
}

afterEach(() => {
  Object.defineProperty(globalThis, "window", {
    configurable: true,
    value: originalWindow,
  });
  Object.defineProperty(globalThis, "localStorage", {
    configurable: true,
    value: originalLocalStorage,
  });
  Object.defineProperty(globalThis, "navigator", {
    configurable: true,
    value: originalNavigator,
  });
});

describe("progress persistence guards", () => {
  test("addCompletedLesson ignores invalid lesson ids", () => {
    const current = [0, 1];

    expect(addCompletedLesson(current, -1)).toBe(current);
    expect(addCompletedLesson(current, TOTAL_LESSONS)).toBe(current);
  });

  test("addCompletedStep ignores invalid step ids", () => {
    const current = [1, 2];

    expect(addCompletedStep(current, 0)).toBe(current);
    expect(addCompletedStep(current, TOTAL_STEPS + 1)).toBe(current);
  });

  test("setCompletedSteps only emits when persistence succeeds", () => {
    const successBrowser = installMockBrowser();
    expect(setCompletedSteps([3, 1, 1, 2, 2.5])).toBe(true);
    expect(successBrowser.getStoredValue(COMPLETED_STEPS_KEY)).toBe("[1,2,3]");
    expect(
      successBrowser.dispatchCalls.some(
        (event) => event.type === COMPLETED_STEPS_CHANGED_EVENT
      )
    ).toBe(true);

    const failingBrowser = installMockBrowser({
      failSetItemForKey: COMPLETED_STEPS_KEY,
    });
    expect(setCompletedSteps([1, 2])).toBe(false);
    expect(failingBrowser.getStoredValue(COMPLETED_STEPS_KEY)).toBeNull();
    expect(
      failingBrowser.dispatchCalls.some(
        (event) => event.type === COMPLETED_STEPS_CHANGED_EVENT
      )
    ).toBe(false);
  });

  test("wizard progress ignores fractional stored step ids", () => {
    const browser = installMockBrowser({
      initialValues: {
        [COMPLETED_STEPS_KEY]: JSON.stringify([1, 2, 2.5, 3]),
      },
    });

    expect(getCompletedSteps()).toEqual([1, 2, 3]);
    expect(getNextReachableWizardStep(getCompletedSteps()).id).toBe(4);
    expect(canAccessWizardStep(getCompletedSteps(), 4)).toBe(true);

    expect(markStepComplete(4)).toEqual([1, 2, 3, 4]);
    expect(browser.getStoredValue(COMPLETED_STEPS_KEY)).toBe("[1,2,3,4]");
  });

  test("stored wizard progress overrides and clears stale URL fallback state", () => {
    const browser = installMockBrowser({
      initialValues: {
        [COMPLETED_STEPS_KEY]: JSON.stringify([1, 2]),
      },
      url: "https://example.test/wizard/accounts?steps=1,2,3,4,5&ip=203.0.113.42&token=secret",
    });

    expect(getCompletedSteps()).toEqual([1, 2]);
    expect(setCompletedSteps([1, 2, 3])).toBe(true);
    expect(browser.getStoredValue(COMPLETED_STEPS_KEY)).toBe("[1,2,3]");
    expect(new URL(browser.getCurrentUrl() ?? "").search).toBe("");
  });

  test("malformed URL fallback progress grants no steps", () => {
    installMockBrowser({
      url: "https://example.test/wizard/accounts?steps=1evil,2",
    });

    expect(getCompletedSteps()).toEqual([]);
  });

  test("preference URL writers remove unrelated sensitive state themselves", () => {
    const browser = installMockBrowser({
      url: "https://example.test/wizard/accounts?mode=vibe&ip=203.0.113.42&unknown=value",
    });

    expect(setInstallMode("safe")).toBe(true);
    expect(new URL(browser.getCurrentUrl() ?? "").search).toBe("?mode=safe");
  });

  test("wizard step access follows contiguous completion", () => {
    expect(canAccessWizardStep([1, 2, 3], 4)).toBe(true);
    expect(canAccessWizardStep([1, 3], 3)).toBe(false);
    expect(getNextReachableWizardStep([1, 3]).slug).toBe("install-terminal");
  });

  test("markStepComplete falls back to persisted state on storage failure", () => {
    const browser = installMockBrowser({
      failSetItemForKey: COMPLETED_STEPS_KEY,
      initialValues: {
        [COMPLETED_STEPS_KEY]: JSON.stringify([1]),
        [COMPLETED_LESSONS_KEY]: JSON.stringify([0]),
      },
    });

    expect(markStepComplete(2)).toEqual([1]);
    expect(browser.getStoredValue(COMPLETED_STEPS_KEY)).toBe("[1]");
    expect(
      browser.dispatchCalls.some(
        (event) =>
          event.type === COMPLETED_STEPS_CHANGED_EVENT ||
          event.type === COMPLETED_LESSONS_CHANGED_EVENT
      )
    ).toBe(false);
  });

  test("create-vps checklist persistence normalizes values and only emits on success", () => {
    const successBrowser = installMockBrowser({
      initialValues: {
        [CREATE_VPS_CHECKLIST_KEY]: JSON.stringify(["region", "region", 42, "ubuntu"]),
      },
    });

    expect(getCreateVPSChecklist()).toEqual(["region", "ubuntu"]);
    expect(setCreateVPSChecklist(["password", "password", "created"])).toBe(true);
    expect(successBrowser.getStoredValue(CREATE_VPS_CHECKLIST_KEY)).toBe(
      JSON.stringify(["password", "created"])
    );
    expect(successBrowser.dispatchCalls).toHaveLength(1);

    const failingBrowser = installMockBrowser({
      failSetItemForKey: CREATE_VPS_CHECKLIST_KEY,
    });
    expect(setCreateVPSChecklist(["ubuntu"])).toBe(false);
    expect(failingBrowser.getStoredValue(CREATE_VPS_CHECKLIST_KEY)).toBeNull();
    expect(failingBrowser.dispatchCalls).toHaveLength(0);
  });

  test("create-vps checklist completion requires all wizard items", () => {
    expect(isCreateVPSChecklistComplete(["ubuntu", "region", "password"])).toBe(false);
    expect(isCreateVPSChecklistComplete(["region", "ubuntu", "created", "password"])).toBe(true);
    expect(isCreateVPSChecklistComplete(["region", "ubuntu", "created", "password", "extra"])).toBe(true);
  });

  test("checked services persistence normalizes values and only emits on success", () => {
    const successBrowser = installMockBrowser({
      initialValues: {
        [CHECKED_SERVICES_TEST_KEY]: JSON.stringify(["github", "github", 42, "codex-cli"]),
      },
    });

    expect(getCheckedServices()).toEqual(["github", "codex-cli"]);
    expect(setCheckedServices(["antigravity-cli", "antigravity-cli", "tailscale"])).toBe(true);
    expect(successBrowser.getStoredValue(CHECKED_SERVICES_TEST_KEY)).toBe(
      JSON.stringify(["antigravity-cli", "tailscale"])
    );
    expect(successBrowser.dispatchCalls).toHaveLength(1);

    const failingBrowser = installMockBrowser({
      failSetItemForKey: CHECKED_SERVICES_TEST_KEY,
    });
    expect(setCheckedServices(["github"])).toBe(false);
    expect(failingBrowser.getStoredValue(CHECKED_SERVICES_TEST_KEY)).toBeNull();
    expect(failingBrowser.dispatchCalls).toHaveLength(0);
  });

  test("VPS readiness selection persistence normalizes wizard inputs", () => {
    const browser = installMockBrowser({
      initialValues: {
        [VPS_READINESS_SELECTION_KEY]: JSON.stringify({
          providerId: " contabo ",
          planName: "Cloud VPS 50",
          ubuntuVersion: "25.10",
          region: " us ",
          targetAgents: 10.8,
          workloadId: "standard",
        }),
      },
    });

    expect(getVPSReadinessSelection()).toEqual({
      providerId: "contabo",
      planName: "Cloud VPS 50",
      ubuntuVersion: "25.10",
      region: "us",
      targetAgents: 10,
      workloadId: "standard",
    });

    expect(
      setVPSReadinessSelection({
        providerId: "",
        planName: "",
        ubuntuVersion: "",
        region: "",
        targetAgents: Number.NaN,
        workloadId: "heavy",
      }),
    ).toBe(true);
    const expectedSelection = {
      providerId: "other",
      planName: "custom plan",
      ubuntuVersion: "25.10",
      region: "not-listed",
      targetAgents: 10,
      workloadId: "heavy",
    };
    expect(browser.getStoredValue(VPS_READINESS_SELECTION_KEY)).toBe(
      JSON.stringify(expectedSelection)
    );
    expect(getVPSReadinessSelection()).toEqual(expectedSelection);
    expect(browser.dispatchCalls).toHaveLength(1);

    localStorage.setItem(VPS_READINESS_SELECTION_KEY, JSON.stringify({
      ...expectedSelection,
      targetAgents: 999,
    }));
    expect(getVPSReadinessSelection()?.targetAgents).toBe(50);

    localStorage.setItem(VPS_READINESS_SELECTION_KEY, JSON.stringify({
      ...expectedSelection,
      targetAgents: -7,
    }));
    expect(getVPSReadinessSelection()?.targetAgents).toBe(5);

    localStorage.setItem(VPS_READINESS_SELECTION_KEY, JSON.stringify({
      ...expectedSelection,
      targetAgents: 13,
    }));
    expect(getVPSReadinessSelection()?.targetAgents).toBe(15);

    localStorage.setItem(VPS_READINESS_SELECTION_KEY, JSON.stringify({
      ...expectedSelection,
      targetAgents: null,
    }));
    expect(getVPSReadinessSelection()?.targetAgents).toBe(10);

    localStorage.setItem(VPS_READINESS_SELECTION_KEY, JSON.stringify({
      ...expectedSelection,
      providerId: "OVH",
      planName: "retired plan",
      ubuntuVersion: "26.04",
      region: "retired-region",
    }));
    expect(getVPSReadinessSelection()).toEqual({
      ...expectedSelection,
      providerId: "ovh",
      planName: "VPS-5",
      ubuntuVersion: "25.10",
      region: "us-east",
    });
  });

  test("VPS IP stays out of the URL when localStorage works", () => {
    const browser = installMockBrowser({
      url: "https://example.test/wizard/create-vps?os=mac&ip=192.0.2.10",
    });

    expect(getVPSIP()).toBeNull();
    expect(setVPSIP("10.0.0.50")).toBe(true);
    expect(browser.getStoredValue(VPS_IP_TEST_KEY)).toBe("10.0.0.50");
    expect(new URL(browser.getCurrentUrl() ?? "").searchParams.get("ip")).toBeNull();
    expect(getVPSIP()).toBe("10.0.0.50");
    expect(browser.dispatchCalls).toHaveLength(1);
  });

  test("sensitive query filtering is spelling-insensitive and preserves safe state", () => {
    const query = "?os=mac&vps_ip=192.0.2.10&API-KEY=secret&note=Bearer%20abc&server=203.0.113.42&mode=safe";

    expect(queryContainsSensitiveState(query)).toBe(true);
    expect(stripSensitiveQueryState(query)).toBe("os=mac&mode=safe");
    expect(queryContainsSensitiveState("?utm_source=docs&mode=vibe&profile=minimal&ref=v0.7.0")).toBe(false);
    expect(stripSensitiveQueryState("?mode=safe&profile=cloud-only"))
      .toBe("mode=safe&profile=cloud-only");
    expect(queryContainsSensitiveState("?profile=safe")).toBe(true);
    expect(queryContainsSensitiveState("?profile=unknown-profile")).toBe(true);
    expect(queryContainsSensitiveState("?from=verify-key-connection")).toBe(false);
    expect(queryContainsSensitiveState("?from=arbitrary-low-entropy-value")).toBe(true);
    expect(stripSensitiveQueryState("?utm_source=docs&unknown=value&mode=vibe"))
      .toBe("utm_source=docs&mode=vibe");
    expect(queryContainsSensitiveState(
      "?ref=github_pat_0123456789abcdefghijklmnopqrstuv",
    )).toBe(true);
    expect(queryContainsSensitiveState(
      "?ref=sk-proj-0123456789abcdefghijklmnopqrstuvwxyz",
    )).toBe(true);
    expect(queryContainsSensitiveState(
      "?ref=hvs.0123456789abcdefghijklmnopqrstuvwxyz",
    )).toBe(true);
    expect(queryContainsSensitiveState(
      "?ref=F1a9B2c8D4e7G6h3J5k0L9m8N7p6Q5r4S3t2U1v0",
    )).toBe(true);
    expect(queryContainsSensitiveState(
      "?ref=0123456789abcdef0123456789abcdef01234567",
    )).toBe(false);
    expect(queryContainsSensitiveState(
      "?ref=feature%2F1234-add-support-for-cloudflare-workers",
    )).toBe(false);
    expect(normalizeGitRef(
      "feature/1234-add-support-for-cloudflare-workers",
    )).toBe("feature/1234-add-support-for-cloudflare-workers");
    const fragmentedToken =
      "AbCdEfGhIjKlMnOpQrSt/1234567890aBcDeFgHiJ/UVWXYZabcdef01234567";
    expect(normalizeGitRef(fragmentedToken)).toBeNull();
    expect(queryContainsSensitiveState(
      `?utm_content=${encodeURIComponent(fragmentedToken)}`,
    )).toBe(true);
    expect(normalizeGitRef(
      "feature/QwErTyUiOpAsDfGhJkLzXcVbNmPoIuYtReWq",
    )).toBeNull();
    expect(normalizeGitRef(`ghp_${"a".repeat(36)}`)).toBeNull();
    expect(normalizeGitRef(`sk-proj-${"a".repeat(32)}`)).toBeNull();
    expect(normalizeGitRef("risk-proj-deployment-hardening-changes")).toBe(
      "risk-proj-deployment-hardening-changes",
    );
    expect(normalizeGitRef("npm_dependency-upgrade-and-cleanup")).toBe(
      "npm_dependency-upgrade-and-cleanup",
    );
    expect(normalizeGitRef(`npm_${"a".repeat(36)}`)).toBeNull();
    expect(normalizeGitRef("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUV"))
      .toBeNull();
    expect(normalizeSSHUsername("a".repeat(33))).toBeNull();
    expect(stripSensitiveQueryState(
      "?mode=safe&ref=sk-proj-0123456789abcdefghijklmnopqrstuvwxyz",
    )).toBe("mode=safe");
  });

  test("the analytics API itself fails closed on sensitive URL state", () => {
    installMockBrowser({
      url: "https://example.test/wizard/run-installer?mode=safe&ip=2001%3Adb8%3A%3A7",
    });
    expect(isAnalyticsPrivacyAllowed()).toBe(false);

    installMockBrowser({
      url: "https://example.test/get-started?mode=safe&ref=v0.7.0",
    });
    expect(isAnalyticsPrivacyAllowed()).toBe(true);

    installMockBrowser({
      url: "https://example.test/wizard/run-installer?mode=safe&ref=v0.7.0",
    });
    expect(isAnalyticsPrivacyAllowed()).toBe(false);

    disableAnalyticsForDocument();
    expect(isAnalyticsPrivacyAllowed()).toBe(false);
  });

  test("analytics admission fails closed on sensitive referrer state", () => {
    expect(analyticsContextContainsSensitiveState(
      "?mode=safe",
      "https://example.test/wizard?ip=203.0.113.42",
    )).toBe(true);
    expect(analyticsContextContainsSensitiveState(
      "?mode=safe",
      "https://203.0.113.42/wizard",
    )).toBe(true);
    expect(analyticsContextContainsSensitiveState(
      "?mode=safe",
      "https://docs.example.test/guide?utm_source=search",
    )).toBe(false);
    expect(analyticsContextContainsSensitiveState(
      "?mode=safe",
      "",
      "https://203.0.113.42/get-started",
    )).toBe(true);
    expect(analyticsContextContainsSensitiveState(
      "?mode=safe",
      "",
      "https://[2001:db8::7]/get-started",
    )).toBe(true);
  });

  test("analytics admission honors every supported global privacy signal", () => {
    installMockBrowser({
      globalPrivacyControl: true,
      url: "https://example.test/get-started?mode=safe",
    });
    expect(isAnalyticsPrivacyAllowed()).toBe(false);

    installMockBrowser({
      navigatorDoNotTrack: "1",
      url: "https://example.test/get-started?mode=safe",
    });
    expect(isAnalyticsPrivacyAllowed()).toBe(false);

    installMockBrowser({
      windowDoNotTrack: "1",
      url: "https://example.test/get-started?mode=safe",
    });
    expect(isAnalyticsPrivacyAllowed()).toBe(false);
  });

  test("full URL privacy checks cover host, userinfo, path, hash, and encoding", () => {
    expect(urlContainsSensitiveState("https://example.test/learn#pricing")).toBe(false);
    expect(urlContainsSensitiveState("https://user:pass@example.test/learn")).toBe(true);
    expect(urlContainsSensitiveState("https://example.test/learn/203.0.113.7")).toBe(true);
    expect(urlContainsSensitiveState("https://example.test/learn#token=secret")).toBe(true);
    expect(urlContainsSensitiveState("https://example.test/learn#password=hunter2")).toBe(true);
    expect(urlContainsSensitiveState("https://example.test/learn#foo=bar&token=secret"))
      .toBe(true);
    expect(urlContainsSensitiveState("https://example.test/learn#foo?access_token=secret"))
      .toBe(true);
    expect(urlContainsSensitiveState("https://example.test/token/secret")).toBe(true);
    expect(urlContainsSensitiveState("https://example.test/docs/code/examples")).toBe(false);
    expect(urlContainsSensitiveState(
      "https://example.test/callback/0123456789abcdef0123456789abcdef01234567",
    )).toBe(true);
    expect(urlContainsSensitiveState(
      `https://example.test/learn#sk-proj-${"a".repeat(32)}`,
    )).toBe(true);
    expect(urlContainsSensitiveState(
      `https://example.test/learn/sk-proj-${"a".repeat(32)}`,
    )).toBe(true);
    const encodedToken = `sk-proj-${"%61".repeat(32)}`;
    expect(urlContainsSensitiveState(
      `https://example.test/learn/${encodedToken}`,
    )).toBe(true);
    expect(urlContainsSensitiveState(
      `https://example.test/learn/${encodeURIComponent(encodedToken)}`,
    )).toBe(true);
    expect(urlContainsSensitiveState("https://example.test/learn/hello%2520world"))
      .toBe(false);
    expect(urlContainsSensitiveState("https://example.test/learn#%E0%A4%A")).toBe(true);
  });

  test("history destinations are sanitized before vendor scripts can observe them", () => {
    expect(sanitizeSensitiveNavigationUrl(
      "/wizard/run-installer?mode=safe&ip=203.0.113.42#run",
      "https://example.test/get-started?utm_source=docs",
    )).toBe("https://example.test/wizard/run-installer?mode=safe#run");
    expect(sanitizeSensitiveNavigationUrl(
      "https://other.example/wizard?ip=203.0.113.42",
      "https://example.test/get-started",
    )).toBe("https://other.example/wizard?ip=203.0.113.42");
    expect(sanitizeSensitiveNavigationUrl(
      "/learn/203.0.113.42?mode=safe#pricing",
      "https://example.test/get-started",
    )).toBe("https://example.test/?mode=safe#pricing");
    expect(sanitizeSensitiveNavigationUrl(
      `/learn?mode=safe#sk-proj-${"a".repeat(32)}`,
      "https://example.test/get-started",
    )).toBe("https://example.test/learn?mode=safe");
    expect(sanitizeSensitiveNavigationUrl(
      "https://user:pass@example.test/learn?mode=safe",
      "https://example.test/get-started",
    )).toBe("https://example.test/learn?mode=safe");
    let coercions = 0;
    const statefulDestination = {
      toString() {
        coercions += 1;
        return coercions === 1
          ? "/get-started?mode=safe"
          : "/get-started?token=second-coercion-secret";
      },
    };
    expect(sanitizeSensitiveNavigationUrl(
      statefulDestination as unknown as URL,
      "https://example.test/get-started",
    )).toBe("/get-started?mode=safe");
    expect(coercions).toBe(1);
    let primitiveCoercions = 0;
    const primitiveDestination = {
      [Symbol.toPrimitive](hint: string) {
        primitiveCoercions += 1;
        expect(hint).toBe("string");
        return "/get-started?mode=vibe";
      },
      toString() {
        throw new Error("native string coercion must prefer Symbol.toPrimitive");
      },
    };
    expect(sanitizeSensitiveNavigationUrl(
      primitiveDestination as unknown as URL,
      "https://example.test/get-started",
    )).toBe("/get-started?mode=vibe");
    expect(primitiveCoercions).toBe(1);
    expect(() => sanitizeSensitiveNavigationUrl(
      { [Symbol.toPrimitive]() { throw new Error("coercion failed"); } } as unknown as URL,
      "https://example.test/get-started",
    )).toThrow("coercion failed");
    expect(() => sanitizeSensitiveNavigationUrl(
      Symbol("destination") as unknown as URL,
      "https://example.test/get-started",
    )).toThrow("History URL cannot be a Symbol");
    expect(sanitizeSensitiveNavigationUrl(
      null,
      "https://example.test/get-started?token=secret",
    )).toBe("https://example.test/get-started");
    expect(sanitizeSensitiveNavigationUrl(
      undefined,
      "https://example.test/get-started?mode=safe",
    )).toBeUndefined();
    expect(isPrivateWizardPath("/wizard/run-installer")).toBe(true);
    expect(isPrivateWizardPath("/learn/commands")).toBe(false);
  });

  test("vendor events require both queued and live URLs to be public and safe", () => {
    expect(vendorEventIsPrivacySafe(
      "https://example.test/get-started?ip=203.0.113.42",
      "https://example.test/get-started?mode=safe",
    )).toBe(false);
    expect(vendorEventIsPrivacySafe(
      "https://example.test/get-started?mode=safe",
      "https://example.test/get-started?token=secret",
    )).toBe(false);
    expect(vendorEventIsPrivacySafe(
      "https://example.test/get-started?mode=safe",
      "https://example.test/get-started?utm_source=docs",
    )).toBe(true);
    expect(vendorEventIsPrivacySafe(
      "https://example.test/wizard/run-installer?mode=safe",
      "https://example.test/get-started",
    )).toBe(false);
  });

  test("navigation merging projects both URLs and preserves explicit state and hash", () => {
    installMockBrowser({
      url: "https://example.test/wizard/accounts?mode=vibe&utm_source=docs&ip=203.0.113.7",
    });

    expect(withCurrentSearch(
      "/wizard/windows-terminal-setup?from=verify-key-connection&mode=safe#pricing",
    )).toBe(
      "/wizard/windows-terminal-setup?utm_source=docs&from=verify-key-connection&mode=safe#pricing",
    );
    expect(withCurrentSearch("/wizard/accounts?ip=203.0.113.7#pricing")).toBe(
      "/wizard/accounts?mode=vibe&utm_source=docs#pricing",
    );
  });

  test("analytics referrers retain acquisition origin without query or path state", () => {
    expect(sanitizeAnalyticsReferrer(
      "https://example.test/wizard/run-installer?ip=2001%3Adb8%3A%3A7#secret",
    )).toEqual({
      referrer: "",
      domain: "",
    });
    expect(sanitizeAnalyticsReferrer("https://docs.example.test/guide?utm_source=search"))
      .toEqual({ referrer: "https://docs.example.test", domain: "docs.example.test" });
    expect(sanitizeAnalyticsReferrer("javascript:alert(1)"))
      .toEqual({ referrer: "", domain: "" });
    expect(sanitizeAnalyticsReferrer("https://203.0.113.7/private?token=secret"))
      .toEqual({ referrer: "", domain: "" });
    expect(sanitizeAnalyticsReferrer("https://[2001:db8::7]/private"))
      .toEqual({ referrer: "", domain: "" });
  });

  test("command-copy analytics retain measurements but never command bytes", () => {
    const command = "ssh -i ~/.ssh/acfs_ed25519 ubuntu@203.0.113.42";
    const properties = commandCopyAnalyticsProperties(command);

    expect(properties).toEqual({ command_length: command.length });
    expect(JSON.stringify(properties)).not.toContain("203.0.113.42");
    expect(JSON.stringify(properties)).not.toContain("ssh");
  });

  test("analytics sinks reject poisoned payloads but accept minted identifiers", () => {
    const token = `sk-proj-${"a".repeat(32)}`;
    expect(analyticsPayloadIsPrivacySafe({ source: "203.0.113.42" })).toBe(false);
    expect(analyticsPayloadIsPrivacySafe({ nested: { campaign: token } })).toBe(false);
    expect(analyticsPayloadIsPrivacySafe({ token: "even-low-entropy" })).toBe(false);
    expect(analyticsPayloadIsPrivacySafe({
      user_id: "user_1787576346000_abc123xyz",
      funnel_id: "lesson_funnel_1787576346000_abc123xyz",
      source: "docs",
      landing_page: "/learn",
    })).toBe(true);
  });

  test("poisoned persistent analytics identities are regenerated or rejected", () => {
    const browser = installMockBrowser({
      initialValues: {
        acfs_user_id: "203.0.113.42",
        acfs_funnel_data: JSON.stringify({
          sessionId: "funnel_1787576346000_abc123xyz",
          startedAt: new Date().toISOString(),
          currentStep: 1,
          maxStepReached: 1,
          stepTimestamps: { 1: { entered: new Date().toISOString() } },
          completedSteps: [],
          source: "203.0.113.42",
          medium: "none",
          campaign: "none",
        }),
        acfs_lesson_funnel_data: JSON.stringify({
          sessionId: `sk-proj-${"a".repeat(32)}`,
          startedAt: new Date().toISOString(),
          currentLesson: 0,
          maxLessonReached: 0,
          lessonTimestamps: {},
          completedLessons: [],
          source: "direct",
          medium: "none",
          campaign: "none",
        }),
      },
      url: "https://example.test/learn",
    });

    const userId = getOrCreateUserId();
    expect(userId).toMatch(/^user_\d{10,16}_[a-z0-9]{6,16}$/);
    expect(userId).not.toContain("203.0.113.42");
    expect(browser.getStoredValue("acfs_user_id")).toBe(userId);
    expect(getFunnelData()).toBeNull();
    expect(getLessonFunnelData()).toBeNull();
  });

  test("VPS IP uses memory without leaking into the URL when localStorage is blocked", () => {
    const browser = installMockBrowser({
      failSetItemForKey: VPS_IP_TEST_KEY,
      url: "https://example.test/wizard/create-vps?os=mac",
    });

    expect(setVPSIP("10.0.0.50")).toBe(true);
    expect(browser.getStoredValue(VPS_IP_TEST_KEY)).toBeNull();
    expect(new URL(browser.getCurrentUrl() ?? "").searchParams.get("ip")).toBeNull();
    expect(getVPSIP()).toBe("10.0.0.50");
    expect(browser.dispatchCalls).toHaveLength(1);
  });

  test("VPS IP setter reports failure when a sensitive URL cannot be scrubbed", () => {
    const browser = installMockBrowser({
      failReplaceState: true,
      initialValues: { [VPS_IP_TEST_KEY]: "192.0.2.10" },
      url: "https://example.test/wizard/create-vps?ip=203.0.113.7",
    });

    expect(setVPSIP("10.0.0.50")).toBe(false);
    expect(browser.getStoredValue(VPS_IP_TEST_KEY)).toBe("192.0.2.10");
    expect(browser.dispatchCalls).toHaveLength(0);
  });

  test("a fresh in-memory VPS IP overrides stale durable state after a failed write", () => {
    const browser = installMockBrowser({
      failSetItemForKey: VPS_IP_TEST_KEY,
      initialValues: {
        [VPS_IP_TEST_KEY]: "192.0.2.10",
      },
      url: "https://example.test/wizard/create-vps",
    });

    expect(getVPSIP()).toBe("192.0.2.10");
    expect(setVPSIP("2001:db8::50")).toBe(true);
    expect(browser.getStoredValue(VPS_IP_TEST_KEY)).toBe("192.0.2.10");
    expect(getVPSIP()).toBe("2001:db8::50");
  });

  test("ACFS ref persistence rejects invalid refs without clearing the saved ref", () => {
    const browser = installMockBrowser({
      initialValues: {
        [ACFS_REF_KEY]: "v1.2.3",
      },
    });

    expect(getACFSRef()).toBe("v1.2.3");
    expect(setACFSRef("bad ref")).toBe(false);
    expect(getACFSRef()).toBe("v1.2.3");
    expect(browser.getStoredValue(ACFS_REF_KEY)).toBe("v1.2.3");
    expect(browser.dispatchCalls).toHaveLength(0);

    expect(setACFSRef(null)).toBe(true);
    expect(getACFSRef()).toBeNull();
    expect(browser.getStoredValue(ACFS_REF_KEY)).toBe("");
    expect(browser.dispatchCalls).toHaveLength(1);
  });

  test("ACFS refs reject credential-shaped state while preserving public pins", () => {
    const token = "hvs.0123456789abcdefghijklmnopqrstuvwxyz";
    const commit = "0123456789abcdef0123456789abcdef01234567";
    const browser = installMockBrowser({
      initialValues: { [ACFS_REF_KEY]: "feature/new-tool" },
      url: `https://example.test/wizard/run-installer?ref=${encodeURIComponent(token)}`,
    });

    expect(getACFSRef()).toBe("feature/new-tool");
    expect(setACFSRef(token)).toBe(false);
    expect(browser.getStoredValue(ACFS_REF_KEY)).toBe("feature/new-tool");
    expect(normalizeGitRef("glpat-0123456789abcdefghijklmnop")).toBeNull();
    expect(normalizeGitRef(`npm_${"a".repeat(36)}`)).toBeNull();
    expect(normalizeGitRef("sbp_0123456789abcdefghijklmnop")).toBeNull();
    expect(normalizeGitRef("AIza0123456789abcdefghijklmnopqrstuv")).toBeNull();
    expect(normalizeGitRef("F1a9B2c8D4e7G6h3J5k0L9m8N7p6Q5r4S3t2U1v0")).toBeNull();
    expect(normalizeGitRef("feature/F1a9B2c8D4e7G6h3J5k0L9m8N7p6Q5r4S3t2U1v0")).toBeNull();
    expect(normalizeGitRef(commit)).toBe(commit);
    expect(normalizeGitRef("feature/new-tool")).toBe("feature/new-tool");
  });

  test("SSH username persistence rejects root as an ACFS target user", () => {
    expect(normalizeSSHUsername("root")).toBeNull();

    const queryBrowser = installMockBrowser({
      url: "https://example.test/wizard/run-installer?user=root",
    });
    expect(getSSHUsername()).toBe("ubuntu");
    expect(queryBrowser.dispatchCalls).toHaveLength(0);

    const storedBrowser = installMockBrowser({
      initialValues: {
        [SSH_USERNAME_TEST_KEY]: "root",
      },
      url: "https://example.test/wizard/run-installer",
    });
    expect(getSSHUsername()).toBe("ubuntu");
    expect(setSSHUsername("root")).toBe(false);
    expect(storedBrowser.getStoredValue(SSH_USERNAME_TEST_KEY)).toBe("root");
    expect(storedBrowser.dispatchCalls).toHaveLength(0);
  });
});
