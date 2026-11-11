import assert from "node:assert/strict";
import { test } from "node:test";
import { formatVoucherCode } from "../../assets/js/voucher_code.mjs";

test("spaces the digits into fours as they're typed", () => {
  assert.deepEqual(formatVoucherCode("1234", 4), { value: "1234", caret: 4 });
  assert.deepEqual(formatVoucherCode("12345", 5), {
    value: "1234 5",
    caret: 6,
  });
});

test("tidies a pasted code however it was written", () => {
  const pasted = "4829-0617-5331-84O7";
  assert.deepEqual(formatVoucherCode(pasted, pasted.length), {
    value: "4829 0617 5331 8407",
    caret: 19,
  });
});

test("keeps the caret after the same digit when fixing one mid-code", () => {
  // Inserting 9 after the 2 in "1234 5678" leaves the browser's caret at index 3.
  // Reformatting must keep it after the inserted digit.
  assert.deepEqual(formatVoucherCode("12934 5678", 3), {
    value: "1293 4567 8",
    caret: 3,
  });
});

test("backspace after a space takes the digit before it", () => {
  // Backspacing the space in "1234 5678" leaves "12345678" with the caret at index 4.
  // The formatter must remove the preceding digit instead of simply restoring the space.
  assert.deepEqual(formatVoucherCode("12345678", 4, true), {
    value: "1235 678",
    caret: 3,
  });
});

test("stops at 16 digits, typed or pasted", () => {
  assert.deepEqual(formatVoucherCode("4829 0617 5331 84075", 20), {
    value: "4829 0617 5331 8407",
    caret: 19,
  });
  const pasted = "4829-0617-5331-8407-99";
  assert.equal(
    formatVoucherCode(pasted, pasted.length).value,
    "4829 0617 5331 8407",
  );
});
