defmodule Edenflowers.Payments.GiftVoucherPdf do
  @moduledoc """
  Renders a Gift voucher's card as a PDF from `priv/receipts/voucher-main.typ`:
  its amount, code, expiry, who it's for and the buyer's message, in the
  language the buyer chose for it. Its sale's order holds those. Expects
  `line_item: :order` loaded.
  """
  use Gettext, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Format
  alias Edenflowers.Payments.GiftVoucher

  def generate(voucher), do: Edenflowers.Typst.render("voucher-main.typ", "voucher", build_payload(voucher))

  # Named by the order, not the code, which shouldn't travel in file names.
  def attachment(pdf, reference) do
    Swoosh.Attachment.new({:data, pdf},
      filename: "eden-flowers-gift-voucher-#{reference}.pdf",
      content_type: "application/pdf"
    )
  end

  def build_payload(%GiftVoucher{line_item: %{order: order}} = voucher) do
    locale = order.voucher_locale || order.locale

    %{
      lang: Edenflowers.Orders.Receipt.lang_from_locale(locale),
      labels: labels(locale),
      seller: Map.take(Application.fetch_env!(:edenflowers, :seller), [:name, :business_id, :address]),
      amount: Format.storefront_price(voucher.amount, locale),
      code: GiftVoucher.format_code(voucher.code),
      expires_on: Format.date(voucher.expires_on, locale),
      recipient_name: order.recipient_name,
      message: order.card_message
    }
  end

  defp labels(locale) do
    EdenflowersWeb.Gettext.with_app_locale(locale, fn ->
      %{
        "gift-voucher" => dgettext("receipts", "Gift voucher"),
        # Translators: Label before the recipient's name on a printed gift voucher, as in "For: Mia".
        "for" => dgettext("receipts", "For"),
        "code" => dgettext("receipts", "Code"),
        "valid-until" => dgettext("receipts", "Valid until"),
        "how-to-use" =>
          dgettext(
            "receipts",
            "Spend it on flowers, subscriptions and courses: enter the code at checkout on edenflowers.fi, or show it in the shop."
          ),
        "terms" =>
          dgettext(
            "receipts",
            "Valid for one year. What you don't spend stays on the code, and it can't be exchanged for cash."
          )
      }
    end)
  end
end
