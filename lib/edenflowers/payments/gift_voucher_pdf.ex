defmodule Edenflowers.Payments.GiftVoucherPdf do
  @moduledoc """
  Renders a Gift voucher's card as a PDF from `priv/receipts/voucher-main.typ`:
  its amount, code, expiry, who it's for and the buyer's message, in the
  language and style the buyer chose for it. Its sale's order holds those.
  Expects `line_item: :order` loaded.
  """
  use Gettext, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Format
  alias Edenflowers.Payments.GiftVoucher

  def generate(voucher), do: Edenflowers.Typst.render("voucher-main.typ", "voucher", build_payload(voucher))

  @doc """
  A PNG of the voucher a buyer is still choosing, for the checkout's preview:
  what they've entered so far, with a placeholder code and a year's validity
  from today.
  """
  def preview(%{amount: amount, locale: locale, style: style, recipient_name: recipient_name, message: message}) do
    payload =
      payload(locale,
        style: style,
        amount: amount,
        code: "XXXX XXXX XXXX XXXX",
        expires_on: Date.shift(Edenflowers.ShopTime.today(), year: 1),
        recipient_name: recipient_name,
        message: message
      )

    Edenflowers.Typst.render("voucher-main.typ", "voucher", payload, format: "png", ppi: 110)
  end

  # Named by the order, not the code, which shouldn't travel in file names.
  def attachment(pdf, reference) do
    Swoosh.Attachment.new({:data, pdf},
      filename: "eden-flowers-gift-voucher-#{reference}.pdf",
      content_type: "application/pdf"
    )
  end

  def build_payload(%GiftVoucher{line_item: %{order: order}} = voucher) do
    payload(order.voucher_locale || order.locale,
      style: order.voucher_style || :cream,
      amount: voucher.amount,
      code: GiftVoucher.format_code(voucher.code),
      expires_on: voucher.expires_on,
      recipient_name: order.recipient_name,
      message: order.card_message
    )
  end

  defp payload(locale, voucher) do
    %{
      lang: Edenflowers.Orders.Receipt.lang_from_locale(locale),
      labels: labels(locale),
      seller: Map.take(Application.fetch_env!(:edenflowers, :seller), [:name, :business_id, :address]),
      style: voucher[:style],
      amount: Format.storefront_price(voucher[:amount], locale),
      code: voucher[:code],
      expires_on: Format.date(voucher[:expires_on], locale),
      recipient_name: voucher[:recipient_name],
      message: voucher[:message]
    }
  end

  defp labels(locale) do
    EdenflowersWeb.Gettext.with_app_locale(locale, fn ->
      %{
        "gift-voucher" => dgettext("receipts", "Gift voucher"),
        # Translators: Label above the recipient's name on a printed gift voucher, as on a gift tag: "To Mia".
        "to" => dgettext("receipts", "To"),
        "code" => dgettext("receipts", "Code"),
        "valid-until" => dgettext("receipts", "Valid until"),
        # Translators: The greeting in script at the top of the Christmas gift voucher. The usual Christmas wish, short.
        "christmas-greeting" => dgettext("receipts", "Merry Christmas"),
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
