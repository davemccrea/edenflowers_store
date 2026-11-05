defmodule EdenflowersWeb.GiftVoucherField do
  @moduledoc """
  The Gift voucher field in the payment step of checkout and course checkout:
  a disclosure to enter a code, then what the voucher pays and what will be
  left on it, with a way to take it off.

  The page handles `"apply_gift_voucher"` (`%{"gift_voucher" => %{"code" => code}}`)
  and `"clear_gift_voucher"`, and passes back any refusal from
  `error_message/1`.
  """
  use EdenflowersWeb, :html

  attr :id, :string, required: true

  attr :payable, :map,
    required: true,
    doc: "the cart or booking, with `voucher_amount` and `voucher_left_after` loaded"

  attr :locale, :any, required: true
  attr :error, :string, default: nil, doc: "why the code entered was refused"
  attr :code, :string, default: nil, doc: "the refused code, left in the box so a typo can be corrected"

  def gift_voucher_field(%{payable: %{gift_voucher_id: nil}} = assigns) do
    assigns = assign(assigns, :form, code_form(assigns.error, assigns.code))

    ~H"""
    <details id={@id} open={@error != nil} data-testid="gift-voucher">
      <%!-- Styled as the promo code toggle, without the browser's disclosure triangle. --%>
      <summary class="link-underline-static-body touch-target text-base-content/70 inline-flex w-fit cursor-pointer list-none items-center gap-2 text-sm hover:decoration-current :[&:-webkit-details-marker]:hidden">
        <.icon name="hero-gift" class="h-4 w-4" />
        {~t"Have a gift voucher?"}
      </summary>
      <.form for={@form} id={"#{@id}-form"} phx-submit="apply_gift_voucher" class="mt-3">
        <.input
          style="button-addon"
          field={@form[:code]}
          type="text"
          button_text={~t"Apply"}
          placeholder={~t"Gift voucher code"}
          aria-label={~t"Gift voucher code"}
          autocomplete="off"
          inputmode="numeric"
          phx-hook="VoucherCode"
          spellcheck="false"
          class="tabular-nums"
        />
      </.form>
    </details>
    """
  end

  def gift_voucher_field(assigns) do
    ~H"""
    <div
      id={@id}
      class="border-base-300 flex items-start gap-3 border px-4 pt-4 pb-2"
      data-testid="gift-voucher-applied"
    >
      <.icon name="hero-gift" class="text-base-content/70 mt-0.5 h-5 w-5 flex-none" />
      <div class="flex grow flex-col">
        <div class="flex items-baseline justify-between gap-4">
          <span class="font-semibold">{~t"Gift voucher"}</span>
          <span class="text-success tabular-nums">- {Edenflowers.Format.currency(@payable.voucher_amount, @locale)}</span>
        </div>
        <div class="text-base-content/70 flex items-baseline justify-between gap-4 text-sm">
          <span>{~t"Left on it afterwards: #{amount = Edenflowers.Format.currency(@payable.voucher_left_after, @locale)}"}</span>
          <button type="button" phx-click="clear_gift_voucher" class="link-underline-static-body touch-target">
            {~t"Remove"}
          </button>
        </div>
      </div>
    </div>
    """
  end

  @doc "What to tell the customer when applying a code failed."
  def error_message(%Ash.Error.Invalid{errors: [%{field: :code, message: message} | _]}), do: message

  def error_message(%Ash.Error.Forbidden{errors: [%AshRateLimiter.LimitExceeded{} | _]}),
    do: ~t"Too many tries. Please wait a few minutes and try again."

  def error_message(_error), do: ~t"Something went wrong. Please try again."

  defp code_form(nil, _code), do: to_form(%{}, as: "gift_voucher")
  defp code_form(error, code), do: to_form(%{"code" => code}, as: "gift_voucher", errors: [code: {error, []}])
end
