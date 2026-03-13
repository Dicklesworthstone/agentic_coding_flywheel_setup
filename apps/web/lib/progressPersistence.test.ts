import { afterEach, describe, expect, test } from "bun:test";
import {
  addCompletedLesson,
  COMPLETED_LESSONS_CHANGED_EVENT,
  COMPLETED_LESSONS_KEY,
  TOTAL_LESSONS,
} from "./lessonProgress";
import {
  addCompletedStep,
  COMPLETED_STEPS_CHANGED_EVENT,
  COMPLETED_STEPS_KEY,
  markStepComplete,
  setCompletedSteps,
  TOTAL_STEPS,
} from "./wizardSteps";

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
    expect(setCompletedSteps([3, 1, 1, 2])).toBe(true);
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
});
