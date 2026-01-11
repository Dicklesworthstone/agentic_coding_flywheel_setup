"use client";

import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { PersistQueryClientProvider } from "@tanstack/react-query-persist-client";
import { createSyncStoragePersister } from "@tanstack/query-sync-storage-persister";
import { useState, useEffect, type ReactNode } from "react";

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

export function QueryProvider({ children }: { children: ReactNode }) {
  const [queryClient] = useState(() => makeQueryClient());
  const [persister, setPersister] = useState<ReturnType<typeof createSyncStoragePersister> | null>(null);

  // Create persister only after mount to avoid hydration mismatch
  // Server and client both render QueryClientProvider initially,
  // then we upgrade to PersistQueryClientProvider on client after mount
  useEffect(() => {
    // Guard against localStorage being unavailable (private browsing, restrictions)
    try {
      // Test localStorage availability first
      const testKey = "__acfs_test__";
      window.localStorage.setItem(testKey, "test");
      window.localStorage.removeItem(testKey);

      const storagePersister = createSyncStoragePersister({
        storage: window.localStorage,
        key: "acfs-query-cache",
      });

      // Defer state update to avoid setState-in-effect lint violations.
      let cancelled = false;
      Promise.resolve().then(() => {
        if (!cancelled) setPersister(storagePersister);
      });

      return () => {
        cancelled = true;
      };
    } catch {
      // localStorage unavailable (private browsing, quota exceeded, etc.)
      // Silently fall back to non-persisted state - app will still work
      console.warn(
        "[ACFS] localStorage unavailable, running without query persistence"
      );
    }
  }, []);

  // Always render PersistQueryClientProvider once we have a persister,
  // but start with QueryClientProvider for SSR/hydration consistency
  if (persister) {
    return (
      <PersistQueryClientProvider
        client={queryClient}
        persistOptions={{ persister }}
      >
        {children}
      </PersistQueryClientProvider>
    );
  }

  // Initial render (SSR + first client render before useEffect)
  return (
    <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
  );
}
