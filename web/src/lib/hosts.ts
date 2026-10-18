/**
 * Where the admin dashboard lives. On the live domain it has its own subdomain
 * (admin.easysesh.live); everywhere else (localhost, *.pages.dev previews) it is at /admin.
 * Kept free of other imports: the boot script reads it before choosing which app to load.
 */
const SITE_DOMAIN = (import.meta.env.VITE_SITE_DOMAIN as string | undefined) || "easysesh.live";

const { hostname, protocol } = window.location;

export const isAdminHost = hostname === `admin.${SITE_DOMAIN}`;
export const hasAdminSubdomain = isAdminHost || hostname === SITE_DOMAIN || hostname === `www.${SITE_DOMAIN}`;

/** Router basename for the admin dashboard. */
export const adminBase = isAdminHost ? "/" : "/admin";

/** Full URL of an admin page, e.g. adminUrl("users"). */
export const adminUrl = (path = "") =>
  hasAdminSubdomain ? `${protocol}//admin.${SITE_DOMAIN}/${path}` : `/admin/${path}`;

/** The public website, seen from the admin dashboard. */
export const websiteUrl = isAdminHost ? `${protocol}//${SITE_DOMAIN}/` : "/";
