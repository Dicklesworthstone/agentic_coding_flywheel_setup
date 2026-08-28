"use client";

import { QueryClient, type Query } from "@tanstack/react-query";
import {
  PersistQueryClientProvider,
  type PersistQueryClientOptions,
} from "@tanstack/react-query-persist-client";
import { createSyncStoragePersister } from "@tanstack/query-sync-storage-persister";
import { useState, type ReactNode } from "react";
import { wizardStepsKeys } from "../lib/wizardSteps";

const PERSIST_KEY = "acfs-query-cache";

function makeQueryClient() {
  return new QueryClient({
    defaultOptions: {
      queries: {
        // With localStorage persistence, we want long cache times
        staleTime: Infinity,
        gcTime: Infinity,
        // Don't refetch on window focus for localStorage-backed data
        refetchOnWindowFocus: false,
        refetchOnReconnect: false,
        retry: false,
      },
    },
  });
}

/**
 * Build the persister exactly once per QueryProvider instance.
 *
 * `createSyncStoragePersister` with `storage: undefined` returns a no-op
 * persister (persist/restore/remove are all noops), so the same provider
 * element type can be rendered on the server, during hydration, and in
 * browsers where localStorage throws (private mode, storage quota, blocked
 * third-party contexts). Swapping `QueryClientProvider` for
 * `PersistQueryClientProvider` after mount — the previous approach —
 * changed the element type at the root of the tree, which made React
 * unmount and recreate every descendant one tick after hydration (refs
 * reset, every effect ran twice, entrance animations replayed, and the
 * analytics `config` + session_start fired twice).
 */
function makePersister() {
  if (typeof window === "undefined") {
    return createSyncStoragePersister({ storage: undefined, key: PERSIST_KEY });
  }
  try {
    // Probe localStorage availability first (private browsing, restrictions)
    const testKey = "__acfs_test__";
    window.localStorage.setItem(testKey, "test");
    window.localStorage.removeItem(testKey);
    return createSyncStoragePersister({
      storage: window.localStorage,
      key: PERSIST_KEY,
    });
  } catch {
    // localStorage unavailable (private browsing, quota exceeded, etc.)
    // Fall back to the in-memory-only cache - app will still work
    console.warn(
      "[ACFS] localStorage unavailable, running without query persistence"
    );
    return createSyncStoragePersister({ storage: undefined, key: PERSIST_KEY });
  }
}

function shouldDehydrateQuery(query: Query): boolean {
  const queryKey = query.queryKey;
  // Exclude wizard steps (manually persisted to separate key)
  if (
    queryKey[0] === wizardStepsKeys.completedSteps[0] &&
    queryKey[1] === wizardStepsKeys.completedSteps[1]
  ) {
    return false;
  }
  // Exclude all user preferences (each preference has its own
  // canonical localStorage key — double-persisting in the query
  // cache would cause stale flashes on page reload)
  if (queryKey[0] === "userPreferences") {
    return false;
  }
  return true;
}

export function QueryProvider({ children }: { children: ReactNode }) {
  const [queryClient] = useState(() => makeQueryClient());
  // Stable identity: PersistQueryClientProvider re-runs its restore effect
  // whenever the options object changes, so build it once.
  const [persistOptions] = useState<Omit<PersistQueryClientOptions, "queryClient">>(() => ({
    persister: makePersister(),
    dehydrateOptions: { shouldDehydrateQuery },
  }));

  return (
    <PersistQueryClientProvider client={queryClient} persistOptions={persistOptions}>
      {children}
    </PersistQueryClientProvider>
  );
}
