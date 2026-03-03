/**
 * Auth slice — Auto-authentication with API key providers.
 *
 * No OAuth flow - just check for API keys in environment and auto-authenticate.
 *
 * @module
 */

import type { StateCreator } from "zustand";
import type { Session } from "../sdk/session.js";
import type { AuthStatus } from "./types.js";

export interface AuthSlice {
  authStatus: AuthStatus;
  authError: string | null;
  availableProviders: string[];

  checkAuth: (session: Session) => void;
  retryAuth: (session: Session) => void;
}

const AUTH_INITIAL = {
  authStatus: "checking" as AuthStatus,
  authError: null as string | null,
  availableProviders: [] as string[],
};

export const createAuthSlice: StateCreator<AuthSlice, [], [], AuthSlice> = (set) => ({
  ...AUTH_INITIAL,

  checkAuth: (session) => {
    void session.auth_
      .status()
      .then((res) => {
        const availableProviders = res.auth?.availableProviders || [];
        
        if (availableProviders.length > 0) {
          // Auto-authenticate with API key providers
          set({
            ...AUTH_INITIAL,
            authStatus: "authenticated",
            availableProviders,
          });
        } else {
          // No providers configured
          set({
            ...AUTH_INITIAL,
            authStatus: "error",
            authError: "No API keys configured. Set OPENROUTER_API_KEY, GROQ_API_KEY, etc. in .env",
            availableProviders: [],
          });
        }
      })
      .catch((err: unknown) => {
        set({
          authStatus: "error",
          authError: err instanceof Error ? err.message : String(err),
          availableProviders: [],
        });
      });
  },

  retryAuth: (session) => {
    set({ ...AUTH_INITIAL, authStatus: "checking" });
    void session.auth_
      .status()
      .then((res) => {
        const availableProviders = res.auth?.availableProviders || [];
        if (availableProviders.length > 0) {
          set({
            ...AUTH_INITIAL,
            authStatus: "authenticated",
            availableProviders,
          });
        } else {
          set({
            ...AUTH_INITIAL,
            authStatus: "error",
            authError: "No API keys configured",
            availableProviders: [],
          });
        }
      })
      .catch((err: unknown) => {
        set({
          authStatus: "error",
          authError: err instanceof Error ? err.message : String(err),
          availableProviders: [],
        });
      });
  },
});
