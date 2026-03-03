/**
 * Auth slice — Copilot device-code and API key authentication.
 *
 * Simple state machine: checking → needsAuth → deviceCode → polling → authenticated.
 * Or: checking → needsAuth → apiKeySelection → authenticated (for API key providers).
 *
 * @module
 */

import type { StateCreator } from "zustand";
import type { Session } from "../sdk/session.js";
import type { AuthStatus } from "./types.js";

// ── Slice state + actions ────────────────────────────────────────

export interface AuthSlice {
  authStatus: AuthStatus;
  deviceCode: string | null;
  verificationUri: string | null;
  authError: string | null;
  availableProviders: string[];

  /** Probe session auth and determine if login is needed. */
  checkAuth: (session: Session) => void;
  /** Start the GitHub device-code login flow. */
  startDeviceFlow: (session: Session) => void;
  /** Select an API key provider and mark as authenticated. */
  selectApiKeyProvider: (provider: string) => void;
  /** Re-check auth from scratch. */
  retryAuth: (session: Session) => void;
}

// ── Initial state ────────────────────────────────────────────────

const AUTH_INITIAL = {
  authStatus: "checking" as AuthStatus,
  deviceCode: null as string | null,
  verificationUri: null as string | null,
  authError: null as string | null,
  availableProviders: [] as string[],
};

// ── Slice creator ────────────────────────────────────────────────

export const createAuthSlice: StateCreator<AuthSlice, [], [], AuthSlice> = (set) => ({
  ...AUTH_INITIAL,

  checkAuth: (session) => {
    const authStatus = session.auth_;
    
    void authStatus.status().then((res) => {
      const availableProviders = res.auth?.available_providers || [];
      const authenticated = res.authenticated || res.auth?.status === "ready";
      
      if (authenticated) {
        // Already authenticated or has valid credentials
        set({
          ...AUTH_INITIAL,
          authStatus: "authenticated",
          availableProviders,
        });
      } else if (availableProviders.length > 0) {
        // Has API key providers available - let user select
        set({
          ...AUTH_INITIAL,
          authStatus: "needsAuth",
          availableProviders,
        });
      } else {
        // No credentials - needs device code flow
        set({
          ...AUTH_INITIAL,
          authStatus: "needsAuth",
          availableProviders,
        });
      }
    }).catch((err: unknown) => {
      set({
        ...AUTH_INITIAL,
        authStatus: "error",
        authError: err instanceof Error ? err.message : String(err),
      });
    });
  },

  startDeviceFlow: (session) => {
    set({ authStatus: "deviceCode", authError: null });

    void session.auth_
      .login()
      .then((flow) => {
        set({
          authStatus: "polling",
          deviceCode: flow.userCode,
          verificationUri: flow.verificationUri,
        });
        return session.auth_.poll(flow.deviceCode, flow.interval);
      })
      .then(() => {
        set({ ...AUTH_INITIAL, authStatus: "authenticated" });
      })
      .catch((err: unknown) => {
        set({
          authStatus: "error",
          authError: err instanceof Error ? err.message : String(err),
        });
      });
  },

  selectApiKeyProvider: (provider: string) => {
    // For API key providers, we just mark as authenticated
    // The actual API key is read from environment on the server side
    set({
      ...AUTH_INITIAL,
      authStatus: "authenticated",
      availableProviders: [provider],
    });
  },

  retryAuth: (session) => {
    set({ ...AUTH_INITIAL, authStatus: "checking" });

    void session.auth_
      .status()
      .then((res) => {
        set({
          ...AUTH_INITIAL,
          authStatus: res.authenticated ? "authenticated" : "needsAuth",
          availableProviders: res.auth?.available_providers || [],
        });
      })
      .catch((err: unknown) => {
        set({
          authStatus: "error",
          authError: err instanceof Error ? err.message : String(err),
        });
      });
  },
});
