import { isAdminHost } from "./lib/hosts";

// admin.easysesh.live opens the admin dashboard; every other address opens the website.
void (isAdminHost ? import("./admin/main") : import("./main"));
