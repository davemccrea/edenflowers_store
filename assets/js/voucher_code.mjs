// Gift voucher codes are 16 digits, printed in groups of four like a card number.
// Phones' number pads have no space key, so the spaces are put in as the code is typed.

// O, I and L read as 0 and 1, as GiftVoucher.normalize_code/1 does on the server.
const digitsOf = (text) =>
  text
    .toUpperCase()
    .replace(/O/g, "0")
    .replace(/[IL]/g, "1")
    .replace(/\D/g, "");

// Backspace right after a space only takes the space, which would come straight
// back, so it takes the digit before it instead.
export function formatVoucherCode(value, caret, backspacedSpace = false) {
  let before = digitsOf(value.slice(0, caret));
  let after = digitsOf(value.slice(caret));
  if (backspacedSpace) before = before.slice(0, -1);

  const formatted = (before + after).replace(/(\d{4})(?=\d)/g, "$1 ");
  const spacesBefore =
    before.length > 0 ? Math.floor((before.length - 1) / 4) : 0;
  return { value: formatted, caret: before.length + spacesBefore };
}

export const VoucherCode = {
  mounted() {
    let previous = this.el.value;
    this.el.addEventListener("input", (event) => {
      const backspacedSpace =
        event.inputType === "deleteContentBackward" &&
        digitsOf(this.el.value).length === digitsOf(previous).length;
      const { value, caret } = formatVoucherCode(
        this.el.value,
        this.el.selectionStart,
        backspacedSpace,
      );
      this.el.value = value;
      this.el.setSelectionRange(caret, caret);
      previous = value;
    });
  },
};
