import { assert, assertEquals } from "jsr:@std/assert@1";
import { temporaryPassword } from "./passwords.ts";

Deno.test("temporary passwords meet the app's password policy", () => {
  const seen = new Set<string>();
  for (let i = 0; i < 200; i++) {
    const password = temporaryPassword();
    assertEquals(password.length, 14);
    assert(/[A-Z]/.test(password) && /[a-z]/.test(password) && /[0-9]/.test(password), password);
    seen.add(password);
  }
  assertEquals(seen.size, 200);
});
