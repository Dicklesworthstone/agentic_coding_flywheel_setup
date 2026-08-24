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
  normalizeSSHUsername,
  setACFSRef,
  setCheckedServices,
  setCreateVPSChecklist,
  setSSHUsername,
  setVPSReadinessSelection,
  setVPSIP,
  VPS_READINESS_SELECTION_KEY,
} from "./userPreferences";

type StorageController = {
  dispatchCalls: Event[];
  getCurrentUrl: () => string | null;
  getStoredValue: (key: string) => string | null;
};

const originalWindow = globalThis.window;
const originalLocalStorage = globalThis.localStorage;
const VPS_IP_TEST_KEY = "agent-flywheel-vps-ip";
const SSH_USERNAME_TEST_KEY = "agent-flywheel-ssh-username";
const CHECKED_SERVICES_TEST_KEY = "agent-flywheel-checked-services";

function installMockBrowser(options?: {
  failSetItemForKey?: string;
  initialValues?: Record<string, string>;
  url?: string;
}): StorageController {
  const dispatchCalls: Event[] = [];
  const storage = new Map(Object.entries(options?.initialValues ?? {}));
  let currentUrl = options?.url ? new URL(options.url) : null;
  let historyState: unknown = null;

  const windowValue = {
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

    expect(setVPSIP("10.0.0.50")).toBe(true);
    expect(browser.getStoredValue(VPS_IP_TEST_KEY)).toBe("10.0.0.50");
    expect(new URL(browser.getCurrentUrl() ?? "").searchParams.get("ip")).toBeNull();
    expect(getVPSIP()).toBe("10.0.0.50");
    expect(browser.dispatchCalls).toHaveLength(1);
  });

  test("VPS IP uses the URL only when localStorage is blocked", () => {
    const browser = installMockBrowser({
      failSetItemForKey: VPS_IP_TEST_KEY,
      url: "https://example.test/wizard/create-vps?os=mac",
    });

    expect(setVPSIP("10.0.0.50")).toBe(true);
    expect(browser.getStoredValue(VPS_IP_TEST_KEY)).toBeNull();
    expect(new URL(browser.getCurrentUrl() ?? "").searchParams.get("ip")).toBe("10.0.0.50");
    expect(getVPSIP()).toBe("10.0.0.50");
    expect(browser.dispatchCalls).toHaveLength(1);
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
