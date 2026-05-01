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
  setACFSRef,
  setCreateVPSChecklist,
} from "./userPreferences";

type StorageController = {
  dispatchCalls: Event[];
  getStoredValue: (key: string) => string | null;
};

const originalWindow = globalThis.window;
const originalLocalStorage = globalThis.localStorage;

function installMockBrowser(options?: {
  failSetItemForKey?: string;
  initialValues?: Record<string, string>;
}): StorageController {
  const dispatchCalls: Event[] = [];
  const storage = new Map(Object.entries(options?.initialValues ?? {}));

  Object.defineProperty(globalThis, "window", {
    configurable: true,
    value: {
      dispatchEvent(event: Event) {
        dispatchCalls.push(event);
        return true;
      },
    },
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
});
