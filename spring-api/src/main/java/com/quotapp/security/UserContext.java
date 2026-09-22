package com.quotapp.security;

/**
 * Thread-local holder for the authenticated Supabase user ID.
 *
 * <p>Set by {@link SupabaseJwtFilter} after a validated JWT. Cleared in the finally
 * block of the same filter — no userId leaks between requests on a pooled thread.
 *
 * <p>Usage in service methods:
 * <pre>{@code
 *   String userId = UserContext.require();  // throws if somehow unauthenticated
 * }</pre>
 */
public final class UserContext {

    private static final ThreadLocal<String> USER_ID = new ThreadLocal<>();

    private UserContext() {}

    /** Called by {@link SupabaseJwtFilter} after JWT validation. */
    public static void set(String userId) {
        USER_ID.set(userId);
    }

    /** Returns the current user ID, or {@code null} if not authenticated. */
    public static String get() {
        String id = USER_ID.get();
        if (id != null) {
            return id;
        }
        var auth = org.springframework.security.core.context.SecurityContextHolder.getContext().getAuthentication();
        if (auth != null && auth.isAuthenticated() && !"anonymousUser".equals(auth.getPrincipal())) {
            return auth.getName();
        }
        return null;
    }

    /** Alias for get() to return current user ID. */
    public static String getUserId() {
        return get();
    }

    /** Alias for set() to set current user ID. */
    public static void setUserId(String userId) {
        set(userId);
    }

    /**
     * Returns the current user ID; throws {@link IllegalStateException} if absent.
     * Use in service methods that must always run within an authenticated context.
     */
    public static String require() {
        String id = USER_ID.get();
        if (id == null) {
            throw new IllegalStateException("No authenticated user in current request context.");
        }
        return id;
    }

    /** Called in the filter's finally block to prevent thread-local leaks. */
    public static void clear() {
        USER_ID.remove();
    }
}
