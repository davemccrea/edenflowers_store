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
  // "1234 5678" with 9 typed after the 2: caret was 3.
  assert.deepEqual(formatVoucherCode("12934 5678", 3), {
    value: "1293 4567 8",
    caret: 3,
  });
});

test("backspace after a space takes the digit before it", () => {
  // "1234 5678" with the space backspaced: browser leaves "12345678", caret 4.
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
