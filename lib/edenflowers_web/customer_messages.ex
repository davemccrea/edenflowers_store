defmodule EdenflowersWeb.CustomerMessages do
  @moduledoc """
  Text messages Jennie sends a customer from the admin order page, written in
  the order's language. They live in `storefront` because `admin` has no
  Finnish catalogue.
  """
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Format

  # Sent the day Jennie finishes it, so "today" is the day she sends it. On a
  # Sunday the shop is shut, so there are no opening hours to give.
  def pickup(order) do
    today = Edenflowers.ShopTime.today()

    message =
      EdenflowersWeb.Gettext.with_app_locale(order.locale, fn ->
        name = order.customer_first_name
        reference = order.order_reference

        case EdenflowersWeb.Business.opening_hours(today) do
          nil ->
            ~t"Hi #{name}, your Eden Flowers order #{reference} is now ready for pick up."

          {opens, closes} ->
            ~t"Hi #{name}, your Eden Flowers order #{reference} is now ready for pick up. Minimossen is open from #{opening_time = Format.time(opens, order.locale)} to #{closing_time = Format.time(closes, order.locale)} today. If that doesn't suit, just let me know."
        end
      end)

    message <> "\nJennie / Eden Flowers"
  end

  def payment(order) do
    EdenflowersWeb.Gettext.with_app_locale(order.locale, fn ->
      name = order.customer_first_name
      reference = order.order_reference
      amount = Format.currency(order.balance, order.locale)
      url = EdenflowersWeb.PaymentLink.url_for(order)

      ~t"Hi #{name}, you can pay #{amount} for your Eden Flowers order #{reference} here: #{url}"
    end)
  end
end
